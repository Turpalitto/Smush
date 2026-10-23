shader_type canvas_item;

// Background of the arena and of the menus. It is a full-screen quad whose UV is
// converted back into world pixels, so the ground scrolls under the camera instead
// of sliding with the screen.
//
// Three maps of the same seamless tile drive it, all sampled in that world space:
//   * albedo  - two scales are combined. Fine (~1024 world px per repeat) carries
//     the moss grain and the pebbles; macro (x7) carries tonal patches wider than
//     the screen, which is what stops the repeat from reading as a visible grid.
//   * normal  - baked by tools/generate_floor_texture.py from the tile's height
//     field. Gives the moss real relief under a fixed light.
//   * AO      - ray-traced by tools/bake_floor_ao.py in Blender. Darkens the
//     grooves between cushions and the contact line under every pebble.
//
// Each layer is independently optional: `floor_strength` is 0 unless a script
// supplies the albedo, `floor_relief` is 0 unless the normal map loaded, and
// `floor_occlusion` is 0 unless the AO map loaded. With everything missing the
// shader degrades to the original two-colour gradient.

uniform vec2 world_offset = vec2(0.0);
uniform float camera_zoom = 1.0;
uniform vec2 view_size = vec2(720.0, 1280.0);
uniform vec4 moss_dark : source_color = vec4(0.043, 0.088, 0.074, 1.0);
uniform vec4 moss_mid : source_color = vec4(0.068, 0.145, 0.115, 1.0);
uniform vec4 canopy_glow : source_color = vec4(0.22, 0.58, 0.48, 1.0);

uniform sampler2D floor_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D floor_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D floor_ao : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float floor_strength = 0.0;
uniform float floor_tile_px = 1024.0;
uniform float floor_macro_scale = 7.0;
uniform float floor_mean = 0.08;
uniform float floor_ao_mean = 0.80;
uniform float floor_relief = 0.0;
uniform float floor_occlusion = 0.0;
uniform float floor_sheen = 0.09;

// Light direction in the normal map's own frame: -x is "toward the left of the
// image", +y is "toward the top of the image" (Godot's UV v runs downwards, the
// normal map's green channel points up). Normalised in the body.
const vec3 FLOOR_LIGHT = vec3(-0.45, 0.55, 0.72);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 world_span = view_size / max(0.35, camera_zoom);
	vec2 world_px = (UV - vec2(0.5)) * world_span + world_offset;
	vec2 wp = world_px * 0.0042;

	float n1 = value_noise(wp);
	float n2 = value_noise(wp * 2.3 + vec2(4.2, -1.7));
	float patch = smoothstep(0.28, 0.78, n1 * 0.65 + n2 * 0.35);

	// Soft diagonal enchanted sunbeams
	float beam = sin((wp.x * 1.4 + wp.y * 0.8) + TIME * 0.25) * 0.5 + 0.5;
	beam = pow(beam, 4.0) * 0.14;

	vec3 col = mix(moss_dark.rgb, moss_mid.rgb, patch);
	col += canopy_glow.rgb * beam;

	if (floor_strength > 0.001) {
		vec2 fuv = world_px / floor_tile_px;

		// Normalised around the tile's own mean, so the modulation is a ±35%
		// shading change rather than a brightness shift of the whole arena.
		vec3 fine_rgb = texture(floor_tex, fuv).rgb;
		vec3 macro_rgb = texture(floor_tex, fuv / floor_macro_scale + vec2(0.31, 0.67)).rgb;

		float fine = (fine_rgb.r + fine_rgb.g + fine_rgb.b) / 3.0 / max(0.001, floor_mean);
		float macro = (macro_rgb.r + macro_rgb.g + macro_rgb.b) / 3.0 / max(0.001, floor_mean);

		float detail = mix(1.0, clamp(fine, 0.35, 2.0), 0.62 * floor_strength);
		float broad = mix(1.0, clamp(macro, 0.55, 1.6), 0.40 * floor_strength);

		col *= detail * broad;

		// A hint of the tile's own green in the lit moss keeps the floor from
		// looking like grey noise on top of a teal wash.
		col = mix(col, col * vec3(0.92, 1.10, 0.98), clamp(fine - 1.0, 0.0, 1.0) * 0.5 * floor_strength);

		if (floor_relief > 0.01) {
			// The baked slopes are gentle (the height field is smooth), so they
			// are stretched here rather than in the map, where the right amount
			// is a matter of taste and of how dark the floor is at the moment.
			vec2 nxy = (texture(floor_normal, fuv).rg * 2.0 - 1.0) * floor_relief;
			float nlen = length(nxy);
			nxy *= min(1.0, 0.92 / max(nlen, 1e-4));
			vec3 nrm = vec3(nxy, sqrt(max(0.02, 1.0 - dot(nxy, nxy))));

			vec3 light_dir = normalize(FLOOR_LIGHT);
			// Divided by L.z so flat ground comes out at exactly 1.0.
			float lambert = dot(nrm, light_dir) / light_dir.z;
			col *= mix(1.0, clamp(lambert, 0.55, 1.45), 0.72 * floor_strength);

			// A wet sheen on the moss: cheap Blinn-Phong against the same light.
			vec3 half_dir = normalize(light_dir + vec3(0.0, 0.0, 1.0));
			float sheen = pow(max(dot(nrm, half_dir), 0.0), 20.0);
			col += canopy_glow.rgb * sheen * floor_sheen * floor_strength;
		}

		if (floor_occlusion > 0.01) {
			// Also normalised around its mean, so the grooves darken without the
			// whole floor losing brightness.
			float ao = texture(floor_ao, fuv).r;
			col *= mix(1.0, clamp(ao / max(0.05, floor_ao_mean), 0.45, 1.5), floor_occlusion * floor_strength);
		}
	}

	// Gentle readability vignette on phone edges
	vec2 vuv = UV - vec2(0.5);
	float vig = 1.0 - dot(vuv, vuv) * 0.42;
	COLOR = vec4(col * clamp(vig, 0.68, 1.0), 1.0);
}

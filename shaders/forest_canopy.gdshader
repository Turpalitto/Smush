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
// A fourth map is not the floor at all: `floor_light` is the canopy's shadow,
// baked by tools/bake_canopy_light.py from a leaf canopy under the same sun. It is
// sampled at a much coarser scale and drifts, so the light moves across the floor
// the way it does when the leaves move.
//
// Each layer is independently optional: `floor_strength` is 0 unless a script
// supplies the albedo, `floor_relief` is 0 unless the normal map loaded,
// `floor_occlusion` is 0 unless the AO map loaded, and `floor_dapple` is 0 unless
// the canopy light loaded. With everything missing the shader degrades to the
// original two-colour gradient.

uniform vec2 world_offset = vec2(0.0);
uniform float camera_zoom = 1.0;
uniform vec2 view_size = vec2(720.0, 1280.0);
uniform vec4 moss_dark : source_color = vec4(0.043, 0.088, 0.074, 1.0);
uniform vec4 moss_mid : source_color = vec4(0.068, 0.145, 0.115, 1.0);
uniform vec4 canopy_glow : source_color = vec4(0.22, 0.58, 0.48, 1.0);

uniform sampler2D floor_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D floor_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D floor_ao : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D floor_light : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float floor_strength = 0.0;
uniform float floor_tile_px = 1024.0;
uniform float floor_macro_scale = 7.0;
uniform float floor_mean = 0.08;
uniform float floor_ao_mean = 0.80;
uniform float floor_relief = 0.0;
uniform float floor_occlusion = 0.0;
uniform float floor_sheen = 0.09;
uniform float floor_dapple = 0.0;
uniform float floor_light_mean = 0.51;
uniform float floor_light_scale = 1.45;
uniform float floor_light_sway = 42.0;
uniform float floor_mist = 0.0;
uniform vec4 mist_tint : source_color = vec4(0.055, 0.105, 0.115, 1.0);

// Aerial perspective. The forest has no edge, so the ground does not stop at a
// drawn line: it recedes into the haze that always hangs under a closed canopy.
// `world_offset` is the player, so `world_span` alone is the distance from them —
// this is a radial falloff around the camera, not around the world origin.
uniform float floor_fog = 0.0;
uniform float floor_fog_start = 620.0;
uniform float floor_fog_end = 1500.0;
uniform vec4 fog_tint : source_color = vec4(0.042, 0.086, 0.098, 1.0);

// Growth, 0..1 from the slime's stage. The floor is where the player spends the
// whole run looking, so the ground itself has to answer: the moss warms from cold
// cave green to sunlit gold-green and starts to breathe a faint glow from its own
// lit patches. This is a tint and an additive term, not new geometry — the floor
// has no chunks to rebuild and no extra draw call.
uniform float growth = 0.0;
uniform vec3 growth_warm = vec3(1.22, 1.18, 0.86);
uniform vec3 growth_glow = vec3(0.26, 0.36, 0.12);
uniform vec3 beam_warm = vec3(1.0, 0.90, 0.58);

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

	// Soft diagonal enchanted sunbeams. One broad sine was the first attempt and it
	// read as a yellow blob at high growth: a shaft has to be a narrow streak, and
	// it has to be broken up by the canopy, so the pattern is sharpened (pow 5) and
	// then masked by a slow noise field.
	float beam_raw = sin((wp.x * 1.55 + wp.y * 0.55) + TIME * 0.10);
	float beam = pow(max(beam_raw, 0.0), 5.0);
	beam *= 0.12 + 0.88 * smoothstep(0.34, 0.86, value_noise(wp * 1.25 + vec2(TIME * 0.015, 0.0)));

	vec3 col = mix(moss_dark.rgb, moss_mid.rgb, patch);
	// Sunbeams through the canopy. They start as a faint cool wash and become the
	// main light source of the late stages: by stage 15 the floor is read as
	// sunlit rather than as a cave, which is the single cheapest way to say "the
	// forest woke up" without adding geometry.
	vec3 beam_col = mix(canopy_glow.rgb, beam_warm, growth);
	col += beam_col * beam * (0.30 + growth * 0.55);

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

		if (floor_dapple > 0.01) {
			// The canopy shadow, one repeat every few floor tiles. Two sines instead
			// of a straight drift: sliding the pattern steadily in one direction
			// reads as the ground moving, while an offset that returns reads as the
			// leaves moving.
			vec2 sway = vec2(sin(TIME * 0.17), cos(TIME * 0.11)) * floor_light_sway;
			vec2 luv = (world_px + sway) / (floor_tile_px * max(1.01, floor_light_scale));
			float lit = texture(floor_light, luv).r;
			// Divided by the tile's mean so the average light level is unchanged and
			// only the variation is added; clamped so the darkest gaps stay readable.
			col *= mix(1.0, clamp(lit / max(0.05, floor_light_mean), 0.34, 1.75),
				floor_dapple * floor_strength);

			if (floor_mist > 0.01) {
				// Haze in the shade, from the same mask. A forest floor never goes
				// black between the light patches: humidity catches the ambient light
				// there. Lifting the darkest areas with a cool tint instead of a plain
				// multiply is what stops the dapple reading as dirt stains, and it also
				// keeps small creatures visible in the shadows.
				float shade = 1.0 - clamp(lit / max(0.05, floor_light_mean), 0.0, 1.0);
				col += mist_tint.rgb * shade * floor_mist * floor_strength;
			}
		}
	}

	if (floor_fog > 0.001) {
		// Distance from the player in world pixels. The floor texture scrolls with
		// `world_offset`, so this offset is the one thing on the floor that stays
		// anchored to the camera — which is exactly what a fog wants.
		vec2 rel = (UV - vec2(0.5)) * world_span;
		float fog_d = length(rel);
		float fog_f = smoothstep(floor_fog_start, floor_fog_end, fog_d) * floor_fog;
		// Mixed, not multiplied: distance haze adds light that is in the air, so the
		// far field settles at the tint instead of fading to black. That is what
		// reads as "the forest keeps going" rather than "the light runs out".
		col = mix(col, fog_tint.rgb, fog_f);
	}

	// Gentle readability vignette on phone edges
	vec2 vuv = UV - vec2(0.5);
	float vig = 1.0 - dot(vuv, vuv) * 0.42;

	if (growth > 0.001) {
		// Warm the moss, then let the lit patches carry a little of the slime's
		// own light. The glow term is scaled by `patch` so it follows the ground's
		// tonal structure instead of fogging the whole screen evenly.
		col *= mix(vec3(1.0), growth_warm, growth * 0.85);
		col += growth_glow * patch * growth * 0.060;
		// The vignette opens up as the forest awakens: a growing slime should not
		// still be standing in a dark tunnel.
		vig = mix(vig, 1.0 - dot(vuv, vuv) * 0.22, growth);
	}

	COLOR = vec4(col * clamp(vig, 0.68, 1.0), 1.0);
}

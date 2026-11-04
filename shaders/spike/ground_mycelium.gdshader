shader_type spatial;
// PHASE 2 render spike: forest floor of the "Moonlit Mycelium" direction.
// Uses a noise texture (generated on the CPU) instead of per-pixel procedural
// noise so the fragment cost stays representative for a phone.
render_mode cull_back, specular_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Palette sampled from the approved concept (B_open_glade_gameplay_screen).
uniform vec3 soil_color : source_color = vec3(0.13, 0.16, 0.18);
uniform vec3 soil_light : source_color = vec3(0.24, 0.28, 0.29);
uniform vec3 moss_color : source_color = vec3(0.09, 0.15, 0.1);
uniform vec3 vein_color : source_color = vec3(0.37, 0.94, 0.88);
uniform float vein_strength : hint_range(0.0, 3.0) = 1.0;
uniform float uv_scale = 0.11;
uniform float glade_radius = 9.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * uv_scale;
	vec4 n1 = texture(noise_tex, p);
	vec4 n2 = texture(noise_tex, p * 3.7 + vec2(0.31, 0.77));
	float soil_mix = smoothstep(0.3, 0.75, n1.r * 0.6 + n2.g * 0.4);
	vec3 col = mix(soil_color, soil_light, soil_mix);
	// Concept: a lighter, worn soil path in the open centre, mossy towards the
	// decor at the edges, with fine moss grain everywhere.
	float r_open = length(world_pos.xz);
	float path = 1.0 - smoothstep(0.9, 2.6, r_open);
	float moss = smoothstep(0.6, 0.72, n1.g * 0.8 + n2.r * 0.3);
	moss = max(moss, smoothstep(1.4, 3.2, r_open) * smoothstep(0.35, 0.6, n2.r));
	moss *= 1.0 - 0.6 * path;
	vec4 n3 = texture(noise_tex, p * 14.0 + vec2(0.13, 0.41));
	float grain = n3.r * 0.55 + n3.g * 0.45;
	col = mix(col, moss_color * (0.7 + 0.6 * grain), moss * 0.9);
	col *= 0.82 + 0.3 * grain;
	col = mix(col, soil_light * 1.05, path * 0.25);

	// Sparse mycelium threads: thin iso-lines, only in a few patches near moss.
	float iso = abs(fract(n2.b * 3.0) - 0.5);
	float vein = (1.0 - smoothstep(0.006, 0.026, iso)) * smoothstep(0.56, 0.7, n1.b);
	vein *= 0.1 + 0.9 * moss;

	// Glade edge darkens softly; the centre stays readable.
	float r = length(world_pos.xz) / glade_radius;
	col *= mix(1.0, 0.55, smoothstep(0.75, 1.15, r));

	ALBEDO = col;
	ROUGHNESS = 0.92;
	EMISSION = vein_color * vein * vein_strength * 0.6;
}

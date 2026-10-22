shader_type canvas_item;

uniform vec2 world_offset = vec2(0.0);
uniform vec4 moss_dark : source_color = vec4(0.06, 0.13, 0.16, 1.0);
uniform vec4 moss_mid : source_color = vec4(0.09, 0.21, 0.22, 1.0);
uniform vec4 canopy_glow : source_color = vec4(0.22, 0.58, 0.48, 1.0);

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
	vec2 wp = (UV * vec2(720.0, 1280.0) + world_offset) * 0.0045;
	float n1 = value_noise(wp);
	float n2 = value_noise(wp * 2.3 + vec2(4.2, -1.7));
	float patch = smoothstep(0.28, 0.78, n1 * 0.65 + n2 * 0.35);

	// Soft diagonal enchanted sunbeams
	float beam = sin((wp.x * 1.4 + wp.y * 0.8) + TIME * 0.25) * 0.5 + 0.5;
	beam = pow(beam, 4.0) * 0.14;

	vec3 col = mix(moss_dark.rgb, moss_mid.rgb, patch);
	col += canopy_glow.rgb * beam;

	// Gentle readability vignette on phone edges
	vec2 vuv = UV - vec2(0.5);
	float vig = 1.0 - dot(vuv, vuv) * 0.42;
	COLOR = vec4(col * clamp(vig, 0.68, 1.0), 1.0);
}

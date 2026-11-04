shader_type spatial;
// PHASE 2 render spike: shallow moonlit pool. Cheap: no screen texture reads.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 deep_color : source_color = vec3(0.10, 0.16, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.45, 0.62);
uniform vec3 moon_color : source_color = vec3(0.78, 0.86, 1.0);
uniform float ripple_t = 0.0;
uniform vec2 ripple_center = vec2(0.0);

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

void fragment() {
	float edge = length(local_xz);
	float d = distance(local_xz, ripple_center);
	float ring = sin(d * 18.0 - TIME * 3.0) * 0.5 + 0.5;
	float ring_mask = (1.0 - smoothstep(0.0, 0.9, d)) * 0.35 + exp(-abs(d - ripple_t) * 12.0) * step(0.001, ripple_t);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, smoothstep(1.0, 0.3, edge));
	EMISSION = moon_color * (ring * ring_mask * 0.25 + fres * 0.35);
	ALPHA = mix(0.55, 0.9, fres) * (1.0 - smoothstep(0.92, 1.0, edge));
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
}

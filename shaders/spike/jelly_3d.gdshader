shader_type spatial;
// PHASE 2 render spike: translucent jelly dome for the hero slime.
// Mesh: unit hemisphere (base radius 1 on y = 0). The node is scaled by the
// gameplay radius, so the visible footprint equals the 2D collision circle.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Mint-cyan sampled from the approved concept (#8ddee4 body, #83e5eb glow).
uniform vec3 body_color : source_color = vec3(0.50, 0.88, 0.90);
uniform vec3 rim_color : source_color = vec3(0.82, 0.99, 0.98);
uniform float alpha_center : hint_range(0.0, 1.0) = 0.62;
uniform float alpha_rim : hint_range(0.0, 1.0) = 0.9;
uniform float glow : hint_range(0.0, 2.0) = 0.3;
// Local-space movement direction (xz) and stretch amount 0..0.6.
uniform vec2 stretch_dir = vec2(0.0, -1.0);
uniform float stretch : hint_range(0.0, 0.8) = 0.0;
// Absorption impulse 0..1 (decays on the CPU) and local entry direction.
uniform float gulp : hint_range(0.0, 1.0) = 0.0;
uniform vec3 gulp_dir = vec3(0.0, 0.3, -1.0);
uniform float breath_speed = 1.6;
// Concept: light pools in the lower body around the core.
uniform float bottom_glow : hint_range(0.0, 2.0) = 0.55;
uniform float model_height = 1.55;

varying float local_h;

void vertex() {
	local_h = clamp(VERTEX.y / model_height, 0.0, 1.0);
	vec3 v = VERTEX;
	float breath = sin(TIME * breath_speed) * 0.035;
	v.y *= 1.0 + breath;
	v.xz *= 1.0 - breath * 0.5;

	if (stretch > 0.001) {
		vec3 d = normalize(vec3(stretch_dir.x, 0.0, stretch_dir.y));
		float along = dot(v, d);
		vec3 side = vec3(v.x, 0.0, v.z) - d * along;
		// Front leads, back trails: elongate with a forward bias, keep volume.
		v += d * along * stretch + d * stretch * 0.12;
		v -= side * stretch * 0.22;
		v.y *= 1.0 - stretch * 0.38;
	}

	if (gulp > 0.001) {
		float dist = distance(normalize(VERTEX + vec3(0.0, 0.001, 0.0)), normalize(gulp_dir));
		v += NORMAL * gulp * 0.07 * sin(dist * 9.0 - TIME * 16.0);
		v -= NORMAL * gulp * 0.16 * smoothstep(0.7, 0.0, dist);
	}

	v.y = max(v.y, 0.0);
	VERTEX = v;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 2.4);
	ALBEDO = mix(body_color * 0.8, rim_color, fres * 0.6);
	ALPHA = mix(alpha_center, alpha_rim, fres);
	EMISSION = body_color * glow + rim_color * fres * 0.4 + body_color * bottom_glow * (1.0 - smoothstep(0.0, 0.55, local_h));
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.05;
}

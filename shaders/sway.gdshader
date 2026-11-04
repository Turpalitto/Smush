shader_type canvas_item;
// Wind rustle for painted props: the top of the sprite moves, the base stays planted.
// Phase comes from the world position, so one shared material serves every prop.

uniform float amount = 6.0;       // sway in world px at the very top
uniform float speed = 1.1;
uniform vec2 slime_pos = vec2(1.0e6);
uniform float part_radius = 150.0;  // how far the slime parts the leaves
uniform float part_push = 18.0;     // how hard

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xy;
	float h = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.6);
	float t = TIME * speed + origin.x * 0.013 + origin.y * 0.009;
	float wind = sin(t) + 0.45 * sin(t * 2.3 + 1.7);
	vec2 away = origin - slime_pos;
	float d = length(away);
	float near = smoothstep(part_radius, 0.0, d);
	float push = near * part_push * sign(away.x + 0.001);
	VERTEX.x += (wind * amount + push) * h;
}

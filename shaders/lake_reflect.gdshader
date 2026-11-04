shader_type canvas_item;
// Fake reflection: the flipped sprite below the waterline, wobbling sideways and fading with distance.

uniform float wobble = 2.2;
uniform float strength = 0.5;

void vertex() {
	VERTEX.x += sin(VERTEX.y * 0.16 + TIME * 1.7) * wobble;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// flipped sprite: UV.y = 1 (the feet) sits at the waterline, so reflect strongest there
	float fade = smoothstep(0.0, 1.0, UV.y) * strength;
	COLOR = vec4(c.rgb * vec3(0.7, 0.85, 1.1), c.a * fade);
}

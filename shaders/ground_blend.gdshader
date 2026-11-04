shader_type canvas_item;
// Ground plates of neighbouring biomes overlap; the upper plate fades out along
// its lower edge so the biomes melt into each other instead of meeting at a seam.
uniform float fade : hint_range(0.01, 0.5) = 0.18;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= smoothstep(0.0, fade, 1.0 - UV.y);
	COLOR = c;
}

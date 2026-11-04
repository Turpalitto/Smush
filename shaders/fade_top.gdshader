shader_type canvas_item;
// A painted plate whose upper edge melts into whatever lies above it (the dewy glade into the flooded grove).

uniform float fade = 0.38;   // fraction of the plate height over which it fades in

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb, c.a * smoothstep(0.0, fade, UV.y));
}

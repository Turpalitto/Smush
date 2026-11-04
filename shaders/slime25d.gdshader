shader_type canvas_item;
// Recolours the painted jelly toward the growth-stage body colour while keeping
// its white highlights, eyes and blush: only saturated pixels are pulled to the tint.
uniform vec4 tint : source_color = vec4(0.55, 0.87, 0.9, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.001);
	vec3 t = clamp(tint.rgb * (0.30 + 1.15 * luma), 0.0, 1.0);
	float w = amount * smoothstep(0.10, 0.42, sat);
	COLOR = vec4(mix(c.rgb, t, w), c.a);
}

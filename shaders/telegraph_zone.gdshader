shader_type canvas_item;

uniform vec4 warn_color : source_color = vec4(1.0, 0.26, 0.36, 0.72);
uniform float progress : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	if (d > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float border = smoothstep(0.90, 0.98, d);
		float fill_wave = step(d, progress) * 0.36;
		float base_fill = 0.14;
		float alpha = clamp(border * 0.95 + fill_wave + base_fill, 0.0, 1.0) * warn_color.a;
		COLOR = vec4(warn_color.rgb, alpha);
	}
}

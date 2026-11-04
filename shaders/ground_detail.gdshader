shader_type canvas_item;
// Ground plate + tiled high-pass detail. The painted plate carries the composition
// (path, moss density, edges); a seamless detail tile in world space adds the fine
// leaf-level texture, so the floor stays crisp at phone resolution without a
// multi-megapixel plate. `fade` melts the lower edge into the biome below.
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_world = 300.0;
uniform float strength : hint_range(0.0, 3.0) = 1.3;
uniform float fade : hint_range(0.0, 0.5) = 0.0;
varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 d = texture(detail, wpos / tile_world).rgb - vec3(0.5);
	// detail shows in the mids; deep shadows and highlights keep the painted plate.
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float mid = smoothstep(0.02, 0.2, luma) * (1.0 - smoothstep(0.7, 0.95, luma));
	c.rgb += d * strength * mid;
	if (fade > 0.0) {
		c.a *= smoothstep(0.0, fade, 1.0 - UV.y);
	}
	COLOR = c;
}

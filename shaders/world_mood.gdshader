shader_type canvas_item;
render_mode unshaded;

// Screen-space grade that makes the forest answer the slime's growth.
//
// This is the one place where growth is allowed to touch every pixel on screen:
// the floor, the props, the enemies and the slime all pass through it, so the
// world reads as a single lit place instead of a pile of independently tinted
// sprites. Everything here is a function of a handful of uniforms that
// WorldMood.gd drives from EvolutionStages, so the grade interpolates smoothly
// between the fifteen stages instead of switching palettes.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Stage hue, blended in as a gentle multiply. Zero at stage 1.
uniform vec3 tint : source_color = vec3(0.42, 0.96, 0.86);
uniform float tint_amount : hint_range(0.0, 0.6) = 0.0;

// Light cast by the slime itself, as a radial falloff around player_uv.
uniform vec3 warm : source_color = vec3(1.0, 0.88, 0.62);
uniform float warm_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 player_uv = vec2(0.5, 0.5);
uniform float aura_radius : hint_range(0.05, 1.5) = 0.42;

uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float lift : hint_range(0.0, 0.25) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;

// Slow breathing of the aura so the light is alive rather than a static lamp.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

// One-shot shockwave of light from the slime, fired when a growth stage opens.
// Decays in WorldMood.gd; 0 in the steady state.
uniform vec3 flash_color : source_color = vec3(1.0, 0.95, 0.75);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);

	// Multiply toward the stage hue. A plain mix toward a flat colour would grey
	// out the blacks, so the tint scales the image instead of replacing it.
	c = mix(c, c * tint * 1.55, tint_amount);

	// Radial light around the slime. The 1.78 vertical factor turns the ellipse
	// into a circle on a 720x1280 portrait screen.
	vec2 d = (SCREEN_UV - player_uv) * vec2(1.0, 1.78);
	float r = length(d) / max(aura_radius, 0.001);
	// Ring, not a blob: the light is *around* the slime. A plain falloff peaks on
	// the character, and at stage 15 that pushed an already-bright body to pure
	// white — measured on a capture, not guessed.
	float ring = smoothstep(0.10, 0.55, r);
	float glow = exp(-r * r * 1.55) * ring * (0.82 + 0.18 * pulse);
	c += warm * glow * warm_amount * 0.62;

	// The stage-up pulse rides the same radial term but is wider and hotter, so it
	// reads as something leaving the slime rather than as the screen brightening.
	if (flash > 0.001) {
		float wave = exp(-r * r * 0.9);
		c += flash_color * wave * flash * 0.55;
	}

	// Lift only the shadows: the deep floor keeps its detail while the whole
	// image gains the milky, dreamlike quality the late stages are going for.
	c += vec3(lift) * (1.0 - smoothstep(0.0, 0.55, l));

	vec2 v = SCREEN_UV - vec2(0.5);
	float vd = length(v * vec2(1.0, 1.3));
	c *= 1.0 - vignette * smoothstep(0.34, 0.98, vd);

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}

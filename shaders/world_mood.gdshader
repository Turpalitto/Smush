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

// Dream bloom: a halo gathered from the mip chain of the screen texture.
//
// Cheaper than a second pass and cheaper than a viewport blur: the mip levels of
// `screen_tex` are already a progressive blur of the frame, so sampling two of them
// at increasing coarseness gives a wide, soft halo for the price of two texture
// fetches. The threshold is what keeps it from being fog: only pixels that are
// already luminous contribute, so the dark moss stays dark and the halo belongs to
// the crown, the runes, the orbs and the flowers rather than to the whole image.
uniform float dream_bloom : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dream_tint : source_color = vec3(1.0, 0.93, 0.78);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);

	// Multiply toward the stage hue. A plain mix toward a flat colour would grey
	// out the blacks, so the tint scales the image instead of replacing it.
	//
	// A luminance-weighted split-tone (warm the lights, cool the shadows) was tried
	// here and reverted: measured on mass-104 captures, the shadow bucket already
	// had G-R = +0.067 before the change and +0.067 after, and every channel mean
	// moved by about 0.01. The flat multiply was never washing the moss out, so the
	// extra code bought nothing measurable.
	c = mix(c, c * tint * 1.55, tint_amount);

	// Gentle slow ambient forest breath (~52 s period): harmonizes with forest_breath.ogg
	float breath_cycle = sin(TIME * 0.12) * 0.5 + 0.5;
	vec3 breath_shift = mix(vec3(0.97, 1.02, 1.03), vec3(1.03, 1.01, 0.97), breath_cycle);
	c *= mix(vec3(1.0), breath_shift, 0.35);

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

	// Volumetric sunshafts (god rays) streaming down through the canopy haze
	vec2 ray_uv = vec2(SCREEN_UV.x * 1.55 + SCREEN_UV.y * 0.85, SCREEN_UV.y * 0.45);
	float r1 = sin(ray_uv.x * 5.4 + TIME * 0.08) * 0.5 + 0.5;
	float r2 = sin(ray_uv.x * 10.2 - TIME * 0.11) * 0.5 + 0.5;
	float r3 = sin((SCREEN_UV.x * 2.2 - SCREEN_UV.y * 1.3) * 3.2 + TIME * 0.05) * 0.5 + 0.5;
	float ray_shafts = pow(r1 * r2, 2.4) * (0.68 + 0.32 * r3);
	float ray_fade = smoothstep(0.96, 0.12, SCREEN_UV.y);
	vec3 ray_color = mix(vec3(0.52, 0.94, 0.82), vec3(1.0, 0.94, 0.68), clamp(warm_amount * 0.75 + tint_amount * 0.45, 0.0, 1.0));
	c += ray_color * ray_shafts * ray_fade * 0.068;

	if (dream_bloom > 0.001) {
		vec3 b1 = textureLod(screen_tex, SCREEN_UV, 2.2).rgb;
		vec3 b2 = textureLod(screen_tex, SCREEN_UV, 3.4).rgb;
		float m1 = smoothstep(0.55, 1.15, dot(b1, vec3(0.2126, 0.7152, 0.0722)));
		float m2 = smoothstep(0.55, 1.15, dot(b2, vec3(0.2126, 0.7152, 0.0722)));
		vec3 bloom = b1 * m1 * 0.55 + b2 * m2 * 0.85;
		// Humid air scatters warm, so the halo is pushed toward the dream tint
		// rather than left neutral - a neutral halo reads as a lens artefact.
		bloom = mix(bloom, bloom * dream_tint, 0.55);
		// Protect the body. On the cream stages the slime is already near white, and
		// adding bloom on top of it clips the whole body into one flat disc - the
		// exact failure the regalia work already fixed twice. Where the source pixel
		// is that bright the halo is suppressed; the glow AROUND the body comes from
		// the mip bleeding into darker neighbours and is unaffected.
		float protect = 1.0 - smoothstep(0.86, 1.0, l);
		c += bloom * dream_bloom * protect;
	}

	vec2 v = SCREEN_UV - vec2(0.5);
	float vd = length(v * vec2(1.0, 1.3));
	c *= 1.0 - vignette * smoothstep(0.34, 0.98, vd);

	// Soft highlight shoulder prevents high-stage warm aura + dream bloom from
	// clipping bright petals and regalia into flat white while keeping midtones untouched.
	vec3 hi = max(c - vec3(0.72), vec3(0.0));
	c = min(c, vec3(0.72)) + hi / (vec3(1.0) + hi * 2.2);

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}

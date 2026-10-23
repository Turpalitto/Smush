shader_type canvas_item;
// Frosted glass for the mutation draft.
//
// The draft used to sit under a flat Color(0.02, 0.06, 0.08, 0.80) wash, which
// erased the forest completely: the player was choosing a mutation for a world
// that had disappeared behind a grey rectangle. This shader keeps the world
// visible but pushes it behind glass — a 13-tap blur, a cool tint, a vignette,
// a diagonal sheen and a faint bevel at the pane edge.
//
// The pane is opaque (the quad writes alpha 1); what survives of the world is
// `transmission`. That distinction is the whole point: an alpha-blended tint
// lets sharp forest detail straight through, while a frosted pane scatters it
// first, so the cards read as objects lying ON a surface instead of stickers
// floating over the level.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float blur_px : hint_range(0.0, 40.0) = 14.0;
uniform float transmission : hint_range(0.0, 1.0) = 0.30;
uniform vec4 glass_tint : source_color = vec4(0.030, 0.078, 0.098, 1.0);
uniform float frost_lift : hint_range(0.0, 0.30) = 0.012;
uniform float vignette : hint_range(0.0, 1.0) = 0.44;
uniform float sheen : hint_range(0.0, 0.25) = 0.050;
uniform float bevel : hint_range(0.0, 0.50) = 0.10;
uniform float grain : hint_range(0.0, 0.05) = 0.010;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 t = SCREEN_PIXEL_SIZE * blur_px;

	// Centre, four axis taps at full radius, four diagonal taps at 0.70 and four
	// axis taps at 1.90. Thirteen samples: enough to dissolve foliage detail and
	// HUD text without the eight-fold ring artefact a single sparse ring leaves
	// on high-contrast edges, and cheap enough to run while the game is paused.
	vec3 acc = texture(screen_tex, uv).rgb * 0.200;
	acc += (texture(screen_tex, uv + vec2( t.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(-t.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0,  t.y)).rgb
		+ texture(screen_tex, uv + vec2(0.0, -t.y)).rgb) * 0.115;
	acc += (texture(screen_tex, uv + t * vec2( 0.70,  0.70)).rgb
		+ texture(screen_tex, uv + t * vec2(-0.70,  0.70)).rgb
		+ texture(screen_tex, uv + t * vec2( 0.70, -0.70)).rgb
		+ texture(screen_tex, uv + t * vec2(-0.70, -0.70)).rgb) * 0.062;
	acc += (texture(screen_tex, uv + vec2( t.x * 1.9, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(-t.x * 1.9, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0,  t.y * 1.9)).rgb
		+ texture(screen_tex, uv + vec2(0.0, -t.y * 1.9)).rgb) * 0.028;
	vec3 blurred = acc / 1.020;

	// Frosted glass scatters, so it loses contrast rather than gaining brightness:
	// the world behind is pulled toward a cool, dim version of itself. Adding a
	// flat lift here instead turned every bloom sprite into a grey cloud, because
	// the lift is an absolute amount and the sprites are already the brightest
	// thing on screen.
	float luma = dot(blurred, vec3(0.299, 0.587, 0.114));
	vec3 milk = mix(blurred, vec3(luma) * vec3(0.62, 0.90, 0.86), 0.42) * 0.82;
	milk += vec3(frost_lift * 0.55, frost_lift * 1.00, frost_lift * 1.10);
	vec3 col = mix(glass_tint.rgb, milk, transmission);

	// The pane is lit from above-left, so the corners fall away from the light.
	vec2 c = (uv - 0.5) * vec2(1.0, 0.82);
	col *= 1.0 - vignette * smoothstep(0.26, 0.84, length(c));

	// A diagonal sheen across the upper-left of the pane. This is the only cue
	// that says "there is a surface here" when the forest behind is already dark.
	float s = dot(uv, vec2(0.55, 0.84));
	col += vec3(0.55, 0.86, 0.92) * sheen * smoothstep(0.62, 0.05, s);

	// Bevel: a thin lit rim at the very edge of the pane, so the glass has a
	// boundary instead of fading into the screen border.
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	col += vec3(0.40, 0.82, 0.80) * bevel * smoothstep(0.055, 0.0, edge);

	// A whisper of grain. A large flat tint bands visibly on an 8-bit phone
	// panel; the noise costs one hash and hides the steps.
	col += (hash21(uv * vec2(1920.0, 1080.0)) - 0.5) * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}

shader_type canvas_item;

uniform vec4 body_color : source_color = vec4(0.13, 0.82, 0.66, 0.90);
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.50, 0.95);
uniform vec4 rim_color : source_color = vec4(0.65, 1.0, 0.91, 1.0);
uniform float wobble_speed : hint_range(0.5, 12.0) = 4.2;
uniform float wobble_amount : hint_range(0.0, 0.12) = 0.032;
uniform float pulse_phase : hint_range(0.0, 6.283) = 0.0;
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;
uniform float stealth_alpha : hint_range(0.25, 1.0) = 1.0;
uniform float evolution_glow : hint_range(0.0, 1.0) = 0.0;
// Growth ladder: stage_glow rises with the stage (0..0.72) and stage_t is the
// continuous position 0..1. Both drive the body's own detail, so the character
// reads as "richer" at every step even where no ornament is drawn yet.
uniform float stage_glow : hint_range(0.0, 1.0) = 0.0;
uniform float stage_t : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// One layer of stars on a jittered lattice. A lattice, not free noise: free noise
// clumps, and a clumped field inside a 40 px body reads as dirt rather than as sky.
// `keep` is the fraction of cells that carry a star.
float star_layer(vec2 p, float keep) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - vec2(0.5);
	float h = hash21(cell);
	if (h > keep) {
		return 0.0;
	}
	vec2 jitter = vec2(hash21(cell + vec2(3.7, 1.3)), hash21(cell + vec2(9.1, 5.5))) - vec2(0.5);
	float d = length(f - jitter * 0.62);
	// Twinkle at a rate taken from the cell's own hash, so the field does not pulse
	// in unison.
	float twinkle = 0.62 + 0.38 * sin(TIME * 1.7 + h * 43.0);
	return smoothstep(0.24, 0.0, d) * twinkle;
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float angle = atan(centered.y, centered.x);
	float dist = length(centered);

	float wave = sin(angle * 5.0 + TIME * wobble_speed + pulse_phase) * wobble_amount
		+ cos(angle * 3.0 - TIME * wobble_speed * 0.7) * (wobble_amount * 0.6);
	float r = dist + wave;

	if (r > 0.95) {
		COLOR = vec4(0.0);
	} else {
		float edge = smoothstep(0.95, 0.84, r);
		// Two separate bands. A bright rim *inside* the silhouette and a thin dark
		// contour at the very edge: the glass-bead read. The old code mixed straight
		// toward rim_color up to r=0.90, which at stages 13-15 (near-white rim, pale
		// gold body) meant the slime had no outline at all and dissolved into the
		// moss. Measured on reports/growth-ladder before this change.
		float rim = smoothstep(0.52, 0.72, r) * smoothstep(0.835, 0.775, r);
		float contour = smoothstep(0.795, 0.858, r) * smoothstep(0.928, 0.882, r);
		float core_pulse = 0.34 + 0.05 * sin(TIME * 3.8 + pulse_phase);
		float core_mask = smoothstep(core_pulse + 0.22, 0.04, length(centered - vec2(0.0, 0.05)));

		// Body luminance decides which way "detail" goes. On a dark jelly the
		// interior reads as light, and every term here used to add light. On the
		// cream stages that meant the spiral bands, the nucleus and the membrane
		// halo were all white-on-cream: the body measured as a flat disc with two
		// eyes, which is what the stage-15 gameplay frame showed. So the detail
		// colour flips to a deeper shade of the body's own hue on light bodies, and
		// the terms MIX toward it instead of adding to it, so the same code reads as
		// "currents inside the jelly" at both ends of the ladder.
		float body_lum = dot(body_color.rgb, vec3(0.2126, 0.7152, 0.0722));
		float light_body = smoothstep(0.58, 0.82, body_lum);
		vec3 detail = mix(core_color.rgb, body_color.rgb * 0.52, light_body);

		// Top-left glossy jelly highlight
		float spec = smoothstep(0.28, 0.08, length(centered - vec2(-0.28, -0.32))) * 0.42;

		vec3 col = mix(body_color.rgb, rim_color.rgb, rim * 0.60);
		col = mix(col, body_color.rgb * 0.40, contour * 0.62);
		col = mix(col, detail, core_mask * 0.72);
		col += vec3(spec);
		col = mix(col, vec3(1.0, 0.32, 0.38), hurt_flash * 0.75);
		col += vec3(0.35, 1.0, 0.82) * evolution_glow * 0.55;

		// Growth detail. A slow spiral of soft bands inside the jelly: at stage 1 it
		// is invisible, by stage 15 the body looks like it has currents running
		// through it. Kept low-contrast on purpose — the slime must still read as
		// one clean silhouette at a glance during a fight.
		float spiral = sin(angle * 2.0 + dist * 14.0 - TIME * 1.1) * 0.5 + 0.5;
		float bands = smoothstep(0.35, 0.95, spiral) * smoothstep(0.92, 0.35, r);
		col = mix(col, detail, bands * stage_glow * 0.26);

		// Outer halo hugging the membrane, so the body glows instead of being
		// outlined. This is the cheap part of the "magical" read. It is additive, so
		// on a light body it can only brighten something that is already bright;
		// there it is faded out and the contour does the work instead.
		float halo = smoothstep(0.95, 0.62, r) * smoothstep(0.55, 0.90, r);
		col += rim_color.rgb * halo * stage_glow * 0.20 * (1.0 - 0.9 * light_body);

		// --- inner cosmos ---------------------------------------------------------
		// Two parallax layers of stars inside the jelly. The body is the one thing on
		// screen the player never stops looking at, so the "magical" read has to come
		// from inside it and not only from the aura around it. The near layer is
		// larger, brighter and drifts faster than the far one; that difference is the
		// whole effect — one scrolling layer reads as a texture, two read as depth.
		//
		// Anchored to the body's own frame (centered), so the sky turns with the
		// slime instead of sliding across it, and faded in with stage_glow: at stage
		// 1 there is no cosmos, by stage 8 the body is a small window.
		vec2 sky = centered * 1.55;
		float near_stars = star_layer(sky * 2.35 + vec2(TIME * 0.055, TIME * 0.021), 0.34);
		float far_stars = star_layer(sky * 1.05 - vec2(TIME * 0.018, TIME * 0.030), 0.20);
		float cosmos = (near_stars * 0.85 + far_stars * 0.55)
			* smoothstep(0.94, 0.50, r) * smoothstep(0.10, 0.42, stage_glow);
		// Mixed, not added: an additive star is invisible on the cream stages, so the
		// star colour has to flip to a deep shade of the body's own hue there and the
		// constellation reads as dark pinpricks instead. The flip is keyed on the
		// body's luminance and not on `light_body`: that ramp starts at 0.58, and the
		// stage-11 lavender body measures 0.56 — it fell on the "dark" side and got
		// white stars, which is why the first version of this block was invisible on
		// exactly the stages it was written for.
		float star_dark = smoothstep(0.36, 0.50, body_lum);
		vec3 star_col = mix(vec3(1.0, 0.99, 0.92), body_color.rgb * 0.18, star_dark);
		col = mix(col, star_col, cosmos * 0.95);

		float alpha = edge * body_color.a * stealth_alpha;
		COLOR = vec4(col, alpha);
	}
}

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

		float alpha = edge * body_color.a * stealth_alpha;
		COLOR = vec4(col, alpha);
	}
}

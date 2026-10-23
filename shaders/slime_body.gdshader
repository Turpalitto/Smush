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
		float rim = smoothstep(0.62, 0.90, r);
		float core_pulse = 0.34 + 0.05 * sin(TIME * 3.8 + pulse_phase);
		float core_mask = smoothstep(core_pulse + 0.22, 0.04, length(centered - vec2(0.0, 0.05)));

		// Top-left glossy jelly highlight
		float spec = smoothstep(0.28, 0.08, length(centered - vec2(-0.28, -0.32))) * 0.42;

		vec3 col = mix(body_color.rgb, rim_color.rgb, rim * 0.55);
		col = mix(col, core_color.rgb, core_mask * 0.72);
		col += vec3(spec);
		col = mix(col, vec3(1.0, 0.32, 0.38), hurt_flash * 0.75);
		col += vec3(0.35, 1.0, 0.82) * evolution_glow * 0.55;

		// Growth detail. A slow spiral of soft bands inside the jelly: at stage 1 it
		// is invisible, by stage 15 the body looks like it has currents running
		// through it. Kept low-contrast on purpose — the slime must still read as
		// one clean silhouette at a glance during a fight.
		float spiral = sin(angle * 2.0 + dist * 14.0 - TIME * 1.1) * 0.5 + 0.5;
		float bands = smoothstep(0.35, 0.95, spiral) * smoothstep(0.92, 0.35, r);
		col += core_color.rgb * bands * stage_glow * 0.16;

		// Outer halo hugging the membrane, so the body glows instead of being
		// outlined. This is the cheap part of the "magical" read.
		float halo = smoothstep(0.95, 0.62, r) * smoothstep(0.55, 0.90, r);
		col += rim_color.rgb * halo * stage_glow * 0.20;

		float alpha = edge * body_color.a * stealth_alpha;
		COLOR = vec4(col, alpha);
	}
}

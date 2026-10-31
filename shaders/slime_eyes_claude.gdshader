shader_type canvas_item;
// CLAUDE VISUAL CHALLENGE V8 — the face. Two glossy eyes with real lids, rendered as
// analytic shapes so they stay crisp at 80 px: a dark lens, a luminous lower iris
// (tapetum), a catchlight that follows the scene light, and a jelly lid that can tilt
// (determined), droop (calm) or squeeze shut (hurt / blink). Positions arrive in
// pixels relative to this quad's centre; the CPU keeps them glued to the deforming
// body and lets them lag half as much as the interior.

uniform vec2 rect_px = vec2(100.0, 60.0);
uniform vec2 eye_a = vec2(-14.0, 0.0);
uniform vec2 eye_b = vec2(14.0, 0.0);
uniform float eye_px = 8.0;
uniform vec2 look = vec2(0.0, 0.0);
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform float tilt = 0.12;
uniform float droop : hint_range(0.0, 1.0) = 0.15;
uniform float wide : hint_range(0.0, 1.0) = 0.0;
uniform vec4 iris_col : source_color = vec4(1.0, 0.82, 0.52, 1.0);
uniform vec4 lid_col : source_color = vec4(0.42, 0.40, 0.86, 1.0);
uniform float alpha = 1.0;
uniform float energy = 0.0;

vec4 over(vec4 dst, vec3 c, float a) {
	float oa = a + dst.a * (1.0 - a);
	vec3 oc = (c * a + dst.rgb * dst.a * (1.0 - a)) / max(oa, 0.0001);
	return vec4(oc, oa);
}

vec4 eye(vec2 p, vec2 centre, float s, vec4 acc) {
	vec2 e = (p - centre) / eye_px;
	float aa = 1.2 / eye_px;
	float oval = length(vec2(e.x, e.y * 0.90));

	// Socket shadow: the eye sits INSIDE the jelly, not on it.
	float sock = smoothstep(1.75, 0.70, length(vec2(e.x, (e.y - 0.30) * 0.85)));
	acc = over(acc, vec3(0.07, 0.04, 0.22), sock * 0.30);

	// Eye lens.
	float cov = smoothstep(1.0 + aa, 1.0 - aa, oval);
	vec2 pe = e - look * 0.26;
	float pr = length(vec2(pe.x, pe.y * 0.92));
	vec3 lens = vec3(0.035, 0.025, 0.13);
	float iris_m = smoothstep(0.90, 0.60, pr);
	float low = smoothstep(-0.55, 0.85, pe.y);
	vec3 ic = iris_col.rgb * (0.10 + 0.95 * low * low) + vec3(0.10, 0.06, 0.28) * (1.0 - low) * 0.5;
	ic *= 1.0 + 0.5 * energy;
	lens = mix(lens, ic, iris_m * (0.55 + 0.25 * low));
	float pupil = smoothstep(0.43, 0.34, length(vec2(pe.x * 1.0, (pe.y + 0.05) * 0.92)));
	lens = mix(lens, vec3(0.012, 0.008, 0.045), pupil);
	float limbal = smoothstep(0.78, 0.96, oval);
	lens = mix(lens, vec3(0.02, 0.012, 0.09), limbal * 0.7);
	// wet rim light from below, opposite the key light
	lens += vec3(0.55, 0.80, 1.0) * smoothstep(0.28, 0.0, abs(length(vec2(e.x * 0.9, e.y - 0.0)) - 0.88) * 1.0) * smoothstep(0.1, 0.9, e.y * 0.8 + e.x * 0.3) * 0.22;

	// Catchlights follow the scene light (top-left).
	float big = smoothstep(0.33, 0.20, length(e - vec2(-0.34, -0.38) - look * 0.10));
	float small_c = smoothstep(0.15, 0.07, length(e - vec2(0.32, 0.34) - look * 0.05));
	float spark = smoothstep(0.07, 0.03, length(e - vec2(-0.05, -0.62)));
	lens = mix(lens, vec3(1.0), big);
	lens = mix(lens, vec3(0.80, 1.0, 0.98), small_c * 0.85);
	lens = mix(lens, vec3(1.0), spark * 0.7);

	// Lids. y grows downward, so a bigger y_lid covers more of the eye.
	float inner = -s * e.x;
	float lid_y = mix(-1.55, 0.10, blink) + tilt * inner + droop * 0.65 - wide * 0.35;
	float low_y = mix(1.55, 0.05, blink);
	float lid_cov = smoothstep(lid_y - aa * 1.2, lid_y + aa * 1.2, -e.y + 2.0 * lid_y - 0.0 * e.y);
	// (lid covers where e.y < lid_y)
	float above = 1.0 - smoothstep(lid_y - aa * 1.4, lid_y + aa * 1.4, e.y);
	float below = smoothstep(low_y - aa * 1.4, low_y + aa * 1.4, e.y);
	float shut = clamp(above + below, 0.0, 1.0);

	acc = over(acc, lens, cov * (1.0 - shut) * alpha);

	// Lid skin over the eye, with a lit edge.
	float lid_zone = smoothstep(1.12 + aa, 1.0 - aa, oval);
	vec3 lc = lid_col.rgb * (0.80 + 0.35 * smoothstep(-1.0, 1.0, -e.y));
	acc = over(acc, lc, lid_zone * shut * 0.95 * alpha);
	float edge = smoothstep(0.17, 0.0, abs(e.y - lid_y)) * smoothstep(1.08, 0.7, oval) * (1.0 - below);
	acc = over(acc, vec3(0.04, 0.02, 0.16), edge * 0.55 * alpha);
	// Brow ridge: a membrane fold above the lid line, only really visible when tilted.
	float brow_band = smoothstep(0.30, 0.0, abs(e.y - (lid_y - 0.34))) * smoothstep(1.35, 0.8, abs(e.x));
	acc = over(acc, lid_col.rgb * 0.55, brow_band * (0.18 + 0.9 * clamp(tilt, 0.0, 0.5)) * alpha * (1.0 - blink * 0.4));
	// seam when closed
	float seam = smoothstep(0.12, 0.0, abs(e.y - mix(lid_y, low_y, 0.5))) * blink * smoothstep(1.05, 0.7, abs(e.x));
	acc = over(acc, vec3(0.03, 0.015, 0.12), seam * 0.9 * alpha);
	return acc;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	vec4 acc = vec4(0.0);
	acc = eye(p, eye_a, -1.0, acc);
	acc = eye(p, eye_b, 1.0, acc);
	COLOR = acc;
}

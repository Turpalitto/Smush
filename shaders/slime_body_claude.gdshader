shader_type canvas_item;
// CLAUDE VISUAL CHALLENGE V8 — "Lunar Jelly" body for the slime.
//
// One quad, world-aligned (it is NOT rotated with the velocity, so the light stays
// where the scene light is). Everything is measured in body-radius units: the CPU
// (SlimeVisualClaude) owns the physics — spring ring, interior inertia, ripples —
// and this shader only turns that state into pixels.
//
//   silhouette   radial function R(a): 16-node spring ring (CPU) + five soft folds +
//                a teardrop tail while moving, inside an elliptical squash frame.
//   membrane     pillow normal, fold ridges, thin-film fresnel, glass edge line,
//                window glint, ground-bounce light.
//   interior     refracted ground + absorption by path length, core sub-surface light,
//                cytoplasm marbling, light fibrils with travelling pulses,
//                vesicles with depth parallax (they lag the shell by different amounts).
//   core         a lunar crescent with faint earthshine inside the bite — stage 8's
//                identity; other stages fall back to a round nucleus (core_style).
//   events       absorb ripple, hurt ripple, evolution wave, electric channels.
//
// quality: 0 Low (no refraction, no marbling, 3 vesicles) · 1 Medium · 2 High.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Names match SlimeVisual's palette contract so the base class can keep feeding them.
uniform vec4 body_color : source_color = vec4(0.56, 0.55, 1.0, 0.9);
uniform vec4 core_color : source_color = vec4(0.95, 0.91, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float stage_glow : hint_range(0.0, 1.0) = 0.28;
uniform float stage_t : hint_range(0.0, 1.0) = 0.5;
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;
uniform float stealth_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float evolution_glow : hint_range(0.0, 1.0) = 0.0;

uniform float extent = 1.5;
uniform float u_time = 0.0;
uniform float px_per_unit = 40.0;
uniform int quality : hint_range(0, 2) = 2;
uniform float breath = 0.0;
uniform float core_energy = 0.0;
uniform vec2 frame_dir = vec2(1.0, 0.0);
uniform vec2 squash = vec2(1.0, 1.0);
uniform vec2 tail_dir = vec2(0.0, 1.0);
uniform float tail = 0.0;
uniform float ring[16];
uniform vec2 lag = vec2(0.0, 0.0);
// xy = ripple origin (R units, world axes) · z = age 0..1 (>=1 idle) · w = amplitude
uniform vec4 ripple_a = vec4(0.0, 0.0, 2.0, 0.0);
uniform vec4 ripple_h = vec4(0.0, 0.0, 2.0, 0.0);
uniform float evo_t = -1.0;
uniform float core_style : hint_range(0.0, 1.0) = 1.0;
uniform float detail : hint_range(0.0, 1.0) = 0.64;
uniform float electro_level : hint_range(0.0, 1.0) = 0.0;
uniform float electro_charge : hint_range(0.0, 1.0) = 0.0;
uniform float electro_flash : hint_range(0.0, 1.0) = 0.0;
uniform float electro_seed = 0.0;

// ---- evolution structure (driven by SlimeVisualClaude._compute_evolution_params) ----
uniform float evo_membrane : hint_range(0.0, 1.0) = 0.5;   // membrane thickness & fold depth
uniform float evo_core_cx : hint_range(0.0, 1.0) = 0.5;     // core complexity (single dot → multi-lobe)
uniform float evo_vesicles : hint_range(0.0, 1.0) = 0.5;    // vesicle density scaling
uniform float evo_fibrils : hint_range(0.0, 1.0) = 0.5;     // fibril network density
uniform float evo_biolum : hint_range(0.0, 1.0) = 0.3;      // bioluminescence intensity
uniform float evo_organelles : hint_range(0.0, 1.0) = 0.0;  // organelle (ER, mito) visibility
uniform float evo_asym : hint_range(0.0, 0.5) = 0.0;        // silhouette organic asymmetry
uniform float evo_opacity : hint_range(0.3, 1.0) = 0.7;     // body opacity (transparent baby → opaque apex)
uniform float evo_eye_scale : hint_range(0.6, 1.4) = 1.0;   // eye relative size factor

const float TAU_C = 6.28318530718;
const vec3 KEY_LIGHT = vec3(-0.45, -0.65, 0.62);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

// Catmull-Rom over the periodic 16-node ring; node i sits at angle (i/16 - 0.5)*TAU.
float ring_at(float a) {
	float f = (a / TAU_C + 0.5) * 16.0;
	float fl = floor(f);
	float t = f - fl;
	int i = int(mod(fl, 16.0));
	float p0 = ring[(i + 15) % 16];
	float p1 = ring[i];
	float p2 = ring[(i + 1) % 16];
	float p3 = ring[(i + 2) % 16];
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
}

float shape_r(float aw) {
	float r = 1.0 + ring_at(aw);
	// Membrane folds: depth and count scale with evo_membrane (0=smooth baby, 1=complex apex)
	float fold_amp = (0.010 + 0.040 * evo_membrane) * (1.0 + 0.30 * breath);
	r += fold_amp * cos(5.0 * aw + 0.55 * sin(u_time * 0.31) + 1.1);
	r += fold_amp * 0.45 * cos(3.0 * aw - 0.08 * u_time + 2.3);
	// Secondary folds appear at higher stages
	r += fold_amp * 0.30 * cos(7.0 * aw + 0.3 * u_time + 0.7) * evo_membrane;
	// Organic asymmetry: slow-drifting random shape offset at high stages
	if (evo_asym > 0.005) {
		float asym1 = sin(aw * 2.0 + u_time * 0.13 + 0.5) * 0.6 + sin(aw * 3.0 - u_time * 0.09 + 1.8) * 0.4;
		r += asym1 * evo_asym * 0.12;
		// Gravity: slightly heavier bottom
		r += sin(aw + 1.5708) * evo_asym * 0.04;
	}
	// Teardrop: a soft point trails behind the motion; the front stays round.
	r += tail * 0.20 * pow(max(dot(vec2(cos(aw), sin(aw)), tail_dir), 0.0), 3.5);
	return r;
}

vec2 frame_to_world(vec2 v) {
	return frame_dir * v.x + vec2(-frame_dir.y, frame_dir.x) * v.y;
}

// Soft vesicle with a dome highlight. Returns shaded fill in rgb, coverage in a.
vec4 vesicle(vec2 q, vec2 c, float rv, vec3 tint, float aa) {
	vec2 d = (q - c) / rv;
	float dl = length(d);
	float cov = smoothstep(1.0 + aa / rv, 1.0 - aa / rv, dl);
	float rim = smoothstep(0.55, 1.0, dl);
	float hl = smoothstep(0.62, 0.0, length(d - vec2(-0.36, -0.42)));
	vec3 c3 = mix(tint * 1.05, tint * 0.55, rim);
	c3 += vec3(1.0, 0.98, 1.0) * hl * 0.55;
	c3 += tint * smoothstep(0.55, 0.0, length(d - vec2(0.30, 0.34))) * 0.18;
	return vec4(c3, cov);
}

void fragment() {
	vec2 pw = (UV - vec2(0.5)) * 2.0 * extent;
	float br_scale = 1.0 + 0.014 * breath + 0.020 * core_energy;
	vec2 pb = pw / br_scale;
	float aw = atan(pb.y, pb.x);

	vec2 q = vec2(dot(pb, frame_dir), dot(pb, vec2(-frame_dir.y, frame_dir.x))) / squash;
	float len_q = length(q);
	vec2 dirq = q / max(len_q, 0.0001);

	float R = shape_r(aw);
	float dn = len_q / R;
	float aa = fwidth(dn) * 0.85 + 0.0015;
	float cov = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, dn);

	float stage_boost = 0.55 + 0.45 * stage_glow;
	// ---- outside the silhouette: only a faint bioluminescent bloom ----------------
	if (dn >= 1.0 + aa) {
		float halo_base = 0.04 + 0.12 * evo_biolum;
		float halo = exp(-(dn - 1.0) * 11.0) * (halo_base + 0.16 * stage_boost + 0.18 * core_energy + 0.20 * electro_flash);
		vec3 hc = mix(rim_color.rgb, vec3(0.65, 0.95, 1.0), electro_flash);
		COLOR = vec4(hc, halo * stealth_alpha * step(dn, 1.38));
	} else {
		// ---- membrane / surface normal ---------------------------------------------
		float rim_t = pow(clamp(dn, 0.0, 1.0), 2.15);
		vec3 nq = vec3(dirq * rim_t * 0.97, 0.0);
		nq.z = sqrt(max(1.0 - dot(nq.xy, nq.xy), 0.02));

		vec2 tang = vec2(-dirq.y, dirq.x);
		// Membrane edge starts closer in at high evo_membrane (thicker visible membrane)
		float edge_start = 0.60 - 0.12 * evo_membrane;
		float edge_w = smoothstep(edge_start, 0.97, dn);
		// Fold normal perturbation scales with evo_membrane
		float fold_str = 0.06 + 0.14 * evo_membrane;
		float fd = sin(aw * 7.0 + 1.7 * sin(aw * 3.0 + u_time * 0.4) + u_time * 0.25);
		nq.xy += tang * fd * fold_str * edge_w;
		nq.xy += dirq * sin(aw * 11.0 - u_time * 0.35 + fd) * fold_str * 0.35 * edge_w;
		if (quality >= 1) {
			vec2 sw = vec2(sin(q.y * 5.1 + u_time * 0.55 + sin(q.x * 3.0)), cos(q.x * 4.6 - u_time * 0.47 + sin(q.y * 3.7)));
			nq.xy += sw * 0.040 * (1.0 - edge_w * 0.6);
		}

		// Event ripples: wavefronts bend the normal, so they refract instead of just glowing.
		float rip_glow = 0.0;
		vec2 rq = ripple_a.xy;
		rq = vec2(dot(rq, frame_dir), dot(rq, vec2(-frame_dir.y, frame_dir.x))) / squash;
		if (ripple_a.z < 1.0) {
			float rd = length(q - rq);
			float front = ripple_a.z * 1.55;
			float env = exp(-pow((rd - front) * 3.4, 2.0)) * (1.0 - ripple_a.z) * ripple_a.w;
			float wv = sin((rd - front) * 17.0) * env;
			nq.xy += normalize(q - rq + vec2(0.0001)) * wv * 0.55;
			rip_glow += max(wv, 0.0) * 0.35;
		}
		vec2 hq = ripple_h.xy;
		hq = vec2(dot(hq, frame_dir), dot(hq, vec2(-frame_dir.y, frame_dir.x))) / squash;
		if (ripple_h.z < 1.0) {
			float hd = length(q - hq);
			float hf = ripple_h.z * 1.7;
			float henv = exp(-pow((hd - hf) * 3.0, 2.0)) * (1.0 - ripple_h.z) * ripple_h.w;
			nq.xy += normalize(q - hq + vec2(0.0001)) * sin((hd - hf) * 13.0) * henv * 0.60;
		}
		float evo_band = 0.0;
		if (evo_t >= 0.0 && evo_t < 1.0) {
			float er = evo_t * 1.35;
			evo_band = exp(-pow((len_q - er) * 4.4, 2.0)) * (1.0 - evo_t);
			nq.xy += dirq * sin((len_q - er) * 15.0) * evo_band * 0.35;
		}
		nq.z = sqrt(max(1.0 - dot(nq.xy, nq.xy), 0.02));
		vec3 n = normalize(vec3(frame_to_world(nq.xy), nq.z));

		vec3 L = normalize(KEY_LIGHT);
		float ndl = dot(n, L);
		float wrap = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
		float fres = pow(1.0 - n.z, 2.25);

		vec3 body = body_color.rgb;
		float lum = dot(body, vec3(0.2126, 0.7152, 0.0722));

		// ---- interior content frame (lags the shell: inertia) ------------------------
		vec2 lag_q = vec2(dot(lag, frame_dir), dot(lag, vec2(-frame_dir.y, frame_dir.x))) / squash;
		float t = u_time;

		// ---- transmitted background ---------------------------------------------------
		vec3 bg = vec3(0.10, 0.14, 0.16);
		if (quality >= 1) {
			vec2 off = n.xy * (0.30 + 0.85 * (1.0 - n.z)) * px_per_unit * 0.55 * SCREEN_PIXEL_SIZE;
			bg = textureLod(screen_tex, SCREEN_UV - off, 1.0).rgb;
		} else {
			bg = textureLod(screen_tex, SCREEN_UV, 1.0).rgb;
		}
		float path = 1.0 / max(n.z, 0.30);
		// evo_opacity: baby (0.35) is almost clear, apex (1.0) is deeply tinted
		float absorb_k = 0.30 + 0.55 * evo_opacity;
		float absorb = 1.0 - exp(-absorb_k * path);
		vec3 clear = bg * mix(vec3(1.0), body * 1.45, 0.62) + body * 0.10;
		vec3 deep = mix(body * vec3(0.30, 0.26, 0.62) + vec3(0.02, 0.01, 0.07), body * vec3(0.78, 0.74, 1.05), wrap);
		float opaque_mix = clamp(0.18 + 0.55 * absorb * evo_opacity, 0.0, 0.95);
		vec3 col = mix(clear, deep, opaque_mix);

		// Thin-film hue travelling over the surface: lavender -> teal -> rose.
		vec3 film = 0.5 + 0.5 * cos(TAU_C * (vec3(0.0, 0.33, 0.67) + fres * 0.95 + 0.20 * n.x - 0.07 * n.y + 0.03 * sin(t * 0.4)));
		vec3 film_tint = mix(body, film, 0.55);

		// ---- core: lunar crescent + earthshine ------------------------------------------
		float breath_e = 0.5 + 0.5 * breath;
		vec2 cq = vec2(0.0, 0.26) + lag_q * 1.0 + vec2(0.012 * sin(t * 0.7), 0.010 * cos(t * 0.9));
		vec2 dc = q - cq;
		float rr = length(dc);
		float energy = clamp(core_energy, 0.0, 1.4);
		float rc = 0.235 * (1.0 + 0.05 * breath + 0.22 * energy);
		// Core grows slightly with evolution complexity
		rc *= (0.80 + 0.30 * evo_core_cx);
		vec3 warm = mix(core_color.rgb, vec3(1.0, 0.86, 0.52), 0.58);

		// Light the cytoplasm from the core (sub-surface scattering).
		// evo_biolum controls how much the core lights up the interior
		float glow_strength = 0.20 + 0.30 * evo_biolum;
		float glow = exp(-rr * rr / (0.20 + 0.10 * energy));
		float glow_wide = exp(-rr * rr / 0.62);
		col += warm * glow * (glow_strength + 0.40 * energy + 0.10 * breath_e);
		col += film_tint * glow_wide * (0.08 + 0.12 * evo_biolum) * (0.5 + energy);

		// Cytoplasm marbling (Medium+): slow currents dragged by the inertia lag.
		// Intensity scales with evo_membrane (more complex body → more visible currents)
		if (quality >= 1) {
			float m1 = fbm(q * 2.9 + vec2(t * 0.045, -t * 0.038) + lag_q * 0.9);
			float m2 = fbm(q * 5.2 - vec2(t * 0.06, t * 0.03) + 7.7);
			float marble_str = 0.10 + 0.15 * evo_membrane;
			float veil = smoothstep(0.38, 0.78, m1);
			col = mix(col, film_tint * 1.25, veil * marble_str * (1.0 - edge_w * 0.5));
			col += rim_color.rgb * smoothstep(0.55, 0.85, m2) * (0.02 + 0.05 * evo_membrane);
		}

		// Light fibrils: structured pathways from the core, with pulses running outward.
		// evo_fibrils controls how many are visible and how bright
		float fibre_w = 0.10 + 0.90 * evo_fibrils;
		float ang_c = atan(dc.y, dc.x);
		float fa = ang_c * 6.0 + sin(rr * 7.5 - t * 0.5) * 0.85 + t * 0.07;
		float fline = pow(clamp(1.0 - abs(sin(fa)), 0.0, 1.0), 22.0);
		float fpulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(rr * 13.0 - t * (2.2 + energy * 3.0) + floor(fa / 3.14159) * 1.7));
		float fmask = smoothstep(rc * 1.05, rc * 1.9, rr) * (1.0 - smoothstep(0.55, 0.96, dn));
		col += mix(warm, film_tint, 0.45) * fline * fpulse * fmask * fibre_w * (0.30 + 0.35 * energy);

		// Crescent. The bite sits down-right, away from the light, so the lit horn faces it.
		float rot = 0.30 * sin(t * 0.45) + 0.8 * energy * sin(t * 6.0) * 0.1;
		vec2 bite_dir = vec2(cos(0.95 + rot), sin(0.95 + rot));
		float disc = smoothstep(rc + 0.010, rc - 0.010, rr);
		float bite = smoothstep(rc * 0.90 + 0.012, rc * 0.90 - 0.012, length(dc - bite_dir * rc * 0.50));
		float cres = disc * (1.0 - bite);
		float round_core = disc;
		float core_mask = mix(round_core, cres, core_style);

		// Secondary core lobe at high evolution (mitosis/complexity hint)
		if (evo_core_cx > 0.4) {
			float lobe_str = smoothstep(0.4, 0.9, evo_core_cx);
			vec2 lobe_off = vec2(cos(t * 0.15 + 1.8), sin(t * 0.12 + 0.5)) * rc * 0.55;
			float lobe_r = rc * (0.45 + 0.15 * sin(t * 0.3));
			float lobe = smoothstep(lobe_r + 0.008, lobe_r - 0.008, length(dc - lobe_off));
			core_mask = max(core_mask, lobe * lobe_str * 0.75);
		}

		// Earthshine: the dark limb of the moon is still faintly lit.
		float earth = disc * bite * core_style;
		float thick = clamp(dot(normalize(dc + vec2(0.0001)), -bite_dir) * 0.5 + 0.5, 0.0, 1.0);
		vec3 core_col = mix(vec3(1.0, 0.95, 0.80), warm, 0.30 + 0.45 * (1.0 - thick));
		core_col = mix(core_col, vec3(1.0, 1.0, 0.96), energy * 0.5 + (1.0 - rr / rc) * 0.25);
		col = mix(col, film_tint * 0.55 + vec3(0.04, 0.02, 0.10), earth * 0.34);
		col = mix(col, core_col, core_mask * 0.96);
		col += warm * core_mask * (0.08 + 0.20 * evo_biolum + 0.25 * energy);

		// ---- organelles: depth-parallax vesicles ----------------------------------------
		// evo_vesicles controls how many appear (0=none at baby, 1=full set at apex)
		int max_ves = quality == 0 ? 3 : (quality == 1 ? 5 : 7);
		int n_ves = int(float(max_ves) * evo_vesicles + 0.5);
		for (int i = 0; i < 7; i++) {
			if (i >= n_ves) {
				break;
			}
			float fi = float(i);
			float s1 = hash21(vec2(fi, 3.7));
			float s2 = hash21(vec2(fi, 9.2));
			float s3 = hash21(vec2(fi, 1.3));
			float dirn = mod(fi, 2.0) < 1.0 ? 1.0 : -1.0;
			float oa = fi * 2.39996 + t * (0.10 + 0.08 * s1) * dirn;
			float orb = 0.40 + 0.30 * s2 + 0.025 * sin(t * 0.7 + fi * 2.0);
			float depth = 0.35 + 1.15 * s3;
			vec2 c = vec2(cos(oa), sin(oa)) * orb * vec2(1.0, 0.90) + lag_q * depth;
			c.y += 0.04;
			float rv = 0.060 + 0.058 * s1;
			float cl = length(c);
			c *= min(1.0, (0.86 - rv) / max(cl, 0.001));
			vec3 vt = mix(film_tint, mix(vec3(1.0, 0.62, 0.86), vec3(0.50, 0.95, 0.92), mod(fi, 2.0)), 0.55);
			vec4 v = vesicle(q, c, rv, vt, aa);
			float behind_core = 1.0 - core_mask * 0.7;
			col = mix(col, v.rgb, v.a * 0.78 * behind_core);
		}
		if (quality >= 2 && evo_organelles > 0.05) {
			int n_org = int(9.0 * evo_organelles + 0.5);
			for (int j = 0; j < 9; j++) {
				if (j >= n_org) { break; }
				float fj = float(j);
				float h1 = hash21(vec2(fj, 21.3));
				float h2 = hash21(vec2(fj, 5.1));
				vec2 gc = vec2(cos(fj * 1.7 + t * (0.18 + 0.1 * h1)), sin(fj * 2.3 - t * (0.15 + 0.1 * h2))) * (0.25 + 0.5 * h2);
				gc += lag_q * (0.4 + h1);
				float g = smoothstep(0.024, 0.006, length(q - gc));
				col = mix(col, mix(warm, rim_color.rgb, 0.4) * 1.05, g * 0.55 * evo_organelles * step(length(gc), 0.82));
			}
		}

		// ---- electric channels (electro_discharge) --------------------------------------
		if (electro_level > 0.0) {
			float act = clamp(0.14 + 0.38 * electro_charge + electro_flash * 1.2, 0.0, 1.4);
			float ch = 0.0;
			for (int k = 0; k < 6; k++) {
				float fk = float(k);
				float a0 = hash21(vec2(fk, 7.0 + electro_seed)) * TAU_C;
				float jag = (vnoise(vec2(rr * 8.0 + fk * 13.0, t * (2.0 + 6.0 * electro_flash) + electro_seed)) - 0.5) * 1.0;
				jag += (vnoise(vec2(rr * 19.0 + fk * 3.0, t * 4.0)) - 0.5) * 0.35;
				float da = abs(atan(sin(ang_c - a0 - jag), cos(ang_c - a0 - jag)));
				float wline = 0.012 + 0.010 * electro_flash;
				float line = smoothstep(wline * 2.2, 0.0, da * rr);
				float live = step(hash21(vec2(fk, 1.0 + electro_seed)), 0.35 + 0.65 * electro_level);
				float flick = 0.55 + 0.45 * sin(t * 17.0 + fk * 5.0 + electro_charge * 9.0);
				ch += line * live * flick * smoothstep(rc * 0.8, rc * 1.25, rr) * (1.0 - smoothstep(0.90, 1.02, dn));
			}
			vec3 ecol = mix(vec3(0.45, 0.88, 1.0), vec3(1.0, 1.0, 1.0), clamp(electro_flash * 1.2 + ch * 0.25, 0.0, 1.0));
			col += ecol * ch * act * 1.25;
			col += vec3(0.30, 0.65, 1.0) * glow * act * 0.35 * electro_charge;
			col += vec3(0.55, 0.90, 1.0) * electro_flash * 0.30 * (1.0 - smoothstep(0.0, 1.0, dn) * 0.4);
		}

		// ---- membrane: contour, thin film, glint, bounce ---------------------------------
		float contour = smoothstep(0.915, 0.975, dn) * (1.0 - smoothstep(0.975, 1.0, dn));
		col = mix(col, body * vec3(0.20, 0.16, 0.42), contour * 0.55);
		float film_band = smoothstep(0.70, 0.93, dn) * (1.0 - smoothstep(0.955, 1.0, dn));
		col = mix(col, mix(rim_color.rgb, film, 0.62), clamp(fres * 0.62 + film_band * 0.20, 0.0, 0.9));

		vec2 ldir2 = normalize(KEY_LIGHT.xy);
		float facing = dot(dirq, vec2(dot(ldir2, frame_dir), dot(ldir2, vec2(-frame_dir.y, frame_dir.x))));
		float arc = smoothstep(0.60, 0.96, facing) * smoothstep(0.66, 0.88, dn) * (1.0 - smoothstep(0.93, 0.99, dn));
		col += vec3(1.0, 0.99, 1.0) * arc * 0.52;
		vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
		float sp = pow(max(dot(n, H), 0.0), 56.0) * 0.55 + pow(max(dot(n, H), 0.0), 9.0) * 0.07;
		col += vec3(1.0, 0.99, 0.96) * sp;
		float ping = smoothstep(0.17, 0.0, length(q - vec2(-0.40, -0.47)));
		col += vec3(1.0) * ping * 0.30 * (1.0 - core_mask);

		float bounce_f = smoothstep(0.15, 0.95, -facing) * pow(1.0 - n.z, 1.6);
		col += mix(vec3(0.35, 0.95, 0.85), film, 0.4) * bounce_f * 0.50;

		// ---- events -------------------------------------------------------------------------
		col += rim_color.rgb * rip_glow;
		col += mix(warm, vec3(1.0), 0.4) * evo_band * 0.65;
		col += vec3(0.45, 1.0, 0.85) * evolution_glow * 0.18;
		vec3 hurt_tint = vec3(1.0, 0.36, 0.44);
		col = mix(col, hurt_tint * (0.55 + 0.6 * wrap), hurt_flash * (0.22 + 0.34 * fres + 0.20 * edge_w));
		col = mix(col, vec3(1.0), hurt_flash * hurt_flash * 0.10);

		col = clamp(col, vec3(0.0), vec3(1.4));
		COLOR = vec4(col, cov * stealth_alpha);
	}
}

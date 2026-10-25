shader_type canvas_item;

// EXPERIMENTAL organic body — GLM visual prototype, alternative to slime_body.gdshader.
// The original stays untouched; the lab (scenes/labs/EvolutionVisualLab.tscn) picks
// between the two at runtime.
//
// Differences from the original, in one paragraph: the silhouette is no longer a
// circle with an angular sine on it — the contour is displaced by domain-warped
// value noise, so it reads as a living membrane. The interior is a shallow volume:
// organelles sit on two depth lattices that shift with a sphere-normal parallax and
// LAG BEHIND acceleration, the nucleus drifts the same way, and fbm currents churn
// between them. All of it is driven by `u_time` (accumulated on the CPU) instead of
// TIME, so the lab can freeze or slow the anatomy without touching Engine.time_scale.
//
// Cost contract: at most ONE screen-texture sample, at most two 2-octave fbm
// evaluations per pixel, everything else is lattices and smoothsteps. The `quality`
// uniform (0/1/2) gates the expensive branches — uniform flow control, no divergence.
// The body must read as beautiful with NO bloom pass: every glow below is computed
// and added directly into the pixel.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// --- compat contract with slime_body.gdshader (set by SlimeVisual._recompute_look) ---
uniform vec4 body_color : source_color = vec4(0.13, 0.82, 0.66, 0.90);
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.50, 0.95);
uniform vec4 rim_color : source_color = vec4(0.65, 1.0, 0.91, 1.0);
uniform float wobble_speed : hint_range(0.5, 12.0) = 4.2;
uniform float wobble_amount : hint_range(0.0, 0.12) = 0.032;
uniform float pulse_phase : hint_range(0.0, 6.283) = 0.0;
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;
uniform float stealth_alpha : hint_range(0.25, 1.0) = 1.0;
uniform float evolution_glow : hint_range(0.0, 1.0) = 0.0;
uniform float stage_glow : hint_range(0.0, 1.0) = 0.0;
uniform float stage_t : hint_range(0.0, 1.0) = 0.0;

// --- organic-only controls (set by SlimeVisualOrganic) ---
uniform float u_time = 0.0;
uniform int quality = 2; // 0 = Low, 1 = Medium, 2 = High
uniform vec2 lag_vec = vec2(0.0); // velocity minus its smoothed self, in local units; drives inertia
uniform float absorb_pulse : hint_range(0.0, 1.0) = 0.0; // decaying envelope while swallowing
uniform vec2 absorb_dir = vec2(0.0, 1.0); // local-space direction of the last swallow
// Six-phase anatomy weights, 0..1, from the per-stage table in SlimeVisualOrganic.
uniform float organelles = 0.0;
uniform float membrane_w = 0.0;
uniform float nucleus_w = 0.0;
uniform float veins_w = 0.0;
uniform float flow_w = 0.0;
uniform float inner_glow = 0.0;
uniform float silhouette_w = 0.0;
// electro_discharge mutation visuals
uniform float electro_level = 0.0; // mutation presence/level, 0..1
uniform float electro_charge = 0.0; // 0..1 build-up between discharges
uniform float electro_flash = 0.0; // 0..1 burst at the discharge moment

const vec3 LIGHT_DIR = vec3(-0.45, -0.65, 0.62);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two octaves is the whole interior/silhouette noise budget. A third octave was
// tried and the difference vanished behind the organelles on a 40 px body.
float fbm2(vec2 p) {
	return vnoise(p) * 0.62 + vnoise(p * 2.13 + vec2(4.7, 1.3)) * 0.38;
}

// One organelle lattice layer. `density` keeps only some cells alive, `radius_px`
// scales with the quad so organelles keep their size when the slime grows.
// `par` is the depth-parallax offset, `drift` the slow cytoplasm current.
float organelle_layer(vec2 p, float density, float par_amt, vec2 par, vec2 drift, inout float rim_shade) {
	vec2 q = p + par * par_amt + drift;
	vec2 cell = floor(q);
	vec2 f = fract(q) - vec2(0.5);
	float h = hash21(cell);
	if (h > density) {
		return 0.0;
	}
	vec2 jitter = vec2(hash21(cell + vec2(3.7, 1.3)), hash21(cell + vec2(9.1, 5.5))) - vec2(0.5);
	vec2 off = f - jitter * 0.55;
	float d = length(off);
	// Cheap sphere shading: brighten the side facing the key light, darken the far
	// side. Without this the organelles read as flat dots glued onto the gel.
	vec2 ln = normalize(off + vec2(0.0001));
	rim_shade = clamp(0.55 + 0.75 * dot(ln, vec2(0.42, -0.88)), 0.0, 1.4);
	return smoothstep(0.30, 0.13, d);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float angle = atan(centered.y, centered.x);
	float dist = length(centered);

	float wave = sin(angle * 5.0 + u_time * wobble_speed + pulse_phase) * wobble_amount
		+ cos(angle * 3.0 - u_time * wobble_speed * 0.7) * (wobble_amount * 0.6);

	// Organic contour: warped noise over the polar domain. Low quality keeps the
	// pure harmonic outline — the silhouette is the cheapest thing to drop.
	if (quality >= 1) {
		vec2 wp = vec2(cos(angle), sin(angle)) * 1.6;
		float n = fbm2(wp * 2.2 + vec2(u_time * 0.11, -u_time * 0.07) + centered * 0.9);
		wave += (n - 0.5) * wobble_amount * (1.6 + 4.5 * silhouette_w);
	}

	// Acceleration & braking live in lag_vec: pushing forward makes the body trail
	// and the contents lean back; a hard stop throws them forward. One signal, no
	// separate accel/brake state on the CPU.
	float lag_amt = clamp(length(lag_vec), 0.0, 0.30);
	wave += dot(normalize(centered + vec2(0.0001)), normalize(lag_vec + vec2(0.0001))) * lag_amt * 0.10;

	float r = dist + wave;

	if (r > 0.95) {
		COLOR = vec4(0.0);
	} else {
	float edge = smoothstep(0.95, 0.84, r);
	// Pain contracts the membrane: the silhouette pulls in a hair and the surface
	// roughens, so hurt reads on the outline, not only as a colour flush.
	float roughness = hurt_flash * 0.55 + electro_flash * 0.35;
	if (quality >= 1 && roughness > 0.01) {
		wave += (fbm2(centered * 5.5 + vec2(u_time * 1.9)) - 0.5) * roughness * 0.05;
		r = dist + wave;
	}
	edge = smoothstep(0.95, 0.84, r - hurt_flash * 0.015);

	// --- sphere normal (same reconstruction the original uses) ------------------
	float norm_r = clamp(r / 0.95, 0.0, 1.0);
	float nz = sqrt(max(0.001, 1.0 - norm_r * norm_r));
	vec3 normal = normalize(vec3(centered.x, centered.y, nz * 1.25));
	vec3 ldir = normalize(LIGHT_DIR);
	float wrap_light = pow(clamp(dot(normal, ldir) * 0.5 + 0.5, 0.0, 1.0), 1.25);
	float fresnel = pow(1.0 - nz, 2.4);

	// --- translucency: one refracted background sample, Medium and above --------
	float body_lum = dot(body_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	float light_body = smoothstep(0.58, 0.82, body_lum);
	vec3 col;
	if (quality >= 1) {
		vec2 refract_offset = normal.xy * (0.014 * (1.0 - nz * 0.5));
		vec3 bg = texture(screen_tex, SCREEN_UV - refract_offset).rgb;
		col = mix(bg * body_color.rgb * 1.55, body_color.rgb, clamp(body_color.a * 0.55 + 0.42 * nz, 0.0, 1.0));
	} else {
		// Low: no screen read. Depth shading alone still sells the volume.
		col = body_color.rgb * clamp(0.55 + 0.45 * nz, 0.0, 1.0);
	}
	// Warped cytoplasm light, cheaper than the original's opal branch and keeping
	// hue alive across the body so the gel never looks like a flat fill.
	float cyto = fbm2(centered * 2.1 + vec2(-u_time * 0.05, u_time * 0.04));
	col = mix(col, col * (0.82 + 0.36 * cyto), 0.55);
	vec3 deep_gel = mix(body_color.rgb * vec3(0.36, 0.52, 0.70), body_color.rgb * vec3(0.42, 0.36, 0.30), light_body);
	col = mix(deep_gel, col, wrap_light * 0.55 + 0.45);

	// --- interior coordinates: parallax + inertial lag --------------------------
	// The interior is a shallow volume: near structures shift more with the sphere
	// normal and more against acceleration. `lag` also carries the braking
	// overshoot because it flips sign when velocity drops faster than its own EMA.
	vec2 lag = -lag_vec * 0.9;
	vec2 swirl = vec2(sin(angle * 2.0 + u_time * 0.35), cos(angle * 2.0 - u_time * 0.28)) * flow_w * 0.10;

	// --- internal currents ------------------------------------------------------
	if (flow_w > 0.02 && quality >= 1) {
		vec2 sp = vec2(angle * 1.35, dist * 3.4 - u_time * (0.16 + 0.12 * flow_w));
		float stream = fbm2(sp + swirl * 2.0);
		float streak = smoothstep(0.46, 0.72, stream) * smoothstep(0.86, 0.62, stream);
		streak *= smoothstep(0.94, 0.42, r) * flow_w;
		// Currents are dark streaks in the gel on dark bodies and pale lit channels
		// on the cream ones — the same luminance flip the original applies to stars.
		vec3 stream_col = mix(core_color.rgb * 1.06, body_color.rgb * 0.52, light_body);
		col = mix(col, stream_col, streak * 0.30);
	}

	// --- dendritic channels (veins) --------------------------------------------
	if (veins_w > 0.02) {
		vec2 vp = centered * 2.6 + vec2(u_time * 0.02, -u_time * 0.015);
		float v1 = fbm2(vp + swirl);
		float filament = pow(1.0 - abs(v1 * 2.0 - 1.0), 7.0);
		// Radial fade: channels run from the nucleus toward the membrane.
		filament *= smoothstep(0.95, 0.25, r) * veins_w;
		vec3 vein_dim = mix(body_color.rgb * 0.42, vec3(0.30, 0.22, 0.16), light_body);
		vec3 vein_lit = mix(vec3(0.62, 0.98, 0.90), vec3(0.55, 0.42, 0.30), light_body);
		// Electro mutation hijacks the same channels: they become the conduction
		// network and brighten with charge before a discharge.
		float elec_mix = clamp(electro_level * (0.35 + 0.75 * electro_charge), 0.0, 1.0);
		vec3 vein_col = mix(vein_dim, mix(vein_lit, vec3(1.0, 0.94, 0.42), 0.75), elec_mix);
		float vein_a = mix(0.22, 0.30 + 0.45 * electro_charge + 0.55 * electro_flash, elec_mix);
		col = mix(col, vein_col, clamp(filament * vein_a, 0.0, 1.0));
	}

	// --- organelles: two depth lattices ----------------------------------------
	if (organelles > 0.02) {
		float shade0 = 0.0;
		float shade1 = 0.0;
		float dens = clamp(0.18 + 0.72 * organelles, 0.0, 0.92);
		// Near layer: big, strong parallax, follows lag almost fully.
		float o0 = organelle_layer(centered * 3.1, dens, 0.55, normal.xy, swirl + lag, shade0);
		// Deep layer: fine, weak parallax, lags only half as much (it sits "further back").
		float o1 = 0.0;
		if (quality >= 1) {
			o1 = organelle_layer(centered * 5.2 + vec2(7.3, 2.9), dens * 0.8, 0.22, normal.xy, swirl * 1.6 + lag * 0.5, shade1);
		}
		// Organelle tissue is DARKER and more saturated than the gel on dark bodies
		// (deeper tissue seen through a translucent membrane) and amber-dark on the
		// cream ones — core-coloured fills were tried and the interior read as white
		// cotton instead of anatomy. Only the small glow-cell motes stay core-bright.
		vec3 fill0 = mix(body_color.rgb * 0.62, body_color.rgb * vec3(0.62, 0.44, 0.30), light_body);
		vec3 fill1 = mix(body_color.rgb * 0.44, body_color.rgb * vec3(0.44, 0.32, 0.24), light_body);
		float o0a = o0 * (0.30 + 0.28 * shade0) * organelles;
		float o1a = o1 * (0.24 + 0.24 * shade1) * organelles;
		col = mix(col, fill1 * shade1, clamp(o1a, 0.0, 1.0));
		col = mix(col, fill0 * shade0, clamp(o0a, 0.0, 1.0));
		// A fraction of cells are luminous: tiny mitochondria that carry the
		// bioluminescence without any bloom pass.
		float glow_cells = 0.0;
		if (quality >= 1) {
			glow_cells = organelle_layer(centered * 4.1 + vec2(13.7, 5.1), dens * 0.35, 0.4, normal.xy, swirl * 1.2 + lag * 0.7, shade0);
		}
		col += core_color.rgb * glow_cells * (0.35 + 0.75 * inner_glow) * smoothstep(0.9, 0.3, r) * (0.5 + 0.5 * sin(u_time * 2.3 + centered.x * 9.0));
	}

	// --- nucleus ----------------------------------------------------------------
	if (nucleus_w > 0.02) {
		// Drifts with the current and lags behind acceleration; sits slightly above
		// centre so the face (eyes live at -0.10r) stays clear.
		vec2 nuc_c = vec2(0.0, 0.16) + swirl * 2.2 + lag * 1.4
			+ vec2(sin(u_time * 0.5), cos(u_time * 0.37)) * 0.045;
		vec2 nd = (centered - nuc_c) / vec2(1.0, 0.84);
		float dn = length(nd);
		float nuc = smoothstep(0.30, 0.24, dn);
		float nuc_rim = smoothstep(0.34, 0.29, dn) * smoothstep(0.24, 0.29, dn);
		// Chromatin: a faint rotating two-arm spiral inside the nucleus appears in
		// the Predator phase and refines through Apex. Two sine arms, no texture.
		float chromatin = 0.0;
		if (nucleus_w > 0.55) {
			float na = atan(nd.y, nd.x) + u_time * 0.4;
			chromatin = (0.5 + 0.5 * sin(na * 2.0 + dn * 16.0)) * smoothstep(0.30, 0.10, dn) * 0.35;
		}
		vec3 nuc_fill = mix(body_color.rgb * vec3(0.34, 0.44, 0.52), body_color.rgb * vec3(0.50, 0.38, 0.30), light_body);
		vec3 nuc_lit = mix(core_color.rgb, vec3(1.0, 0.93, 0.72), light_body * 0.6);
		col = mix(col, nuc_fill + nuc_lit * chromatin, nuc * (0.55 + 0.35 * nucleus_w));
		col = mix(col, nuc_lit, nuc_rim * 0.45 * nucleus_w);
		// Nucleolus: one bright dot, the anchor the swallowed prey drifts toward.
		float nucleolus = smoothstep(0.085, 0.035, length(centered - nuc_c - vec2(0.05, -0.04)));
		col += nuc_lit * nucleolus * (0.55 + 0.45 * inner_glow) * nucleus_w;
	}

	// --- absorption ripple ------------------------------------------------------
	if (absorb_pulse > 0.003) {
		// One ring travelling inward from the membrane while the envelope decays,
		// biased toward the side the prey entered from. Low quality keeps one ring;
		// High adds a faint second one trailing behind.
		float prog = 1.0 - absorb_pulse;
		float ring_r = mix(0.93, 0.18, prog);
		float dir_bias = 0.55 + 0.45 * dot(normalize(centered + vec2(0.0001)), normalize(absorb_dir));
		float ring = exp(-pow((r - ring_r) * 8.5, 2.0)) * absorb_pulse * dir_bias;
		col += rim_color.rgb * ring * 0.85;
		col = mix(col, core_color.rgb, ring * 0.25);
		if (quality >= 2) {
			float ring2 = exp(-pow((r - (ring_r + 0.10)) * 10.0, 2.0)) * absorb_pulse * 0.4 * dir_bias;
			col += rim_color.rgb * ring2;
		}
	}

	// --- membrane ---------------------------------------------------------------
	// Two bands + fresnel, thickened by the membrane weight: a thin bright inner
	// rim and a crisp outer contour, plus at high weight a second inner band (the
	// "double membrane" of the Apex phases).
	float rim = smoothstep(0.52, 0.72, r) * smoothstep(0.835, 0.775, r);
	float contour = smoothstep(0.795, 0.858, r) * smoothstep(0.928, 0.882, r);
	col = mix(col, rim_color.rgb, rim * (0.30 + 0.30 * membrane_w) + fresnel * (0.22 + 0.20 * membrane_w));
	col = mix(col, deep_gel * 0.62, contour * (0.45 + 0.25 * membrane_w));
	if (membrane_w > 0.5) {
		float inner_band = smoothstep(0.58, 0.66, r) * smoothstep(0.74, 0.66, r);
		col = mix(col, rim_color.rgb * 0.85, inner_band * (membrane_w - 0.5) * 0.55);
	}

	// Specular + internal caustic bounce (kept from the original: they carry the
	// "wet gel" read even with zero bloom).
	vec3 vdir = vec3(0.0, 0.0, 1.0);
	vec3 hdir = normalize(ldir + vdir);
	float spec = pow(max(0.0, dot(normal, hdir)), 30.0) * 0.55;
	vec3 bdir = normalize(vec3(0.48, 0.58, 0.35) + vdir);
	float sub_bounce = pow(max(0.0, dot(normal, bdir)), 12.0) * 0.20;
	col += vec3(1.0, 0.98, 0.92) * spec;
	col += rim_color.rgb * sub_bounce;

	// --- electro discharge burst -------------------------------------------------
	if (electro_flash > 0.01) {
		// The moment of discharge: the whole cytoplasm flares, the filaments blow
		// out to white-yellow, and the membrane flickers.
		float flare = electro_flash * (0.55 + 0.45 * sin(u_time * 47.0 + angle * 3.0));
		col += vec3(1.0, 0.95, 0.55) * flare * smoothstep(0.95, 0.30, r) * 0.8;
	}

	// --- growth detail + outer halo (compat with the original's stage language) --
	float spiral = sin(angle * 2.0 + dist * 14.0 - u_time * 1.1) * 0.5 + 0.5;
	float bands = smoothstep(0.35, 0.95, spiral) * smoothstep(0.92, 0.35, r);
	vec3 detail = mix(core_color.rgb, body_color.rgb * vec3(0.68, 0.52, 0.85), light_body);
	col = mix(col, detail, bands * stage_glow * 0.30);
	float halo = smoothstep(0.95, 0.62, r) * smoothstep(0.55, 0.90, r);
	col += rim_color.rgb * halo * stage_glow * 0.22 * (1.0 - 0.8 * light_body);

	// --- self luminosity (the no-bloom guarantee) ---------------------------------
	// A wide soft radial emission plus a lifted base: the body glows by itself and
	// the light pool drawn by SlimeAura completes the effect without any post pass.
	float glow_falloff = smoothstep(0.92, 0.12, r);
	col += core_color.rgb * glow_falloff * inner_glow * (0.30 + 0.10 * sin(u_time * 1.9 + pulse_phase));
	col *= 1.0 + inner_glow * 0.16;

	// --- status composites --------------------------------------------------------
	col = mix(col, vec3(1.0, 0.32, 0.38), hurt_flash * 0.62);
	col += vec3(0.35, 1.0, 0.82) * evolution_glow * 0.55;

	float alpha = edge * body_color.a * stealth_alpha;
	COLOR = vec4(col, alpha);
	}
}

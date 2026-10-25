shader_type canvas_item;

// EXPERIMENTAL organic shield membrane — GLM visual prototype for the `shield`
// mutation. Drawn on a quad slightly larger than the body by OrganicShield.gd.
//
// Not an energy bubble: a second translucent cell membrane stretched over the
// slime. It deforms at the point of impact (a dent plus concentric ripple rings
// radiating from the hit), then the ripples smooth out and the film re-tensions
// over ~1 s — the recovery the mutation already has mechanically. No screen-texture
// reads; one fbm evaluation; cheap enough to sit over the body every frame.

uniform float u_time = 0.0;
uniform vec4 tint : source_color = vec4(0.45, 0.88, 1.0, 1.0);
uniform float film_alpha : hint_range(0.0, 1.0) = 0.85; // overall presence (fades when inactive/broken)
uniform float impact : hint_range(0.0, 1.0) = 0.0; // decaying hit envelope
uniform vec2 impact_dir = vec2(1.0, 0.0); // local-space direction the hit came from
uniform float recovery : hint_range(0.0, 1.0) = 1.0; // 0 just broken -> 1 fully re-tensioned
uniform int quality = 2;

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

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	// The membrane silhouette: a circle dented where the blow landed. The dent is
	// a cosine lobe around impact_dir whose depth rides the decaying envelope, with
	// a short ripple train radiating inward while the film is still shocked.
	float dent_a = acos(clamp(dot(normalize(centered + vec2(0.0001)), normalize(impact_dir)), -1.0, 1.0));
	float lobe = pow(max(0.0, cos(dent_a)), 6.0);
	float ripple = sin(dent_a * 9.0 - (1.0 - impact) * 22.0) * 0.4 + 0.6;
	float dent = lobe * impact * (0.10 + 0.16 * ripple);
	float r = dist + dent;

	if (r > 1.0) {
		COLOR = vec4(0.0);
	} else {

	// Spherical shading: the film is a hemisphere, so the lit side is where the
	// light lands and the silhouette edge burns brightest (fresnel).
	float norm_r = clamp(r, 0.0, 1.0);
	float nz = sqrt(max(0.001, 1.0 - norm_r * norm_r));
	float fresnel = pow(1.0 - nz, 2.6);
	float wrap_light = clamp(dot(normalize(vec3(centered, nz * 1.2)), normalize(vec3(-0.45, -0.65, 0.62))) * 0.5 + 0.5, 0.0, 1.0);

	// Fibrous film: two faint angular families of strands warped by noise, the
	// texture that says "biological film" rather than "glass sphere".
	float fib = 0.0;
	if (quality >= 1) {
		float warp = vnoise(centered * 3.0 + vec2(u_time * 0.06)) * 2.4;
		float strands = sin(angle * 22.0 + warp * 3.0);
		fib = smoothstep(0.86, 0.99, strands) * 0.30 + smoothstep(0.90, 0.99, sin(angle * 13.0 - warp * 2.0)) * 0.22;
		fib *= smoothstep(1.0, 0.45, r);
	}

	// Loose film while recovering: sag noise grows as recovery drops, so a fresh
	// membrane visibly wobbles before it re-tensions.
	float sag = (1.0 - recovery) * (vnoise(centered * 4.0 + vec2(u_time * 0.9, -u_time * 0.7)) - 0.5) * 0.35;

	// Ripples crossing the whole dome right after the hit, fading with the envelope.
	float hit_wash = 0.0;
	if (impact > 0.01) {
		float ring = sin((dist - (1.0 - impact) * 1.2) * 14.0);
		hit_wash = smoothstep(0.75, 1.0, ring) * impact * 0.45;
	}

	vec3 col = tint.rgb;
	float a = 0.0;
	a += 0.16 * film_alpha * smoothstep(1.0, 0.2, r); // body of the film
	a += 0.42 * film_alpha * fresnel; // edge concentration
	// A definite rim ring: a film whose only edge cue is fresnel measured as
	// "not there" on the dark lab backdrop, exactly like the faint-alpha halo
	// lesson from SlimeAura.
	a += smoothstep(0.82, 0.97, r) * smoothstep(1.0, 0.97, r) * 0.40 * film_alpha;
	a += fib * 0.45 * film_alpha; // strands
	a += hit_wash * 0.5; // impact wash
	a += lobe * impact * 0.45; // the dent itself is denser (compressed film)
	a *= recovery * 0.75 + 0.25; // a broken film is barely there
	a += sag * 0.12 * film_alpha; // sag wobble while recovering

	col *= 0.8 + 0.4 * wrap_light;
	col += vec3(1.0) * fresnel * 0.35 * film_alpha; // self-lit edge, no bloom needed
	col = mix(col, vec3(1.0, 0.95, 0.8), hit_wash * 0.35);

	// Bright flash ring at the instant of impact, riding the dent.
	col += vec3(1.0, 0.98, 0.9) * lobe * impact * impact * 0.8;

	COLOR = vec4(col, clamp(a, 0.0, 1.0));
	}
}

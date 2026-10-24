shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

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

const vec3 LIGHT_DIR = vec3(-0.45, -0.65, 0.62);

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

		// --- 3D Spherical Normal Reconstruction ---------------------------------
		// Turn the 2D quad into a volumetric hemisphere. Normal z is reconstructed
		// from distance to the wobbly edge, giving genuine curved 3D lighting.
		float norm_r = clamp(r / 0.95, 0.0, 1.0);
		float nz = sqrt(max(0.001, 1.0 - norm_r * norm_r));
		vec3 normal = normalize(vec3(centered.x, centered.y, nz * 1.25));

		// Spherical directional lighting
		vec3 ldir = normalize(LIGHT_DIR);
		float NdotL = dot(normal, ldir);
		float wrap_light = pow(clamp(NdotL * 0.5 + 0.5, 0.0, 1.0), 1.25);

		// True Fresnel rim curve (peaks at silhouette edge, zero at apex)
		float fresnel = pow(1.0 - nz, 2.4);

		// Screen-space refraction: fluid gel displaces the ground underneath it
		vec2 refract_offset = normal.xy * (0.012 * (1.0 - nz * 0.5));
		vec3 bg = texture(screen_tex, SCREEN_UV - refract_offset).rgb;

		// Two edge bands: bright inner rim and crisp outer contour
		float rim = smoothstep(0.52, 0.72, r) * smoothstep(0.835, 0.775, r);
		float contour = smoothstep(0.795, 0.858, r) * smoothstep(0.928, 0.882, r);
		float core_pulse = 0.34 + 0.05 * sin(TIME * 3.8 + pulse_phase);
		float core_mask = smoothstep(core_pulse + 0.22, 0.04, length(centered - vec2(0.0, 0.05)));

		// Body luminance decides which way "detail" goes
		float body_lum = dot(body_color.rgb, vec3(0.2126, 0.7152, 0.0722));
		float light_body = smoothstep(0.58, 0.82, body_lum);

		// Opalescent subsurface hue for pale/celestial stages
		vec3 opal_tint = mix(
			body_color.rgb * vec3(0.68, 0.52, 0.85),
			vec3(0.92, 0.62, 0.32),
			0.5 + 0.5 * sin(angle * 2.0 - TIME * 0.7)
		);
		vec3 detail = mix(core_color.rgb, opal_tint, light_body);

		// Deep volumetric gel: shaded lower hemisphere with rich undertones
		vec3 deep_gel = mix(body_color.rgb * vec3(0.36, 0.52, 0.70), opal_tint * 0.75, light_body);

		// Base body with refracted background showing through translucent jelly
		vec3 col = mix(bg * body_color.rgb * 1.55, body_color.rgb, clamp(body_color.a * 0.65 + 0.35 * nz, 0.0, 1.0));

		// Apply volumetric spherical shading (light wraps around the blob)
		col = mix(deep_gel, col, wrap_light * 0.55 + 0.45);

		// Specular glint + secondary internal caustic bounce
		vec3 vdir = vec3(0.0, 0.0, 1.0);
		vec3 hdir = normalize(ldir + vdir);
		float spec = pow(max(0.0, dot(normal, hdir)), 28.0) * 0.58;
		vec3 bdir = normalize(vec3(0.48, 0.58, 0.35) + vdir);
		float sub_bounce = pow(max(0.0, dot(normal, bdir)), 12.0) * 0.22;

		// Composite features
		col = mix(col, rim_color.rgb, rim * 0.52 + fresnel * 0.35);
		col = mix(col, deep_gel * 0.62, contour * 0.68);
		col = mix(col, detail, core_mask * 0.72);
		col += rim_color.rgb * sub_bounce;
		col += vec3(1.0, 0.98, 0.92) * spec;
		col = mix(col, vec3(1.0, 0.32, 0.38), hurt_flash * 0.75);
		col += vec3(0.35, 1.0, 0.82) * evolution_glow * 0.55;

		// Growth detail spiral currents
		float spiral = sin(angle * 2.0 + dist * 14.0 - TIME * 1.1) * 0.5 + 0.5;
		float bands = smoothstep(0.35, 0.95, spiral) * smoothstep(0.92, 0.35, r);
		col = mix(col, detail, bands * stage_glow * 0.30);

		// Outer halo hugging the membrane
		float halo = smoothstep(0.95, 0.62, r) * smoothstep(0.55, 0.90, r);
		col += rim_color.rgb * halo * stage_glow * 0.22 * (1.0 - 0.8 * light_body);

		// --- inner cosmos ---------------------------------------------------------
		vec2 sky = centered * 1.55;
		float near_stars = star_layer(sky * 2.35 + vec2(TIME * 0.055, TIME * 0.021), 0.34);
		float far_stars = star_layer(sky * 1.05 - vec2(TIME * 0.018, TIME * 0.030), 0.20);
		float cosmos = (near_stars * 0.85 + far_stars * 0.55)
			* smoothstep(0.94, 0.50, r) * smoothstep(0.10, 0.42, stage_glow);

		float star_dark = smoothstep(0.36, 0.50, body_lum);
		vec3 star_col = mix(vec3(1.0, 0.99, 0.92), body_color.rgb * 0.18, star_dark);
		col = mix(col, star_col, cosmos * 0.95);

		float alpha = edge * body_color.a * stealth_alpha;
		COLOR = vec4(col, alpha);
	}
}

shader_type canvas_item;
// CLAUDE VISUAL CHALLENGE V8 — shield membrane. A thin glass bubble: nearly clear in
// the middle, a thin-film rainbow at the grazing edge, refraction that bends whatever
// is behind it (including the slime), and an impact that dents the shell and sends a
// ring around it. `burst` expands and thins it out when the game consumes the shield.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float extent = 1.5;
uniform float u_time = 0.0;
uniform float pop = 1.0;
uniform float burst = -1.0;
uniform vec2 impact_dir = vec2(0.0, 1.0);
uniform float impact_t = 9.0;
uniform float impact_amp = 0.0;
uniform vec2 frame_dir = vec2(1.0, 0.0);
uniform vec2 squash = vec2(1.0, 1.0);
uniform vec4 tint : source_color = vec4(0.56, 0.55, 1.0, 1.0);
uniform float alpha = 1.0;
uniform int quality : hint_range(0, 2) = 2;
uniform float px_per_unit = 50.0;
uniform float ice = 0.0;

const float TAU_C = 6.28318530718;

void fragment() {
	vec2 pw = (UV - vec2(0.5)) * 2.0 * extent;
	vec2 q = vec2(dot(pw, frame_dir), dot(pw, vec2(-frame_dir.y, frame_dir.x))) / squash;
	float a = atan(pw.y, pw.x);
	float len_q = length(q);

	float ia = atan(impact_dir.y, impact_dir.x);
	float da = atan(sin(a - ia), cos(a - ia));
	float g = exp(-da * da / (2.0 * 0.50 * 0.50));
	float ring_decay = exp(-impact_t * 4.2);
	float dent = -0.19 * impact_amp * g * cos(impact_t * 26.0) * ring_decay;
	dent += 0.035 * impact_amp * sin(da * 3.0 - impact_t * 17.0) * exp(-impact_t * 3.0) * (1.0 - g);

	float scale = pop;
	float burst_k = burst >= 0.0 ? burst : 0.0;
	scale *= 1.0 + 0.40 * burst_k;
	float R = scale * (1.0 + 0.010 * sin(a * 5.0 + u_time * 1.3) + 0.006 * sin(a * 3.0 - u_time * 0.9) + dent);
	float dn = len_q / max(R, 0.001);
	float aa = fwidth(dn) * 0.9 + 0.0015;
	float cov = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, dn);
	if (cov <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		float nz = sqrt(max(1.0 - dn * dn, 0.0));
		vec2 dirq = q / max(len_q, 0.0001);
		vec2 nxy = dirq * pow(dn, 2.0) * 0.96;
		// the dent bends the surface where it is struck
		nxy += dirq * (-dent) * 1.6 * smoothstep(0.4, 1.0, dn);
		vec3 n = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.02)));

		float fres = pow(1.0 - n.z, 2.0);
		vec3 film = 0.5 + 0.5 * cos(TAU_C * (vec3(0.0, 0.33, 0.67) + fres * 1.25 + 0.18 * n.x - 0.12 * n.y + 0.04 * sin(u_time * 0.7)));
		vec3 icy = vec3(0.78, 0.95, 1.0);
		film = mix(film, icy, ice * 0.7);

		vec3 bg = texture(screen_tex, SCREEN_UV).rgb;
		if (quality >= 1) {
			vec2 off = n.xy * (0.4 + 1.1 * fres) * px_per_unit * 0.10 * SCREEN_PIXEL_SIZE;
			bg = textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb;
		}

		vec3 L = normalize(vec3(-0.45, -0.65, 0.62));
		vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(dot(n, H), 0.0), 38.0);
		vec2 ld = normalize(L.xy);
		float facing = dot(dirq, vec2(dot(ld, frame_dir), dot(ld, vec2(-frame_dir.y, frame_dir.x))));
		float arc = smoothstep(0.55, 0.95, facing) * smoothstep(0.80, 0.93, dn) * (1.0 - smoothstep(0.96, 0.995, dn));
		float bounce = smoothstep(0.2, 0.95, -facing) * fres;

		vec3 col = bg;
		col = mix(col, film, clamp(fres * 0.75, 0.0, 0.85));
		col = mix(col, tint.rgb * 1.2, 0.04);
		col += vec3(1.0) * (spec * 0.6 + arc * 0.55);
		col += film * bounce * 0.35;
		// impact flash and thin rim
		float hit = g * ring_decay * impact_amp;
		col += vec3(0.85, 0.97, 1.0) * hit * 0.55 * smoothstep(0.5, 1.0, dn);
		float edge = smoothstep(0.90, 0.985, dn) * (1.0 - smoothstep(0.985, 1.0, dn));
		col = mix(col, film * 1.1, edge * 0.55);

		float a_out = (0.06 + 0.52 * fres + 0.30 * edge + hit * 0.35 + (spec + arc) * 0.5) * alpha;
		a_out = clamp(a_out, 0.0, 0.92);
		float burst_fade = 1.0 - burst_k;
		a_out *= burst_fade * clamp(pop * 1.3, 0.0, 1.0);
		// fully transparent colour mix where the bubble is clear: composite as glass
		COLOR = vec4(col, a_out * cov);
	}
}

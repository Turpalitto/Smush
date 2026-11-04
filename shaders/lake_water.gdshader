shader_type canvas_item;
// Moonlit lake surface (prototype). One caustic texture, two fetches, no screen texture, so it stays
// cheap on the Mobile renderer. Ripples are up to 8 rings passed from script: xy world position,
// z age in seconds, w strength 0..1 (grows with the slime's mass).

uniform sampler2D caustic : filter_linear_mipmap, repeat_enable;
uniform sampler2D plate : filter_linear_mipmap, repeat_enable;   // painted lake plate (cross-blended into a seamless tile)
uniform vec2 plate_world = vec2(1100.0, 2380.0);
uniform float plate_mix = 0.82;
uniform vec4 shallow_colour : source_color = vec4(0.18, 0.62, 0.74, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.05, 0.15, 0.40, 1.0);
uniform vec4 caustic_colour : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float tile_world = 250.0;
uniform float caustic_strength = 0.42;
uniform float water_alpha = 0.6;   // below 1 so roots and fish shadows show through
uniform vec4 ripples[8];
uniform float ripple_speed = 95.0;
uniform float dry_from = 640.0;   // below this world y the water thins out to nothing: the dewy glade on dry ground
uniform float dry_to = 900.0;
uniform float dive = 0.0;   // 0 on the surface, 1 when the slime has dived: clearer water, stronger caustics, no ripples
uniform float shallow_from = 450.0;   // world y where the water is ankle-deep (the flooded grove) ...
uniform float shallow_to = -150.0;    // ... and where it has become the open lake
uniform vec2 moon_world = vec2(0.0, -400.0);   // where the moon's reflection column sits (follows the camera)
uniform vec2 slime_pos = vec2(1.0e6);           // duckweed parts around the slime
uniform float part_radius = 70.0;
uniform float duck_amount = 0.0;
uniform float lite = 0.0;   // 1 = cheap water for slow phones: one caustic layer, no glints, streaks or duckweed
uniform vec4 duck_colour : source_color = vec4(0.34, 0.78, 0.30, 1.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float t = TIME;
	// slow depth variation: big soft patches from the same texture
	float depth = 0.5 + 0.28 * sin(world.x * 0.0061 + 1.3 + sin(world.y * 0.0023)) + 0.22 * sin(world.y * 0.0043 + world.x * 0.0019);
	depth = clamp(depth, 0.0, 1.0);
	float sh = smoothstep(shallow_to, shallow_from, world.y);   // 1 in the grove, 0 on the lake
	vec3 col = mix(shallow_colour.rgb, deep_colour.rgb, depth * 0.85 * (1.0 - sh * 0.8));
	vec2 raw = world / plate_world;
	vec2 pu = fract(raw);   // the tile is made seamless by tools, plain repeat
		col = mix(col, textureGrad(plate, pu, dFdx(raw), dFdy(raw)).rgb, plate_mix * (1.0 - sh * 0.95));

	// caustics: two drifting copies multiplied, so the network breathes
	float c1 = texture(caustic, world / tile_world + vec2(t * 0.012, t * 0.007)).r;
	float c2 = c1;
	if (lite < 0.5) {
		c2 = texture(caustic, world / (tile_world * 0.63) - vec2(t * 0.009, t * 0.011)).r;
	}
	float c = (lite < 0.5) ? c1 * c2 * 1.5 : c1 * c1 * 1.3;
	col += caustic_colour.rgb * c * caustic_strength * (1.0 + sh * 0.9 + dive * 1.6) * (1.0 - depth * 0.55);

	// moon glints: sharp peaks of a fast-moving fine layer
	if (lite < 0.5) {
		float g = texture(caustic, world / 160.0 + vec2(t * 0.03, -t * 0.02)).r;
		col += vec3(0.85, 0.95, 1.0) * pow(g, 6.0) * 0.22;
	}

	// moon reflection: a column of horizontal streaks fading with distance from the moon
	vec2 m = world - moon_world;
	float streak = (lite < 0.5) ? texture(caustic, vec2(world.x / 300.0, world.y / 70.0 + t * 0.035)).r : 0.0;
	float column = exp(-pow(m.x / 95.0, 2.0)) * exp(-pow(m.y / 380.0, 2.0));
	col += vec3(0.75, 0.9, 1.0) * pow(streak, 2.0) * column * 1.3 * (1.0 - dive);
	col += vec3(0.45, 0.6, 0.95) * column * 0.12;

	// duckweed: small green blobs in patches; they open up around the slime
	float duck = 0.0;
	if (lite < 0.5 && duck_amount > 0.001) {
	float patch = smoothstep(0.55, 0.85, 0.5 + 0.5 * sin(world.x * 0.0105 + sin(world.y * 0.0079) * 2.3) * sin(world.y * 0.0121 + 1.7 + sin(world.x * 0.006)));
	vec2 cell = floor(world / 15.0);
	vec2 local = fract(world / 15.0) - 0.5;
	float rnd = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec2 jitter = vec2(fract(rnd * 17.0), fract(rnd * 41.0)) - 0.5;
	float dots = (rnd > 0.42) ? smoothstep(0.34, 0.16, length(local - jitter * 0.4)) : 0.0;
	float open_up = smoothstep(part_radius * 0.55, part_radius, distance(world, slime_pos));
	duck = patch * dots * open_up;
	}
	// duckweed stays off until painted leaves exist (a pure shader version read as noise)
	col = mix(col, duck_colour.rgb * (0.75 + 0.25 * sin(t + world.x)), duck * duck_amount);

	float rim = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 r = ripples[i];
		if (r.w > 0.001) {
			float d = distance(world, r.xy);
			float radius = r.z * ripple_speed;
			float width = 6.0 + r.z * 11.0;
			float fade = exp(-r.z * 0.85) * r.w;
			float ring = exp(-pow((d - radius) / width, 2.0));
			float ring2 = exp(-pow((d - radius * 0.62) / (width * 0.8), 2.0)) * 0.55;
			rim += (ring + ring2) * fade;
		}
	}
	float dry = smoothstep(dry_from, dry_to, world.y);
	rim *= (1.0 - dive) * (1.0 - dry);
	col += vec3(0.6, 0.9, 1.0) * rim * 0.55;
	col = mix(col, vec3(0.12, 0.4, 0.65), dive * 0.08);
	COLOR = vec4(col, clamp(mix(mix(water_alpha, 0.3, sh), 0.12, dive) + rim * 0.1, 0.0, 1.0) * (1.0 - dry));
}

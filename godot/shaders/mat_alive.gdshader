shader_type canvas_item;
// The duel mats come alive (scripts/duel/duel.gd): the neon in the art pulses, each light on its own
// rhythm; a wet sheen drifts over the lit ground; rain rings spread on the dark asphalt; a slow haze
// rolls across. Works on any mat: the neon is found in the image (bright, saturated pixels), nothing
// is placed by hand. Now and then duel.gd makes one light stutter (stutter_zone, stutter_k) and plays
// its buzz from there.

uniform vec2 tex_size = vec2(1536.0, 1024.0);   // the image in pixels (rings and patches keep their size)
uniform float neon = 0.45;      // how much the neon swells at its brightest
uniform float sheen = 0.14;
uniform float rain = 0.2;
uniform float haze = 0.06;
uniform vec2 stutter_zone = vec2(-1.0);   // the 160 px patch whose light stutters
uniform float stutter_k = -1.0;           // how far through the stutter (0..1), -1 for none

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 tex = texture(TEXTURE, UV).rgb;
	float hi = max(tex.r, max(tex.g, tex.b));
	float lo = min(tex.r, min(tex.g, tex.b));
	float sat = hi > 0.001 ? (hi - lo) / hi : 0.0;
	vec2 px = UV * tex_size;
	vec3 col = COLOR.rgb;

	// Neon: bright, saturated light swells and fades; each patch of the mat on its own rhythm,
	// and once in a while one stutters for a moment
	float lit = smoothstep(0.4, 0.85, hi) * smoothstep(0.3, 0.65, sat);
	vec2 zone = floor(px / 160.0);
	float speed = 0.7 + hash(zone + 7.0) * 1.5;
	float pulse = 0.5 + 0.5 * sin(TIME * speed + hash(zone) * 6.2832);
	// (the stutter: off, on, off... dying out, as its buzz plays)
	float stutter = 0.0;
	if (stutter_k >= 0.0 && distance(zone, stutter_zone) < 0.5) {
		stutter = step(0.45, fract(stutter_k * 7.0 + 0.3)) * (1.0 - smoothstep(0.75, 1.0, stutter_k));
	}
	col *= 1.0 + lit * (neon * pulse - stutter * 0.85);

	// The wet sheen: soft highlights drifting over the ground the light reaches
	float n = noise(px / 90.0 + vec2(TIME * 0.12, TIME * 0.05)) * noise(px / 37.0 - vec2(TIME * 0.07, 0.0));
	col += col * sheen * 3.0 * smoothstep(0.25, 0.6, n) * smoothstep(0.06, 0.35, hi);

	// Rain: a ring spreading on the dark asphalt now and then in each little patch
	vec2 cell = floor(px / 56.0);
	vec2 f = fract(px / 56.0) - 0.5;
	float h = hash(cell);
	float t = fract(TIME * (0.25 + h * 0.35) + h * 7.0);
	vec2 at = (vec2(hash(cell + 1.3), hash(cell + 2.9)) - 0.5) * 0.5;
	float ring = smoothstep(0.025, 0.0, abs(length(f - at) - t * 0.3)) * (1.0 - t) * step(0.72, h);
	col += vec3(0.62, 0.66, 0.9) * ring * rain * (1.0 - smoothstep(0.25, 0.55, hi));

	// Haze rolling slowly across
	float fog = noise(px / 420.0 + vec2(TIME * 0.03, TIME * 0.012));
	col += vec3(0.42, 0.36, 0.66) * haze * smoothstep(0.35, 0.9, fog);

	COLOR = vec4(col, COLOR.a);
}

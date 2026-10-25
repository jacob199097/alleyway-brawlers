shader_type canvas_item;
// Fog, mist, smoke or cloud shadows rolling over part of an arena (scripts/duel/arena_life.gd): two
// layers of soft noise drifting at different speeds, faded out at the edges of its rectangle. With
// "frame" it hugs the rectangle's edges (mist creeping in around a graveyard) and leaves the middle
// clear for the cards.

uniform vec4 color : source_color = vec4(0.7, 0.7, 0.8, 1.0);
uniform float density = 0.4;
uniform vec2 drift = vec2(0.03, 0.008);   // noise units a second
uniform float scale = 1.0;                // bigger: larger, softer billows
uniform vec2 rect_size = vec2(1000.0, 600.0);
uniform float frame = 0.0;                // 0 everywhere, 1 only round the edges
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * rect_size / (300.0 * scale) + seed * 13.0;
	float a = fbm(p + drift * TIME);
	float b = fbm(p * 1.6 - drift.yx * TIME * 1.4 + 7.3);
	float f = smoothstep(0.38, 0.82, a * 0.62 + b * 0.48);
	vec2 e = min(UV, 1.0 - UV) * rect_size;
	float edge = smoothstep(0.0, 0.16 * min(rect_size.x, rect_size.y), min(e.x, e.y));
	vec2 r = min(UV, 1.0 - UV);
	float hug = 1.0 - smoothstep(0.04, 0.32, min(r.x, r.y));
	float w = edge * mix(1.0, hug, frame);
	COLOR = vec4(color.rgb, f * density * w);
}

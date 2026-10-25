shader_type canvas_item;
// A cloud of dust or smoke (scripts/duel/duel.gd): a billowing puff, thinner at its edges, that the
// node's scale grows while "life" thins it away.

uniform vec4 color : source_color = vec4(0.55, 0.5, 0.42, 1.0);
uniform float life = 1.0;
uniform float density = 0.8;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.05 + 1.7; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p * vec2(1.0, 1.3));
	float n = fbm(p * 2.6 + vec2(TIME * 0.4, -TIME * 0.25));
	float puff = (1.0 - smoothstep(0.25 + n * 0.45, 0.95, r)) * (0.45 + n * 0.9);
	float shade = 0.75 + 0.35 * fbm(p * 4.0 + 3.0);   // lit tops, darker folds
	COLOR = vec4(color.rgb * shade, clamp(puff * density * life, 0.0, 1.0));
}

shader_type canvas_item;
render_mode blend_add;
// Spectral fire (scripts/duel/duel.gd): a column of flame licking upward (shape 0), or a round burst
// of flame blooming outward (shape 1). Noise rises through it; "life" fades it in and out.

uniform vec4 core : source_color = vec4(1.0, 0.85, 1.0, 1.0);
uniform vec4 outer : source_color = vec4(0.55, 0.15, 1.0, 1.0);
uniform int shape = 0;
uniform float life = 1.0;
uniform float speed = 1.6;
uniform float seed = 0.0;
uniform float gain = 0.8;   // overall brightness

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
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + 3.1; a *= 0.5; }
	return v;
}

void fragment() {
	float t = TIME * speed;
	float heat;
	if (shape == 0) {
		// x across (-1..1), y up from the base (0) to the tip (1)
		vec2 p = vec2((UV.x - 0.5) * 2.0, 1.0 - UV.y);
		float n = fbm(vec2(p.x * 2.4, p.y * 3.0 - t * 2.2));
		float width = mix(0.95, 0.12, p.y) * (0.75 + 0.5 * n);
		float body = 1.0 - smoothstep(width * 0.6, width, abs(p.x));
		heat = body * (1.0 - smoothstep(0.35 + n * 0.6, 1.0, p.y)) * smoothstep(0.0, 0.08, p.y + 0.02);
		heat *= 0.6 + n;
	} else {
		vec2 p = (UV - 0.5) * 2.0;
		float r = length(p);
		float a = atan(p.y, p.x);
		float n = fbm(vec2(a * 1.6 + seed, r * 3.0 - t * 2.4));
		heat = (1.0 - smoothstep(0.25 + n * 0.55, 0.95, r)) * (0.55 + n);
	}
	heat = clamp(heat, 0.0, 1.6) * life;
	vec3 col = mix(outer.rgb, core.rgb, smoothstep(0.95, 1.5, heat)) * heat * gain;
	COLOR = vec4(col, 1.0);
}

shader_type canvas_item;
// Nebula's summoning portal (scripts/duel/duel.gd): a whirlpool of violet light and star dust turning
// round a black heart, a bright rim at its edge. The node's scale opens and closes it; "angle" turns it.

uniform vec4 glow : source_color = vec4(0.62, 0.32, 1.0, 1.0);
uniform float angle = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// spiral arms wound tighter toward the middle, broken up by noise
	float s = sin(a * 4.0 + angle - log(r + 0.04) * 5.5);
	float n = noise(vec2(a * 3.0 + angle * 0.5, r * 6.0 - angle * 0.8)) * 0.6 + noise(p * 9.0 + angle) * 0.4;
	float disk = (1.0 - smoothstep(0.62, 0.96, r)) * smoothstep(0.1, 0.32, r);
	float arms = pow(0.5 + 0.5 * s, 2.5) * disk * (0.5 + 0.8 * n);
	float rim = exp(-pow((r - 0.9) * 14.0, 2.0)) * (0.7 + 0.3 * n);
	float heart = 1.0 - smoothstep(0.12, 0.34, r);
	// star dust caught in the whirl
	vec2 sp = vec2(a + angle * (1.2 - r), r) * vec2(18.0, 22.0);
	float star = step(0.985, hash(floor(sp))) * disk * smoothstep(0.4, 0.0, length(fract(sp) - 0.5));
	vec3 light = glow.rgb * (arms * 1.6 + rim * 1.4) + vec3(1.0, 0.95, 1.0) * (star * 1.5 + rim * 0.35);
	float alpha = clamp(max(max(arms * 1.4, rim), max(heart * 0.92, star)), 0.0, 1.0) * (1.0 - smoothstep(0.95, 1.0, r));
	vec3 col = mix(light, vec3(0.02, 0.0, 0.05), heart * (1.0 - arms));
	COLOR = vec4(col, alpha);
}

shader_type canvas_item;
render_mode blend_add;
// A comet's tail of flame behind something flying (Underworld's skulls, scripts/duel/duel.gd). The
// rectangle lies along the flight: UV.x 0 at the head, 1 at the end of the tail.

uniform vec4 core : source_color = vec4(1.0, 0.8, 1.0, 1.0);
uniform vec4 outer : source_color = vec4(0.55, 0.12, 1.0, 1.0);
uniform float life = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float x = UV.x;
	float y = (UV.y - 0.5) * 2.0;
	float n = noise(vec2(x * 7.0 + TIME * 9.0, y * 2.5)) * 0.6 + noise(vec2(x * 15.0 + TIME * 14.0, y * 5.0 + 3.0)) * 0.4;
	float width = mix(0.85, 0.05, pow(x, 0.7)) * (0.7 + 0.6 * n);
	float body = 1.0 - smoothstep(width * 0.4, width, abs(y));
	float heat = body * (1.0 - smoothstep(0.2, 1.0, x)) * smoothstep(0.0, 0.05, x) * (0.6 + n) * life;
	vec3 col = mix(outer.rgb, core.rgb, smoothstep(0.9, 1.4, heat)) * heat * 0.8;
	COLOR = vec4(col, 1.0);
}

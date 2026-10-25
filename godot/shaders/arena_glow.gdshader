shader_type canvas_item;
render_mode blend_add;
// A light in an arena (scripts/duel/arena_life.gd): a soft glow on its own rhythm. A flame flickers
// and wavers (candles, lanterns, torches), a pulse swells and fades (mushrooms, tanks, glow sticks),
// a screen jitters and drops out, a beacon blinks, a lamp breathes. Each light has its own seed.

uniform vec4 color : source_color = vec4(1.0, 0.75, 0.4, 1.0);
uniform float strength = 0.35;
uniform int mode = 0;      // 0 breathe, 1 flame, 2 pulse, 3 screen, 4 blink
uniform float speed = 1.0;
uniform float seed = 0.0;
uniform float core = 0.0;  // a small hot centre (the flame itself)

float hash(float n) { return fract(sin(n * 12.9898 + 4.1) * 43758.5453); }
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float t = TIME * speed + seed * 17.0;
	float k = 1.0;
	vec2 c = vec2(0.5);
	if (mode == 0) {
		k = 0.82 + 0.18 * sin(t * 1.4);
	} else if (mode == 1) {
		// a flame: quick uneven flicker over a slower sway, a gust now and then, the light wavering
		k = 0.6 + 0.28 * noise1(t * 7.0) + 0.18 * noise1(t * 21.0 + 3.0);
		k *= 1.0 - 0.3 * smoothstep(0.86, 1.0, noise1(t * 1.7 + 9.0));
		c += (vec2(noise1(t * 2.6), noise1(t * 2.6 + 5.0)) - 0.5) * 0.05;
	} else if (mode == 2) {
		k = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 1.8));
	} else if (mode == 3) {
		k = 0.75 + 0.25 * hash(floor(t * 11.0) + seed);
		k *= 1.0 - 0.7 * step(0.94, hash(floor(t * 2.5) + seed * 3.0));
	} else {
		k = step(0.62, fract(t * 0.55)) * (0.85 + 0.15 * sin(t * 30.0));
	}
	float d = length(UV - c) * 2.0;
	float glow = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
	float hot = core * pow(clamp(1.0 - d * 5.0, 0.0, 1.0), 2.0);
	COLOR = vec4(color.rgb * (glow * strength + hot) * k, 1.0);
}

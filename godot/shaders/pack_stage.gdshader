shader_type canvas_item;
// The pack opening's stage (scripts/ui/pack_opening.gd), on a full-screen rect: a dark room lit from
// the centre in the clan's colour, with drifting haze, a pool of light on the floor, slow god rays
// (stronger as the pack tears open and for rare cards) and an edge glow that pulses before a big reveal.

uniform vec4 glow_color : source_color = vec4(0.6, 0.35, 1.0, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float glow = 0.6;
uniform float rays = 0.0;
uniform float pulse = 0.0;
uniform vec2 center = vec2(0.5, 0.45);
uniform float aspect = 1.7777778;

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
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 col = vec3(0.012, 0.012, 0.03);
	// Light from the centre, through drifting haze
	float haze = noise(p * 2.6 + vec2(TIME * 0.035, -TIME * 0.025)) * 0.6 + noise(p * 6.5 - vec2(TIME * 0.06, 0.0)) * 0.4;
	col += glow_color.rgb * glow * (exp(-r * 2.3) * 0.5 + haze * 0.07 * exp(-r * 1.1));
	// God rays: a few sets of soft bands turning slowly (whole numbers of bands, so no seam)
	float b = pow(max(0.0, sin(a * 7.0 + TIME * 0.32)), 8.0)
		+ pow(max(0.0, sin(a * 11.0 - TIME * 0.45 + 1.7)), 12.0) * 0.8
		+ pow(max(0.0, sin(a * 4.0 + TIME * 0.18 + 0.6)), 16.0) * 0.6;
	b *= 0.6 + 0.4 * noise(vec2(a * 3.0, TIME * 0.5));
	col += ray_color.rgb * rays * b * exp(-r * 1.05) * smoothstep(0.02, 0.14, r);
	// A pool of light on the floor under the stage
	float fy = UV.y - 0.88;
	col += glow_color.rgb * glow * 0.16 * exp(-fy * fy * 80.0) * exp(-abs(p.x) * 1.5);
	// Vignette, and the edges glowing in time with a build-up
	col *= mix(0.22, 1.0, smoothstep(1.3, 0.22, r));
	col += glow_color.rgb * pulse * smoothstep(0.5, 1.15, r) * 0.6;
	COLOR = vec4(col, 1.0);
}

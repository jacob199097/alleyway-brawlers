shader_type canvas_item;
render_mode blend_add;
// The ground splitting open (Underworld's summon, scripts/duel/duel.gd): a web of glowing cracks spreads
// out from the middle as "open" grows, with molten light pooled in the centre, then cools as "heat" falls.

uniform vec4 color : source_color = vec4(0.72, 0.3, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.45, 0.6, 1.0);
uniform float open = 0.0;   // 0..1: how far the cracks have run
uniform float heat = 1.0;   // 1 glowing, 0 gone
uniform float seed = 0.0;
uniform float gain = 1.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1)) + seed) * 24634.63); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance to the nearest cell border of a Voronoi pattern: the crack lines
float cracks(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 o = hash2(n + g);
		vec2 r = g + o - f;
		float d = dot(r, r);
		if (d < md) { md = d; mr = r; mg = g; }
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
		vec2 g = mg + vec2(float(i), float(j));
		vec2 o = hash2(n + g);
		vec2 r = g + o - f;
		if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
	}
	return md;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p * vec2(1.0, 1.35));
	// cracks: fine near the middle, wider apart further out; wobbly edges
	vec2 q = p * 4.2 + (vec2(noise(p * 6.0), noise(p * 6.0 + 5.0)) - 0.5) * 0.35;
	float e = cracks(q);
	float line = exp(-e * e * 2200.0) + 0.3 * exp(-e * e * 300.0);
	float reach = 1.0 - smoothstep(open * 1.05 - 0.15, open * 1.05, r);
	float fade = 1.0 - smoothstep(0.55, 1.0, r);
	float flicker = 0.85 + 0.15 * noise(vec2(TIME * 6.0, r * 4.0));
	vec3 c = mix(color.rgb, hot.rgb, exp(-r * 3.0));
	float pool = exp(-r * r * 9.0) * open;
	vec3 col = c * (line * reach * fade * 1.3 + pool * 0.8) * heat * flicker * gain;
	COLOR = vec4(col, 1.0);
}

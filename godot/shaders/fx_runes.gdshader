shader_type canvas_item;
render_mode blend_add;
// A summoning circle (scripts/duel/duel.gd): two rings, a band of glyph-like marks between them and a
// star inside, turning slowly; "open" draws it on, "life" fades it.

uniform vec4 color : source_color = vec4(0.75, 0.35, 1.0, 1.0);
uniform float open = 1.0;
uniform float life = 1.0;
uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 12.9898 + seed) * 43758.5453); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * 0.6;
	float sweep = step(fract(a / 6.2832 + 0.5), open);   // drawn on round the circle
	float ring = exp(-pow((r - 0.92) * 90.0, 2.0)) + exp(-pow((r - 0.66) * 90.0, 2.0)) * 0.8 + exp(-pow((r - 0.96) * 140.0, 2.0)) * 0.5;
	// glyphs: little runes in the band, each a stroke or two of its own shape
	float cells = 22.0;
	float u = (a + 3.1416) / 6.2832 * cells;
	float seg = floor(u);
	vec2 cp = vec2((fract(u) - 0.5) * 1.6, (r - 0.79) / 0.09);   // (-0.8..0.8 across, -1..1 up the band)
	float h1 = hash(seg), h2 = hash(seg + 3.0), h3 = hash(seg + 9.0);
	float stem = 1.0 - smoothstep(0.03, 0.09, abs(cp.x - (h1 - 0.5) * 0.6));
	stem *= step(abs(cp.y), 0.75);
	float slash = 1.0 - smoothstep(0.03, 0.09, abs(cp.y - cp.x * (h2 * 2.0 - 1.0) * 1.6 - (h3 - 0.5) * 0.6));
	slash *= step(abs(cp.x), 0.45) * step(abs(cp.y), 0.8);
	float dot2 = 1.0 - smoothstep(0.06, 0.12, length(cp - vec2((h3 - 0.5) * 0.8, 0.55)));
	float glyph = max(stem, max(slash * step(0.3, h2), dot2 * step(0.6, h1))) * step(abs(cp.y), 1.0);
	// a five-pointed star inside, turning the other way
	float star = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 s0 = vec2(cos(float(i) * 2.5133 - TIME * 0.4), sin(float(i) * 2.5133 - TIME * 0.4)) * 0.62;
		vec2 s1 = vec2(cos(float(i + 2) * 2.5133 - TIME * 0.4), sin(float(i + 2) * 2.5133 - TIME * 0.4)) * 0.62;
		vec2 pa = p - s0;
		vec2 ba = s1 - s0;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		star = max(star, exp(-pow(length(pa - ba * h) * 90.0, 2.0)));
	}
	float glow = exp(-pow((r - 0.8) * 4.0, 2.0)) * 0.25;
	float v = (ring + glyph + star * 0.7) * sweep + glow * open;
	COLOR = vec4(color.rgb * v * life * 1.6, 1.0);
}

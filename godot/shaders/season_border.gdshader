// A season border round a player's picture (UI.season_border; backend/economy/seasons.js honours): a metal rim
// in the colour of the rank reached that season, livelier the higher the rank.
//   level 1 Street Tough: the rim; 2 Enforcer: + a shine sweeping across it; 3 Underboss: + a pulsing glow;
//   4 Kingpin: + two lights running round it; 5 Legend: + sparks circling it.
// The rect covers the picture plus `margin` (a fraction of the rect) on every side; the picture shows through.
shader_type canvas_item;

uniform vec4 color : source_color = vec4(1.0, 0.83, 0.3, 1.0);
uniform float level = 1.0;
uniform float margin = 0.08;

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 p = UV - 0.5;
	float inner = 0.5 - margin;          // the picture's half size
	float t = margin * 0.62;             // the rim's width (outside the picture's edge)
	float d = sd_box(p, vec2(inner), margin * 0.25);
	float px = fwidth(d);
	float band = smoothstep(-px * 2.0, 0.0, d) * (1.0 - smoothstep(t - px * 1.5, t, d));
	// Metal: bright down its middle, darker at its edges, lit from the top left
	float f = clamp(d / t, 0.0, 1.0);
	float lit = dot(normalize(p + 1e-4), vec2(-0.7071, -0.7071)) * 0.5 + 0.5;
	vec3 metal = color.rgb * (0.55 + 0.55 * sin(f * 3.14159)) + vec3(0.35) * pow(lit, 3.0) * sin(f * 3.14159);
	vec3 col = metal;
	float a = band;
	// Enforcer and up: a shine sweeping across, corner to corner
	if (level >= 2.0) {
		float diag = (UV.x + UV.y) * 0.5;
		float w = fract(TIME * 0.28) * 1.8 - 0.4;
		col += vec3(1.0) * exp(-pow((diag - w) * 16.0, 2.0)) * 0.85 * band;
	}
	// Underboss and up: a glow round the outside, breathing
	if (level >= 3.0) {
		float out_d = max(d - t, 0.0);
		float pulse = 0.65 + 0.35 * sin(TIME * 2.2);
		float g = exp(-out_d / (margin * 0.22)) * step(t * 0.6, d) * pulse * 0.75;
		col = mix(col, color.rgb * 1.3, (1.0 - band) * clamp(g, 0.0, 1.0));
		a = max(a, g);
	}
	// Kingpin and up: two lights running round the rim
	if (level >= 4.0) {
		float ang = atan(p.y, p.x) / 6.28318 + 0.5;
		for (int i = 0; i < 2; i++) {
			float k = fract(ang - TIME * 0.18 + float(i) * 0.5);
			float run = exp(-pow(min(k, 1.0 - k) * 22.0, 2.0));
			col += vec3(1.0, 0.95, 0.85) * run * band * 1.2;
		}
	}
	// Legend: sparks circling just outside the rim
	if (level >= 5.0) {
		for (int i = 0; i < 12; i++) {
			float fi = float(i);
			float sp = 0.06 + 0.1 * hash(fi + 3.0);
			float an = hash(fi) * 6.28318 + TIME * sp * 6.28318 * (hash(fi + 7.0) > 0.5 ? 1.0 : -1.0);
			vec2 dir = vec2(cos(an), sin(an));
			float rr = inner + t * (0.6 + 1.1 * hash(fi + 11.0));
			vec2 at = dir / max(abs(dir.x), abs(dir.y)) * rr;   // (on a square round the rim)
			float tw = 0.5 + 0.5 * sin(TIME * (4.0 + 4.0 * hash(fi + 5.0)) + fi);
			float s = exp(-length(p - at) / (margin * 0.06)) * tw;
			col += mix(color.rgb, vec3(1.0), 0.6) * s * 1.5;
			a = max(a, s);
		}
	}
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * color.a);
}

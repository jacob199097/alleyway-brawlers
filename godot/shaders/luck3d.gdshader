shader_type canvas_item;
// A coin or a die in 3D (scripts/duel/duel.gd, luck effects), ray-marched in its rectangle:
// a thick metal coin (heads: a raised star in gold; tails: a ring of studs in silver) with a ridged edge,
// or an ivory die with rounded corners and sunken pips (1 opposite 6, 2 opposite 5, 3 opposite 4).
// "rot" turns it (object to view); light comes from the top left; "glow" rims it once it lands.

uniform int kind = 0;          // 0 coin, 1 die
uniform mat3 rot = mat3(1.0);
uniform vec4 glow : source_color = vec4(0.0);
uniform float flash = 0.0;     // a white glint as it lands

const float COIN_R = 0.62;
const float COIN_H = 0.075;
const float DIE_B = 0.42;
const float DIE_R = 0.09;

float sd_coin(vec3 p) {
	vec2 d = vec2(length(p.xy) - COIN_R, abs(p.z) - COIN_H);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - 0.02;
}

float sd_die(vec3 p) {
	vec3 q = abs(p) - vec3(DIE_B);
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - DIE_R;
}

float sd(vec3 p) {
	return kind == 0 ? sd_coin(p) : sd_die(p);
}

vec3 normal_at(vec3 p) {
	vec2 e = vec2(0.0015, 0.0);
	return normalize(vec3(sd(p + e.xyy) - sd(p - e.xyy), sd(p + e.yxy) - sd(p - e.yxy), sd(p + e.yyx) - sd(p - e.yyx)));
}

// The coin's raised design (height 0..1) at a point on its face: heads a star in a ring, tails studs
float coin_design(vec2 q, bool heads) {
	float r = length(q);
	float ring = smoothstep(0.035, 0.0, abs(r - 0.5));
	if (heads) {
		float a = atan(q.y, q.x) + 1.5708;
		float k = 0.5 + 0.5 * cos(a * 5.0);   // five points
		float star = smoothstep(0.02, -0.02, r - mix(0.16, 0.38, pow(k, 3.0)));
		return max(ring, star);
	}
	float a2 = atan(q.y, q.x);
	vec2 cell = vec2(cos(floor(a2 / 0.5236 + 0.5) * 0.5236), sin(floor(a2 / 0.5236 + 0.5) * 0.5236)) * 0.4;
	float studs = smoothstep(0.06, 0.035, length(q - cell));
	float hub = smoothstep(0.17, 0.13, r) - smoothstep(0.1, 0.07, r) * 0.6;
	return max(max(ring, studs), hub);
}

// The pips on a die face (u, v in -1..1 across the face), 1 where a pip is
float pips(vec2 uv, int n) {
	float d = 10.0;
	vec2 c = vec2(0.0);
	float s = 0.52;
	if (n == 1 || n == 3 || n == 5) d = min(d, length(uv));
	if (n >= 2) { d = min(d, length(uv - vec2(-s, -s))); d = min(d, length(uv - vec2(s, s))); }
	if (n >= 4) { d = min(d, length(uv - vec2(-s, s))); d = min(d, length(uv - vec2(s, -s))); }
	if (n == 6) { d = min(d, length(uv - vec2(-s, 0.0))); d = min(d, length(uv - vec2(s, 0.0))); }
	return smoothstep(0.2, 0.16, d);
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	vec3 ro = vec3(0.0, 0.0, 3.4);
	vec3 rd = normalize(vec3(uv.x, -uv.y, -2.4));
	mat3 inv = transpose(rot);
	float t = 0.0;
	float closest = 10.0;
	bool hit = false;
	vec3 p;
	for (int i = 0; i < 72; i++) {
		p = ro + rd * t;
		float d = sd(inv * p);
		closest = min(closest, d);
		if (d < 0.0008) { hit = true; break; }
		t += d * 0.9;
		if (t > 6.0) break;
	}
	if (!hit) {
		float halo = exp(-closest * 22.0) * glow.a;
		COLOR = vec4(glow.rgb, clamp(halo, 0.0, 1.0) * 0.85);
	} else {
		vec3 op = inv * p;
		vec3 n_obj = normal_at(op);
		vec3 albedo;
		float metal = 0.0;
		float rough = 0.5;
		if (kind == 0) {
			bool face = abs(n_obj.z) > 0.6;
			bool heads = op.z > 0.0;
			vec3 gold = vec3(1.0, 0.76, 0.28);
			vec3 silver = vec3(0.82, 0.85, 0.92);
			albedo = heads ? gold : silver;
			metal = 1.0;
			rough = 0.25;
			if (face) {
				// emboss: tilt the normal along the design's slope, darken its edges
				vec2 q = op.xy / COIN_R * vec2(heads ? 1.0 : -1.0, 1.0);
				float h = coin_design(q, heads);
				float hx = coin_design(q + vec2(0.01, 0.0), heads) - h;
				float hy = coin_design(q + vec2(0.0, 0.01), heads) - h;
				vec3 bump = normalize(vec3(-hx * 6.0, -hy * 6.0, 1.0));
				n_obj = normalize(vec3(bump.xy * vec2(heads ? 1.0 : -1.0, 1.0), sign(op.z) * bump.z));
				albedo *= mix(0.78, 1.08, h);
			} else {
				// the ridged edge
				float a = atan(op.y, op.x);
				float ridge = 0.5 + 0.5 * cos(a * 90.0);
				albedo *= mix(0.7, 1.0, ridge);
				n_obj = normalize(n_obj + vec3(-sin(a), cos(a), 0.0) * (ridge - 0.5) * 0.3);
			}
		} else {
			albedo = vec3(0.96, 0.94, 0.88);
			rough = 0.6;
			vec3 a = abs(op);
			int fv = 0;
			vec2 fuv = vec2(0.0);
			if (a.z >= a.x && a.z >= a.y) { fv = op.z > 0.0 ? 1 : 6; fuv = op.xy; }
			else if (a.x >= a.y) { fv = op.x > 0.0 ? 2 : 5; fuv = op.zy; }
			else { fv = op.y > 0.0 ? 3 : 4; fuv = op.xz; }
			float pip = pips(fuv / DIE_B, fv);
			albedo = mix(albedo, fv == 1 ? vec3(0.75, 0.05, 0.08) : vec3(0.06, 0.05, 0.1), pip);
			rough = mix(rough, 0.3, pip);
		}
		vec3 n = normalize(rot * n_obj);
		vec3 l = normalize(vec3(-0.5, 0.65, 0.6));
		vec3 v = -rd;
		vec3 hv = normalize(l + v);
		float diff = max(dot(n, l), 0.0);
		float spec = pow(max(dot(n, hv), 0.0), mix(90.0, 18.0, rough));
		// a simple studio around it, for the metal to reflect: warm above, dark below, a bright strip
		vec3 r = reflect(rd, n);
		vec3 env = mix(vec3(0.08, 0.06, 0.1), vec3(1.0, 0.92, 0.78), smoothstep(-0.2, 0.7, r.y));
		env += vec3(1.2) * smoothstep(0.92, 0.99, abs(dot(r, normalize(vec3(0.7, 0.4, 0.6)))));
		vec3 col;
		if (metal > 0.5) {
			col = albedo * (0.25 + 0.55 * diff) + albedo * env * 0.75 + vec3(1.0, 0.95, 0.85) * spec * 1.4;
		} else {
			col = albedo * (0.3 + 0.75 * diff) + vec3(1.0) * spec * 0.45 + env * 0.05;
		}
		float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
		col += glow.rgb * fres * glow.a * 0.9;   // the rim catches the result colour
		col = mix(col, vec3(1.0), flash);
		COLOR = vec4(col, 1.0);
	}
}

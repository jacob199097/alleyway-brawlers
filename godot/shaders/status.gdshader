shader_type canvas_item;
render_mode blend_premul_alpha;
// What a status looks like on a card in play (scripts/duel/card_view.gd): one sheet over the card, a little
// bigger than it, with each status's amount turned up from 0. BURN: flames along the edge nearest the
// bottom of the screen; POISON: a green murk pooling there, bubbles rising through it; BLEED: blood running
// down from the top; FREEZE: frost growing in from the edges, icicles under it; SHIELD: a film of gold
// hexagons; BLIND: smoke across the eyes. "up" is the way to the top of the screen in the card's own frame
// (a card lying sideways in DEF still burns upward).

uniform vec2 size = vec2(164.0, 215.0);   // the sheet, in pixels
uniform vec2 card = vec2(124.0, 175.0);   // the card in its middle
uniform vec2 up = vec2(0.0, -1.0);
uniform float burn = 0.0;
uniform float poison = 0.0;
uniform float bleed = 0.0;
uniform float frost = 0.0;
uniform float shield = 0.0;
uniform float blind = 0.0;
uniform float calm = 0.0;    // Photosensitive mode: 1 = no flicker
uniform float seed = 0.0;
uniform vec4 shield_color : source_color = vec4(1.0, 0.84, 0.35, 1.0);

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
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 3.1; a *= 0.5; }
	return v;
}
// Sharp ridges (ice crystals): bright along the creases of the noise
float ridges(vec2 p) {
	float v = 0.0;
	float a = 0.6;
	for (int i = 0; i < 3; i++) { v += a * (1.0 - abs(2.0 * noise(p) - 1.0)); p = p * 2.1 + 5.3; a *= 0.5; }
	return v;
}
// Distance to the nearest edge of a hexagon grid (0 on an edge)
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.732);
	vec2 a = mod(p, r) - r * 0.5;
	vec2 b = mod(p - r * 0.5, r) - r * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(g.x, dot(g, vec2(0.5, 0.866)));
}

void fragment() {
	vec2 p = (UV - 0.5) * size;          // pixels from the card's middle, in its own frame
	vec2 hc = card * 0.5;
	vec2 q = abs(p) - hc;
	float sd = max(q.x, q.y);            // below 0 inside the card
	float inside = 1.0 - smoothstep(-1.0, 1.0, sd);
	vec2 rt = vec2(-up.y, up.x);
	float ext_u = abs(up.x) * hc.x + abs(up.y) * hc.y;
	float ext_r = abs(rt.x) * hc.x + abs(rt.y) * hc.y;
	float h = dot(p, up);                // pixels above the middle, on screen
	float s = dot(p, rt);
	float y01 = (h + ext_u) / (2.0 * ext_u);   // 0 at the edge nearest the bottom of the screen, 1 at the top
	float t = TIME;
	float flick = 1.0 - calm;
	float rim = exp(-abs(sd) * 0.3);

	vec3 rgb = vec3(0.0);   // (premultiplied)
	float a = 0.0;

	if (poison > 0.001) {
		float pn = fbm(vec2(s * 0.035 + t * 0.12, h * 0.035 - t * 0.3) + 11.0);
		float level = 0.46 * poison + (pn - 0.5) * 0.3;
		float fog = (1.0 - smoothstep(level * 0.35, level, y01)) * inside * min(poison, 1.0);
		float fa = fog * 0.72;
		rgb = rgb * (1.0 - fa) + vec3(0.13, 0.46, 0.1) * fa;
		a += fa * (1.0 - a);
		rgb += vec3(0.45, 1.0, 0.35) * fog * (1.0 - fog) * 0.9;   // (its surface catching the light)
		// Bubbles rising through it
		vec2 g = vec2(s / 20.0, (h - t * 22.0) / 20.0);
		vec2 id = floor(g);
		float r1 = hash(id);
		vec2 f = fract(g) - 0.5 - (vec2(hash(id + 3.7), hash(id + 9.1)) - 0.5) * 0.4;
		float rad = 0.02 + 0.2 * r1;
		float some = step(0.66, r1);
		float ring = smoothstep(0.06, 0.0, abs(length(f) - rad)) * some;
		float shine = smoothstep(0.08, 0.0, length(f + vec2(rad * 0.4, -rad * 0.4))) * some;
		rgb += vec3(0.62, 1.0, 0.5) * (ring * 0.6 + shine * 0.5) * inside * (1.0 - smoothstep(level * 0.7, level * 1.25, y01)) * min(poison, 1.0);
		rgb += vec3(0.3, 0.95, 0.25) * rim * 0.3 * poison;
	}

	if (bleed > 0.001) {
		float d01 = 1.0 - y01;   // 0 at the top
		float cw = 12.0;
		float sw = s + (noise(vec2(d01 * 7.0, 1.7)) - 0.5) * 9.0;   // (the runs wander on their way down)
		float cx = floor(sw / cw);
		float r1 = hash(vec2(cx, 3.0));
		float len = (0.08 + 0.36 * r1) * (0.7 + 0.3 * sin(t * (0.4 + r1) * mix(1.0, 0.3, calm) + r1 * 6.28)) * bleed;
		float across = abs(fract(sw / cw) - 0.5);
		float width = (0.07 + 0.12 * r1) * (1.0 - 0.45 * smoothstep(0.0, len, d01));   // (thinner toward the end)
		float run = (1.0 - smoothstep(width * 0.5, width, across)) * (1.0 - smoothstep(len - 0.015, len, d01));
		// the bead at the end of each run
		vec2 tip = vec2((fract(sw / cw) - 0.5) * cw, (d01 - len) * 2.0 * ext_u);
		run = max(run, 1.0 - smoothstep(1.4 + width * 5.0, 2.4 + width * 5.0, length(tip)));
		run *= step(0.45, r1) * inside;
		float wet = (1.0 - smoothstep(0.0, 0.05, d01)) * inside * 0.6 * min(bleed, 1.0);
		float ba = clamp(run * 0.9 + wet, 0.0, 0.92);
		rgb = rgb * (1.0 - ba) + vec3(0.55, 0.02, 0.07) * ba;
		a += ba * (1.0 - a);
		rgb += vec3(1.0, 0.35, 0.4) * run * (1.0 - smoothstep(0.0, width * 0.5, across)) * 0.25;   // (a wet glint down each run)
		rgb += vec3(0.9, 0.1, 0.2) * rim * 0.25 * bleed;
	}

	if (frost > 0.001) {
		float fn = fbm(p * 0.05 + 2.0);
		// How far in from the edge the ice has grown (past 1, as it lands, it closes over the whole card)
		float reach = min(frost, 1.0) * (8.0 + 30.0 * fn) + max(frost - 1.0, 0.0) * 70.0;
		float ice = (1.0 - smoothstep(reach * 0.3, reach, -sd)) * inside;
		float cr = pow(ridges(p * 0.09), 3.0);
		float ia = clamp(ice * (0.4 + 0.5 * cr) + inside * (0.06 + 0.13 * cr) * min(frost, 1.0), 0.0, 0.9);
		vec3 ic = mix(vec3(0.55, 0.8, 1.0), vec3(1.0), clamp(cr * 1.2, 0.0, 1.0));
		rgb = rgb * (1.0 - ia) + ic * ia;
		a += ia * (1.0 - a);
		// Icicles under the edge nearest the bottom of the screen
		float below = -(h + ext_u);
		float iw = 13.0;
		float r1 = hash(vec2(floor(s / iw), 7.0));
		float tooth = (1.0 - 2.0 * abs(fract(s / iw) - 0.5)) * (5.0 + 15.0 * r1) * min(frost, 1.0);
		float icicle = step(0.0, below) * (1.0 - smoothstep(tooth - 1.5, tooth, below)) * step(abs(s), ext_r - 2.0) * step(0.3, r1);
		rgb = rgb * (1.0 - icicle * 0.85) + vec3(0.8, 0.94, 1.0) * icicle * 0.85;
		a += icicle * 0.85 * (1.0 - a);
		// A glint sliding across
		float sweep = mod(t * 55.0, ext_r * 2.0 + 260.0) - ext_r - 60.0;
		rgb += vec3(0.85, 0.95, 1.0) * exp(-pow((s + h * 0.35 - sweep) / 9.0, 2.0)) * inside * 0.3 * flick * min(frost, 1.0);
		rgb += vec3(0.6, 0.9, 1.0) * rim * 0.4 * min(frost, 1.0);
	}

	if (blind > 0.001) {
		float by = -hc.y + card.y * 0.31;   // (across the eyes of the art)
		float bn = fbm(vec2(p.x * 0.05 - t * 0.35, p.y * 0.09 + t * 0.08) + 5.0);
		float band = (1.0 - smoothstep(7.0 + bn * 9.0, 13.0 + bn * 12.0, abs(p.y - by))) * inside * min(blind, 1.0);
		float sa = band * 0.92;
		rgb = rgb * (1.0 - sa) + vec3(0.03, 0.03, 0.07) * sa;
		a += sa * (1.0 - a);
		float wisp = fbm(vec2(p.x * 0.07 + t * 0.5, p.y * 0.07 - t * 0.2) + 9.0);
		rgb += vec3(0.5, 0.56, 0.75) * band * smoothstep(0.5, 0.8, wisp) * 0.35;
	}

	if (burn > 0.001) {
		float n = fbm(vec2(s * 0.045, h * 0.03 - t * 1.9));
		float n2 = fbm(vec2(s * 0.09 + 7.0, h * 0.06 - t * 2.7));
		float reach = (0.26 + 0.3 * n) * burn;
		float f = 1.0 - smoothstep(reach * 0.3, reach, y01 + (n2 - 0.5) * 0.2);
		f *= smoothstep(-0.1, 0.0, y01) * (1.0 - smoothstep(ext_r + 2.0, ext_r + 14.0, abs(s)));
		float heat = f * (0.5 + 0.95 * n2);
		heat *= mix(1.0, 0.85 + 0.15 * sin(t * 9.0 + s * 0.2), flick);
		rgb += mix(vec3(1.0, 0.22, 0.03), vec3(1.0, 0.88, 0.45), smoothstep(0.45, 1.05, heat)) * heat * min(burn, 1.3);
		// The card glowing hot at its edge, and charring where the fire sits
		rgb += vec3(1.0, 0.42, 0.1) * rim * 0.4 * min(burn, 1.5) * mix(1.0, 0.75 + 0.25 * sin(t * 6.0 + s * 0.1), flick);
		float charred = (1.0 - smoothstep(0.0, 0.3 * min(burn, 1.5), y01)) * inside * 0.3;
		a += charred * (1.0 - a);
	}

	if (shield > 0.001) {
		float sdg = sd - 5.0;
		float within = 1.0 - smoothstep(-1.0, 1.0, sdg);
		float line = smoothstep(0.07, 0.0, hex_edge(p / 15.0));
		float wave = 0.5 + 0.5 * sin(t * 2.6 - length(p) * 0.06);
		float edge = exp(-abs(sdg) * 0.45);
		float sweep = exp(-pow((h - (mod(t * 70.0, ext_u * 2.0 + 300.0) - ext_u - 40.0)) / 12.0, 2.0));
		vec3 sc = shield_color.rgb;
		rgb += sc * (line * (0.16 + 0.26 * wave + 0.5 * sweep * flick) * within + edge * (0.7 + 0.2 * wave)) * min(shield, 1.4);
		rgb += sc * within * 0.05 * shield;
	}

	COLOR = vec4(rgb, clamp(a, 0.0, 1.0)) * COLOR.a;
}

shader_type canvas_item;
// A flat card shown in 3D. The sprite's quad is enlarged by `margin`, and each pixel casts a ray
// onto the card plane rotated by y_rot / x_rot (degrees), so the card can lean toward the mouse,
// into its motion, or turn over (y_rot ±90) without the warping of a skewed quad.
// glare: light sheen that follows the tilt. foil: holographic rainbow for rare cards.
// galaxy: the nebula on a clan card back turns slowly around the crest (the Nebula back).

uniform float y_rot = 0.0;
uniform float x_rot = 0.0;
uniform float dist = 3.2;      // camera distance, in card widths (smaller = stronger perspective)
uniform float margin = 0.35;   // must match CardView.SHADER_MARGIN
uniform float glare = 0.0;
uniform float foil = 0.0;
uniform float holo = 0.0;     // 0..1: hovered Epic/Legendary: a strong rainbow sweep and twinkling glints
uniform float flash = 0.0;     // white hit-flash
uniform float shine = 0.0;        // Rare and up: a soft glint sweeps across the card every few seconds
uniform float shine_seed = 0.0;   // 0..1, so cards don't all glint at once
uniform float sparkle = 0.0;      // Legendary: a few faint twinkles, all the time
uniform float calm = 0.0;         // Photosensitive mode (UI.rarity_fx): no glints, twinkles or sweeping shine
uniform float veteran = 0.0;      // a veteran card's tier (UI.veteran_fx): its frame turns 1 bronze, 2 chrome, 3 gold (veteran_frame)
// art_fx: the card's art itself moves. 1 = Epic: its glowing parts (neon, eyes, energy, crystals) throb,
// with energy rippling up through them and a halo that breathes. 2 = Legendary: stronger, the glow
// shifts colour, the scene drifts gently and sparks rise. Only inside art_rect (the Forge card's art
// window, centred uv), so the frame and text stay still.
uniform float art_fx = 0.0;
uniform vec4 art_rect = vec4(-0.455, -0.374, 0.455, 0.07);
uniform float galaxy = 0.0;
uniform float galaxy_angle = 0.0;     // how far the swirl has turned (radians; CardView turns it)
uniform float galaxy_glow = 0.0;      // 0..1: brighter swirl and crest (hovered)
// radar: a beam sweeps around the emblem's rings (the Militia back), lighting blips as it passes.
// It turns by galaxy_angle and brightens with galaxy_glow, like the galaxy.
uniform float radar = 0.0;
uniform float radar_center_y = -0.044;   // the emblem's centre, as uv.y (card centre = 0)
uniform float radar_radius = 0.335;      // the outer ring, in card widths
// roulette: the wheel behind the crest turns (the Wildcard back), with a ball rolling the other way.
// roulette_tex: the wheel band as its own layer (RGB; A = how much of each pixel turns: the band, not
// the chips lying on it or the crest), the size of the card. It turns by galaxy_angle.
uniform float roulette = 0.0;
uniform sampler2D roulette_tex : filter_linear;
uniform vec2 roulette_center = vec2(0.0, -0.035);   // the wheel's centre, as uv (card centre = 0)
// hellfire: the Underworld back: its red cracks pulse, violet mist drifts up around the horned skull,
// and the skull's eyes glow. Brighter while hovered (galaxy_glow).
uniform float hellfire = 0.0;
uniform vec2 hell_eyes = vec2(0.056, -0.025);   // the skull's eyes: ±x and y, as uv (card centre = 0)
// embers: the Arsonists back: sparks drift up past the Molotov, swaying, each fading slowly in and out,
// and the fire in the art breathes. Brighter while hovered (galaxy_glow). Slow on purpose: no flicker.
uniform float embers = 0.0;
// The Molotov's flame on that back: its centre and radii, as uv (card centre = 0): it licks upward
uniform vec4 molotov_flame = vec4(0.03, -0.175, 0.16, 0.095);
uniform float reveal = 1.0;   // 0..1: the card burning into view from the bottom up (Underworld's rise), 1 = whole
uniform vec4 reveal_color : source_color = vec4(0.75, 0.35, 1.0, 1.0);   // the glowing edge of the reveal
uniform vec2 quad_size = vec2(0.0);   // Controls (TextureRect): the drawn size; sprites use the texture size

varying vec2 s;
varying vec4 vcol;
varying float aspect;

void vertex() {
	vec2 qs = quad_size.x > 0.0 ? quad_size : 1.0 / TEXTURE_PIXEL_SIZE;
	aspect = qs.y / qs.x;   // height / width
	s = (UV - 0.5) * (1.0 + margin) * vec2(1.0, aspect);
	VERTEX += (UV - 0.5) * qs * margin;
	vcol = COLOR;
}

// The Nebula crest: a disc with a cross of spikes (in card widths, centred)
float crest(vec2 p) {
	float disc = 1.0 - smoothstep(0.24, 0.29, length(p));
	float vbar = (1.0 - smoothstep(0.045, 0.085, abs(p.x))) * (1.0 - smoothstep(0.42, 0.48, abs(p.y + 0.04)));
	float hbar = (1.0 - smoothstep(0.04, 0.08, abs(p.y))) * (1.0 - smoothstep(0.3, 0.36, abs(p.x)));
	return max(disc, max(vbar, hbar));
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// How much a colour looks like a light source: bright and saturated (neon, glowing eyes), or near white
float glowness(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.001);
	return max(smoothstep(0.55, 0.85, mx) * smoothstep(0.35, 0.65, sat), smoothstep(0.86, 0.97, mx) * 0.6);
}

// The card's frame, plus a little inside it
float frame_mask(vec2 p, float asp) {
	return max(smoothstep(0.395, 0.435, abs(p.x)), smoothstep(0.405, 0.445, abs(p.y / asp)));
}

// A Forge card's own panels (centred uv: x and y each -0.5..0.5): name, art, type line, text, stats,
// card code. A veteran's frame is everything else, bar the clan crest (top right).
float in_rect(vec2 p, vec4 r) {
	return smoothstep(r.x - 0.004, r.x + 0.004, p.x) * (1.0 - smoothstep(r.z - 0.004, r.z + 0.004, p.x))
			* smoothstep(r.y - 0.003, r.y + 0.003, p.y) * (1.0 - smoothstep(r.w - 0.003, r.w + 0.003, p.y));
}
float veteran_frame(vec2 p, float asp) {
	float panel = max(max(in_rect(p, vec4(-0.378, -0.453, 0.344, -0.39)), in_rect(p, vec4(-0.461, -0.384, 0.464, 0.079))),
			max(max(in_rect(p, vec4(-0.333, 0.089, 0.333, 0.124)), in_rect(p, vec4(-0.464, 0.132, 0.464, 0.36))),
			max(in_rect(p, vec4(-0.461, 0.37, 0.461, 0.446)), in_rect(p, vec4(0.3, 0.459, 0.461, 0.49)))));
	float crest = 1.0 - smoothstep(0.05, 0.068, length(vec2(p.x - 0.425, (p.y + 0.445) * asp)));
	return (1.0 - panel) * (1.0 - crest);
}

void fragment() {
	float a = radians(y_rot);
	float b = radians(x_rot);
	mat3 ry = mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(b), sin(b)), vec3(0.0, -sin(b), cos(b)));
	mat3 r = ry * rx;
	vec3 c = vec3(0.0, 0.0, dist);
	vec3 rd = vec3(s, dist);
	vec3 n = r[2];
	float den = dot(n, rd);
	float lam = abs(den) < 1e-5 ? -1.0 : dot(n, c) / den;
	vec3 x = transpose(r) * (lam * rd - c);
	vec2 uv = x.xy / vec2(1.0, aspect);
	float inside = step(0.0, lam) * step(max(abs(uv.x), abs(uv.y)), 0.5);
	vec4 col = texture(TEXTURE, uv + 0.5);
	if (art_fx > 0.0) {
		float in_art = smoothstep(art_rect.x, art_rect.x + 0.012, uv.x) * (1.0 - smoothstep(art_rect.z - 0.012, art_rect.z, uv.x))
				* smoothstep(art_rect.y, art_rect.y + 0.01, uv.y) * (1.0 - smoothstep(art_rect.w - 0.01, art_rect.w, uv.y));
		if (in_art > 0.0) {
			float t = TIME + shine_seed * 20.0;
			bool legend = art_fx > 1.5;
			vec2 auv = uv;
			if (legend) {   // the whole scene drifts very slightly, like air moving through it
				vec2 w = vec2(vnoise(uv * 5.0 + vec2(t * 0.3, 0.0)), vnoise(uv * 5.0 + vec2(3.7, t * 0.25))) - 0.5;
				auv += w * 0.005 * in_art;
				col = mix(col, texture(TEXTURE, auv + 0.5), in_art);
			}
			vec3 base = col.rgb;
			float g = glowness(base);
			// Glowing parts nearby, for a halo that spills past their edges
			float halo = 0.0;
			vec3 hc = vec3(0.0);
			for (int i = 0; i < 8; i++) {
				float ang = float(i) * 0.7854;
				vec2 o = vec2(cos(ang), sin(ang) / aspect) * 0.014;
				vec3 sc = texture(TEXTURE, auv + 0.5 + o).rgb;
				float sg = glowness(sc);
				halo += sg;
				hc += sc * sg;
			}
			hc /= max(halo, 0.001);
			halo /= 8.0;
			float flow = vnoise(vec2(uv.x * 10.0, uv.y * 10.0 * aspect) + vec2(0.0, t * 0.9));   // energy rising
			float pulse = 0.5 + 0.5 * sin(t * 2.1 + flow * 6.28318);
			float k = legend ? 1.25 : 0.75;
			vec3 lit = base;
			if (legend) {   // the glow drifts through neighbouring hues
				vec3 rb = 0.5 + 0.5 * cos(6.28318 * (flow * 0.6 + t * 0.07 + vec3(0.0, 0.33, 0.67)));
				lit = mix(base, rb * max(base.r, max(base.g, base.b)), 0.35);
			}
			col.rgb += lit * g * (0.3 * pulse + 0.2 * flow) * k * in_art;
			col.rgb += hc * halo * (0.12 + 0.3 * pulse) * k * in_art;
			if (legend) {   // sparks rising through the art
				for (int L = 0; L < 2; L++) {
					float fl = float(L);
					vec2 q = vec2(uv.x, uv.y * aspect) * (9.0 + fl * 5.0) + vec2(fl * 3.1, t * (0.55 + fl * 0.3));
					vec2 cell = floor(q);
					float r = hash21(cell + fl * 17.0);
					vec2 f = fract(q) - 0.5 - vec2((hash21(cell + 5.0) - 0.5) * 0.6 + 0.12 * sin(t + r * 30.0), 0.0);
					float mote = smoothstep(0.11, 0.0, length(f)) * step(0.72, r) * (0.55 + 0.45 * sin(t * 3.0 + r * 40.0));
					col.rgb += mix(vec3(1.0, 0.85, 0.6), hc + 0.3, 0.5) * mote * 1.1 * in_art;
				}
			}
		}
	}
	if (galaxy > 0.0) {
		// Turn the swirl around the crest. The crest (a disc plus a cross of spikes) and the frame are
		// masked by shape on both ends: they stay put, and the turning swirl never drags copies of them
		vec2 p = vec2(uv.x, uv.y * aspect);   // card widths, centred
		float ang = -galaxy_angle;
		// The swirl is painted as a tall oval, like the card, so it turns along that oval (in texture
		// space): it rolls onto itself instead of being squashed sideways as it goes round
		vec2 te = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * uv;
		vec4 spun = texture(TEXTURE, te + 0.5);
		vec2 q = vec2(te.x, te.y * aspect);
		// ...and towards the edges it hands back to the still art, so the turning part flows into it
		float re = length(uv) * 2.0;   // 0 at the centre, 1 at the middle of each edge
		float settle = 1.0 - smoothstep(0.6, 0.98, re);
		float w = (1.0 - crest(p)) * (1.0 - crest(q)) * (1.0 - frame_mask(p, aspect)) * (1.0 - frame_mask(q, aspect)) * settle;
		col.rgb = mix(col.rgb, spun.rgb * (1.0 + 0.35 * galaxy_glow), w * galaxy);
		float rr = length(p);
		// The crest breathes
		col.rgb += vec3(0.55, 0.4, 1.0) * galaxy * (0.05 + 0.07 * (0.5 + 0.5 * sin(TIME * 1.6))) * (1.0 + 3.0 * galaxy_glow) * exp(-rr * rr * 60.0);
	}

	if (radar > 0.0) {
		vec2 p = vec2(uv.x, uv.y * aspect);
		vec2 pc = vec2(0.0, radar_center_y * aspect);
		vec2 q = p - pc;
		float r = length(q);
		float inside_r = 1.0 - smoothstep(radar_radius - 0.01, radar_radius + 0.004, r);
		float behind = mod(galaxy_angle - atan(q.y, q.x), 6.28318);   // 0 at the beam, growing behind it
		vec3 lime = vec3(0.66, 1.0, 0.25);
		col.rgb += lime * radar * inside_r * (exp(-behind * 2.4) * (0.2 + 0.22 * galaxy_glow) + smoothstep(0.035, 0.0, behind) * 0.4);
		for (int i = 0; i < 6; i++) {   // blips the beam lights up
			float fi = float(i);
			float ba = fi * 2.39 + 0.6;
			vec2 bp = pc + vec2(cos(ba), sin(ba)) * (0.07 + 0.042 * fi);
			float bb = mod(galaxy_angle - ba, 6.28318);
			col.rgb += lime * radar * exp(-bb * 2.6) * smoothstep(0.013, 0.0, length(p - bp)) * 0.95;
		}
		col.rgb += lime * radar * (0.06 + 0.06 * galaxy_glow) * (0.5 + 0.5 * sin(TIME * 2.2)) * smoothstep(0.006, 0.0, abs(r - radar_radius));
	}

	if (roulette > 0.0) {
		// The wheel band turns around its centre (in card widths, so it stays round); the chips on it and
		// the crest don't (the layer's alpha, read where the pixel is)
		vec2 d = (uv - roulette_center) * vec2(1.0, aspect);
		float ang = galaxy_angle;
		vec2 rd = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * d;
		vec3 wheel = texture(roulette_tex, roulette_center + rd / vec2(1.0, aspect) + 0.5).rgb;
		float w = texture(roulette_tex, uv + 0.5).a * roulette;
		col.rgb = mix(col.rgb, wheel * (1.0 + 0.3 * galaxy_glow), w);
		// The ball runs round the track the other way, faster
		float ba = -galaxy_angle * 2.7 + 1.3;
		vec2 bp = vec2(cos(ba), sin(ba)) * 0.318;
		float ball = smoothstep(0.016, 0.009, length(d - bp));
		float glint = smoothstep(0.006, 0.0, length(d - bp - vec2(-0.004, -0.004)));
		col.rgb = mix(col.rgb, vec3(0.95, 0.92, 0.85) + 0.3 * glint, ball * w);
		// Lights round the rim chase the turn, brighter while hovered
		float r = length(d);
		float rim = smoothstep(0.012, 0.0, abs(r - 0.37)) * (0.5 + 0.5 * sin(atan(d.y, d.x) * 18.0 - galaxy_angle * 9.0));
		col.rgb += vec3(1.0, 0.75, 0.3) * rim * w * (0.12 + 0.25 * galaxy_glow);
	}

	if (hellfire > 0.0) {
		vec2 p = vec2(uv.x, uv.y * aspect);
		// The red cracks throb, unevenly
		float red = clamp((col.r - max(col.g, col.b)) * 3.0, 0.0, 1.0);
		float throb = 0.5 + 0.5 * sin(TIME * 2.2 + vnoise(p * 6.0) * 5.0);
		col.rgb += vec3(1.0, 0.15, 0.22) * red * throb * 0.6 * hellfire * (1.0 + 0.8 * galaxy_glow);
		// Violet mist rising, thinner over the skull
		float mist = vnoise(vec2(p.x * 5.0, p.y * 4.0 + TIME * 0.35)) * vnoise(vec2(p.x * 3.0 + 1.7, p.y * 2.5 + TIME * 0.22));
		float away = smoothstep(0.12, 0.42, length(p - vec2(0.0, hell_eyes.y * aspect)));
		col.rgb += vec3(0.55, 0.25, 0.95) * mist * (0.4 + 0.3 * galaxy_glow) * away * hellfire;
		// The skull's eyes glow
		for (int i = 0; i < 2; i++) {
			vec2 e = vec2((i == 0 ? -1.0 : 1.0) * hell_eyes.x, hell_eyes.y * aspect);
			float g = exp(-pow(length(p - e) / 0.03, 2.0));
			col.rgb += vec3(0.85, 0.45, 1.0) * g * (0.55 + 0.45 * sin(TIME * 3.0 + float(i) * 0.7)) * hellfire * (1.0 + 1.2 * galaxy_glow);
		}
	}

	if (embers > 0.0) {
		vec2 p = vec2(uv.x, uv.y * aspect);
		// The Molotov's flame burns: inside it the art is redrawn rippling upward like real fire (most at
		// the tips, none at the rag), and its hot colours flare and settle
		vec2 fd = (uv - molotov_flame.xy) / molotov_flame.zw;
		float fm = smoothstep(1.0, 0.55, length(fd)) * embers;
		if (fm > 0.0) {
			float rise = clamp(0.5 - fd.y * 0.5, 0.0, 1.0);   // 0 at the bottom of the flame, 1 at the top
			vec2 fq = vec2(uv.x * 22.0, uv.y * 14.0 + TIME * 2.4);
			vec2 off = vec2(vnoise(fq) - 0.5, (vnoise(fq + vec2(5.2, 1.3)) - 0.5) * 0.6) * 0.022 * rise * fm;
			off.y += 0.006 * rise * fm * (0.5 + 0.5 * sin(TIME * 3.1 + uv.x * 30.0));   // (tongues licking up)
			col = mix(col, texture(TEXTURE, uv + 0.5 + off), fm);
			float hot = clamp((col.r - col.b) * 1.6 - 0.35, 0.0, 1.0) * smoothstep(0.35, 0.8, col.r);
			float flick = 0.5 + 0.5 * sin(TIME * 5.0 + vnoise(vec2(TIME * 2.0, uv.y * 18.0)) * 6.0);
			col.rgb += vec3(1.0, 0.6, 0.2) * hot * flick * 0.28 * fm * (1.0 + 0.6 * galaxy_glow);
		}
		// The fire in the art (its hot orange and yellow) swells and settles, unevenly
		float fire = clamp((col.r - col.b) * 1.6 - 0.35, 0.0, 1.0) * smoothstep(0.35, 0.8, col.r);
		float breathe = 0.5 + 0.5 * sin(TIME * 1.7 + vnoise(p * 5.0 + vec2(0.0, TIME * 0.4)) * 4.0);
		col.rgb += vec3(1.0, 0.45, 0.1) * fire * breathe * 0.35 * embers * (1.0 + 0.8 * galaxy_glow);
		// Sparks drifting up: one to a cell of a grid that rises, two layers (near: bigger and faster)
		for (int l = 0; l < 2; l++) {
			float sc = l == 0 ? 9.0 : 15.0;
			vec2 q = p * sc + vec2(0.0, TIME * (l == 0 ? 0.8 : 0.9));
			vec2 cell = floor(q);
			float rnd = fract(sin(dot(cell, vec2(12.9898, 78.233)) + float(l) * 7.1) * 43758.5453);
			vec2 c = vec2(0.5 + 0.3 * sin(TIME * 1.3 + rnd * 20.0 + q.y * 0.7), 0.5 + 0.35 * (fract(rnd * 7.3) - 0.5));
			float spark = smoothstep(l == 0 ? 0.09 : 0.07, 0.0, length(fract(q) - c)) * step(0.72, rnd);
			float glow = 0.5 + 0.5 * sin(TIME * 0.9 + rnd * 30.0);
			col.rgb += vec3(1.0, 0.55, 0.15) * spark * glow * embers * (0.55 + 0.4 * galaxy_glow);
		}
	}

	// A soft diagonal band of light that slides across as the card tilts
	float band = uv.x * 0.8 + uv.y * 0.55 + y_rot / 40.0 - x_rot / 55.0;
	float sheen = exp(-band * band * 14.0);
	col.rgb += sheen * glare * 0.32;
	if (foil > 0.0) {
		float h = fract(band * 1.3 + uv.y * 0.4 + TIME * 0.04);
		vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67)));
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		col.rgb += rainbow * foil * (0.04 + 0.2 * sheen + 0.22 * glare) * (0.3 + lum);
	}
	if (holo > 0.0) {
		// Rainbow bands that slide as the card tilts, plus scattered glints that twinkle
		float h2 = fract(uv.x * 0.9 - uv.y * 0.6 + y_rot / 30.0 + x_rot / 40.0 + TIME * 0.12);
		vec3 rb = 0.5 + 0.5 * cos(6.28318 * (h2 + vec3(0.0, 0.33, 0.67)));
		float lum2 = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		col.rgb += rb * holo * (0.12 + 0.22 * lum2);
		vec2 cell = floor((uv + 0.5) * vec2(16.0, 23.0));
		float rnd = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float tw = pow(max(0.0, sin(TIME * 2.6 + rnd * 40.0)), 22.0);
		col.rgb += vec3(1.0, 0.97, 0.9) * tw * step(0.8, rnd) * holo * 0.75 * (1.0 - calm);
	}
	if (veteran >= 1.0) {
		// A veteran's frame: its grey metal is plated, keeping its own shading: 1 bronze, 2 chrome with
		// a sheen that slides as the card tilts, 3 gold with a sheen and glints. The clan's own colours
		// (neon lines, coloured trim, camo, the crest) stay and glow brighter with each tier, so a clan
		// still reads at a glance. The art and text stay as they are.
		float fm = veteran_frame(uv, aspect);
		float lumv = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		float mxv = max(col.r, max(col.g, col.b));
		float clan_col = smoothstep(0.2, 0.45, (mxv - min(col.r, min(col.g, col.b))) / max(mxv, 0.001)) * smoothstep(0.08, 0.2, mxv);
		vec3 metal = veteran >= 3.0 ? vec3(1.0, 0.76, 0.28) : (veteran >= 2.0 ? vec3(0.8, 0.86, 0.96) : vec3(0.82, 0.48, 0.26));
		float amt = veteran >= 3.0 ? 0.86 : (veteran >= 2.0 ? 0.8 : 0.7);
		col.rgb = mix(col.rgb, metal * (0.18 + 1.45 * lumv), amt * fm * (1.0 - clan_col));
		float pulse = veteran >= 2.0 ? 0.75 + 0.25 * sin(TIME * 2.0 + shine_seed * 6.0) : 1.0;
		col.rgb *= 1.0 + clan_col * fm * 0.14 * veteran * pulse;
		// ...and a bevelled rim of the tier's metal all round the card's edge: the tier at a glance on any clan
		float ed = min(0.5 - abs(uv.x), (0.5 - abs(uv.y)) * aspect) / 0.025;   // (0 at the edge, 1 at the rim's inner side)
		float rim = 1.0 - smoothstep(0.85, 1.15, ed);
		float bevel = 0.55 + 0.75 * smoothstep(0.0, 0.3, ed) * (1.0 - smoothstep(0.45, 0.9, ed)) - 0.3 * smoothstep(0.85, 1.0, ed);
		col.rgb = mix(col.rgb, metal * bevel * (0.8 + 0.4 * lumv), rim * 0.92);
		if (veteran >= 2.0) {
			float hv = fract(uv.x * 0.7 - uv.y * 0.5 + y_rot / 30.0 + x_rot / 40.0 + TIME * 0.06);
			col.rgb += mix(vec3(1.0), metal, 0.5) * pow(0.5 + 0.5 * cos(6.28318 * hv), 10.0) * (0.12 + 0.35 * lumv) * fm;
		}
		if (veteran >= 3.0) {
			vec2 cell = floor((uv + 0.5) * vec2(22.0, 31.0));
			float rnd = fract(sin(dot(cell, vec2(27.17, 61.3))) * 31718.927);
			vec2 inc = fract((uv + 0.5) * vec2(22.0, 31.0)) - 0.5;
			float tw = pow(max(0.0, sin(TIME * 2.1 + rnd * 40.0)), 26.0) * step(0.7, rnd);
			col.rgb += vec3(1.0, 0.92, 0.65) * tw * smoothstep(0.35, 0.0, length(inc)) * fm * 0.9 * (1.0 - calm);
		}
	}
	if (shine > 0.0 && calm < 0.5) {
		// A glint crosses the card in the first ~2 s of every 6.5 s, then rests
		float t = fract(TIME / 6.5 + shine_seed);
		float pos = mix(-1.4, 1.4, smoothstep(0.0, 0.32, t));
		float d = uv.x * 0.75 + uv.y * 0.45 - pos;
		float lum3 = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		col.rgb += vec3(1.0, 0.95, 0.85) * exp(-d * d * 60.0) * shine * (0.26 + 0.42 * lum3) * (1.0 - smoothstep(0.3, 0.34, t));
	}
	if (sparkle > 0.0) {
		vec2 cell2 = floor((uv + 0.5) * vec2(11.0, 16.0));
		float rnd2 = fract(sin(dot(cell2, vec2(41.31, 17.77)) + shine_seed * 9.0) * 24634.6345);
		float tw2 = pow(max(0.0, sin(TIME * 1.7 + rnd2 * 50.0)), 30.0);
		vec2 inc = fract((uv + 0.5) * vec2(11.0, 16.0)) - 0.5;
		col.rgb += vec3(1.0, 0.93, 0.7) * tw2 * step(0.86, rnd2) * sparkle * 0.6 * smoothstep(0.3, 0.0, length(inc));
	}
	col.rgb = mix(col.rgb, vec3(1.0), flash);
	if (reveal < 1.0) {
		// a ragged line of embers climbs the card; below it the card is there, above it not yet
		float h = 0.5 - uv.y / aspect;
		float edge = reveal * 1.25 - 0.12 + (vnoise(vec2(uv.x * 11.0, TIME * 2.0)) - 0.5) * 0.1 + (vnoise(uv * 26.0) - 0.5) * 0.05;
		float d = edge - h;
		float band = 1.0 - smoothstep(0.0, 0.07, d);
		col.rgb = col.rgb * smoothstep(-0.02, 0.09, d) + reveal_color.rgb * band * 2.2 * step(0.0, d);
		col.a *= smoothstep(0.0, 0.012, d);
	}
	col.a *= inside;
	COLOR = col * vcol;
}

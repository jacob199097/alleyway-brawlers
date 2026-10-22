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
		col.rgb += vec3(1.0, 0.97, 0.9) * tw * step(0.8, rnd) * holo * 0.75;
	}
	if (shine > 0.0) {
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
	col.a *= inside;
	COLOR = col * vcol;
}

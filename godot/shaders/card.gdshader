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
uniform float veteran = 0.0;      // a veteran card's tier (UI.veteran_fx): a metal rim and corner brackets, 1 bronze, 2 chrome, 3 gold
// art_fx: the card's art itself moves. 1 = Epic: its glowing parts (neon, eyes, energy, crystals) throb,
// with energy rippling up through them and a halo that breathes. 2 = Legendary: stronger, the glow
// shifts colour, the scene drifts gently and sparks rise. Only inside art_rect (the Forge card's art
// window, centred uv), so the frame and text stay still.
uniform float art_fx = 0.0;
uniform vec4 art_rect = vec4(-0.455, -0.374, 0.455, 0.07);
// art_anim: the card's own animated art, chosen per card in the Forge (card.artFx, UI.rarity_fx): the picture
// moves inside art_rect. 1 water (rippling), 2 heat (shimmer), 3 sway (cloth, leaves, smoke), 4 drift (fog,
// stars, a slow breath through the scene). art_amp: how far it moves; art_speed: how fast. What moves:
// art_mask 0 all of it, 1 its glowing parts (glowness), 2 pixels near art_key (within art_tol).
// art_sparks: glints twinkling over the moving parts (0 none .. 1 many), in art_spark's colour.
uniform float art_anim = 0.0;
uniform float art_amp = 1.0;
uniform float art_speed = 1.0;
uniform float art_mask = 0.0;
uniform vec4 art_key : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float art_tol = 0.25;
uniform float art_sparks = 0.0;
uniform vec4 art_spark : source_color = vec4(1.0, 0.95, 0.8, 1.0);
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
// streetlight: the generic AlleyWay Brawlers back (Neutral cards'): rain falls through the warm light
// over the logo, the light hums, a glint slides across the logo now and then, and drops ripple the
// puddles at the bottom. Brighter while hovered (galaxy_glow). Slow on purpose: no flicker.
uniform float streetlight = 0.0;
uniform float street_light_y = -0.04;   // the light's (and the logo's) centre, as uv.y (card centre = 0)
// tide: the Pirates back: the night sea around the ship's-wheel emblem swells, its waves rolling across
// the card, light runs along the wave crests, the emblem's teal glow breathes and a glint runs over its brass every few seconds.
// Brighter while hovered (galaxy_glow). Slow on purpose: no flicker.
uniform float tide = 0.0;
uniform float tide_center_y = -0.033;   // the emblem's centre, as uv.y (card centre = 0)
uniform float reveal = 1.0;   // 0..1: the card burning into view from the bottom up (Underworld's rise), 1 = whole
uniform vec4 reveal_color : source_color = vec4(0.75, 0.35, 1.0, 1.0);   // the glowing edge of the reveal
uniform vec2 quad_size = vec2(0.0);   // Controls (TextureRect): the drawn size; sprites use the texture size
// The match's light on the card (CardView): the arena's colour (scene_light, a = strength) coming from
// scene_dir (card space, y down: (0, 1) = from below), brighter on that side and along that edge, and
// stronger as the card tilts toward it; a big effect nearby (burst_light) flashes its colour from its side.
uniform vec4 scene_light : source_color = vec4(0.0);
uniform vec2 scene_dir = vec2(0.0, -1.0);
uniform vec4 burst_light : source_color = vec4(0.0);
uniform vec2 burst_dir = vec2(0.0);
uniform float parallax = 0.0;   // 0..1: the art sits a little behind its window, shifting against the frame as the card tilts
uniform float smoulder = 0.0;   // 0..1: a Downed card's edges charred, with embers creeping along them (CardView)

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

// A veteran's metal: a thin rim round the card's edge and an L-shaped bracket at each corner, longer with
// each tier, like a graded card in its holder. Returns (coverage, bevel 0..1 across the metal's width).
// The clan's own frame underneath is left as it was drawn. dx, dy: distance from the nearest side, in card widths.
vec2 veteran_metal(float dx, float dy, float tier) {
	float rim_w = 0.016;
	float th = 0.034;
	float len = 0.06 + 0.035 * tier;
	float rim = 1.0 - smoothstep(rim_w - 0.003, rim_w, min(dx, dy));
	float arm_v = (1.0 - smoothstep(th - 0.003, th, dx)) * (1.0 - smoothstep(len - 0.004, len, dy));
	float arm_h = (1.0 - smoothstep(th - 0.003, th, dy)) * (1.0 - smoothstep(len - 0.004, len, dx));
	float bracket = max(arm_v, arm_h);
	float cover = max(rim, bracket);
	float w = bracket > rim ? th : rim_w;
	float e = clamp(min(dx, dy) / w, 0.0, 1.0);   // 0 at the outer edge, 1 at the inner
	float bevel = 0.55 + 0.75 * smoothstep(0.0, 0.25, e) * (1.0 - smoothstep(0.45, 0.85, e)) - 0.25 * smoothstep(0.8, 1.0, e);
	// (the bracket's inner corner: a darker groove where it meets the frame)
	bevel -= 0.25 * bracket * smoothstep(0.85, 1.0, e);
	return vec2(cover, bevel);
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
	if (parallax > 0.0) {
		// Parallax: inside the art window the picture is zoomed in a touch and slides against the tilt, easing to
		// nothing at the window's edge, so the art reads as behind the frame (everything after follows the art)
		vec2 lo = art_rect.xy, hi = art_rect.zw;
		float edge = min(min(uv.x - lo.x, hi.x - uv.x), min(uv.y - lo.y, hi.y - uv.y));
		if (edge > 0.0) {
			float k = smoothstep(0.0, 0.05, edge) * parallax;
			vec2 mid = (lo + hi) * 0.5;
			vec2 slide = clamp(vec2(-y_rot, x_rot) / 24.0, vec2(-1.0), vec2(1.0)) * vec2(0.018, 0.012);
			uv = mix(uv, mid + (uv - mid) * 0.955 + slide, k);
		}
	}
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
	if (art_anim > 0.5) {
		float in_art = smoothstep(art_rect.x, art_rect.x + 0.012, uv.x) * (1.0 - smoothstep(art_rect.z - 0.012, art_rect.z, uv.x))
				* smoothstep(art_rect.y, art_rect.y + 0.01, uv.y) * (1.0 - smoothstep(art_rect.w - 0.01, art_rect.w, uv.y));
		if (in_art > 0.0) {
			float t = (TIME + shine_seed * 20.0) * art_speed;
			vec2 p = vec2(uv.x, uv.y * aspect);   // card widths, centred
			int kind = int(art_anim + 0.5);
			vec2 off = vec2(0.0);
			if (kind == 1) {   // water: two drifting noise fields, like light through ripples
				off = (vec2(vnoise(p * 12.0 + vec2(t * 0.4, t * 0.12)), vnoise(p * 12.0 + vec2(3.7, -t * 0.35))) - 0.5) * 0.026;
			} else if (kind == 2) {   // heat: a fine horizontal shimmer rising through the picture
				float h = vnoise(p * 9.0 + vec2(0.0, -t * 0.9));
				off = vec2(sin(p.y * 70.0 + t * 3.0 + h * 6.0) * (0.3 + 0.7 * h) * 0.006, h * 0.002);
			} else if (kind == 3) {   // sway: a slow side-to-side wave, like wind through cloth or leaves
				float g = 0.5 + 0.5 * vnoise(p * 4.0 + vec2(t * 0.2, 0.0));
				off = vec2(sin(t * 1.2 + p.y * 6.0) * g * 0.009, cos(t * 0.9 + p.x * 5.0) * g * 0.003);
			} else {   // drift: the scene breathes, as if fog or starlight moved through it
				off = (vec2(vnoise(p * 4.0 + vec2(t * 0.25, 0.0)), vnoise(p * 4.0 + vec2(5.1, t * 0.2))) - 0.5) * 0.024;
			}
			off *= art_amp * in_art;
			float m = 1.0;
			if (art_mask > 1.5) m = 1.0 - smoothstep(art_tol * 0.5, art_tol, distance(col.rgb, art_key.rgb));
			else if (art_mask > 0.5) m = glowness(col.rgb);
			// Sample inside the art window only: the frame never bleeds into the moving picture
			vec2 suv = clamp(uv + off * m, art_rect.xy + 0.002, art_rect.zw - 0.002);
			col = mix(col, texture(TEXTURE, suv + 0.5), in_art);
			// Light that moves with it, so the motion reads even at a glance: caustics dancing on water,
			// a slow swell of light drifting through fog and starlight
			float la = min(art_amp, 2.0) * m * in_art;
			if (kind == 1) {
				float ca = 1.0 - abs(vnoise(p * 18.0 + vec2(t * 0.5, t * 0.2)) - vnoise(p * 18.0 + vec2(-t * 0.4, 2.3 + t * 0.3)));
				col.rgb += col.rgb * pow(ca, 7.0) * 0.55 * la;
			} else if (kind == 4) {
				float sw = vnoise(p * 2.2 + vec2(t * 0.18, -t * 0.07));
				col.rgb *= 1.0 + (sw - 0.45) * 0.4 * la;
			}
			if (art_sparks > 0.0 && calm < 0.5) {   // glints twinkling over the moving parts
				float dens = 0.95 - art_sparks * 0.35;
				for (int L = 0; L < 2; L++) {
					float fl = float(L);
					vec2 q = p * (11.0 + fl * 6.0) + vec2(fl * 2.3, 0.0);
					vec2 cell = floor(q);
					float r = hash21(cell + fl * 23.0);
					vec2 f = fract(q) - 0.5 - (vec2(hash21(cell + 7.0), hash21(cell + 11.0)) - 0.5) * 0.6;
					float tw = 0.5 + 0.5 * sin(t * (1.6 + fl * 0.7) + r * 40.0);
					float glint = smoothstep(0.09, 0.0, length(f)) * step(dens, r) * tw * tw;
					col.rgb += art_spark.rgb * glint * m * in_art * 0.9;
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

	if (streetlight > 0.0) {
		vec2 p = vec2(uv.x, uv.y * aspect);
		float inner = (1.0 - smoothstep(0.44, 0.452, abs(uv.x))) * (1.0 - smoothstep(0.456, 0.466, abs(uv.y)));   // (inside the steel border)
		// The light over the logo hums: its warm pool swells and settles, slowly and a little unevenly
		vec2 lc = vec2(0.0, street_light_y * aspect);
		float pool = exp(-pow(length((p - lc) * vec2(1.0, 0.8)) / 0.42, 2.0));
		float hum = 0.5 + 0.5 * sin(TIME * 1.3 + 1.5 * vnoise(vec2(TIME * 0.6, 0.0)));
		col.rgb += vec3(1.0, 0.62, 0.3) * pool * (0.05 + 0.07 * hum) * (1.0 + 1.5 * galaxy_glow) * inner * streetlight;
		// Rain: thin slanted streaks, one to a cell of a falling grid, two layers (near: longer and faster),
		// brightest where they pass through the light
		for (int l = 0; l < 2; l++) {
			vec2 q = vec2(p.x + p.y * 0.18, p.y) * (l == 0 ? vec2(34.0, 2.6) : vec2(56.0, 4.2));
			q.y -= TIME * (l == 0 ? 3.0 : 2.4);
			vec2 cell = floor(q);
			float rnd = hash21(cell + float(l) * 31.0);
			vec2 f = fract(q);
			float o = fract(rnd * 7.13) * 0.5;
			float streak = smoothstep(0.07, 0.0, abs(f.x - 0.5 - (fract(rnd * 3.7) - 0.5) * 0.6))
					* smoothstep(o, o + 0.08, f.y) * (1.0 - smoothstep(o + (l == 0 ? 0.32 : 0.22), o + (l == 0 ? 0.42 : 0.3), f.y)) * step(0.55, rnd);
			col.rgb += vec3(0.8, 0.86, 1.0) * streak * (0.07 + 0.32 * pool) * (l == 0 ? 1.0 : 0.6) * (1.0 + 0.6 * galaxy_glow) * inner * streetlight;
		}
		// The logo (its white and red letters) catches the light: a glint slides across it every few
		// seconds (not in Photosensitive mode), and the red glows with the hum
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		float red = clamp((col.r - max(col.g, col.b)) * 2.5 - 0.4, 0.0, 1.0);
		float letters = max(smoothstep(0.6, 0.85, lum), red) * (1.0 - smoothstep(0.36, 0.4, abs(uv.x))) * (1.0 - smoothstep(0.13, 0.15, abs(uv.y - street_light_y)));
		float sweep = fract(TIME * 0.16 + 0.3) / 0.35;   // (crosses in the first third of each turn)
		float d = uv.x + (uv.y - street_light_y) * 0.6 - mix(-0.55, 0.55, sweep);
		col.rgb += vec3(1.0, 0.95, 0.85) * exp(-d * d * 320.0) * step(sweep, 1.0) * letters * (0.45 + 0.3 * galaxy_glow) * (1.0 - calm) * streetlight;
		col.rgb += vec3(1.0, 0.2, 0.15) * red * letters * (0.08 + 0.1 * hum) * (1.0 + galaxy_glow) * streetlight;
		// Drops ripple the wet ground at the bottom: rings spreading, seen at an angle (flattened)
		vec2 rq = vec2(p.x, p.y * 2.6) * 6.0;
		vec2 rc = floor(rq);
		float rr = hash21(rc + 3.3);
		float age = fract(TIME * 0.45 + rr * 7.0);
		float rdist = length(fract(rq) - 0.5 - (vec2(hash21(rc + 1.1), hash21(rc + 2.2)) - 0.5) * 0.4);
		float ring = smoothstep(0.035, 0.0, abs(rdist - age * 0.42)) * (1.0 - age) * step(0.6, rr);
		col.rgb += vec3(1.0, 0.78, 0.55) * ring * smoothstep(0.14, 0.32, uv.y) * inner * 0.2 * (1.0 + galaxy_glow) * streetlight;
	}

	if (tide > 0.0) {
		vec2 p = vec2(uv.x, uv.y * aspect);
		vec2 ec = vec2(0.0, tide_center_y * aspect);
		float r = length(p - ec);
		float inner = (1.0 - smoothstep(0.44, 0.452, abs(uv.x))) * (1.0 - smoothstep(0.458, 0.468, abs(uv.y)));   // (inside the brass border)
		// The emblem is brass and bone (warm); the sea is teal and navy (cool)
		float warm = smoothstep(0.02, 0.12, col.r - col.b);
		// The sea swells: the art redrawn through waves that roll across the card, each rising and
		// falling as it passes, over a slow drifting chop (none on the emblem or the border)
		float calm_edge = (1.0 - smoothstep(0.40, 0.44, abs(uv.x))) * (1.0 - smoothstep(0.42, 0.458, abs(uv.y)));   // (fades out at the border)
		float open_sea = smoothstep(0.33, 0.40, r);   // (and round the wheel)
		vec2 sq = vec2(p.x * 3.0, p.y * 5.0);
		vec2 off = vec2(vnoise(sq + vec2(TIME * 0.35, 0.0)) - 0.5, vnoise(sq + vec2(3.7, TIME * 0.25)) - 0.5) * vec2(0.018, 0.010);
		float roll = TIME * 1.1 - p.x * 11.0 + p.y * 3.0;
		off.y += 0.008 * sin(roll) + 0.004 * sin(roll * 1.9 + 1.3 - p.y * 7.0);
		off.x += 0.010 * cos(roll * 0.8 + p.y * 5.0);
		off *= calm_edge * open_sea;
		vec4 rolled = texture(TEXTURE, uv + 0.5 + off);
		float sea = (1.0 - warm) * (1.0 - smoothstep(0.02, 0.12, rolled.r - rolled.b)) * inner;
		col.rgb = mix(col.rgb, rolled.rgb, sea * tide);
		// Light slides along the crests (the brighter teal), in long slow bands
		float crest = smoothstep(0.18, 0.45, col.g) * (1.0 - warm);
		float band = 0.5 + 0.5 * sin(p.x * 7.0 - p.y * 2.0 - TIME * 0.9 + vnoise(p * 4.0 + TIME * 0.2) * 4.0);
		col.rgb += vec3(0.45, 1.0, 0.9) * crest * band * band * 0.26 * inner * (1.0 + 0.8 * galaxy_glow) * tide;
		// ...and foam glints on the swell as each wave peaks
		float peak = smoothstep(0.75, 1.0, sin(roll)) * smoothstep(0.12, 0.35, col.g);
		col.rgb += vec3(0.6, 1.0, 0.95) * peak * 0.12 * calm_edge * open_sea * (1.0 - warm) * tide;
		// The emblem's teal glow breathes: the halo round the wheel swells and settles
		float halo = exp(-pow((r - 0.30) / 0.09, 2.0)) * (1.0 - warm);
		float breathe = 0.5 + 0.5 * sin(TIME * 1.2);
		col.rgb += vec3(0.25, 0.95, 0.85) * halo * (0.05 + 0.07 * breathe) * (1.0 + 2.0 * galaxy_glow) * tide;
		// A glint runs over the brass every few seconds (not in Photosensitive mode)
		float sweep = fract(TIME * 0.14 + 0.5) / 0.35;   // (crosses in the first third of each turn)
		float d = uv.x + (uv.y - tide_center_y) * 0.7 - mix(-0.5, 0.5, sweep);
		float brass = warm * (1.0 - smoothstep(0.44, 0.47, r));
		col.rgb += vec3(1.0, 0.9, 0.65) * exp(-d * d * 180.0) * step(sweep, 1.0) * brass * (0.7 + 0.3 * galaxy_glow) * (1.0 - calm) * tide;
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
		// A veteran: the clan's frame stays exactly as drawn; the tier shows in metal laid over its edge,
		// a thin rim and a bracket at each corner (veteran_metal): 1 bronze, 2 chrome with a sheen that
		// slides as the card tilts, 3 gold, longer brackets, the sheen and glints running along the metal.
		float dx = 0.5 - abs(uv.x);
		float dy = (0.5 - abs(uv.y)) * aspect;
		vec2 vm = veteran_metal(dx, dy, floor(veteran + 0.01));
		if (vm.x > 0.0) {
			vec3 metal = veteran >= 3.0 ? vec3(1.0, 0.78, 0.32) : (veteran >= 2.0 ? vec3(0.82, 0.88, 0.97) : vec3(0.8, 0.5, 0.28));
			// brushed grain along the metal, so it reads as metal and not paint
			float grain = 0.92 + 0.08 * vnoise(vec2(uv.x * 260.0, uv.y * 20.0) + vec2(uv.y * 40.0, 0.0));
			vec3 plate = metal * vm.y * grain;
			if (veteran >= 2.0) {
				float hv = fract(uv.x * 0.7 - uv.y * 0.5 + y_rot / 30.0 + x_rot / 40.0 + TIME * 0.06);
				plate += mix(vec3(1.0), metal, 0.4) * pow(0.5 + 0.5 * cos(6.28318 * hv), 12.0) * 0.55;
			}
			if (veteran >= 3.0 && calm < 0.5) {
				vec2 q = vec2(uv.x, uv.y * aspect) * 48.0;
				vec2 cell = floor(q);
				float rnd = fract(sin(dot(cell, vec2(27.17, 61.3))) * 31718.927);
				float tw = pow(max(0.0, sin(TIME * 2.1 + rnd * 40.0)), 26.0) * step(0.75, rnd);
				plate += vec3(1.0, 0.95, 0.75) * tw * smoothstep(0.4, 0.0, length(fract(q) - 0.5)) * 1.2;
			}
			col.rgb = mix(col.rgb, plate, vm.x * 0.95);
		}
		// a faint glow of the metal's colour just inside it, so the bracket sits on the card, not on top of it
		float near = max(1.0 - smoothstep(0.0, 0.03, min(dx, dy) - 0.016), 0.0) * (1.0 - vm.x);
		vec3 glow_c = veteran >= 3.0 ? vec3(1.0, 0.8, 0.35) : (veteran >= 2.0 ? vec3(0.75, 0.85, 1.0) : vec3(0.85, 0.5, 0.25));
		col.rgb += glow_c * near * 0.08 * veteran;
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
	if (smoulder > 0.0) {
		float e = min(0.5 - abs(uv.x), (0.5 - abs(uv.y)) * aspect);   // how far in from the nearest edge
		float n = vnoise(vec2(uv.x * 26.0, uv.y * 26.0 * aspect) + vec2(0.0, -TIME * 0.7));
		float n2 = vnoise(vec2(uv.x * 64.0, uv.y * 64.0 * aspect) + vec2(TIME * 0.3, -TIME * 1.3));
		float reach = 0.03 + 0.035 * n;   // a ragged burnt rim
		float burnt = 1.0 - smoothstep(reach * 0.5, reach, e);
		col.rgb *= 1.0 - burnt * 0.6 * smoulder;   // charred
		float line = 1.0 - smoothstep(0.0, reach * 0.45, abs(e - reach * 0.6));
		float ember = line * smoothstep(0.42, 0.78, n2) * (0.55 + 0.45 * sin(TIME * 4.0 + n * 14.0));
		col.rgb += vec3(1.0, 0.42, 0.1) * ember * 1.5 * smoulder * (calm > 0.5 ? 0.5 : 1.0);
	}
	if (scene_light.a > 0.0) {
		vec2 dir = normalize(scene_dir + vec2(1e-4));
		float side = dot(uv, dir) * 2.0;   // -1 the far edge, 1 the edge facing the light
		float facing = clamp(1.0 + dot(r[2].xy, dir) * 2.5, 0.5, 1.8);   // tilted toward it: more
		float key = smoothstep(-0.7, 1.0, side) * facing;
		float rim = pow(clamp(side, 0.0, 1.0), 7.0);
		col.rgb *= mix(vec3(1.0), 0.7 + scene_light.rgb * 0.45, scene_light.a * 0.6);   // the arena's colour over it
		col.rgb += scene_light.rgb * (key * 0.24 + rim * 0.5) * scene_light.a;
	}
	if (burst_light.a > 0.0) {
		float bl = length(burst_dir);
		float near_side = bl > 0.01 ? smoothstep(-0.9, 1.0, dot(uv, burst_dir / bl) * 2.0) : 1.0;
		col.rgb += burst_light.rgb * burst_light.a * (0.1 + 0.4 * near_side);
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

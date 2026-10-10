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
uniform float flash = 0.0;     // white hit-flash
uniform float galaxy = 0.0;
uniform float galaxy_angle = 0.0;     // how far the swirl has turned (radians; CardView turns it)
uniform float galaxy_glow = 0.0;      // 0..1: brighter swirl and crest (hovered)
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
	if (galaxy > 0.0) {
		// Turn the swirl around the crest. The crest (a disc plus a cross of spikes) and the frame are
		// masked by shape on both ends: they stay put, and the turning swirl never drags copies of them
		vec2 p = vec2(uv.x, uv.y * aspect);   // card widths, centred
		float ang = -galaxy_angle;
		vec2 q = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * p;
		vec4 spun = texture(TEXTURE, vec2(q.x, q.y / aspect) + 0.5);
		float w = (1.0 - crest(p)) * (1.0 - crest(q)) * (1.0 - frame_mask(p, aspect)) * (1.0 - frame_mask(q, aspect));
		col.rgb = mix(col.rgb, spun.rgb * (1.0 + 0.35 * galaxy_glow), w * galaxy);
		float rr = length(p);
		// The crest breathes
		col.rgb += vec3(0.55, 0.4, 1.0) * galaxy * (0.05 + 0.07 * (0.5 + 0.5 * sin(TIME * 1.6))) * (1.0 + 3.0 * galaxy_glow) * exp(-rr * rr * 60.0);
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
	col.rgb = mix(col.rgb, vec3(1.0), flash);
	col.a *= inside;
	COLOR = col * vcol;
}

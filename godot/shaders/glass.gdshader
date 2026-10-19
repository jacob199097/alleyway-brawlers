shader_type canvas_item;
// Frosted glass behind a panel (UI.glass): what's behind it, blurred and tinted, in a rounded rect,
// with a faint sheen along the top. Drawn by a node behind the panel's own box (show_behind_parent).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 12.0;
uniform float blur = 9.0;                                   // px
uniform vec4 tint : source_color = vec4(0.03, 0.03, 0.08, 0.6);
uniform float sheen = 0.05;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	float d = rounded_box(local - half_size, half_size, radius);
	float mask = clamp(0.5 - d, 0.0, 1.0);
	// A disc of taps around the pixel: the centre, then three rings of eight (turned against each other)
	vec2 px = SCREEN_PIXEL_SIZE * blur;
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb;
	float wsum = 1.0;
	for (int ring = 1; ring <= 3; ring++) {
		float rr = float(ring) / 3.0;
		float w = 1.0 - rr * 0.55;
		for (int k = 0; k < 8; k++) {
			float a = (float(k) + float(ring) * 0.5) * 0.7853982;
			acc += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * rr * px).rgb * w;
			wsum += w;
		}
	}
	vec3 col = mix(acc / wsum, tint.rgb, tint.a);
	col += sheen * smoothstep(0.4, 0.0, local.y / max(rect_size.y, 1.0));
	COLOR = vec4(col, mask);
}

shader_type canvas_item;
render_mode blend_add;
// A neon sign's glow (UI.image_button): the sign's own artwork blurred and added over it, so its
// tubes bloom; it breathes slowly, and `boost` lifts it on hover.

uniform float radius = 9.0;      // blur reach, in texels
uniform float strength = 0.55;
uniform float boost = 0.0;       // 0..1: hovered
uniform float seed = 0.0;        // keeps signs out of step with each other

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	vec4 acc = vec4(0.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236 + seed * 6.0;
		for (int r = 1; r <= 3; r++) {
			vec2 o = vec2(cos(a), sin(a)) * px * float(r) / 3.0;
			float w = 1.0 / float(r);
			acc += texture(TEXTURE, UV + o) * w;
			total += w;
		}
	}
	acc /= total;
	float breathe = 0.82 + 0.18 * sin(TIME * 1.3 + seed * 20.0);
	float k = (strength * breathe + boost * 0.6);
	COLOR = vec4(acc.rgb * k, acc.a * COLOR.a);
}

shader_type canvas_item;
// Full-screen hit effects for the duel, drawn over everything (see duel.gd _post):
//   wave_*      a shockwave ring rippling out from a point (UV coordinates)
//   aberration  RGB split pushed outward from wave_center, in pixels
//   impact      anime-style impact frame: the screen snaps to stark black with white silhouettes
//   danger      red vignette, pulsed by the duel while the player's Morale is low

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec2 wave_center = vec2(0.5, 0.5);
uniform float wave_radius = 0.0;     // in screen heights
uniform float wave_strength = 0.0;
uniform float aberration = 0.0;
uniform float impact = 0.0;
uniform vec4 impact_tint : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float danger = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // width / height
	vec2 d = (uv - wave_center) * vec2(asp, 1.0);
	float dl = length(d);
	vec2 dn = d / max(dl, 1e-4);

	if (wave_strength > 0.0) {
		float ring = dl - wave_radius;
		float w = exp(-ring * ring * 700.0) * wave_strength;
		uv -= dn / vec2(asp, 1.0) * w * 0.025;
	}

	vec2 ca = dn / vec2(asp, 1.0) * aberration * SCREEN_PIXEL_SIZE.y * (0.4 + dl);
	vec3 col = vec3(
		texture(screen, uv + ca).r,
		texture(screen, uv).g,
		texture(screen, uv - ca).b);

	if (impact > 0.0) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		float ink = smoothstep(0.16, 0.34, lum);
		col = mix(col, mix(vec3(0.06, 0.0, 0.03), impact_tint.rgb, ink), impact);
	}

	if (danger > 0.0) {
		vec2 v = (SCREEN_UV - 0.5) * vec2(asp, 1.0);
		float edge = smoothstep(0.42, 1.0, length(v));
		col = mix(col, vec3(0.75, 0.0, 0.06), edge * danger);
	}

	COLOR = vec4(col, 1.0);
}

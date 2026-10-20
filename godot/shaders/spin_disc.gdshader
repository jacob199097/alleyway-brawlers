shader_type canvas_item;
// A round part of an arena's picture turning in place (the casino's roulette wheel): the node is a
// square over the disc; each pixel samples the picture at its spot turned back by angle, faded at the rim.
// (data/arenas.json "spin"; scripts/duel/duel.gd _arena_fx)

uniform sampler2D picture : filter_linear_mipmap;
uniform vec2 tex_size = vec2(1536.0, 1024.0);
uniform vec2 centre = vec2(768.0, 512.0);   // the disc's middle, in the picture's pixels
uniform float radius = 100.0;               // in the picture's pixels
uniform float angle = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * radius;
	float rim = 1.0 - smoothstep(radius - 3.0, radius, length(p));
	vec2 q = vec2(cos(angle) * p.x - sin(angle) * p.y, sin(angle) * p.x + cos(angle) * p.y);
	vec2 uv = (centre + q) / tex_size;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 c = texture(picture, uv) * tint;
	COLOR = vec4(c.rgb, rim * inside);
}

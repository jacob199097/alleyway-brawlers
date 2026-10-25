shader_type canvas_item;
// Part of an arena's picture moving (scripts/duel/arena_life.gd), drawn over it from the picture
// itself: water rippling and glittering (it can flow, and a colour key keeps it to the water),
// heat shimmering up off sand, cloth and leaves swaying from where they hang, or ice and snow
// glittering in the light. Its edges fade into the picture underneath.

uniform sampler2D picture : filter_linear, repeat_disable;
uniform vec2 tex_size = vec2(1536.0, 1024.0);
uniform vec4 region = vec4(0.0, 0.0, 100.0, 100.0);   // x, y, w, h in the picture's pixels
uniform vec4 tint : source_color = vec4(1.0);          // the background's own modulate
uniform int mode = 0;          // 0 water, 1 heat, 2 sway, 3 glitter
uniform float amp = 3.0;       // how far it moves, in picture pixels
uniform float speed = 1.0;
uniform vec2 flow = vec2(0.0); // water: the way it runs (picture pixels a second / 10)
uniform vec4 key : source_color = vec4(0.0);
uniform float tol = -1.0;      // > 0: only pixels near the key colour move
uniform float cool = -1.0;     // >= 0: only pixels bluer than they are red by this much (water among wood)
uniform float sparkle = 0.0;
uniform vec4 spark_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float anchor = 0.0;    // sway: 0 hangs from the top, 1 stands on the bottom
uniform float feather = 24.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = region.xy + UV * region.zw;
	float t = TIME * speed + seed * 11.0;
	vec2 off = vec2(0.0);
	if (mode == 0) {
		vec2 q = p - flow * TIME * 10.0;
		off = vec2(noise(q / 34.0 + vec2(t * 0.5, t * 0.17)) - 0.5, noise(q / 27.0 + vec2(-t * 0.31, t * 0.43) + 7.0) - 0.5) * amp * 2.0;
	} else if (mode == 1) {
		off = vec2(sin(p.y / 7.0 - t * 5.0) * (noise(p / 70.0 + vec2(0.0, -t * 0.6)) - 0.2), 0.0) * amp;
	} else if (mode == 2) {
		float along = mix(UV.y, 1.0 - UV.y, anchor);
		off = vec2(sin(t * 1.25 + p.y / 80.0) + 0.45 * sin(t * 2.7 + p.x / 45.0), 0.25 * sin(t * 1.9 + p.x / 60.0)) * amp * along;
	}
	vec3 src = texture(picture, p / tex_size).rgb;
	vec3 col = texture(picture, (p + off) / tex_size).rgb;
	float m = 1.0;
	if (tol > 0.0) {
		m = 1.0 - smoothstep(tol, tol * 1.8, distance(src, key.rgb));
	}
	if (cool >= 0.0) {
		m *= smoothstep(cool, cool + 0.06, src.b - src.r);
	}
	if ((mode == 0 || mode == 3) && sparkle > 0.0) {
		// glitter: tiny points of light winking on and off where the light catches it
		float s = noise(p / 6.0 + vec2(t * 0.9, -t * 0.4)) * noise(p / 17.0 - vec2(t * 0.25, t * 0.55));
		float lum = dot(src, vec3(0.333));
		col += spark_color.rgb * sparkle * smoothstep(0.5, 0.72, s) * (0.25 + lum * 1.8);
	}
	vec2 e = min(UV, 1.0 - UV) * region.zw;
	float edge = smoothstep(0.0, feather, min(e.x, e.y));
	COLOR = vec4(col * tint.rgb, m * edge);
}

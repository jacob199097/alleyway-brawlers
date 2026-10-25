shader_type canvas_item;
render_mode blend_add;
// A searchlight / floodlight beam sweeping slowly back and forth from its lamp (scripts/duel/
// arena_life.gd). The rectangle is centred on the lamp; the beam is a soft cone with dust in it.

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float strength = 0.16;
uniform float angle = 1.0;     // where it points (radians, 0 = right, down is positive)
uniform float sweep = 0.3;     // how far it swings each way
uniform float speed = 0.25;
uniform float width = 0.22;    // half the cone's angle
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	float a = angle + sweep * sin(TIME * speed + seed * 6.0);
	float diff = abs(atan(sin(atan(d.y, d.x) - a), cos(atan(d.y, d.x) - a)));
	float cone = 1.0 - smoothstep(width * 0.45, width, diff);
	float fall = 1.0 - smoothstep(0.1, 1.0, r);
	float near = smoothstep(0.0, 0.05, r);
	float dust = 0.7 + 0.3 * noise(d * 9.0 + vec2(TIME * 0.15, -TIME * 0.1) + seed);
	COLOR = vec4(color.rgb * strength * cone * fall * near * dust, 1.0);
}

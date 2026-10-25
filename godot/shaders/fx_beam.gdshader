shader_type canvas_item;
render_mode blend_add;
// An energy beam (Nebula's laser, scripts/duel/duel.gd). The rectangle lies along the beam: UV.x 0 at
// the gun, 1 at the target; UV.y across. A white-hot core in a violet glow, plasma rippling along it
// toward the target, a little pinch at each end; "width" narrows it away.

uniform vec4 glow : source_color = vec4(0.62, 0.32, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.95, 0.9, 1.0, 1.0);
uniform float width = 1.0;   // 0..1
uniform float length_px = 400.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float x = UV.x * length_px / 60.0;
	float y = (UV.y - 0.5) * 2.0;
	float flow = noise(vec2(x * 1.6 - TIME * 14.0, y * 3.0)) * 0.6 + noise(vec2(x * 4.0 - TIME * 22.0, y * 6.0 + 4.0)) * 0.4;
	float ends = smoothstep(0.0, 0.03, UV.x) * (0.75 + 0.25 * smoothstep(1.0, 0.94, UV.x));
	float w = width * (0.85 + 0.3 * flow);
	float coreband = exp(-pow(y / max(0.05, 0.16 * w), 2.0));
	float glowband = exp(-pow(y / max(0.08, 0.55 * w), 2.0));
	float haze = exp(-pow(y / max(0.1, 1.0 * w), 2.0)) * 0.35;
	vec3 col = core.rgb * coreband * 1.3 + glow.rgb * (glowband * (0.7 + 0.6 * flow) + haze);
	COLOR = vec4(col * ends * step(0.01, width), 1.0);
}

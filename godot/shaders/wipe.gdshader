shader_type canvas_item;
// Screen transition: a slanted dark panel sweeps across with a glowing edge.
// progress 0 → 1 covers the screen (left to right); 1 → 2 uncovers it (also left to right).

uniform float progress = 0.0;
uniform vec4 edge_color : source_color = vec4(0.96, 0.83, 0.37, 1.0);

void fragment() {
	float x = UV.x * 0.8 + (1.0 - UV.y) * 0.2;      // slanted coordinate, 0..1
	float head = clamp(progress, 0.0, 1.0) * 1.25;   // leading edge
	float tail = clamp(progress - 1.0, 0.0, 1.0) * 1.25;
	float covered = step(x, head - 0.1) * step(tail - 0.1, x);
	float d = min(abs(x - (head - 0.1)), abs(x - (tail - 0.1)));
	float glow = exp(-d * 260.0) * step(0.001, progress) * step(progress, 1.999);
	vec3 col = mix(vec3(0.02, 0.02, 0.05), edge_color.rgb, glow);
	COLOR = vec4(col, max(covered, glow));
}

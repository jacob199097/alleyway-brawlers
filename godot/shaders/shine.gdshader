shader_type canvas_item;
// A band of light sweeping across artwork (the Victory / Defeat titles). It only catches the
// bright parts, so lettering gleams and the dark background stays dark.
// post_match.gd moves `progress` from about -0.3 to 1.3.

uniform float progress = -1.0;
uniform float width = 0.1;
uniform float strength = 0.9;
uniform vec4 shine : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float pos = UV.x + (UV.y - 0.5) * 0.35;
	float band = smoothstep(width, 0.0, abs(pos - progress));
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += shine.rgb * band * strength * smoothstep(0.3, 0.85, lum);
	COLOR = c * COLOR;
}

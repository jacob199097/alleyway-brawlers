shader_type canvas_item;
// Post-match background: the board as the match ended, blurred out of focus, drained of colour
// and graded toward the result (warm for a win, cold red for a loss). post_match.gd animates
// blur and saturation as the result lands.

uniform float blur = 3.0;            // sample spacing in texels
uniform float saturation = 0.5;
uniform float brightness = 0.5;
uniform vec4 grade : source_color = vec4(1.0);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	vec3 c = vec3(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float w = exp(-float(x * x + y * y) / 8.0);
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px).rgb * w;
			total += w;
		}
	}
	c /= total;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation) * grade.rgb * brightness;
	COLOR = vec4(c, COLOR.a);
}

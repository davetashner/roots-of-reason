shader_type canvas_item;

uniform vec4 player_color : source_color = vec4(0.2, 0.4, 0.9, 1.0);
uniform float tolerance : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Magenta reference: RGB(1, 0, 1)
	float dist = distance(tex.rgb, vec3(1.0, 0.0, 1.0));
	if (dist < tolerance) {
		// Preserve luminance from the original pixel
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(player_color.rgb * lum * 2.0, tex.a);
	} else {
		COLOR = tex;
	}
}

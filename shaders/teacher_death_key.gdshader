shader_type canvas_item;

uniform bool key_background = false;
uniform vec3 background_color : source_color = vec3(0.0902, 0.0471, 0.0941);
uniform float key_threshold = 0.004;
uniform float edge_softness = 0.012;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec4 pixel = source * COLOR;
	if (key_background) {
	// Compare the unmodulated texel: the Teacher may have been tinted by an
	// attack telegraph immediately before dying.
	float color_distance = distance(source.rgb, background_color);
	pixel.a = source.a * COLOR.a * smoothstep(key_threshold, key_threshold + edge_softness, color_distance);
	}
	COLOR = pixel;
}

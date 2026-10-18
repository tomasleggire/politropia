shader_type canvas_item;

// Soft drifting fog: a seamless grey noise texture becomes a coloured haze
// that fades out at the top and bottom of its band. Used by ParallaxBackdrop.

uniform vec4 fog_color : source_color = vec4(0.8, 0.7, 0.6, 0.3);
// Noise below this value disappears, so the fog breaks into patches.
uniform float threshold : hint_range(0.0, 1.0) = 0.4;
uniform float softness : hint_range(0.01, 1.0) = 0.4;
uniform float fade_top : hint_range(0.0, 1.0) = 0.4;
uniform float fade_bottom : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float n = texture(TEXTURE, UV).r;
	float density = smoothstep(threshold, threshold + softness, n);
	float fade = smoothstep(0.0, fade_top, UV.y) * (1.0 - smoothstep(1.0 - fade_bottom, 1.0, UV.y));
	COLOR = vec4(fog_color.rgb, fog_color.a * density * fade);
}

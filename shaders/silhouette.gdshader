shader_type canvas_item;

// Distant architecture: the sprite becomes a flat tinted shape that dissolves
// into the haze at the top and sides, so it never reads as a hard cut-out.
// Used by ParallaxBackdrop's mid layer.

uniform vec4 tint : source_color = vec4(0.07, 0.05, 0.05, 0.6);
// How much of the sprite's own shading survives (0 = flat silhouette).
uniform float detail : hint_range(0.0, 1.0) = 0.25;
uniform float fade_top : hint_range(0.0, 1.0) = 0.45;
uniform float fade_side : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float shade = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = tint.rgb * mix(1.0, shade * 2.0, detail);
	float top = smoothstep(0.0, max(fade_top, 0.001), UV.y);
	float side = smoothstep(0.0, max(fade_side, 0.001), UV.x) * (1.0 - smoothstep(1.0 - fade_side, 1.0, UV.x));
	COLOR = vec4(rgb, src.a * tint.a * top * side);
}

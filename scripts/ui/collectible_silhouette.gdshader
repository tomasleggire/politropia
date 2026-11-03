shader_type canvas_item;

// Draws a locked collectible as a dark version of its own coin while keeping
// the source alpha untouched, so the transparent margins stay transparent.
uniform vec4 silhouette_color : source_color = vec4(0.035, 0.06, 0.1, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(silhouette_color.rgb, source.a * silhouette_color.a);
}

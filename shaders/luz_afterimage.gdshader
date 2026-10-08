shader_type canvas_item;

// Flat tint over Luz's pose for the dash afterimages: the silhouette keeps its
// shading, shifted toward `tint`. Alpha is faded by the node's own modulate.

uniform vec4 tint : source_color = vec4(0.45, 0.58, 0.8, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, tint.rgb, tint_strength);
}

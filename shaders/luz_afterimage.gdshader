shader_type canvas_item;

// Flat tint over Luz's pose for the dash afterimages: the silhouette keeps its
// shading, shifted toward `tint`, with a thin light rim on its edge pixels so
// the ghost separates from bright and dark scenery. Alpha is faded by the
// node's own modulate.

uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.9;
uniform vec4 rim_color : source_color = vec4(0.88, 0.97, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.85;
uniform float rim_width : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * rim_width;
	float edge = 1.0 - min(
		min(texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a, texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a, texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a));
	vec3 body = mix(COLOR.rgb, tint.rgb, tint_strength);
	COLOR.rgb = mix(body, rim_color.rgb, edge * rim_strength * step(0.5, COLOR.a));
}

shader_type canvas_item;

// Soft dark edge for the stillness beat. Nothing near the centre is touched,
// so Luz and the UI stay readable; `level` scales the whole effect.

uniform float level : hint_range(0.0, 1.0) = 0.0;
uniform float max_darkness = 0.75;
uniform vec3 tint = vec3(0.01, 0.015, 0.05);

void fragment() {
	vec2 c = (UV - 0.5) * vec2(1.6, 1.0);
	float edge = smoothstep(0.16, 0.85, length(c));
	COLOR = vec4(tint, edge * max_darkness * level);
}

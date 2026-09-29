shader_type canvas_item;
render_mode blend_add;

// Reveals the lit floor ring like a clock hand: it starts at the left, runs
// clockwise over the back arc, the right, and the front arc.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float softness = 0.45;
uniform float gain = 1.0;
uniform vec3 warm = vec3(1.0, 0.72, 0.3);
uniform float band_glow = 0.3;
uniform float tick_glow = 1.5;
uniform vec2 radii = vec2(364.0, 60.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Guards: zero radii/softness would divide by zero, and smoothstep needs
	// edge0 < edge1. The tiny x bias keeps atan(0, 0) (undefined) off the centre.
	vec2 safe_radii = max(radii, vec2(0.001));
	float soft = max(softness, 0.001);
	float angle = atan(-local_pos.y / safe_radii.y, local_pos.x / safe_radii.x + 0.000001);
	float travelled = mod(PI - angle, TAU);
	float front = progress * (TAU + soft);
	float revealed = 1.0 - smoothstep(front - soft, front, travelled);
	// Explicit square: pow() with a negative base is undefined on Metal.
	float edge_offset = (travelled - front + soft * 0.5) / (soft * 0.5);
	float edge = exp(-(edge_offset * edge_offset));
	edge *= 1.0 - smoothstep(0.95, 1.0, progress);
	// The lit art is a blue band with amber ticks: re-tint it as warm light.
	float tick = clamp((COLOR.r - COLOR.b) * 2.0, 0.0, 1.0);
	COLOR.rgb = warm * (band_glow + tick_glow * tick) * gain * (1.0 + 0.7 * edge);
	COLOR.a *= revealed;
}

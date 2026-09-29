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
	float angle = atan(-local_pos.y / radii.y, local_pos.x / radii.x);
	float travelled = mod(PI - angle, TAU);
	float front = progress * (TAU + softness);
	float revealed = 1.0 - smoothstep(front - softness, front, travelled);
	float edge = exp(-pow((travelled - front + softness * 0.5) / (softness * 0.5), 2.0));
	edge *= 1.0 - smoothstep(0.95, 1.0, progress);
	// The lit art is a blue band with amber ticks: re-tint it as warm light.
	float tick = clamp((COLOR.r - COLOR.b) * 2.0, 0.0, 1.0);
	COLOR.rgb = warm * (band_glow + tick_glow * tick) * gain * (1.0 + 0.7 * edge);
	COLOR.a *= revealed;
}

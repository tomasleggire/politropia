shader_type canvas_item;
render_mode blend_add;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strength = 1.15;
uniform float ring_width = 0.045;
uniform vec3 pulse_color : source_color = vec3(1.0, 0.74, 0.34);

void fragment() {
	vec2 centered_uv = (UV - vec2(0.5)) * 2.0;
	float distance_from_center = length(centered_uv);
	float ring_radius = progress * 0.84;
	float distance_to_ring = abs(distance_from_center - ring_radius);
	float ring = 1.0 - smoothstep(ring_width * 0.35, ring_width, distance_to_ring);
	float soft_halo = 1.0 - smoothstep(ring_width, ring_width * 3.0, distance_to_ring);
	float fade = 1.0 - progress * 0.35;
	float alpha = (ring + soft_halo * 0.16) * fade * strength;
	COLOR = vec4(pulse_color, alpha) * COLOR;
}
shader_type canvas_item;
render_mode blend_add;

// One expanding ring of light: a bright thin leading edge with a soft trailing
// wake. `progress` 0 is the halo's outer edge, 1 is fully faded at about twice
// that radius. Radii are in world units from the sprite centre.

uniform float size_units = 200.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float start_radius = 36.0;
uniform float end_radius = 76.0;
uniform vec3 color = vec3(1.0, 0.8, 0.45);

void fragment() {
	float r = length((UV - 0.5) * size_units);
	float eased = 1.0 - pow(1.0 - progress, 2.5);
	float radius = mix(start_radius, end_radius, eased);
	float fade = 1.0 - progress;
	fade *= fade;
	float width = mix(3.2, 1.4, progress);
	float edge = 1.0 - smoothstep(0.0, width, abs(r - radius));
	float wake = smoothstep(radius - 14.0, radius, r) * (1.0 - smoothstep(radius, radius + 0.6, r));
	float a = (edge * 1.4 + wake * 0.35) * fade * step(0.0001, progress);
	COLOR = vec4(color * a, 1.0);
}

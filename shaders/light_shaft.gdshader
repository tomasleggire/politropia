shader_type canvas_item;
render_mode blend_add;

// A tall warm beam falling onto the altar: wide soft edges, slow "god ray"
// striations and a posterised falloff so it sits in the pixel-art look.
// UV.y runs from the top of the beam (0) to the floor (1).

uniform float intensity = 1.0;
uniform float phase = 0.0;
uniform float strength = 0.2;
uniform float top_half = 0.09;
uniform float bottom_half = 0.2;
// Horizontal offset of the beam's top, so it leans in from the upper right.
uniform float lean = 0.275;
uniform float bands = 12.0;
// Soft ellipse (UV space) where the beam is dimmed so Luz's head reads against it.
uniform vec2 mask_centre = vec2(0.5, 0.9125);
uniform vec2 mask_radii = vec2(0.14, 0.042);
uniform float mask_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec3 warm = vec3(1.0, 0.74, 0.38);
uniform vec3 cool = vec3(0.72, 0.82, 1.0);

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float value_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float v = UV.y;
	float half_width = max(mix(top_half, bottom_half, v), 0.001);
	float centre = 0.5 + lean * (1.0 - v);
	float d = (UV.x - centre) / half_width;
	float edge = 1.0 - smoothstep(0.3, 1.0, abs(d));
	float core = 1.0 - smoothstep(0.0, 0.9, abs(d));
	float profile = edge * edge * 0.7 + core * 0.3;

	float rays = value_noise(d * 6.0 + phase * 0.35) * 0.6 + value_noise(d * 13.0 - phase * 0.5 + 7.0) * 0.4;
	rays = mix(0.55, 1.15, rays);
	float slices = 0.92 + 0.08 * sin(phase * 1.7 + v * 9.0);
	float along = smoothstep(0.0, 0.12, v) * (1.0 - 0.3 * smoothstep(0.75, 1.0, v));

	float a = clamp(profile * rays * slices * along * intensity * strength, 0.0, 1.0);
	vec2 m = (UV - mask_centre) / mask_radii;
	a *= 1.0 - mask_strength * (1.0 - smoothstep(0.35, 1.0, length(m)));
	a = floor(a * bands + 0.5) / bands;
	vec3 tint = mix(warm, cool, smoothstep(0.55, 1.0, abs(d)) * 0.45);
	COLOR = vec4(tint, a * COLOR.a);
}

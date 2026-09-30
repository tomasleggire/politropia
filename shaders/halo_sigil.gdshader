shader_type canvas_item;
render_mode blend_add;

// Vertical protractor / clock sigil drawn behind the seated Luz: two outer
// rings, 36 ticks (every 9th longer), an inner ring, a half-circle protractor
// scale and one clock hand. Everything is snapped to the art's texel grid and
// drawn with hard edges so it matches the pixel art. Nothing is drawn inside
// radius 19 so the area behind Luz's face stays clear.

const float TEXEL = 0.175;
const float TICKS = 36.0;

uniform float size_units = 80.0;
uniform float intensity = 1.0;
// Fraction of ticks lit clockwise from the ring's zero mark.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
// Full-ring flash.
uniform float flare : hint_range(0.0, 1.0) = 0.0;
// Ring rotation in radians (the protractor scale stays fixed).
uniform float rotation = 0.0;
// Clock hand, radians clockwise from twelve o'clock.
uniform float hand = 0.0;
uniform float warmth : hint_range(0.0, 1.0) = 0.0;
uniform float breath : hint_range(0.0, 1.0) = 0.5;
// Ignition: 1 dims the engraved rings and unlit ticks so the lit ones stand out.
uniform float dark : hint_range(0.0, 1.0) = 0.0;
uniform float breath_swing : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cold_color = vec3(0.74, 0.7, 0.46);
uniform vec3 warm_color = vec3(1.0, 0.68, 0.26);

float band(float x, float centre, float width) {
	return step(abs(x - centre), width * 0.5);
}

float span(float x, float lo, float hi) {
	return step(lo, x) * step(x, hi);
}

void fragment() {
	float alpha_in = COLOR.a;
	vec2 p = (UV - 0.5) * size_units;
	// Snap to texel centres: never exactly zero, so atan() is always defined.
	p = (floor(p / TEXEL) + 0.5) * TEXEL;
	float r = length(p);
	float angle = atan(p.x, -p.y);

	float ring_angle = mod(angle - rotation, TAU);
	float step_angle = TAU / TICKS;
	float index = floor(ring_angle / step_angle + 0.5);
	float tick_id = mod(index, TICKS);
	float arc_dist = (ring_angle - index * step_angle) * r;
	float is_major = 1.0 - step(0.5, mod(tick_id, 9.0));
	float tick_half = mix(1.5, 2.0, is_major) * TEXEL;
	float tick_start = mix(29.4, 26.6, is_major);
	float lit = step(tick_id + 0.5, fill * TICKS);
	// Lit ticks reach further in, so a filling ring reads as light spreading.
	float tick = step(abs(arc_dist), tick_half) * span(r, tick_start - lit * dark * 2.6, 32.0);

	// Protractor scale over the top half: a mark every 5 degrees, longer every 30.
	float degrees_cw = degrees(angle);
	float upper = step(abs(degrees_cw), 90.0);
	float mark = floor(degrees_cw / 5.0 + 0.5);
	float mark_dist = (degrees_cw - mark * 5.0) * 0.0174533 * r;
	float mark_major = 1.0 - step(0.5, mod(mark + 36.0, 6.0));
	float mark_end = mix(23.4, 24.6, mark_major);
	float scale_ticks = step(abs(mark_dist), 1.5 * TEXEL) * span(r, 21.9, mark_end) * upper;
	float scale_arc = band(r, 21.5, 3.0 * TEXEL) * upper;
	float scale = max(scale_ticks, scale_arc);

	vec2 hand_dir = vec2(sin(hand), -cos(hand));
	float along = dot(p, hand_dir);
	float across = dot(p, vec2(-hand_dir.y, hand_dir.x));
	float hand_mask = step(abs(across), 2.0 * TEXEL) * span(along, 19.5, 30.5);
	hand_mask = max(hand_mask, step(abs(across) + abs(along - 31.5), 1.6));

	float lines = max(max(band(r, 34.0, 4.0 * TEXEL), band(r, 32.7, 3.0 * TEXEL) * 0.6),
			max(band(r, 25.0, 4.0 * TEXEL) * 0.75, scale * 0.85));
	float lead = step(abs(tick_id + 0.5 - fill * TICKS), 1.0) * step(0.001, fill) * (1.0 - step(0.999, fill));

	// Spark pop: a tick that just lit throws a small bright burst that fades over
	// the next few ticks, only while the ring is actually filling.
	float age = fill * TICKS - (tick_id + 0.5);
	float filling = step(0.001, fill) * (1.0 - step(0.999, fill)) * step(0.0, age);
	float tick_angle = index * step_angle + rotation;
	float tick_dist = length(p - vec2(sin(tick_angle), -cos(tick_angle)) * 31.0);
	float pop = filling * (1.0 - smoothstep(0.0, 7.0, age)) * (1.0 - smoothstep(0.8, 2.8, tick_dist));

	float dim = intensity * (1.0 + breath_swing * (breath - 0.5) * 2.0);
	vec3 line_color = mix(cold_color, warm_color, warmth);
	float engraved = 1.0 - dark * 0.7;
	vec3 rgb = line_color * (lines + tick * (1.0 - lit) * 0.6) * dim * engraved;
	rgb += warm_color * (tick * lit * mix(1.5, 2.6, dark) + tick * lead * 2.0 + hand_mask * 1.7 * engraved) * dim;

	rgb += vec3(1.0, 0.86, 0.5) * pop * 2.4 * dim;

	// Faint posterised haze between the rings; never inside the face zone.
	float haze = smoothstep(19.0, 25.0, r) * (1.0 - smoothstep(32.0, 36.5, r));
	haze = floor(haze * 6.0) / 6.0;
	rgb += warm_color * haze * 0.07 * dim * (0.3 + 0.7 * warmth);

	float shape = max(max(lines, tick), scale);
	rgb += vec3(1.0, 0.9, 0.62) * flare * (shape * 2.2 + haze * 0.5);
	COLOR = vec4(rgb * alpha_in, 1.0);
}

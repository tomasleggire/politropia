shader_type canvas_item;
render_mode blend_premul_alpha;

// Pixel-art wayfinding roots. The trail is rasterised on the CPU into a small
// image (one texel per art pixel) shown with nearest filtering; each texel
// stores its kind (paper, ink, scrap), its strand id and its position along
// the surface path, packed as r = kind * 64 + id, g/b = 16-bit position.
// Warm amber packets travel along the strands toward the altar, and one burst
// can travel back out. There is only a faint bloom around the paper.

uniform vec4 paper_color : source_color = vec4(0.937, 0.902, 0.824, 1.0);
uniform vec4 ink_color : source_color = vec4(0.227, 0.204, 0.275, 1.0);
uniform vec4 pulse_color : source_color = vec4(1.0, 0.72, 0.28, 1.0);
uniform float trail_length = 400.0;
// Length of the surface path in world units, and packet length likewise.
uniform float path_length = 400.0;
uniform float pulse_length = 16.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.26;
// 0 = cold dormant paper, 1 = warm awakened paper.
uniform float warmth : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_clock = 0.0;
uniform float pulse_cycle = 6.0;
uniform float pulse_travel = 3.0;
uniform float pulse_strength : hint_range(0.0, 2.0) = 1.0;
// Outward burst: centre along the path (negative = idle) and strength.
uniform float burst_pos = -2.0;
uniform float burst_strength : hint_range(0.0, 2.0) = 0.0;
// Overall opacity of the roots (subtle desk roots use less).
uniform float root_opacity : hint_range(0.0, 1.0) = 1.0;

// Comet: sharp head at `center`, tail toward smaller `along` (heading +1) or
// larger (heading -1).
float comet(float along, float center, float width, float heading) {
	float d = (along - center) * heading;
	return d > 0.0 ? exp(-d * d / (width * width * 0.04)) : exp(d / (width * 2.4));
}

float stagger_of(float id) {
	return fract(sin(id * 12.9898) * 43758.5453);
}

float light_of(vec4 t) {
	float v = floor(t.r * 255.0 + 0.5);
	float kind = floor(v / 64.0);
	if (t.a < 0.5 || kind > 2.5) {
		return 0.0;
	}
	float id = v - kind * 64.0;
	float along = (floor(t.g * 255.0 + 0.5) * 256.0 + floor(t.b * 255.0 + 0.5)) / 65535.0;
	float width_u = pulse_length / path_length;
	float phase = mod(pulse_clock + stagger_of(mod(id, 3.0)) * pulse_cycle, pulse_cycle);
	float run = phase / pulse_travel;
	float inward = run <= 1.0 ? comet(along, mix(-0.1, 1.1, run), width_u, 1.0) : 0.0;
	float wave = burst_strength * comet(along, burst_pos, width_u * 3.0, -1.0);
	return floor(clamp(inward * pulse_strength + wave * 1.4, 0.0, 1.0) * 4.0 + 0.5) / 4.0;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	if (t.a < 0.5) {
		vec4 n0 = texture(TEXTURE, UV + vec2(px.x, 0.0));
		vec4 n1 = texture(TEXTURE, UV - vec2(px.x, 0.0));
		vec4 n2 = texture(TEXTURE, UV + vec2(0.0, px.y));
		vec4 n3 = texture(TEXTURE, UV - vec2(0.0, px.y));
		float near = n0.a + n1.a + n2.a + n3.a;
		float far = texture(TEXTURE, UV + vec2(2.0 * px.x, 0.0)).a + texture(TEXTURE, UV - vec2(2.0 * px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, 2.0 * px.y)).a + texture(TEXTURE, UV - vec2(0.0, 2.0 * px.y)).a;
		float g = near > 0.5 ? 1.0 : (far > 0.5 ? 0.45 : 0.0);
		float packet = max(max(light_of(n0), light_of(n1)), max(light_of(n2), light_of(n3)));
		vec3 bloom = mix(vec3(1.0, 0.93, 0.8), pulse_color.rgb, 0.4 + warmth * 0.4);
		vec3 rgb = bloom * g * glow_strength * (0.6 + warmth * 0.4);
		rgb += pulse_color.rgb * packet * 0.85 * (near > 0.5 ? 1.0 : 0.0);
		COLOR = vec4(rgb * root_opacity, 0.0);
	} else {
		float v = floor(t.r * 255.0 + 0.5);
		float kind = floor(v / 64.0);
		float light = light_of(t);
		vec3 paper = mix(paper_color.rgb, vec3(1.0, 0.9, 0.72), warmth * 0.5);
		vec3 col;
		if (kind < 1.5) {
			col = mix(paper, pulse_color.rgb, light);
		} else if (kind < 2.5) {
			col = mix(ink_color.rgb, pulse_color.rgb * 0.6, light * 0.7);
		} else {
			col = paper * 0.96;
		}
		COLOR = vec4(col * root_opacity, root_opacity);
	}
}

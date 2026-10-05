shader_type canvas_item;

// Warm rim on the opaque edges that face the light shaft: a pixel is on the
// rim when the texture is transparent a few texels toward the light.

uniform float strength : hint_range(0.0, 2.0) = 0.6;
uniform vec3 rim_color = vec3(1.0, 0.72, 0.34);
// Screen-space direction toward the light (y down).
uniform vec2 light_dir = vec2(0.3, -1.0);
uniform float reach = 5.0;
uniform float falloff_start = 150.0;
uniform float falloff_end = 330.0;

varying float local_x;

void vertex() {
	local_x = VERTEX.x;
}

void fragment() {
	vec2 dir = normalize(light_dir);
	float open_air = 0.0;
	for (int i = 1; i <= 3; i++) {
		vec2 offset = dir * TEXTURE_PIXEL_SIZE * reach * float(i) / 3.0;
		vec2 uv = UV + offset;
		// Outside the sprite counts as open air, so edges on the image border glow too.
		bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
		float neighbour = inside ? texture(TEXTURE, uv).a : 0.0;
		open_air = max(open_air, 1.0 - neighbour);
	}
	float near_axis = 1.0 - 0.6 * smoothstep(falloff_start, falloff_end, abs(local_x));
	COLOR.rgb += rim_color * open_air * COLOR.a * strength * near_axis;
}

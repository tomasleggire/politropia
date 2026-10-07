shader_type canvas_item;

// Cel-shaded cool rim on Luz's silhouette. An opaque texel is lit when the
// texture is transparent within `width` texels toward the light. Directions
// are in TEXTURE space (art faces right): UVs are mirrored together with the
// art by flip_h, so "back" stays behind Luz when she faces left.

uniform bool enabled = true;
uniform vec4 rim_color : source_color = vec4(0.4, 0.46, 0.58, 1.0);
// Texels from the silhouette edge that get lit (about 1 world px at Luz's scale).
uniform float width : hint_range(0.0, 16.0) = 5.0;
// Toward the light, texture space, y down: top and behind (art faces right).
uniform vec2 light_direction = vec2(-0.5, -1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	if (enabled && COLOR.a > 0.5) {
		vec2 step_uv = normalize(light_direction) * TEXTURE_PIXEL_SIZE * width * 0.25;
		float open_air = 0.0;
		for (int i = 1; i <= 4; i++) {
			// LOD 0: the mipmapped sample would blur the edge test at this scale.
			float neighbour = textureLod(TEXTURE, UV + step_uv * float(i), 0.0).a;
			open_air = max(open_air, 1.0 - step(0.5, neighbour));
		}
		COLOR.rgb = mix(COLOR.rgb, rim_color.rgb, open_air * strength * rim_color.a);
	}
}

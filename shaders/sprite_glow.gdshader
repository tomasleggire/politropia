shader_type canvas_item;

// Telegraph glow and hit flash drawn on a sprite itself, so they follow its exact
// silhouette: an outline grown from the alpha channel plus a light tint of the body
// (`glow_amount`), and a white flash (`flash_amount`). Driven by BossSpriteFx; meant
// for any boss sprite (El Profesor now, El Topo and La Hidra later).

uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
// 0 = off, 1 = full outline and tint.
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
// 0 = untouched, 1 = flat white.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
// Outline reach in texels (about 2 screen px at a 0.29 sprite scale).
uniform float outline_width : hint_range(0.0, 24.0) = 7.0;
// Share of the glow colour mixed into the body at full glow.
uniform float body_tint : hint_range(0.0, 1.0) = 0.3;

const int DIRECTIONS = 8;

void fragment() {
	vec4 pixel = COLOR;
	if (glow_amount > 0.0) {
		// Highest alpha on two rings around the texel (LOD 0: no mip blur on the edge).
		vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;
		float found = 0.0;
		for (int i = 0; i < DIRECTIONS; i++) {
			float angle = float(i) * TAU / float(DIRECTIONS);
			vec2 dir = vec2(cos(angle), sin(angle)) * texel;
			found = max(found, textureLod(TEXTURE, UV + dir * 0.5, 0.0).a);
			found = max(found, textureLod(TEXTURE, UV + dir, 0.0).a);
		}
		float ring = found * (1.0 - pixel.a) * glow_amount;
		vec3 body = mix(pixel.rgb, glow_color.rgb, glow_amount * body_tint);
		pixel = vec4(mix(glow_color.rgb, body, pixel.a), max(pixel.a, ring));
	}
	pixel.rgb = mix(pixel.rgb, vec3(1.0), flash_amount * step(0.001, pixel.a));
	COLOR = pixel;
}

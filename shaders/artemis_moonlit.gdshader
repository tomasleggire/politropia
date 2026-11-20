shader_type canvas_item;

// Artemis phase two ("Full Moon") skin on the phase-one sheets: the blue cape turns
// moon silver, cloth and hair get brighter silver glints, and a thin silver halo
// hugs the silhouette. Same pixel grid and silhouette as phase one, so every clip
// is reused (docs/bosses/ARTEMIS_ANIMATIONS.md, section 1).

uniform vec4 silver_dark : source_color = vec4(0.36, 0.45, 0.6, 1.0);
uniform vec4 silver_light : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform float cape_strength : hint_range(0.0, 1.0) = 0.85;
uniform float glint_lift : hint_range(0.0, 0.5) = 0.07;
uniform float halo_alpha : hint_range(0.0, 1.0) = 0.5;
// Halo reach in texels (about 1 world px per 3.5 texels at Artemis's scale).
uniform float halo_width : hint_range(1.0, 16.0) = 6.0;
// 1 = the phase-two silver skin above, 0 = the sheet as drawn (phase one).
uniform float moonlit : hint_range(0.0, 1.0) = 1.0;

// Telegraph glow and hit flash on the sprite itself (the same as sprite_glow.gdshader, driven
// by BossSpriteFx), so they follow her silhouette in both skins.
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float outline_width : hint_range(0.0, 24.0) = 7.0;
uniform float body_tint : hint_range(0.0, 1.0) = 0.3;

const int DIRECTIONS = 8;

void fragment() {
	vec4 pixel = COLOR;
	if (moonlit > 0.5) {
		vec4 base = texture(TEXTURE, UV);
		if (base.a > 0.5) {
			float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
			float cape = smoothstep(0.1, 0.22, base.b - base.r) * step(base.g, base.b);
			vec3 silver = mix(silver_dark.rgb, silver_light.rgb, smoothstep(0.2, 0.75, lum));
			vec3 rgb = mix(base.rgb, silver, cape * cape_strength);
			// Brighter cloth highlights and silver glints on light areas (veil, chiton, bow tips).
			rgb += glint_lift * smoothstep(0.55, 0.95, lum);
			pixel = vec4(min(rgb, vec3(1.0)), base.a);
		} else {
			float near = 0.0;
			float far = 0.0;
			for (int i = 0; i < 8; i++) {
				float angle = float(i) * 0.785398;
				vec2 dir = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE;
				// LOD 0: the mipmapped sample would blur the silhouette test at this scale.
				near = max(near, step(0.5, textureLod(TEXTURE, UV + dir * halo_width * 0.5, 0.0).a));
				far = max(far, step(0.5, textureLod(TEXTURE, UV + dir * halo_width, 0.0).a));
			}
			float halo = near * halo_alpha + (1.0 - near) * far * halo_alpha * 0.4;
			pixel = vec4(silver_light.rgb, halo);
		}
	}
	if (glow_amount > 0.0) {
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

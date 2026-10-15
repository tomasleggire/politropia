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

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a > 0.5) {
		float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
		float cape = smoothstep(0.1, 0.22, base.b - base.r) * step(base.g, base.b);
		vec3 silver = mix(silver_dark.rgb, silver_light.rgb, smoothstep(0.2, 0.75, lum));
		vec3 rgb = mix(base.rgb, silver, cape * cape_strength);
		// Brighter cloth highlights and silver glints on light areas (veil, chiton, bow tips).
		rgb += glint_lift * smoothstep(0.55, 0.95, lum);
		COLOR = vec4(min(rgb, vec3(1.0)), base.a);
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
		float glow = near * halo_alpha + (1.0 - near) * far * halo_alpha * 0.4;
		COLOR = vec4(silver_light.rgb, glow);
	}
}

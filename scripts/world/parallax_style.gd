class_name ParallaxStyle
extends Resource

## Layers of a biome's parallax backdrop, used by ParallaxBackdrop. Duplicate
## `data/parallax/library.tres` to make a new look, or drop final art into the
## texture slots below (no code). Textures left empty use the provisional
## defaults: the zone's own background, generated silhouettes and fog.

@export_group("Far layer")
## Distant sky / wall. Empty = the zone's existing background sprite.
@export var far_texture: Texture2D
## Multiplied with the zone background's own tint.
@export var far_tint := Color.WHITE
## Used when the zone has no background sprite of its own.
@export var far_default_texture: Texture2D
## 0 = glued to the screen, 1 = moves with the world. Lower = farther away.
@export var far_scroll_scale := Vector2(0.4, 0.5)
## Never enlarge the picture past this; scroll_scale is lowered to fit instead.
@export_range(1.0, 3.0, 0.05) var far_max_scale := 1.5

@export_group("Mid layer")
## Silhouettes (columns, shelves, arches); each one is picked at random.
## Empty = no mid layer.
@export var mid_textures: Array[Texture2D] = []
## Colour (alpha = opacity) of the silhouettes against the far layer.
@export var mid_tint := Color(0.1, 0.07, 0.07, 0.9)
## How much of each sprite's own shading shows through (0 = flat shape).
@export_range(0.0, 1.0, 0.05) var mid_detail := 0.25
## Fraction of the height, from the top, where a silhouette fades in.
@export_range(0.0, 1.0, 0.05) var mid_fade_top := 0.45
@export var mid_scroll_scale := Vector2(0.7, 0.75)
## Average distance between silhouettes, in world pixels.
@export_range(60.0, 1200.0, 10.0) var mid_spacing := 300.0
## Random shift of each silhouette, as a fraction of the spacing.
@export_range(0.0, 1.0, 0.05) var mid_jitter := 0.45
## Random size range of the silhouettes.
@export var mid_scale_range := Vector2(2.0, 3.0)
## Rounds each size to a whole number so the pixel art stays crisp.
@export var mid_pixel_snap := true
## Push the base of the silhouettes below the zone's bottom edge (pixels).
@export_range(-200.0, 400.0, 1.0) var mid_sink := 60.0
@export var mid_seed := 7

@export_group("Fog layer")
@export var fog_enabled := true
## Seamless grey noise. Empty = assets/art/fx/fog_noise.png.
@export var fog_texture: Texture2D
@export var fog_color := Color(0.85, 0.7, 0.5, 0.22)
@export var fog_scroll_scale := Vector2(0.85, 0.0)
## Drift speed in pixels per second.
@export var fog_autoscroll := Vector2(6.0, 0.0)
## Vertical position of the band on screen (0 top, 1 bottom).
@export_range(0.0, 1.0, 0.01) var fog_screen_y := 0.72
## Band height in world pixels and noise stretch.
@export var fog_height := 170.0
@export_range(0.5, 6.0, 0.1) var fog_stretch := 2.2
@export_range(0.0, 1.0, 0.01) var fog_threshold := 0.38

@export_group("Near haze")
@export var haze_enabled := true
## Seamless grey noise. Empty = assets/art/fx/haze_noise.png.
@export var haze_texture: Texture2D
@export var haze_color := Color(0.08, 0.05, 0.04, 0.16)
## Above 1 the haze moves faster than the world, selling depth.
@export var haze_scroll_scale := Vector2(1.25, 0.0)
@export var haze_autoscroll := Vector2(-4.0, 0.0)
@export_range(0.0, 1.0, 0.01) var haze_screen_y := 0.92
@export var haze_height := 150.0
@export_range(0.5, 8.0, 0.1) var haze_stretch := 3.5

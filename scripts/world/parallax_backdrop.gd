@tool
class_name ParallaxBackdrop
extends Node2D

## Layered backdrop for a zone. Drop ONE `scenes/world/parallax_backdrop.tscn`
## in each zone (as its first child, so it draws behind the tiles) and pick a
## biome look in `style` (data/parallax/library.tres or greece.tres).
## Layers, from far to near: the sky/wall picture, dark silhouettes, a drifting
## fog band and a faint near haze that moves faster than the world.
##
## The zone's own background sprite (TilemapLayers/Background/*) is adopted as
## the far picture and hidden, so no per-zone setup is needed. Everything is
## sized from the zone's camera limits, so the layers never show their edges.
## To use final art, set the textures inside the style resource.

const FOG_NOISE := preload("res://assets/art/fx/fog_noise.png")
const HAZE_NOISE := preload("res://assets/art/fx/haze_noise.png")
const SILHOUETTE_SHADER := preload("res://shaders/silhouette.gdshader")
const ZONE_BACKGROUND := "TilemapLayers/Background"
## Extra pixels kept around the view so the camera kick never shows an edge.
const EDGE_MARGIN := 48.0

@export var style: ParallaxStyle:
	set(value):
		style = value
		_rebuild()
## Hides the zone's own background sprite and uses its picture as the far layer.
@export var adopt_zone_background := true

@export_group("Area")
## Camera area used when the zone has no CameraRegion and no tiles.
@export var fallback_rect := Rect2(0.0, 0.0, 2000.0, 700.0)
## Largest view the camera can show (wide phones and tablets). Layers are
## sized to cover it.
@export var design_view := Vector2(800.0, 500.0)

var _area := Rect2()

@onready var _far: Parallax2D = $Far
@onready var _far_image: Sprite2D = $Far/Image
@onready var _mid: Parallax2D = $Mid
@onready var _fog: Parallax2D = $Fog
@onready var _fog_band: Sprite2D = $Fog/Band
@onready var _haze: Parallax2D = $Haze
@onready var _haze_band: Sprite2D = $Haze/Band


func _ready() -> void:
	_rebuild()


## Camera area the layers were sized for, in world coordinates.
func get_area_rect() -> Rect2:
	return _area


func _rebuild() -> void:
	if not is_node_ready():
		return
	var look := style if style != null else ParallaxStyle.new()
	var view := get_viewport_rect().size
	_area = ZoneBounds.find_rect(get_parent(), fallback_rect)
	_area.size = _area.size.max(design_view)
	_build_far(look, view)
	_build_mid(look, view)
	_build_band(_fog, _fog_band, FOG_NOISE if look.fog_texture == null else look.fog_texture, view, look.fog_enabled, {
		"color": look.fog_color, "scroll": look.fog_scroll_scale, "auto": look.fog_autoscroll,
		"screen_y": look.fog_screen_y, "height": look.fog_height, "stretch": look.fog_stretch,
		"threshold": look.fog_threshold,
	})
	_build_band(_haze, _haze_band, HAZE_NOISE if look.haze_texture == null else look.haze_texture, view, look.haze_enabled, {
		"color": look.haze_color, "scroll": look.haze_scroll_scale, "auto": look.haze_autoscroll,
		"screen_y": look.haze_screen_y, "height": look.haze_height, "stretch": look.haze_stretch,
		"threshold": 0.4,
	})


## `scroll_offset` that puts a layer's origin on the zone's centre when the
## camera sits at the centre of its range (Parallax2D moves its layer to
## `camera_top_left * (1 - scroll_scale) + scroll_offset`).
func _anchor(scroll: Vector2, view: Vector2) -> Vector2:
	return scroll * _area.get_center() + (Vector2.ONE - scroll) * view * 0.5


## Size a layer must have to cover every camera position at `scroll`.
func _needed_size(scroll: Vector2) -> Vector2:
	var travel := (_area.size - design_view).max(Vector2.ZERO)
	return design_view + travel * scroll + Vector2.ONE * EDGE_MARGIN * 2.0


func _build_far(look: ParallaxStyle, view: Vector2) -> void:
	var tint := look.far_tint
	var texture := look.far_texture
	var zone_sprite: Sprite2D = null
	if texture == null:
		zone_sprite = _find_zone_background() if adopt_zone_background else null
		if zone_sprite != null:
			texture = zone_sprite.texture
			tint = zone_sprite.modulate * look.far_tint
			if not Engine.is_editor_hint():
				zone_sprite.visible = false
		else:
			texture = look.far_default_texture
	_far.visible = texture != null
	_far_image.texture = texture
	if texture == null:
		return
	var size := texture.get_size()
	var travel := (_area.size - design_view).max(Vector2.ZERO)
	var scroll := look.far_scroll_scale
	# A picture that would need enlarging too much scrolls less instead.
	for axis in 2:
		if travel[axis] > 0.0:
			var limit := (size[axis] * look.far_max_scale - design_view[axis] - EDGE_MARGIN * 2.0) / travel[axis]
			scroll[axis] = clampf(minf(scroll[axis], limit), 0.0, 1.0)
	var need := _needed_size(scroll)
	# Keep the zone sprite's own scale and place it where the level artist put
	# it (when the camera is mid-zone); grow it only if it cannot cover.
	var scale_xy := zone_sprite.global_scale.abs() if zone_sprite != null else Vector2.ONE
	var grow := maxf(maxf(need.x / (size.x * scale_xy.x), need.y / (size.y * scale_xy.y)), 1.0)
	scale_xy *= grow
	var shown := size * scale_xy
	var slack := ((shown - need) * 0.5).max(Vector2.ZERO)
	var shift := Vector2.ZERO
	if zone_sprite != null:
		shift = (zone_sprite.global_position - _area.get_center()).clamp(-slack, slack)
	_far_image.scale = scale_xy
	_far_image.modulate = tint
	_far.scroll_scale = scroll
	_far.scroll_offset = _anchor(scroll, view) + shift


func _find_zone_background() -> Sprite2D:
	var holder := get_parent().get_node_or_null(ZONE_BACKGROUND) if get_parent() != null else null
	if holder == null:
		return null
	for child in holder.get_children():
		var sprite := child as Sprite2D
		if sprite != null and sprite.texture != null:
			return sprite
	return null


func _build_mid(look: ParallaxStyle, view: Vector2) -> void:
	for child in _mid.get_children():
		child.queue_free()
	_mid.visible = not look.mid_textures.is_empty()
	if not _mid.visible:
		return
	var scroll := look.mid_scroll_scale
	_mid.scroll_scale = scroll
	_mid.scroll_offset = _anchor(scroll, view)
	var need := _needed_size(scroll)
	var rng := RandomNumberGenerator.new()
	rng.seed = look.mid_seed
	var material := ShaderMaterial.new()
	material.shader = SILHOUETTE_SHADER
	material.set_shader_parameter(&"tint", look.mid_tint)
	material.set_shader_parameter(&"detail", look.mid_detail)
	material.set_shader_parameter(&"fade_top", look.mid_fade_top)
	var baseline := _area.size.y * 0.5 + look.mid_sink
	var x := -need.x * 0.5
	while x < need.x * 0.5:
		var texture := look.mid_textures[rng.randi() % look.mid_textures.size()]
		var zoom := rng.randf_range(look.mid_scale_range.x, look.mid_scale_range.y)
		if look.mid_pixel_snap:
			zoom = maxf(roundf(zoom), 1.0)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.flip_h = rng.randf() < 0.5
		sprite.scale = Vector2.ONE * zoom
		sprite.material = material
		var jitter := rng.randf_range(-1.0, 1.0) * look.mid_jitter * look.mid_spacing
		sprite.position = Vector2(x + jitter - texture.get_width() * zoom * 0.5, baseline - texture.get_height() * zoom)
		_mid.add_child(sprite)
		x += look.mid_spacing


func _build_band(layer: Parallax2D, band: Sprite2D, texture: Texture2D, view: Vector2, enabled: bool, cfg: Dictionary) -> void:
	layer.visible = enabled
	if not enabled:
		return
	var scroll: Vector2 = cfg["scroll"]
	var stretch: float = cfg["stretch"]
	var tile_width := texture.get_width() * stretch
	band.texture = texture
	band.centered = true
	band.scale = Vector2(stretch, float(cfg["height"]) / texture.get_height())
	var material := band.material as ShaderMaterial
	material.set_shader_parameter(&"fog_color", cfg["color"])
	material.set_shader_parameter(&"threshold", cfg["threshold"])
	layer.scroll_scale = scroll
	layer.scroll_offset = _anchor(scroll, view) + Vector2(0.0, (float(cfg["screen_y"]) - 0.5) * view.y)
	layer.repeat_size = Vector2(tile_width, 0.0)
	layer.repeat_times = ceili(design_view.x * 1.4 / tile_width) + 1
	layer.autoscroll = cfg["auto"]

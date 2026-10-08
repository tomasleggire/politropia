class_name DashAfterimage
extends Sprite2D

## One translucent copy of Luz's pose, left in world space while she dashes and
## faded out over `lifetime`. Luz spawns one every couple of frames, so a few are
## alive at once and form the trail. Tune color, life and alpha here (scene).

## Light cyan-blue from her rim palette, bright enough to read on Greece and dark areas (the Penitent's are purple).
@export var color := Color(0.55, 0.85, 1.0)
## 0 keeps the sprite's own shading, 1 is a flat silhouette of `color`.
@export_range(0.0, 1.0) var tint_strength := 0.9
## Thin light edge on the ghost (width in px is `rim_width` in the scene material).
@export var rim_color := Color(0.88, 0.97, 1.0)
@export_range(0.0, 1.0) var rim_strength := 0.85
## Seconds each ghost lives (the Penitent's: ~0.14 s, 8-9 frames).
@export var lifetime := 0.14
@export_range(0.0, 1.0) var start_alpha := 0.82
@export_range(0.0, 1.0) var end_alpha := 0.1

var _elapsed := 0.0


## Copies the current frame, transform, offset and facing of `source`.
func setup(source: AnimatedSprite2D, frame_texture: Texture2D) -> void:
	texture = frame_texture
	centered = source.centered
	offset = source.offset
	flip_h = source.flip_h
	global_transform = source.global_transform
	_apply_tint()
	_apply_alpha()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Left where it was created: no interpolation between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	_apply_alpha()


func _apply_alpha() -> void:
	var t := clampf(_elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	modulate.a = lerpf(start_alpha, end_alpha, t)


func _apply_tint() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter(&"tint", color)
	shader_material.set_shader_parameter(&"tint_strength", tint_strength)
	shader_material.set_shader_parameter(&"rim_color", rim_color)
	shader_material.set_shader_parameter(&"rim_strength", rim_strength)

class_name RoomCamera
extends Camera2D

## Cámara lateral continua: anticipa la carrera y sigue al héroe en vertical en todo momento.

@export var target: Node2D
@export var world_size := Vector2(6400.0, 720.0)

@export_group("Framing")
## Punto medio entre la vista completa (1.0) y el encuadre de Blasphemous (~2.5).
@export var view_zoom := 1.8
## Distancia vertical desde los pies del héroe al centro de la cámara.
@export var vertical_offset := 20.0

@export_group("Follow")
@export var follow_speed := 7.5
@export var vertical_follow_speed := 6.0

@export_group("Look Ahead")
@export var look_ahead_distance := 60.0
@export var look_ahead_speed := 4.0
@export var look_ahead_min_speed := 45.0

## 0 follows the target as usual, 1 is fully framed on the pushed focus.
var _focus_weight := 0.0
var _focus_position := Vector2.ZERO
var _focus_zoom := 1.0
var _focus_tween: Tween
var _look_ahead := 0.0
var _follow_position := Vector2.ZERO


func _ready() -> void:
	# Keeps easing and following while a ritual pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	zoom = Vector2(view_zoom, view_zoom)
	make_current()
	snap_to_target()


# Runs on physics ticks so physics interpolation smooths it together with the player.
func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired_look := _desired_look_ahead()
	_look_ahead = lerpf(_look_ahead, desired_look, 1.0 - exp(-look_ahead_speed * delta))
	var desired := _desired_position()
	_follow_position = Vector2(
		lerpf(_follow_position.x, desired.x, 1.0 - exp(-follow_speed * delta)),
		lerpf(_follow_position.y, desired.y, 1.0 - exp(-vertical_follow_speed * delta))
	)
	_apply_framing()


func snap_to_target() -> void:
	_look_ahead = 0.0
	_follow_position = _desired_position()
	_apply_framing()
	reset_physics_interpolation()


## Eases the camera onto `target_position` (world space) at `zoom_scale` times
## the room zoom, holding until `pop_focus()`. A later push replaces the
## previous focus. Runs while the tree is paused.
func push_focus(target_position: Vector2, zoom_scale: float, time: float) -> void:
	_focus_position = target_position
	_focus_zoom = maxf(zoom_scale, 0.1)
	_tween_focus(1.0, time)


## Eases back to normal room framing. Immediate when `time` is 0.
func pop_focus(time: float) -> void:
	_tween_focus(0.0, time)


## 0 when framing normally, 1 when fully focused.
func get_focus_weight() -> float:
	return _focus_weight


## Current zoom relative to the room zoom (1.0 outside a focus).
func get_zoom_ratio() -> float:
	return zoom.x / view_zoom


func _tween_focus(weight: float, time: float) -> void:
	if _focus_tween != null:
		_focus_tween.kill()
		_focus_tween = null
	if time <= 0.0:
		_focus_weight = weight
		_apply_framing()
		return
	_focus_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_focus_tween.tween_method(_set_focus_weight, _focus_weight, weight, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_focus_weight(weight: float) -> void:
	_focus_weight = weight
	_apply_framing()


func _apply_framing() -> void:
	if not is_inside_tree():
		return
	var ratio := lerpf(1.0, _focus_zoom, _focus_weight)
	zoom = Vector2.ONE * view_zoom * ratio
	global_position = _follow_position.lerp(_clamped_focus_position(), _focus_weight)


func _clamped_focus_position() -> Vector2:
	var half_view := get_viewport_rect().size * 0.5 / zoom
	return Vector2(
		clampf(_focus_position.x, half_view.x, world_size.x - half_view.x),
		clampf(_focus_position.y, half_view.y, world_size.y - half_view.y)
	)


func _desired_look_ahead() -> float:
	if not target is CharacterBody2D:
		return 0.0
	var velocity_x := (target as CharacterBody2D).velocity.x
	if absf(velocity_x) <= look_ahead_min_speed:
		return 0.0
	return signf(velocity_x) * look_ahead_distance


func _desired_position() -> Vector2:
	if target == null:
		return Vector2(640.0, 360.0)
	var half_view := get_viewport_rect().size * 0.5 / (Vector2.ONE * view_zoom)
	var desired_x := target.global_position.x + _look_ahead
	return Vector2(
		clampf(desired_x, half_view.x, world_size.x - half_view.x),
		clampf(target.global_position.y - vertical_offset, half_view.y, world_size.y - half_view.y)
	)

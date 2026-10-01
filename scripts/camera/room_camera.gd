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

@export_group("Room Bounds")
## Seconds the clamp rect takes to blend into the next room's bounds.
@export var bounds_transition_time := 0.35

## 0 follows the target as usual, 1 is fully framed on the pushed focus.
var _focus_weight := 0.0
var _focus_position := Vector2.ZERO
var _focus_zoom := 1.0
var _focus_tween: Tween
var _look_ahead := 0.0
var _follow_position := Vector2.ZERO

## Optional per-room clamp rect. Blends from `_bounds_from` to `_bounds_to`;
## while inactive the camera clamps to the whole world.
var _bounds_active := false
var _bounds_keep := true
var _bounds_from := Rect2()
var _bounds_to := Rect2()
var _bounds_blend := 1.0
var _bounds_tween: Tween


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
	_finish_bounds_blend()
	_look_ahead = 0.0
	_follow_position = _desired_position()
	_apply_framing()
	reset_physics_interpolation()


## Clamps the camera to `rect` (world space) instead of the whole world, like a
## Hollow Knight room. An axis where the room is smaller than the view is
## centred. The clamp blends from the current bounds over `transition_time`
## seconds (`bounds_transition_time` when negative, immediate when 0).
func set_room_bounds(rect: Rect2, transition_time := -1.0) -> void:
	_blend_bounds_to(rect, true, transition_time)


## Goes back to clamping against the whole world, blending like set_room_bounds().
func clear_room_bounds(transition_time := -1.0) -> void:
	_blend_bounds_to(Rect2(Vector2.ZERO, world_size), false, transition_time)


## The rect the camera is clamped to right now, mid-blend included.
func get_room_bounds() -> Rect2:
	if not _bounds_active:
		return Rect2(Vector2.ZERO, world_size)
	return Rect2(
		_bounds_from.position.lerp(_bounds_to.position, _bounds_blend),
		_bounds_from.size.lerp(_bounds_to.size, _bounds_blend)
	)


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


func _blend_bounds_to(rect: Rect2, keep_active: bool, transition_time: float) -> void:
	var time := bounds_transition_time if transition_time < 0.0 else transition_time
	_bounds_from = get_room_bounds()
	_bounds_to = rect
	_bounds_keep = keep_active
	_bounds_active = true
	_bounds_blend = 0.0
	_kill_bounds_tween()
	if time <= 0.0 or not is_inside_tree():
		_bounds_blend = 1.0
		_bounds_active = _bounds_keep
		return
	_bounds_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bounds_tween.tween_property(self, "_bounds_blend", 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bounds_tween.tween_callback(_on_bounds_blend_done)


func _on_bounds_blend_done() -> void:
	_bounds_active = _bounds_keep


## Jumps to the end of a running bounds blend.
func _finish_bounds_blend() -> void:
	if _bounds_tween == null:
		return
	_kill_bounds_tween()
	_bounds_blend = 1.0
	_bounds_active = _bounds_keep


func _kill_bounds_tween() -> void:
	if _bounds_tween != null:
		_bounds_tween.kill()
		_bounds_tween = null


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
	return _clamp_to_bounds(_focus_position, get_viewport_rect().size * 0.5 / zoom)


## Keeps a view of half size `half_view` centred on `point` inside the bounds.
func _clamp_to_bounds(point: Vector2, half_view: Vector2) -> Vector2:
	var rect := get_room_bounds()
	return Vector2(
		_clamp_axis(point.x, rect.position.x, rect.end.x, half_view.x),
		_clamp_axis(point.y, rect.position.y, rect.end.y, half_view.y)
	)


## A span shorter than the view has no slack, so the view sits on its middle.
static func _clamp_axis(value: float, low: float, high: float, half_view: float) -> float:
	if high - low <= half_view * 2.0:
		return (low + high) * 0.5
	return clampf(value, low + half_view, high - half_view)


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
	var wanted := Vector2(target.global_position.x + _look_ahead, target.global_position.y - vertical_offset)
	return _clamp_to_bounds(wanted, half_view)

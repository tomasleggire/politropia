class_name RoomCamera
extends Camera2D

## Cámara lateral continua: anticipa la carrera sin perder estabilidad vertical.

@export var target: Node2D
@export var world_size := Vector2(6400.0, 720.0)
@export var follow_speed := 7.5
@export var look_ahead_distance := 150.0
@export var look_ahead_speed := 4.0

var _look_ahead := 0.0


func _ready() -> void:
	make_current()
	position = _desired_position()


func _process(delta: float) -> void:
	if target == null:
		return
	var target_velocity := 0.0
	if target is CharacterBody2D:
		target_velocity = (target as CharacterBody2D).velocity.x
	var desired_look := signf(target_velocity) * look_ahead_distance if absf(target_velocity) > 45.0 else 0.0
	_look_ahead = lerpf(_look_ahead, desired_look, 1.0 - exp(-look_ahead_speed * delta))
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_speed * delta))


func snap_to_target() -> void:
	_look_ahead = 0.0
	global_position = _desired_position()


func _desired_position() -> Vector2:
	if target == null:
		return Vector2(640.0, 360.0)
	var half_view := get_viewport_rect().size * 0.5
	var desired_x := target.global_position.x + _look_ahead
	return Vector2(
		clampf(desired_x, half_view.x, world_size.x - half_view.x),
		clampf(target.global_position.y - 65.0, half_view.y, world_size.y - half_view.y)
	)

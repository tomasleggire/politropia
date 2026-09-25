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

var _look_ahead := 0.0


func _ready() -> void:
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
	global_position = Vector2(
		lerpf(global_position.x, desired.x, 1.0 - exp(-follow_speed * delta)),
		lerpf(global_position.y, desired.y, 1.0 - exp(-vertical_follow_speed * delta))
	)


func snap_to_target() -> void:
	_look_ahead = 0.0
	global_position = _desired_position()
	reset_physics_interpolation()


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
	var half_view := get_viewport_rect().size * 0.5 / zoom
	var desired_x := target.global_position.x + _look_ahead
	return Vector2(
		clampf(desired_x, half_view.x, world_size.x - half_view.x),
		clampf(target.global_position.y - vertical_offset, half_view.y, world_size.y - half_view.y)
	)

class_name RoomCamera
extends Camera2D

## Cámara lateral continua: anticipa la carrera y, como en Blasphemous, no sigue
## cada salto en vertical; solo se reencuadra al aterrizar o al salir de la banda.

@export var target: Node2D
@export var world_size := Vector2(6400.0, 720.0)

@export_group("Framing")
## Punto medio entre la vista completa (1.0) y el encuadre de Blasphemous (~2.5).
@export var view_zoom := 1.8
## Distancia vertical desde los pies del héroe al centro de la cámara.
@export var vertical_offset := 20.0

@export_group("Follow")
@export var follow_speed := 7.5
@export var vertical_follow_speed := 4.0
## Cuánto puede subir el héroe en el aire antes de que la cámara lo acompañe.
@export var rise_margin := 150.0
## Cuánto puede caer el héroe en el aire antes de que la cámara lo acompañe.
@export var fall_margin := 40.0

@export_group("Look Ahead")
@export var look_ahead_distance := 60.0
@export var look_ahead_speed := 4.0
@export var look_ahead_min_speed := 45.0

var _look_ahead := 0.0
var _anchor_y := 0.0


func _ready() -> void:
	zoom = Vector2(view_zoom, view_zoom)
	make_current()
	snap_to_target()


# Runs on physics ticks so physics interpolation smooths it together with the player.
func _physics_process(delta: float) -> void:
	if target == null:
		return
	_update_anchor()
	var desired_look := _desired_look_ahead()
	_look_ahead = lerpf(_look_ahead, desired_look, 1.0 - exp(-look_ahead_speed * delta))
	var desired := _desired_position()
	global_position = Vector2(
		lerpf(global_position.x, desired.x, 1.0 - exp(-follow_speed * delta)),
		lerpf(global_position.y, desired.y, 1.0 - exp(-vertical_follow_speed * delta))
	)


func snap_to_target() -> void:
	_look_ahead = 0.0
	if target != null:
		_anchor_y = target.global_position.y
	global_position = _desired_position()
	reset_physics_interpolation()


func _update_anchor() -> void:
	var feet_y := target.global_position.y
	var grounded := target is CharacterBody2D and (target as CharacterBody2D).is_on_floor()
	if grounded:
		_anchor_y = feet_y
	else:
		_anchor_y = clampf(_anchor_y, feet_y - fall_margin, feet_y + rise_margin)


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
		clampf(_anchor_y - vertical_offset, half_view.y, world_size.y - half_view.y)
	)

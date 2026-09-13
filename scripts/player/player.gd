class_name Player
extends CharacterBody2D

## Movimiento top-down responsivo: aceleración corta, freno firme y control analógico.

@export var max_speed := 325.0
@export var acceleration := 2350.0
@export var deceleration := 2950.0
@export var turn_boost := 1.24
@export var analog_curve := 1.12
@export var walk_frames_per_second := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shadow: Polygon2D = $Shadow

# El sheet recorta cada fila a distinta altura; esto apoya los pies en el mismo punto.
const SPRITE_POS_BY_FACING := [
	Vector2(-3.4, -17.2),
	Vector2(1.6, -13.1),
	Vector2(-10.8, -10.1),
	Vector2(0.8, -11.1),
]
const SHADOW_POS := Vector2(0.0, 13.5)

var _facing_row := 0
var _walk_time := 0.0
var _transition_time := 0.0
var _transition_direction := Vector2.ZERO
var _last_input := Vector2.DOWN
var _base_sprite_scale := Vector2(0.265, 0.265)


func _ready() -> void:
	_sprite.frame_coords = Vector2i(1, _facing_row)
	_sprite.position = SPRITE_POS_BY_FACING[_facing_row]
	_shadow.position = SHADOW_POS


func _physics_process(delta: float) -> void:
	var input_vector := _read_input()

	if _transition_time > 0.0:
		_transition_time = maxf(_transition_time - delta, 0.0)
		input_vector = _transition_direction
		velocity = _transition_direction * max_speed * 0.82
	else:
		_apply_movement(input_vector, delta)

	move_and_slide()
	_update_facing(input_vector)
	_update_animation(delta, input_vector)


func begin_room_transition(direction: Vector2, duration: float) -> void:
	if direction == Vector2.ZERO:
		return
	_transition_direction = direction.normalized()
	_transition_time = maxf(duration, 0.05)
	velocity = _transition_direction * max_speed * 0.82


func _read_input() -> Vector2:
	var keyboard := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var touch := Vector2.ZERO
	if is_instance_valid(TouchControls):
		touch = TouchControls.get_movement_vector()
	var raw := touch if touch.length_squared() > keyboard.length_squared() else keyboard
	if raw.length_squared() <= 0.0001:
		return Vector2.ZERO
	var strength := minf(raw.length(), 1.0)
	return raw.normalized() * pow(strength, analog_curve)


func _apply_movement(input_vector: Vector2, delta: float) -> void:
	if input_vector == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		return

	var target := input_vector * max_speed
	var rate := acceleration
	if velocity.length_squared() > 1.0 and velocity.normalized().dot(input_vector.normalized()) < 0.35:
		rate *= turn_boost
	velocity = velocity.move_toward(target, rate * delta)


func _update_facing(input_vector: Vector2) -> void:
	if input_vector.length_squared() < 0.01:
		return
	_last_input = input_vector
	if absf(input_vector.x) > absf(input_vector.y):
		_facing_row = 2 if input_vector.x > 0.0 else 1
	else:
		_facing_row = 0 if input_vector.y > 0.0 else 3


func _update_animation(delta: float, input_vector: Vector2) -> void:
	var moving := velocity.length() > 34.0 and input_vector.length_squared() > 0.01
	if moving:
		var speed_ratio := clampf(velocity.length() / max_speed, 0.35, 1.0)
		_walk_time += delta * walk_frames_per_second * speed_ratio
		_sprite.frame_coords = Vector2i(int(_walk_time) % 4, _facing_row)
	else:
		_walk_time = 1.0
		_sprite.frame_coords = Vector2i(1, _facing_row)

	_sprite.scale = _base_sprite_scale
	_sprite.position = SPRITE_POS_BY_FACING[_facing_row]
	_shadow.position = SHADOW_POS
	_shadow.scale = Vector2.ONE

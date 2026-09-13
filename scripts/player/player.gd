class_name Player
extends CharacterBody2D

## Movimiento top-down responsivo: aceleración corta, freno firme y control analógico.

signal died

@export var max_speed := 325.0
@export var acceleration := 2350.0
@export var deceleration := 2950.0
@export var turn_boost := 1.24
@export var analog_curve := 1.12
@export var walk_frames_per_second := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shadow: Polygon2D = $Shadow

const WandBolt := preload("res://scripts/combat/wand_projectile.gd")

# El sheet recorta cada fila a distinta altura; esto apoya los pies en el mismo punto.
const SPRITE_POS_BY_FACING := [
	Vector2(-3.4, -17.2),
	Vector2(1.6, -13.1),
	Vector2(-10.8, -10.1),
	Vector2(0.8, -11.1),
]
const SHADOW_POS := Vector2(0.0, 13.5)
const ATTACK_SPAWN_DISTANCE := 42.0
const MAX_HP := 3

var _facing_row := 0
var _walk_time := 0.0
var _transition_time := 0.0
var _transition_direction := Vector2.ZERO
var _last_input := Vector2.DOWN
var _base_sprite_scale := Vector2(0.265, 0.265)
var _has_wand := false
var _hp := MAX_HP
var _i_frames := 0.0
var _stun := 0.0
var _checkpoint := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"player")
	_sprite.frame_coords = Vector2i(1, _facing_row)
	_sprite.position = SPRITE_POS_BY_FACING[_facing_row]
	_shadow.position = SHADOW_POS


func _physics_process(delta: float) -> void:
	_i_frames = maxf(_i_frames - delta, 0.0)
	_stun = maxf(_stun - delta, 0.0)
	modulate.a = 0.42 if _i_frames > 0.0 and int(_i_frames * 18.0) % 2 == 0 else 1.0

	var input_vector := _read_input()

	if _transition_time > 0.0:
		_transition_time = maxf(_transition_time - delta, 0.0)
		input_vector = _transition_direction
		velocity = _transition_direction * max_speed * 0.82
	elif _stun > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * 0.55 * delta)
	else:
		_apply_movement(input_vector, delta)

	move_and_slide()
	_update_facing(input_vector)
	_update_animation(delta, input_vector)
	_update_attack(delta)


func unlock_wand() -> void:
	if _has_wand:
		return
	_has_wand = true
	if is_instance_valid(TouchControls):
		TouchControls.unlock_attack()


func mark_checkpoint(world_position: Vector2) -> void:
	_checkpoint = world_position


func take_damage(amount: int, from_dir: Vector2) -> void:
	if _i_frames > 0.0:
		return
	_hp -= amount
	_i_frames = 0.78
	_stun = 0.12
	if from_dir != Vector2.ZERO:
		velocity += from_dir.normalized() * 360.0
	Input.vibrate_handheld(36, 0.55)
	if _hp <= 0:
		_respawn()


func _respawn() -> void:
	died.emit()
	_hp = MAX_HP
	_i_frames = 1.15
	_stun = 0.0
	velocity = Vector2.ZERO
	if _checkpoint != Vector2.ZERO:
		global_position = _checkpoint


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


func facing_direction() -> Vector2:
	match _facing_row:
		1:
			return Vector2.LEFT
		2:
			return Vector2.RIGHT
		3:
			return Vector2.UP
		_:
			return Vector2.DOWN


func _update_attack(_delta: float) -> void:
	if not _has_wand:
		return
	if _is_attack_just_pressed():
		_fire_wand()


func _is_attack_just_pressed() -> bool:
	if is_instance_valid(TouchControls) and TouchControls.poll_attack_just_pressed():
		return true
	return Input.is_action_just_pressed(&"attack")


func _fire_wand() -> void:
	var direction := facing_direction()
	var bolt := WandBolt.new()
	var parent := get_parent().get_node_or_null("Projectiles")
	if parent == null:
		parent = get_parent()
	parent.add_child(bolt)
	bolt.global_position = global_position + Vector2(0, 6) + direction * ATTACK_SPAWN_DISTANCE
	bolt.launch(direction)

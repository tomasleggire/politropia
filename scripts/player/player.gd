class_name Player
extends CharacterBody2D

## Controlador lateral ágil y con peso. El input puede venir del teclado o de gestos.

signal respawned

@export_category("Movimiento")
@export var max_run_speed: float = 300.0
@export var ground_acceleration: float = 1900.0
@export var ground_deceleration: float = 2400.0
@export var turn_acceleration: float = 3000.0
@export var air_acceleration: float = 1050.0
@export var air_deceleration: float = 360.0

@export_category("Salto")
@export var jump_speed: float = 585.0
@export var gravity_rise: float = 1500.0
@export var gravity_fall: float = 2050.0
@export var gravity_apex: float = 900.0
@export var max_fall_speed: float = 980.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.14
@export var apex_threshold: float = 85.0

@export_category("Sensación")
@export var landing_lock_time: float = 0.07
@export var footstep_interval: float = 0.24
@export var drop_through_time: float = 0.20

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump

var _facing := 1
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _landing_left := 0.0
var _drop_left := 0.0
var _footstep_left := 0.0
var _was_on_floor := false
var _spawn_position := Vector2.ZERO


func _ready() -> void:
	_spawn_position = global_position
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_read_actions()

	var grounded := is_on_floor()
	if grounded:
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)

	var input_axis := Input.get_axis(&"move_left", &"move_right")
	_apply_horizontal(input_axis, grounded, delta)
	_try_jump()
	_apply_gravity(delta)

	var fall_speed_before_move := velocity.y
	move_and_slide()

	if not _was_on_floor and is_on_floor() and fall_speed_before_move > 120.0:
		_landing_left = landing_lock_time
		_sfx_land.play()
	_was_on_floor = is_on_floor()

	_update_facing(input_axis)
	_update_footsteps(delta, input_axis)
	_update_animation()


func _update_timers(delta: float) -> void:
	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)
	_landing_left = maxf(_landing_left - delta, 0.0)
	if _drop_left > 0.0:
		_drop_left -= delta
		if _drop_left <= 0.0:
			set_collision_mask_value(2, true)


func _read_actions() -> void:
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time
	if Input.is_action_just_pressed(&"drop_down"):
		_begin_drop_through()


func _apply_horizontal(input_axis: float, grounded: bool, delta: float) -> void:
	var target := input_axis * max_run_speed
	var acceleration: float
	if grounded:
		if is_zero_approx(input_axis):
			acceleration = ground_deceleration
		elif not is_zero_approx(velocity.x) and signf(input_axis) != signf(velocity.x):
			acceleration = turn_acceleration
		else:
			acceleration = ground_acceleration
	else:
		acceleration = air_acceleration if not is_zero_approx(input_axis) else air_deceleration
	velocity.x = move_toward(velocity.x, target, acceleration * delta)


func _try_jump() -> void:
	if _jump_buffer_left <= 0.0 or _coyote_left <= 0.0 or _drop_left > 0.0:
		return
	velocity.y = -jump_speed
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_landing_left = 0.0
	_sfx_jump.play()


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		return
	var gravity := gravity_rise
	if absf(velocity.y) < apex_threshold:
		gravity = gravity_apex
	elif velocity.y > 0.0:
		gravity = gravity_fall
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _begin_drop_through() -> void:
	if not is_on_floor() or _drop_left > 0.0 or not _standing_on_one_way():
		return
	# Las plataformas atravesables viven en la capa 2; el piso sigue sólido.
	set_collision_mask_value(2, false)
	_drop_left = drop_through_time
	velocity.y = 110.0
	global_position.y += 5.0


func _standing_on_one_way() -> bool:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision.get_normal().y > -0.7:
			continue
		var collider := collision.get_collider() as CollisionObject2D
		if collider != null and collider.get_collision_layer_value(2):
			return true
	return false


func set_checkpoint(checkpoint: Vector2) -> void:
	_spawn_position = checkpoint


func respawn() -> void:
	set_collision_mask_value(2, true)
	_drop_left = 0.0
	velocity = Vector2.ZERO
	global_position = _spawn_position
	respawned.emit()


func _update_facing(input_axis: float) -> void:
	if absf(input_axis) < 0.05:
		return
	_facing = 1 if input_axis > 0.0 else -1
	_sprite.flip_h = _facing < 0


func _update_footsteps(delta: float, input_axis: float) -> void:
	if not is_on_floor() or absf(input_axis) < 0.05 or absf(velocity.x) < 60.0:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left <= 0.0:
		_sfx_foot.play()
		_footstep_left = footstep_interval


func _update_animation() -> void:
	if not is_on_floor():
		_play_animation(&"jump" if velocity.y < 40.0 else &"fall")
	elif _landing_left > 0.0:
		_play_animation(&"land")
	elif absf(velocity.x) > 28.0:
		_play_animation(&"walk")
		_sprite.speed_scale = clampf(absf(velocity.x) / 185.0, 0.75, 1.65)
	else:
		_play_animation(&"idle")
		_sprite.speed_scale = 1.0


func _play_animation(animation_name: StringName) -> void:
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)

class_name Player
extends CharacterBody2D

## Jugador con salto cargado estilo Jump King.
## Estados explícitos para lectura clara y rendimiento predecible.

enum State {
	GROUNDED,
	CHARGING,
	AIRBORNE,
	LANDING,
}

@export var move_speed: float = 150.0
@export var gravity: float = 2200.0
@export var max_charge_time: float = 0.85
@export var min_jump_strength: float = 380.0
@export var max_jump_strength: float = 1250.0
@export var min_horizontal_factor: float = 0.28
@export var max_horizontal_factor: float = 0.62
@export var bounce_retention: float = 0.92
@export var land_recover_time: float = 0.28
@export var footstep_interval: float = 0.22

@onready var _charge_meter: JumpChargeMeter = $JumpChargeMeter
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_wall: AudioStreamPlayer = $SfxWall
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_charge: AudioStreamPlayer = $SfxCharge
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump

var _state: State = State.GROUNDED
var _charge_time: float = 0.0
var _aim_direction: int = 0
var _facing: int = 1
var _land_timer: float = 0.0
var _fall_speed_on_land: float = 0.0
var _foot_timer: float = 0.0


func _ready() -> void:
	_charge_meter.visible = false
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	match _state:
		State.GROUNDED:
			_process_grounded(delta)
		State.CHARGING:
			_process_charging(delta)
		State.AIRBORNE:
			_process_airborne(delta)
		State.LANDING:
			_process_landing(delta)
	_update_animation()


func _process_grounded(delta: float) -> void:
	_apply_gravity(delta)

	var input_dir := _read_horizontal_input()
	velocity.x = input_dir * move_speed
	if input_dir != 0:
		_set_facing(input_dir)
		_update_footsteps(delta, true)
	else:
		_foot_timer = 0.0

	if Input.is_action_just_pressed("jump"):
		_begin_charge()
		move_and_slide()
		return

	move_and_slide()

	if not is_on_floor():
		_enter_airborne()


func _process_charging(delta: float) -> void:
	velocity = Vector2.ZERO
	_charge_time = minf(_charge_time + delta, max_charge_time)
	_foot_timer = 0.0

	var input_dir := _read_horizontal_input()
	if input_dir != 0:
		_aim_direction = input_dir
		_set_facing(input_dir)

	_update_charge_meter()

	if Input.is_action_just_released("jump"):
		_release_jump()
		return

	move_and_slide()

	if not is_on_floor():
		_cancel_charge()
		_enter_airborne()


func _process_airborne(delta: float) -> void:
	_foot_timer = 0.0
	_apply_gravity(delta)
	var velocity_before_move := velocity
	move_and_slide()
	_resolve_bounces(velocity_before_move)

	if is_on_floor():
		_fall_speed_on_land = maxf(velocity_before_move.y, velocity.y)
		_land()


func _process_landing(delta: float) -> void:
	velocity = Vector2.ZERO
	_land_timer -= delta
	move_and_slide()
	if _land_timer <= 0.0:
		_state = State.GROUNDED


func _begin_charge() -> void:
	_state = State.CHARGING
	_charge_time = 0.0
	_aim_direction = _facing
	velocity = Vector2.ZERO
	_charge_meter.visible = true
	_update_charge_meter()
	_sfx_charge.play()


func _cancel_charge() -> void:
	_charge_time = 0.0
	_charge_meter.visible = false
	_charge_meter.set_ratio(0.0)


func _release_jump() -> void:
	var ratio := _charge_ratio()
	var strength := lerpf(min_jump_strength, max_jump_strength, ratio)
	var jump_dir := _aim_direction if _aim_direction != 0 else _facing
	var horizontal_factor := lerpf(min_horizontal_factor, max_horizontal_factor, ratio)
	velocity = Vector2(jump_dir * strength * horizontal_factor, -strength)

	_charge_meter.visible = false
	_charge_meter.set_ratio(0.0)
	_charge_time = 0.0
	_sfx_jump.play()
	_enter_airborne()


func _enter_airborne() -> void:
	_state = State.AIRBORNE


func _land() -> void:
	velocity = Vector2.ZERO
	_sfx_land.play()
	var impact := clampf(_fall_speed_on_land / 900.0, 0.35, 1.0)
	_land_timer = land_recover_time * impact
	_state = State.LANDING


func _resolve_bounces(velocity_before_move: Vector2) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		if normal.y < -0.7:
			continue

		if velocity_before_move.dot(normal) >= 0.0:
			continue

		velocity = velocity_before_move.bounce(normal) * bounce_retention
		_sfx_wall.play()
		break


func _update_footsteps(delta: float, walking: bool) -> void:
	if not walking or not is_on_floor():
		return
	_foot_timer -= delta
	if _foot_timer <= 0.0:
		_sfx_foot.play()
		_foot_timer = footstep_interval


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


func _read_horizontal_input() -> int:
	var axis := Input.get_axis("move_left", "move_right")
	if axis < 0.0:
		return -1
	if axis > 0.0:
		return 1
	return 0


func _charge_ratio() -> float:
	var linear := clampf(_charge_time / max_charge_time, 0.0, 1.0)
	return linear * linear


func _update_charge_meter() -> void:
	_charge_meter.set_ratio(_charge_ratio())


func _set_facing(direction: int) -> void:
	if direction == 0:
		return
	_facing = direction
	_sprite.flip_h = direction < 0


func _update_animation() -> void:
	match _state:
		State.CHARGING:
			_play_animation(&"charge")
		State.AIRBORNE:
			if velocity.y < 0.0:
				_play_animation(&"jump")
			else:
				_play_animation(&"fall")
		State.LANDING:
			_play_animation(&"land")
		State.GROUNDED:
			if absf(velocity.x) > 5.0:
				_play_animation(&"walk")
			else:
				_play_animation(&"idle")


func _play_animation(anim_name: StringName) -> void:
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)

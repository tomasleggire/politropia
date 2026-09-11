class_name Player
extends CharacterBody2D

## Jugador estilo Jump King (calco de potencia/ángulo + knockdown).

enum State {
	GROUNDED,
	CHARGING,
	AIRBORNE,
	LANDING,
	FALLEN,
}

## Constantes reales de Jump King (px/frame @ 60fps), escaladas a nuestro mundo.
## Fuente: simulación del mod jump-king-parabole / valores del juego.
const JK_GRAVITY_PER_FRAME := 0.2571429
const JK_JUMP_VY_MAX := 8.742858
const JK_JUMP_VX := 3.5
const JK_MAX_FALL := 10.0
const JK_CHARGE_SECONDS := 0.6
## ~36 pasos a 60fps (speedrunners miden 35–38 frames de carga completa).
const CHARGE_FRAMES := 36
## Escala visual para habitaciones 720×1280 (preserva ángulos JK).
const WORLD_SCALE := 2.25

@export var move_speed: float = 145.0
## Solo para mostrar el medidor/SFX; un tap igual salta (mínimo 1 frame).
@export var min_hold_to_arm: float = 0.10

## Rebote: el primero conserva subida (mecánica de pared → plataforma).
@export var bounce_retention: float = 0.72
@export var bounce_up_boost: float = 1.05

@export var soft_land_time: float = 0.18
## Knockdown corto; solo en caídas fuertes (no en aterrizajes de salto OK).
@export var fallen_time: float = 0.62
@export var hard_fall_speed: float = 1560.0
@export var hard_fall_air_time: float = 0.55
@export var footstep_interval: float = 0.22

@onready var _charge_meter: JumpChargeMeter = $JumpChargeMeter
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_wall: AudioStreamPlayer = $SfxWall
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_fall: AudioStreamPlayer = $SfxFall
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_charge: AudioStreamPlayer = $SfxCharge
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump

var _state: State = State.GROUNDED
var _charge_frames: int = 0
var _charge_accum: float = 0.0
var _aim_direction: int = 0
var _facing: int = 1
var _land_timer: float = 0.0
var _fall_speed_on_land: float = 0.0
var _foot_timer: float = 0.0
var _charge_armed: bool = false
var _wall_bounce_used: bool = false
var _peak_fall_speed: float = 0.0
var _falling_air_time: float = 0.0
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _sprite_base_rot: float = 0.0

var gravity: float:
	get:
		return JK_GRAVITY_PER_FRAME * 60.0 * 60.0 * WORLD_SCALE

var jump_vy_max: float:
	get:
		return JK_JUMP_VY_MAX * 60.0 * WORLD_SCALE

var jump_vx: float:
	get:
		return JK_JUMP_VX * 60.0 * WORLD_SCALE

var max_fall_speed: float:
	get:
		# Un poco sobre el tope JK para permitir caídas largas → knockdown.
		return JK_MAX_FALL * 60.0 * WORLD_SCALE * 1.4


func _ready() -> void:
	_sprite_base_pos = _sprite.position
	_sprite_base_rot = _sprite.rotation
	_charge_meter.visible = false
	_charge_meter.configure_ticks(CHARGE_FRAMES)
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
		State.FALLEN:
			_process_fallen(delta)
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
	_foot_timer = 0.0

	# Avance de carga en “frames JK” (60 Hz), no en FPS del dispositivo.
	_charge_accum += delta * 60.0
	while _charge_accum >= 1.0 and _charge_frames < CHARGE_FRAMES:
		_charge_accum -= 1.0
		_charge_frames += 1

	var charge_time := float(_charge_frames) / 60.0
	if not _charge_armed and charge_time >= min_hold_to_arm:
		_charge_armed = true
		_charge_meter.visible = true
		_sfx_charge.play()

	var input_dir := _read_horizontal_input()
	if input_dir != 0:
		_aim_direction = input_dir
		_set_facing(input_dir)

	if _charge_armed:
		_charge_meter.set_frame(_charge_frames)

	if Input.is_action_just_released("jump"):
		# Tap = salto mínimo (1 frame). Hold = carga. Nunca cancelar sin saltar.
		_charge_frames = maxi(_charge_frames, 1)
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

	_peak_fall_speed = maxf(_peak_fall_speed, maxf(velocity.y, velocity_before_move.y))
	if velocity_before_move.y > 80.0 or velocity.y > 80.0:
		_falling_air_time += delta
	else:
		_falling_air_time = 0.0

	if is_on_floor():
		_fall_speed_on_land = maxf(_peak_fall_speed, maxf(velocity_before_move.y, velocity.y))
		_land()


func _process_landing(delta: float) -> void:
	velocity = Vector2.ZERO
	_land_timer -= delta
	# Buffer de tap: si tapeás durante el soft-land, arranca carga al instante.
	if Input.is_action_just_pressed("jump"):
		_reset_sprite_pose()
		_begin_charge()
		move_and_slide()
		return
	move_and_slide()
	if _land_timer <= 0.0:
		_reset_sprite_pose()
		_state = State.GROUNDED


func _process_fallen(delta: float) -> void:
	velocity = Vector2.ZERO
	_land_timer -= delta
	move_and_slide()
	if _land_timer <= 0.0:
		_reset_sprite_pose()
		_state = State.GROUNDED


func _begin_charge() -> void:
	_state = State.CHARGING
	_charge_frames = 0
	_charge_accum = 0.0
	_charge_armed = false
	_aim_direction = _facing
	velocity = Vector2.ZERO
	_charge_meter.visible = false
	_charge_meter.set_frame(0)


func _cancel_charge() -> void:
	_charge_frames = 0
	_charge_accum = 0.0
	_charge_armed = false
	_charge_meter.visible = false
	_charge_meter.set_frame(0)


func _release_jump() -> void:
	# Calco JK: vY = -max * intensity; vX = dirección * velocidad fija.
	# intensity mínima = 1/36 (tap = saltito casi caminar).
	var intensity := clampf(float(_charge_frames) / float(CHARGE_FRAMES), 0.0, 1.0)
	intensity = maxf(intensity, 1.0 / float(CHARGE_FRAMES))

	var jump_dir := _aim_direction if _aim_direction != 0 else _facing
	velocity = Vector2(jump_dir * jump_vx, -jump_vy_max * intensity)

	_cancel_charge()
	_sfx_jump.play()
	_enter_airborne()


func _enter_airborne() -> void:
	_state = State.AIRBORNE
	_wall_bounce_used = false
	_peak_fall_speed = maxf(0.0, velocity.y)
	_falling_air_time = 0.0
	_reset_sprite_pose()


func _land() -> void:
	velocity = Vector2.ZERO
	_wall_bounce_used = false

	var is_hard_fall := (
		_fall_speed_on_land >= hard_fall_speed
		and _falling_air_time >= hard_fall_air_time
	)
	_falling_air_time = 0.0
	if is_hard_fall:
		_enter_fallen()
	else:
		_sfx_land.play()
		# Saltitos chicos: recuperación casi nula para poder tapeear.
		if _fall_speed_on_land < 420.0:
			_land_timer = 0.04
		else:
			_land_timer = soft_land_time
		_state = State.LANDING


func _enter_fallen() -> void:
	_sfx_fall.play()
	_land_timer = fallen_time
	_state = State.FALLEN
	_apply_fallen_pose()


func _apply_fallen_pose() -> void:
	# Boca abajo en el piso (lectura clara de “fue una caída”).
	_sprite.rotation = PI * 0.5 * float(_facing)
	_sprite.position = _sprite_base_pos + Vector2(float(_facing) * 8.0, 10.0)


func _reset_sprite_pose() -> void:
	_sprite.rotation = _sprite_base_rot
	_sprite.position = _sprite_base_pos


func _resolve_bounces(velocity_before_move: Vector2) -> void:
	# Un solo rebote por vuelo; el primero sirve para llegar a plataformas.
	if _wall_bounce_used:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		if normal.y < -0.7:
			continue

		if velocity_before_move.dot(normal) >= 0.0:
			continue

		var bounced := velocity_before_move.bounce(normal)
		bounced.x *= bounce_retention

		# Si venimos subiendo / con energía, el rebote empuja hacia arriba.
		if velocity_before_move.y < 0.0:
			bounced.y = minf(bounced.y, velocity_before_move.y) * bounce_up_boost
			bounced.y = minf(bounced.y, -absf(velocity_before_move.x) * 0.35)
		else:
			# En caída: toque sutil y sigue bajando (sin segundo “super salto”).
			bounced.y = absf(bounced.y) * 0.25

		velocity = bounced
		_wall_bounce_used = true
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
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _read_horizontal_input() -> int:
	var axis := Input.get_axis("move_left", "move_right")
	if axis < 0.0:
		return -1
	if axis > 0.0:
		return 1
	return 0


func _set_facing(direction: int) -> void:
	if direction == 0:
		return
	_facing = direction
	_sprite.flip_h = direction < 0


func _update_animation() -> void:
	match _state:
		State.CHARGING:
			if _charge_armed:
				_play_animation(&"charge")
			elif absf(velocity.x) > 5.0:
				_play_animation(&"walk")
			else:
				_play_animation(&"idle")
		State.AIRBORNE:
			if velocity.y < 0.0:
				_play_animation(&"jump")
			else:
				_play_animation(&"fall")
		State.LANDING:
			_play_animation(&"land")
		State.FALLEN:
			_play_animation(&"fall")
		State.GROUNDED:
			if absf(velocity.x) > 5.0:
				_play_animation(&"walk")
			else:
				_play_animation(&"idle")


func _play_animation(anim_name: StringName) -> void:
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)

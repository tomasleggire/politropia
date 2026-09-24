class_name Player
extends CharacterBody2D

## Blasphemous-style finite state machine: weighty ground run, a precise
## jump arc, crouch, a ground-only dash/slide, wall cling + climb jump,
## ledge grab, a 3-hit ground combo, up/air/crouch attacks and a down plunge.

signal respawned

enum State {
	IDLE, RUN, CROUCH, JUMP, FALL, DASH,
	WALL_CLING, LEDGE_HANG, LEDGE_CLIMB,
	ATTACK, AIR_ATTACK, UP_ATTACK, CROUCH_ATTACK, PLUNGE, PLUNGE_LAND,
}

const PHASE_STARTUP := 0
const PHASE_ACTIVE := 1
const PHASE_RECOVERY := 2

@export_group("Run")
@export var run_max_speed := 250.0
@export var run_acceleration := 4000.0
@export var run_deceleration := 5000.0

@export_group("Jump")
## Apex height and time-to-apex derive rise gravity and launch velocity.
@export var jump_height := 130.0
@export var jump_time_to_apex := 0.36
## Releasing jump while rising multiplies the current upward speed by this.
@export var jump_release_multiplier := 0.45
@export var fall_gravity_multiplier := 1.2
@export var max_fall_speed := 900.0
@export var coyote_time := 0.08
@export var jump_buffer_time := 0.10

@export_group("Air Control")
@export var air_acceleration := 2600.0
@export var air_deceleration := 2600.0

@export_group("Landing")
@export var landing_squash_time := 0.08
@export var landing_impact_speed := 150.0

@export_group("Crouch")
@export var crouch_collider_scale := 0.5
@export var crouch_headroom_margin := 4.0

@export_group("Drop Through")
@export var drop_through_time := 0.20

@export_group("Dash")
@export var dash_duration := 0.45
@export var dash_speed := 480.0
## Fraction of dash_duration spent at full dash_speed before easing to run speed.
@export var dash_full_speed_ratio := 0.70
@export var dash_cooldown := 0.35

@export_group("Wall")
@export var wall_ray_length := 20.0
@export var wall_cling_apex_threshold := 60.0
@export var wall_climb_hop_speed := 620.0
@export var wall_climb_hop_outward_speed := 140.0
@export var wall_jump_horizontal_speed := 300.0
@export var wall_jump_vertical_speed := 560.0
@export var wall_jump_lock_time := 0.15
@export var wall_recling_lockout := 0.2

@export_group("Ledge")
@export var ledge_climb_duration := 0.25
@export var ledge_climb_forward_offset := 40.0

@export_group("Attack")
@export var attack_startup_time := 0.06
@export var attack_active_time := 0.10
## Total time (from attack start) before combo hit 1/2 close and buffer expires.
@export var attack_window_hit1 := 0.30
@export var attack_window_hit2 := 0.30
## Total time for the finisher (hit 3) and for crouch/up-attack windows.
@export var attack_window_hit3 := 0.45
@export var attack_forward_step_speed := 60.0
## Air attack total cycle (startup + active + recovery); re-attack allowed once recovery starts.
@export var air_attack_recovery := 0.35

@export_group("Plunge")
@export var plunge_hang_time := 0.12
@export var plunge_fall_speed := 1300.0
@export var plunge_land_active_time := 0.12
@export var plunge_land_recovery_time := 0.25

@export_group("Attack Hitboxes")
@export var hitbox_ground_size := Vector2(52.0, 30.0)
@export var hitbox_ground_offset := Vector2(34.0, -35.0)
@export var hitbox_finisher_size := Vector2(64.0, 34.0)
@export var hitbox_finisher_offset := Vector2(40.0, -34.0)
@export var hitbox_crouch_size := Vector2(50.0, 18.0)
@export var hitbox_crouch_offset := Vector2(32.0, -13.0)
@export var hitbox_up_size := Vector2(26.0, 54.0)
@export var hitbox_up_offset := Vector2(0.0, -82.0)
@export var hitbox_air_size := Vector2(50.0, 26.0)
@export var hitbox_air_offset := Vector2(34.0, -40.0)
@export var hitbox_plunge_size := Vector2(28.0, 18.0)
@export var hitbox_plunge_offset := Vector2(0.0, 12.0)
@export var hitbox_plunge_land_size := Vector2(150.0, 20.0)
@export var hitbox_plunge_land_offset := Vector2(0.0, 6.0)

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _wall_check_head: RayCast2D = $WallCheckHead
@onready var _wall_check_chest: RayCast2D = $WallCheckChest
@onready var _ledge_check_above: RayCast2D = $LedgeCheckAbove
@onready var _headroom_check: RayCast2D = $HeadroomCheck
@onready var _attack_hitbox: AttackHitbox = $AttackHitbox

var _state := State.IDLE
var _state_time := 0.0
var _facing := 1
var _spawn_position := Vector2.ZERO

var _rise_gravity := 0.0
var _fall_gravity := 0.0
var _jump_velocity := 0.0
var _standing_shape_height := 58.0

var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _landing_left := 0.0
var _footstep_left := 0.0
var _was_on_floor := false
var _drop_left := 0.0

var _dash_direction := 1
var _dash_cooldown_left := 0.0

var _wall_direction := 0
var _wall_recling_lock := 0.0
var _wall_jump_lock_left := 0.0

var _ledge_snap_from := Vector2.ZERO
var _ledge_snap_to := Vector2.ZERO
var _ledge_climb_time := 0.0

var _attack_phase := PHASE_STARTUP
var _attack_combo_index := 0
var _attack_buffered := false


func _ready() -> void:
	add_to_group(&"player")
	_spawn_position = global_position
	_recompute_jump_physics()

	var shape := _collision_shape.shape as RectangleShape2D
	_standing_shape_height = shape.size.y
	_collision_shape.shape = shape.duplicate()

	_wall_check_head.collision_mask = 1
	_wall_check_chest.collision_mask = 1
	_ledge_check_above.collision_mask = 1
	_headroom_check.collision_mask = 1

	_enter_state(State.IDLE)


func _recompute_jump_physics() -> void:
	_rise_gravity = (2.0 * jump_height) / (jump_time_to_apex * jump_time_to_apex)
	_jump_velocity = -_rise_gravity * jump_time_to_apex
	_fall_gravity = _rise_gravity * fall_gravity_multiplier


func _physics_process(delta: float) -> void:
	_state_time += delta
	_update_shared_timers(delta)
	_update_facing()
	_update_facing_rays()

	if Input.is_action_just_pressed(&"attack"):
		_queue_attack(_held_vertical_direction())

	var fall_speed_before_move := velocity.y

	match _state:
		State.IDLE, State.RUN:
			_update_ground_move(delta)
		State.CROUCH:
			_update_crouch(delta)
		State.JUMP, State.FALL:
			_update_airborne(delta)
		State.DASH:
			_update_dash(delta)
		State.WALL_CLING:
			_update_wall_cling(delta)
		State.LEDGE_HANG:
			_update_ledge_hang(delta)
		State.LEDGE_CLIMB:
			_update_ledge_climb(delta)
			_update_animation()
			return
		State.ATTACK:
			_update_attack(delta)
		State.CROUCH_ATTACK:
			_update_crouch_attack(delta)
		State.UP_ATTACK:
			_update_up_attack(delta)
		State.AIR_ATTACK:
			_update_air_attack(delta)
		State.PLUNGE:
			_update_plunge(delta)
		State.PLUNGE_LAND:
			_update_plunge_land(delta)

	move_and_slide()
	_after_move(fall_speed_before_move)
	_update_footsteps(delta)
	_update_animation()


func _update_shared_timers(delta: float) -> void:
	_landing_left = maxf(_landing_left - delta, 0.0)
	_wall_recling_lock = maxf(_wall_recling_lock - delta, 0.0)
	_wall_jump_lock_left = maxf(_wall_jump_lock_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)

	if _drop_left > 0.0:
		_drop_left -= delta
		if _drop_left <= 0.0:
			set_collision_mask_value(2, true)

	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	var grounded_state := _state != State.WALL_CLING and _state != State.LEDGE_HANG and _state != State.LEDGE_CLIMB
	if is_on_floor() and grounded_state:
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)


## -- Facing ---------------------------------------------------------------

func _horizontal_input() -> float:
	if _wall_jump_lock_left > 0.0:
		return 0.0
	return Input.get_axis(&"move_left", &"move_right")


func _update_facing() -> void:
	if _state == State.DASH or _state == State.WALL_CLING or _state == State.LEDGE_HANG or _state == State.LEDGE_CLIMB:
		return
	var axis := _horizontal_input()
	if not is_zero_approx(axis):
		_facing = 1 if axis > 0.0 else -1
	_sprite.flip_h = _facing < 0


func _update_facing_rays() -> void:
	_wall_check_head.target_position.x = wall_ray_length * _facing
	_wall_check_chest.target_position.x = wall_ray_length * _facing
	_ledge_check_above.target_position.x = wall_ray_length * _facing
	_wall_check_head.force_raycast_update()
	_wall_check_chest.force_raycast_update()
	_ledge_check_above.force_raycast_update()


## -- Ground: idle / run -----------------------------------------------------

func _update_ground_move(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return

	var axis := _horizontal_input()
	var target_speed := axis * run_max_speed
	var accel := run_acceleration if not is_zero_approx(axis) else run_deceleration
	velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	velocity.y = 0.0

	if Input.is_action_pressed(&"move_down"):
		_enter_state(State.CROUCH)
		return

	if _try_launch_jump():
		return

	if Input.is_action_just_pressed(&"dash") and _dash_cooldown_left <= 0.0:
		_start_dash()
		return

	_state = State.RUN if absf(velocity.x) > 5.0 else State.IDLE


## -- Crouch ------------------------------------------------------------------

func _update_crouch(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return

	velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	velocity.y = 0.0

	if _jump_buffer_left > 0.0:
		# On a one-way platform: fall through. On solid ground: stay crouched,
		# down + jump is not a jump.
		if _standing_on_one_way():
			_begin_drop_through()
		_jump_buffer_left = 0.0

	if not Input.is_action_pressed(&"move_down") and _has_standing_headroom():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


func _has_standing_headroom() -> bool:
	var crouch_height := _standing_shape_height * crouch_collider_scale
	var needed := (_standing_shape_height - crouch_height) + crouch_headroom_margin
	_headroom_check.position = Vector2(0.0, -crouch_height)
	_headroom_check.target_position = Vector2(0.0, -needed)
	_headroom_check.force_raycast_update()
	return not _headroom_check.is_colliding()


## -- Combat: attack dispatch -----------------------------------------------------

## direction: -1 up, 0 neutral, 1 down. Used by both the keyboard attack
## action and the touch UI's request_attack override.
func _held_vertical_direction() -> int:
	if Input.is_action_pressed(&"move_up"):
		return -1
	if Input.is_action_pressed(&"move_down"):
		return 1
	return 0


## Touch UI entry point: get_tree().call_group(&"player", &"request_attack", dir).
## A neutral (0) touch attack falls back to whatever move_up/move_down the
## on-screen joystick is currently holding, same as the keyboard path.
func request_attack(direction: int) -> void:
	var resolved := direction
	if resolved == 0:
		resolved = _held_vertical_direction()
	_queue_attack(resolved)


func _queue_attack(direction: int) -> void:
	match _state:
		State.ATTACK:
			if _attack_phase == PHASE_RECOVERY:
				_attack_buffered = true
			return
		State.AIR_ATTACK:
			if _attack_phase == PHASE_RECOVERY:
				_state_time = 0.0
				_attack_phase = PHASE_STARTUP
			return
		State.CROUCH_ATTACK, State.UP_ATTACK, State.PLUNGE, State.PLUNGE_LAND:
			return
		State.DASH, State.WALL_CLING, State.LEDGE_HANG, State.LEDGE_CLIMB:
			return
		_:
			pass

	if not is_on_floor():
		if direction == 1:
			_start_plunge()
		elif direction == -1:
			_start_up_attack()
		else:
			_start_air_attack()
		return

	if _state == State.CROUCH:
		_start_crouch_attack()
		return

	if direction == -1:
		_start_up_attack()
		return

	_start_ground_attack()


func _end_generic_attack() -> void:
	if is_on_floor():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
	else:
		_enter_state(State.JUMP if velocity.y < 0.0 else State.FALL)


## -- Combat: ground combo -----------------------------------------------------

func _start_ground_attack() -> void:
	_attack_combo_index = 0
	_attack_buffered = false
	_enter_state(State.ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		_apply_gravity(delta)

	var window := _attack_window_for(_attack_combo_index)
	var t := _state_time

	if t < attack_startup_time:
		_attack_phase = PHASE_STARTUP
	elif t < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_attack_hitbox(_ground_attack_name(_attack_combo_index))
		velocity.x = float(_facing) * attack_forward_step_speed
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if Input.is_action_just_pressed(&"attack"):
			_attack_buffered = true
		if Input.is_action_just_pressed(&"dash") and _dash_cooldown_left <= 0.0:
			_start_dash()
			return
		if _try_launch_jump():
			return

	if t >= window:
		if _attack_buffered and _attack_combo_index < 2:
			_attack_combo_index += 1
			_attack_buffered = false
			_state_time = 0.0
			_attack_phase = PHASE_STARTUP
		else:
			_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


func _attack_window_for(index: int) -> float:
	match index:
		0:
			return attack_window_hit1
		1:
			return attack_window_hit2
		_:
			return attack_window_hit3


func _ground_attack_name(index: int) -> StringName:
	match index:
		0:
			return &"attack_ground_1"
		1:
			return &"attack_ground_2"
		_:
			return &"attack_ground_3"


## -- Combat: crouch attack -----------------------------------------------------

func _start_crouch_attack() -> void:
	_enter_state(State.CROUCH_ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_crouch_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	velocity.y = 0.0

	if _state_time < attack_startup_time:
		pass
	elif _state_time < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_attack_hitbox(&"attack_crouch")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _state_time >= attack_window_hit3:
			if Input.is_action_pressed(&"move_down") or not _has_standing_headroom():
				_enter_state(State.CROUCH)
			else:
				_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


## -- Combat: up attack (ground or air) -----------------------------------------

func _start_up_attack() -> void:
	_enter_state(State.UP_ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_up_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
		velocity.y = 0.0
	else:
		var axis := _horizontal_input()
		velocity.x = move_toward(velocity.x, axis * run_max_speed, air_acceleration * delta)
		_apply_gravity(delta)

	if _state_time < attack_startup_time:
		pass
	elif _state_time < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_attack_hitbox(&"attack_up")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _state_time >= attack_window_hit3:
			_end_generic_attack()


## -- Combat: air attack ---------------------------------------------------------

func _start_air_attack() -> void:
	_enter_state(State.AIR_ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_air_attack(delta: float) -> void:
	var axis := _horizontal_input()
	velocity.x = move_toward(velocity.x, axis * run_max_speed, air_acceleration * delta)
	_apply_gravity(delta)

	if is_on_floor():
		_deactivate_attack_hitbox()
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	if _state_time < attack_startup_time:
		_attack_phase = PHASE_STARTUP
	elif _state_time < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_attack_hitbox(&"attack_air")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()

	if _state_time >= air_attack_recovery:
		_state = State.JUMP if velocity.y < 0.0 else State.FALL


## -- Combat: down plunge ---------------------------------------------------------

func _start_plunge() -> void:
	_enter_state(State.PLUNGE)
	_attack_phase = PHASE_STARTUP


func _update_plunge(_delta: float) -> void:
	if is_on_floor():
		_deactivate_attack_hitbox()
		_enter_state(State.PLUNGE_LAND)
		return

	velocity.x = 0.0
	if _state_time < plunge_hang_time:
		velocity.y = 0.0
		return

	if _attack_phase != PHASE_ACTIVE:
		_attack_phase = PHASE_ACTIVE
		_activate_attack_hitbox(&"attack_plunge")
	velocity.y = plunge_fall_speed


func _update_plunge_land(_delta: float) -> void:
	velocity = Vector2.ZERO

	if _state_time < plunge_land_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_attack_hitbox(&"attack_plunge_land")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _state_time >= plunge_land_active_time + plunge_land_recovery_time:
			_enter_state(State.IDLE)


## -- Combat: hitbox helpers -------------------------------------------------------

func _activate_attack_hitbox(attack_name: StringName) -> void:
	var config := _hitbox_config_for(attack_name)
	var offset: Vector2 = config.offset
	_attack_hitbox.configure(config.size, Vector2(offset.x * float(_facing), offset.y))
	_attack_hitbox.activate(attack_name)


func _deactivate_attack_hitbox() -> void:
	_attack_hitbox.deactivate()


func _hitbox_config_for(attack_name: StringName) -> Dictionary:
	match attack_name:
		&"attack_ground_1", &"attack_ground_2":
			return {size = hitbox_ground_size, offset = hitbox_ground_offset}
		&"attack_ground_3":
			return {size = hitbox_finisher_size, offset = hitbox_finisher_offset}
		&"attack_crouch":
			return {size = hitbox_crouch_size, offset = hitbox_crouch_offset}
		&"attack_up":
			return {size = hitbox_up_size, offset = hitbox_up_offset}
		&"attack_air":
			return {size = hitbox_air_size, offset = hitbox_air_offset}
		&"attack_plunge":
			return {size = hitbox_plunge_size, offset = hitbox_plunge_offset}
		&"attack_plunge_land":
			return {size = hitbox_plunge_land_size, offset = hitbox_plunge_land_offset}
		_:
			return {size = hitbox_ground_size, offset = hitbox_ground_offset}


## -- Airborne: jump / fall ----------------------------------------------------

func _update_airborne(delta: float) -> void:
	var axis := _horizontal_input()
	var target_speed := axis * run_max_speed
	var accel := air_acceleration if not is_zero_approx(axis) else air_deceleration
	velocity.x = move_toward(velocity.x, target_speed, accel * delta)

	if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= jump_release_multiplier

	_apply_gravity(delta)

	if not is_on_floor():
		if velocity.y >= 0.0 and _try_start_ledge_hang():
			return
		if _try_start_wall_cling():
			return
		if _try_launch_jump():
			return

	_state = State.JUMP if velocity.y < 0.0 else State.FALL


func _apply_gravity(delta: float) -> void:
	var gravity := _fall_gravity if velocity.y > 0.0 else _rise_gravity
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _try_launch_jump() -> bool:
	if _jump_buffer_left <= 0.0 or not (is_on_floor() or _coyote_left > 0.0):
		return false
	velocity.y = _jump_velocity
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_sfx_jump.play()
	_enter_state(State.JUMP)
	return true


## -- Dash / slide -------------------------------------------------------------

func _start_dash() -> void:
	_dash_direction = _facing
	_enter_state(State.DASH)
	velocity.x = float(_dash_direction) * dash_speed
	velocity.y = 0.0


func _update_dash(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return

	var t := clampf(_state_time / dash_duration, 0.0, 1.0)
	var target_speed := dash_speed
	if t >= dash_full_speed_ratio:
		var ease_t := (t - dash_full_speed_ratio) / maxf(1.0 - dash_full_speed_ratio, 0.0001)
		target_speed = lerpf(dash_speed, run_max_speed, ease_t)
	velocity.x = float(_dash_direction) * target_speed
	velocity.y = 0.0

	if Input.is_action_just_pressed(&"jump") and _try_launch_jump():
		return

	if _state_time >= dash_duration:
		if _has_standing_headroom():
			_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		else:
			_enter_state(State.CROUCH)


## -- Wall cling / climb --------------------------------------------------------

func _try_start_wall_cling() -> bool:
	if _wall_recling_lock > 0.0:
		return false
	if velocity.y < -wall_cling_apex_threshold:
		return false
	if not (_wall_check_head.is_colliding() and _wall_check_chest.is_colliding()):
		return false
	_wall_direction = _facing
	_enter_state(State.WALL_CLING)
	return true


func _update_wall_cling(_delta: float) -> void:
	if is_on_floor():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	velocity = Vector2.ZERO
	_facing = _wall_direction
	_sprite.flip_h = _facing < 0

	if Input.is_action_pressed(&"move_down"):
		_wall_recling_lock = wall_recling_lockout
		_enter_state(State.FALL)
		return

	if Input.is_action_just_pressed(&"jump"):
		var axis := Input.get_axis(&"move_left", &"move_right")
		var jumping_away := not is_zero_approx(axis) and signf(axis) != float(_wall_direction)
		if jumping_away:
			velocity.x = -float(_wall_direction) * wall_jump_horizontal_speed
			velocity.y = -wall_jump_vertical_speed
			_facing = -_wall_direction
			_wall_jump_lock_left = wall_jump_lock_time
			_wall_recling_lock = wall_recling_lockout
		else:
			# Tiny outward push that air control pulls back in, so repeated
			# jumps climb higher along the same wall. No re-cling lockout
			# here: climbing depends on re-triggering the cling quickly.
			velocity.x = -float(_wall_direction) * wall_climb_hop_outward_speed
			velocity.y = -wall_climb_hop_speed
		_sfx_jump.play()
		_enter_state(State.JUMP)
		return

	if not (_wall_check_head.is_colliding() and _wall_check_chest.is_colliding()):
		_enter_state(State.FALL)


## -- Ledge grab -----------------------------------------------------------------

func _try_start_ledge_hang() -> bool:
	if _wall_recling_lock > 0.0:
		return false
	if velocity.y < 0.0:
		return false
	if not _wall_check_chest.is_colliding() or _ledge_check_above.is_colliding():
		return false
	_snap_to_ledge()
	_enter_state(State.LEDGE_HANG)
	return true


func _snap_to_ledge() -> void:
	if _wall_check_chest.is_colliding():
		var hit_x: float = _wall_check_chest.get_collision_point().x
		var half_width := (_collision_shape.shape as RectangleShape2D).size.x * 0.5
		global_position.x = hit_x - float(_facing) * (half_width + 2.0)
	velocity = Vector2.ZERO


func _update_ledge_hang(_delta: float) -> void:
	velocity = Vector2.ZERO

	if Input.is_action_just_pressed(&"move_up") or Input.is_action_just_pressed(&"jump"):
		_ledge_snap_from = global_position
		_ledge_snap_to = global_position + Vector2(float(_facing) * ledge_climb_forward_offset, -_standing_shape_height)
		_enter_state(State.LEDGE_CLIMB)
		return

	if Input.is_action_pressed(&"move_down"):
		_wall_recling_lock = wall_recling_lockout
		_enter_state(State.FALL)


func _update_ledge_climb(delta: float) -> void:
	_ledge_climb_time += delta
	var t := clampf(_ledge_climb_time / ledge_climb_duration, 0.0, 1.0)
	global_position = _ledge_snap_from.lerp(_ledge_snap_to, ease(t, 0.3))
	velocity = Vector2.ZERO
	if t >= 1.0:
		_enter_state(State.RUN if not is_zero_approx(_horizontal_input()) else State.IDLE)


## -- State transitions -------------------------------------------------------

func _enter_state(new_state: State) -> void:
	var previous := _state
	_state = new_state
	_state_time = 0.0

	if previous == State.DASH and new_state != State.DASH:
		_dash_cooldown_left = dash_cooldown

	var was_low := previous == State.CROUCH or previous == State.DASH or previous == State.CROUCH_ATTACK
	var is_low := new_state == State.CROUCH or new_state == State.DASH or new_state == State.CROUCH_ATTACK
	if is_low and not was_low:
		_set_collider_height(_standing_shape_height * crouch_collider_scale)
	elif was_low and not is_low:
		_set_collider_height(_standing_shape_height)

	if new_state == State.LEDGE_CLIMB:
		_ledge_climb_time = 0.0


func _set_collider_height(height: float) -> void:
	var shape := _collision_shape.shape as RectangleShape2D
	shape.size.y = height
	_collision_shape.position.y = -height * 0.5


## -- Drop-through / one-way platforms -----------------------------------------

func _begin_drop_through() -> void:
	if not is_on_floor() or _drop_left > 0.0 or not _standing_on_one_way():
		return
	set_collision_mask_value(2, false)
	_drop_left = drop_through_time
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


## -- Checkpoints / respawn -----------------------------------------------------

func set_checkpoint(checkpoint: Vector2) -> void:
	_spawn_position = checkpoint


func respawn() -> void:
	set_collision_mask_value(2, true)
	_drop_left = 0.0
	velocity = Vector2.ZERO
	global_position = _spawn_position
	_set_collider_height(_standing_shape_height)
	_deactivate_attack_hitbox()
	_enter_state(State.IDLE)
	respawned.emit()


## -- Post-move / feedback -------------------------------------------------------

func _after_move(fall_speed_before_move: float) -> void:
	if not _was_on_floor and is_on_floor() and fall_speed_before_move > landing_impact_speed:
		_landing_left = landing_squash_time
		_sfx_land.play()
	if is_on_floor() and (_state == State.JUMP or _state == State.FALL):
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
	_was_on_floor = is_on_floor()


func _update_footsteps(delta: float) -> void:
	if _state != State.RUN or not is_on_floor() or absf(velocity.x) < 70.0:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left <= 0.0:
		_sfx_foot.play()
		_footstep_left = clampf(0.30 - absf(velocity.x) / 2600.0, 0.12, 0.26)


func _update_animation() -> void:
	match _state:
		State.CROUCH:
			_play_animation(&"idle")
			_sprite.scale = Vector2(0.44, 0.28)
		State.DASH:
			_play_animation(&"walk")
			_sprite.scale = Vector2(0.46, 0.28)
			_sprite.speed_scale = 1.6
		State.JUMP:
			_play_animation(&"jump")
			_sprite.scale = Vector2(0.4, 0.4)
		State.FALL:
			_play_animation(&"fall")
			_sprite.scale = Vector2(0.4, 0.4)
		State.WALL_CLING, State.LEDGE_HANG, State.LEDGE_CLIMB:
			_play_animation(&"fall")
			_sprite.scale = Vector2(0.4, 0.4)
		State.ATTACK, State.CROUCH_ATTACK:
			_play_animation(&"land")
			_sprite.scale = Vector2(0.46, 0.36) if _attack_phase == PHASE_ACTIVE else Vector2(0.4, 0.4)
		State.UP_ATTACK:
			_play_animation(&"jump")
			_sprite.scale = Vector2(0.34, 0.46) if _attack_phase == PHASE_ACTIVE else Vector2(0.4, 0.4)
		State.AIR_ATTACK:
			_play_animation(&"fall")
			_sprite.scale = Vector2(0.46, 0.36) if _attack_phase == PHASE_ACTIVE else Vector2(0.4, 0.4)
		State.PLUNGE:
			_play_animation(&"fall")
			_sprite.scale = Vector2(0.34, 0.46)
		State.PLUNGE_LAND:
			_play_animation(&"land")
			_sprite.scale = Vector2(0.5, 0.3)
		_:
			if _landing_left > 0.0:
				_play_animation(&"land")
				_sprite.scale = Vector2(0.44, 0.34)
			elif absf(velocity.x) > 35.0:
				_play_animation(&"walk")
				_sprite.scale = Vector2(0.4, 0.4)
				_sprite.speed_scale = clampf(absf(velocity.x) / 220.0, 0.7, 1.8)
			else:
				_play_animation(&"idle")
				_sprite.scale = Vector2(0.4, 0.4)
				_sprite.speed_scale = 1.0


func _play_animation(animation_name: StringName) -> void:
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)

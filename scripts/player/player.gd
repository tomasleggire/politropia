class_name Player
extends CharacterBody2D

## Blasphemous-style finite state machine: weighty ground run, a precise
## jump arc, crouch, a dash/slide usable on the ground or in the air (one
## air dash per airborne period), wall cling + climb kick,
## a 3-hit ground combo, up/air/crouch attacks.

signal respawned
## Emitted after a hazard return has moved her onto the last safe ground, while
## the screen is still dark, so a level can re-frame its camera.
signal safe_ground_returned
## Emitted when a gated movement ability is granted (e.g. &"double_jump").
signal ability_unlocked(ability: StringName)
signal health_changed(current: int, maximum: int)
## Soul meter level; fires on every gain, spend and reset.
signal soul_changed(current: int, maximum: int)
## Emitted when a hit lands: how much it took and the health left.
signal damaged(amount: int, current: int)
## Emitted once when health reaches zero; the respawn follows the death beat.
signal died
signal meditation_started
signal meditation_finished
## Emitted while meditating when the player gives gameplay input (a fresh
## press or a touch request); the resting desk decides whether to release.
signal rest_exit_requested
signal rest_animation_finished(animation_name: StringName)
signal rest_animation_frame_changed(animation_name: StringName, frame: int)

enum ReturnPhase { NONE, OUT, IN }

enum State {
	IDLE, RUN, CROUCH, JUMP, FALL, DASH,
	WALL_CLING,
	ATTACK, AIR_ATTACK, UP_ATTACK, CROUCH_ATTACK,
	HURT, DEAD, FOCUS,
	TURN, SKID,
}

## Opaque body height (px) of the standing frames inside their 512 px cell.
const LUZ_BODY_PIXELS := 331.5
const PHASE_STARTUP := 0
const PHASE_ACTIVE := 1
const PHASE_RECOVERY := 2
## Gameplay actions that release a resting Luz when freshly pressed.
const REST_EXIT_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"jump", &"dash", &"attack", &"interact",
]

@export_group("Health")
@export var max_health := 3

@export_group("Soul")
@export var max_soul := 99
## Soul gained by each hit that damages an enemy (Hollow Knight nail: 11).
@export var soul_per_hit := 11
## Soul spent by one focus heal (3 hits per pip, as in Hollow Knight).
@export var focus_cost := 33

@export_group("Focus")
## Seconds of standing still to heal one pip.
@export var focus_time := 0.9
@export var focus_glow_radius := 20.0

@export_group("Damage")
## Knockback launched away from the damage source: x is the horizontal speed
## (signed by the side the source is on), y the upward kick.
@export var knockback_speed := Vector2(320.0, -260.0)
## Movement input is ignored this long after a hit; gravity still applies.
@export var hurt_control_lock := 0.22
## Invulnerable window after a hit, shown as a blink of the sprite's alpha.
@export var invulnerability_time := 1.0
@export var flicker_interval := 0.08
@export var flicker_alpha := 0.35
## Local freeze of the player (and the camera that follows her) on impact.
## Never touches Engine.time_scale, so it cannot fight the desk's pause_world
## or the tests' time scale. 0 disables it.
@export var hit_stop_time := 0.06
## Fade-out of the placeholder death beat before the respawn.
@export var death_fade_time := 0.6
## A non-lethal hit nudges the room camera by this many pixels for this long.
@export var hit_shake_strength := 3.0
@export var hit_shake_time := 0.2
## Hazard hit: dark fade out, move to the last safe ground, fade back in.
@export var hazard_fade_out := 0.15
@export var hazard_fade_in := 0.2
## Safe ground: a floor spot she stood on this long, away from the surface's
## edges and from every hazard by the margin.
@export var safe_ground_time := 0.1
@export var safe_ground_margin := 24.0

@export_group("Body")
## On-screen height of Luz in world pixels (team standard: 32x48). The sprite
## scale derives from it; the collider lives in player.tscn (29 x 46).
@export var body_height := 48.0

@export_group("Dust")
## Scene spawned at her feet in world space (see GroundDust); swap it to
## change the dust look.
@export var ground_dust_scene: PackedScene = preload("res://scenes/vfx/ground_dust.tscn")
## Seconds between footstep puffs while running (one per run cycle).
@export var footstep_dust_interval := 0.29

@export_group("Run")
## Blasphemous reference: ~150 px/s with near-instant acceleration.
@export var run_max_speed := 150.0
@export var run_acceleration := 3000.0
@export var run_deceleration := 5000.0

@export_group("Turn")
## Two-frame snap pivot with no movement when starting to run opposite to the facing
## or when reversing while running.
@export var turn_time := 0.1

@export_group("Skid")
## Releasing the run input at (near) full speed snaps to a low skid pose,
## brakes linearly to zero, holds the pose, then returns to idle. Any new
## input cancels the hold immediately.
@export var skid_brake_time := 0.14
## Seconds the pose is held once the brake has finished (~10 frames at 60 fps).
@export var skid_hold_time := 0.17
## Fraction of run_max_speed needed to skid (shorter taps just stop).
@export_range(0.0, 1.0) var skid_min_speed_ratio := 0.9
## Seconds spent at that speed before a release skids (filters taps).
@export var skid_min_run_time := 0.12

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

@export_group("Double Jump")
## Gated ability, off until unlock_double_jump() (the Greece boss reward).
@export var can_double_jump := false
## Rise of an air jump, launched with the same rise gravity as the main jump.
@export var double_jump_height := 130.0
## Extra jumps available per airborne period.
@export var air_jumps := 1

@export_group("Air Control")
## Horizontal air speed target; kept separate from run_max_speed so jumps keep
## their original reach (the jump retune lives in a later task).
@export var air_max_speed := 250.0
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
## Air dash: horizontal only, gravity suspended for its duration, standing
## collider kept (unlike the ground dash's low slide collider). One per
## airborne period — resets on landing or wall cling.
@export var air_dash_duration := 0.30

@export_group("Wall")
@export var wall_ray_length := 16.5
@export var wall_cling_apex_threshold := 60.0
## A collider only counts as a clingable wall when its shape is at least this
## tall and is not wider than it is tall — filters out horizontal platforms.
@export var min_wall_height := 80.0
@export var wall_slide_speed := 70.0
## How fast the slide speed above is approached, so clinging eases in instead
## of snapping to a fixed downward speed.
@export var wall_slide_acceleration := 600.0
@export var wall_slide_max_speed := 140.0
@export var wall_kick_outward_speed := 220.0
## Raised from 560 -> 630 for a modestly faster climb: ~+26.6% peak height
## per kick (v^2/(2*rise_gravity), rise_gravity derived from Jump/jump_height
## and jump_time_to_apex — unchanged), within the requested 25-35% range.
@export var wall_kick_vertical_speed := 630.0
## Horizontal input is ignored for this long right after a kick, so the
## outward push reads as a real impulse instead of a vertical hop.
@export var wall_kick_input_lock_time := 0.12
## Air-control target speed used to drift back toward the wall after a kick,
## once the input lock above ends, unless the player holds away from it.
@export var wall_kick_drift_speed := 160.0
@export var wall_jump_horizontal_speed := 300.0
@export var wall_jump_vertical_speed := 560.0
@export var wall_jump_lock_time := 0.15
@export var wall_recling_lockout := 0.2

@export_group("Attack")
## Startup (windup) shared by hits 1/2 of the ground combo and by
## crouch/up/air attacks. The finisher (hit 3) uses its own, longer
## attack_finisher_startup_time instead -- see _attack_startup_for.
@export var attack_startup_time := 0.08
@export var attack_active_time := 0.12
## Combo cadence, measured from a 60fps Blasphemous ground-combo reference:
## hit1->hit2 contact-to-contact ~0.35s, hit2->hit3 ~0.42s. This is also each
## hit's own minimum interval -- the next combo hit cannot start (even with a
## buffered input) before this much time has passed since THIS hit started,
## so the combo cannot be spammed faster than a readable cut-per-cut
## cadence. Recovery frames (never startup/active frames) are what
## stretches to fill the extra time -- see LuzAnimationCatalog._frame_seconds.
@export var attack_window_hit1 := 0.35
@export var attack_window_hit2 := 0.42
## Finisher (hit 3) total window: also the minimum interval before the combo
## can loop back to hit 1 -- a press during the finisher restarts the combo
## here only if it is still within attack_buffer_time of this mark (see
## _queue_attack's State.ATTACK branch and _attack_restart_buffered_left);
## an earlier press is dropped.
@export var attack_window_hit3 := 0.42
## Finisher-only windup before its active (contact) frame -- longer than
## attack_startup_time, matching the reference's more telegraphed last hit.
@export var attack_finisher_startup_time := 0.15
## Crouch/up attack total window -- kept independent of the ground
## finisher's attack_window_hit3 so retuning the ground combo doesn't also
## change these.
@export var crouch_up_attack_window := 0.60
@export var attack_forward_step_speed := 60.0
## Air attack total cycle (startup + active + recovery); re-attack allowed once recovery starts.
@export var air_attack_recovery := 0.40
## How long ANY buffered attack press stays queued before being dropped:
## a press that can't start an attack right away (dash, wall cling,
## crouch/up attack), a press for the next combo hit
## (hit1->2, hit2->3), and a press during the finisher that would restart
## the combo -- all three share this one short window (~0.15s, matching the
## Blasphemous reference) so a press is consumed at most once and a press
## older than this window is dropped instead of firing an unexpected attack
## later ("one attack too many" from a burst of taps -- see
## _attack_buffered_left/_attack_restart_buffered_left below).
@export var attack_buffer_time := 0.15

@export_group("Attack Recoil")
## Damage one slash deals to whatever it strikes.
@export var attack_damage := 1
## A horizontal slash that lands pushes Luz away from the target at this speed
## for this long. Up slashes never recoil her.
@export var attack_recoil_speed := 120.0
@export var attack_recoil_time := 0.08

@export_group("Attack Hitboxes")
## T4d item 3 (iPhone playtest: "in the 3rd hit Luz gets bigger and so does
## the attack hitbox; that must not happen. All hits must have the same
## hitbox, vertical or horizontal"). ONE shared hitbox size/reach for every
## horizontal attack (ground combo hits 1-3, crouch, air): same length
## (reach from the player's own local origin) and same thickness -- only
## the vertical placement (offset.y) differs, taken from each attack's own
## measured ruler height at contact (the ground combo's three hits share
## ONE "chest" placement, averaged across all three; crouch is low; air is
## mid-air torso height). hitbox_up_size/offset is the same size rotated 90
## degrees, reaching the same distance upward. The upward box intentionally
## retains its previously accepted size and offset; it is not part of the
## shared horizontal-hitbox derivation.
@export var hitbox_attack_size := Vector2(49.9, 19.9)
## offset.x, shared by every horizontal attack (ground combo, crouch, air).
@export var hitbox_attack_reach_x := 40.7
@export var hitbox_ground_offset_y := -21.26  ## combo (hits 1-3): shared contact height
@export var hitbox_crouch_offset_y := -14.09  ## crouch: low horizontal cut height
@export var hitbox_air_offset_y := -25.37     ## air: mid-air torso height
@export var hitbox_up_size := Vector2(21.5, 56.3)
@export var hitbox_up_offset := Vector2(0, -66.2)

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _wall_check_head: RayCast2D = $WallCheckHead
@onready var _wall_check_chest: RayCast2D = $WallCheckChest
@onready var _wall_check_feet: RayCast2D = $WallCheckFeet
@onready var _headroom_check: RayCast2D = $HeadroomCheck
@onready var _attack_hitbox: AttackHitbox = $AttackHitbox
@onready var _slash_vfx: PlayerSlashVfx = $SlashVfx
@onready var _animation_sprite_frames: SpriteFrames = LuzAnimationCatalog.build_sprite_frames({
	"ground_dash": dash_duration,
	"air_dash": air_dash_duration,
	"wall_jump": wall_kick_input_lock_time,
	"land": landing_squash_time,
	"turn": turn_time,
	"skid": skid_brake_time + skid_hold_time,
	"attack_1": attack_window_hit1,
	"attack_2": attack_window_hit2,
	"attack_3": attack_window_hit3,
	"crouch_attack": crouch_up_attack_window,
	# Ends together with the slash VFX (attack_startup_time + its fixed
	# TOTAL_DURATION), not with the whole up-attack state's recovery
	# (crouch_up_attack_window) -- otherwise the body clip freezes on a
	# still-extended pose for the rest of the state after the slash is
	# already gone (see PlayerSlashVfx.TOTAL_DURATION).
	"up_attack": attack_startup_time + PlayerSlashVfx.TOTAL_DURATION,
	"air_attack": air_attack_recovery,
}, {
	"attack_1": attack_startup_time,
	"attack_2": attack_startup_time,
	"attack_3": attack_finisher_startup_time,
	"crouch_attack": attack_startup_time,
	"up_attack": attack_startup_time,
	"air_attack": attack_startup_time,
})

var _state := State.IDLE
var _state_time := 0.0
var _facing := 1
var _spawn_position := Vector2.ZERO
var _health := 0
var _input_locked := false
var _meditating := false
var _dead := false
var _hurt_left := 0.0
var _invuln_left := 0.0
var _hit_stop_left := 0.0
var _base_alpha := 1.0
var _return_phase := ReturnPhase.NONE
var _return_left := 0.0
var _fade: ScreenFade
var _transition_locked := false
var _auto_walk := 0
var _keep_momentum := false
var _last_safe_ground := Vector2.ZERO
var _has_safe_ground := false
var _ground_time := 0.0
var _ground_collider: Object
var _rest_animation := &""
var _default_process_mode := Node.PROCESS_MODE_INHERIT

var _rise_gravity := 0.0
var _fall_gravity := 0.0
var _jump_velocity := 0.0
var _double_jump_velocity := 0.0
var _standing_shape_height := 46.0

var _coyote_left := 0.0
var _jump_buffer_left := 0.0
## True only on the physics frame a jump press arrives (keyboard edge or touch
## request). Air jumps need a fresh press; stale buffered ones stay ground jumps.
var _jump_pressed_now := false
var _jump_press_pending := false
var _air_jumps_left := 0
var _landing_left := 0.0
var _footstep_left := 0.0
var _dust_left := 0.0
var _run_time := 0.0
var _skid_deceleration := 0.0
var _dust_warned := false
var _was_on_floor := false
var _drop_left := 0.0

var _dash_direction := 1
var _dash_cooldown_left := 0.0
var _dash_is_air := false
var _air_dash_used := false

var _wall_direction := 0
var _wall_recling_lock := 0.0
var _wall_jump_lock_left := 0.0
var _wall_kick_lock_left := 0.0
var _wall_kick_pending := false
var _wall_kick_wall_direction := 0

var _attack_phase := PHASE_STARTUP
var _attack_combo_index := 0
var _attack_facing := 1
## Time left (seconds) for a pending hit1->2 / hit2->3 combo continuation;
## <= 0.0 means no press is queued. Set to attack_buffer_time on a
## qualifying press, ticked down every frame (_update_shared_timers) and
## consumed (reset to 0.0) the instant the current hit's window ends -- a
## press older than attack_buffer_time has already ticked down to 0.0 and is
## dropped, matching every other buffered action instead of firing
## unexpectedly later.
var _attack_buffered_left := 0.0
## Same mechanism as _attack_buffered_left, for a press during the finisher
## (combo index 2) that should restart the combo (loop back to hit 1) --
## see _queue_attack's State.ATTACK branch and _update_attack's window-end
## check.
var _attack_restart_buffered_left := 0.0
## Same mechanism, for a press during the air attack's active phase that
## should restart it once its recovery phase begins.
var _air_attack_buffered_left := 0.0
var _attack_buffer_left := 0.0
var _attack_buffer_direction := 0
var _recoil_left := 0.0
var _recoil_velocity := 0.0

var _soul := 0
var _focus_left := 0.0
var _focus_requested := false
var _focus_glow: Polygon2D


func _ready() -> void:
	add_to_group(&"player")
	_sprite.sprite_frames = _animation_sprite_frames
	_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_sprite.frame_changed.connect(_on_sprite_frame_changed)
	# Every Luz frame is a uniform 512x512 grid cell (see LuzAnimationCatalog
	# and tools/process_luz_sheet.py) already repacked so its opaque bottom
	# lands on canvas row 413; this offset puts that row at local y=0, so the
	# feet-anchored origin lines up with every frame regardless of pose.
	_sprite.offset = Vector2(0.0, -157.0)
	# The idle standing frames' opaque body is ~331.5 px inside the 512 px
	# cell, so this scale makes Luz exactly body_height px tall.
	_sprite.scale = Vector2.ONE * (body_height / LUZ_BODY_PIXELS)
	_spawn_position = global_position
	_health = max_health
	_base_alpha = _sprite.modulate.a
	_default_process_mode = process_mode
	_recompute_jump_physics()
	_air_jumps_left = air_jumps
	_attack_hitbox.attack_hit.connect(_on_attack_hit)

	var shape := _collision_shape.shape as RectangleShape2D
	_standing_shape_height = shape.size.y
	_collision_shape.shape = shape.duplicate()

	_wall_check_head.collision_mask = 1
	_wall_check_chest.collision_mask = 1
	_wall_check_feet.collision_mask = 1
	_headroom_check.collision_mask = 1

	_enter_state(State.IDLE)


func _recompute_jump_physics() -> void:
	_rise_gravity = (2.0 * jump_height) / (jump_time_to_apex * jump_time_to_apex)
	_jump_velocity = -_rise_gravity * jump_time_to_apex
	_double_jump_velocity = -sqrt(2.0 * _rise_gravity * double_jump_height)
	_fall_gravity = _rise_gravity * fall_gravity_multiplier


func _physics_process(delta: float) -> void:
	if _hit_stop_left > 0.0:
		_hit_stop_left = maxf(_hit_stop_left - delta, 0.0)
		return
	_update_damage_timers(delta)
	if _dead:
		_update_dead(delta)
		return
	if _return_phase != ReturnPhase.NONE:
		_update_return(delta)
		return
	if is_input_locked():
		_update_locked(delta)
		return

	_state_time += delta
	_update_shared_timers(delta)
	_update_facing()
	_update_facing_rays()

	_poll_focus_cancel()

	if Input.is_action_just_pressed(&"attack"):
		_queue_attack(_held_vertical_direction())
	if _attack_buffer_left > 0.0 and _can_start_attack():
		var buffered_direction := _attack_buffer_direction
		_attack_buffer_left = 0.0
		_queue_attack(buffered_direction)

	if Input.is_action_just_pressed(&"dash"):
		_try_start_dash()

	_try_start_focus()

	var fall_speed_before_move := velocity.y

	match _state:
		State.IDLE, State.RUN:
			_update_ground_move(delta)
		State.TURN:
			_update_turn(delta)
		State.SKID:
			_update_skid(delta)
		State.CROUCH:
			_update_crouch(delta)
		State.JUMP, State.FALL:
			_update_airborne(delta)
		State.DASH:
			_update_dash(delta)
		State.WALL_CLING:
			_update_wall_cling(delta)
		State.ATTACK:
			_update_attack(delta)
		State.CROUCH_ATTACK:
			_update_crouch_attack(delta)
		State.UP_ATTACK:
			_update_up_attack(delta)
		State.AIR_ATTACK:
			_update_air_attack(delta)
		State.HURT:
			_update_hurt(delta)
		State.FOCUS:
			_update_focus(delta)

	_apply_attack_recoil(delta)
	move_and_slide()
	_after_move(fall_speed_before_move)
	_track_safe_ground(delta)
	_update_footsteps(delta)
	_update_animation()


func _update_shared_timers(delta: float) -> void:
	_landing_left = maxf(_landing_left - delta, 0.0)
	_wall_recling_lock = maxf(_wall_recling_lock - delta, 0.0)
	_wall_jump_lock_left = maxf(_wall_jump_lock_left - delta, 0.0)
	_wall_kick_lock_left = maxf(_wall_kick_lock_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_attack_buffer_left = maxf(_attack_buffer_left - delta, 0.0)
	_attack_buffered_left = maxf(_attack_buffered_left - delta, 0.0)
	_attack_restart_buffered_left = maxf(_attack_restart_buffered_left - delta, 0.0)
	_air_attack_buffered_left = maxf(_air_attack_buffered_left - delta, 0.0)

	if _drop_left > 0.0:
		_drop_left -= delta
		if _drop_left <= 0.0:
			set_collision_mask_value(2, true)

	_jump_pressed_now = _jump_press_pending or Input.is_action_just_pressed(&"jump")
	_jump_press_pending = false
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	var grounded_state := _state != State.WALL_CLING
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
	if _is_directional_attack_state():
		_sprite.flip_h = _attack_facing < 0
		return
	if _state in [State.TURN, State.DASH, State.WALL_CLING, State.HURT]:
		return
	var axis := _horizontal_input()
	if _wants_turn(axis):
		_begin_turn(1 if axis > 0.0 else -1)
		return
	if not is_zero_approx(axis):
		_facing = 1 if axis > 0.0 else -1
	_sprite.flip_h = _facing < 0


func _is_directional_attack_state() -> bool:
	return _state in [State.ATTACK, State.CROUCH_ATTACK, State.UP_ATTACK, State.AIR_ATTACK]


func _capture_attack_facing() -> void:
	_attack_facing = _facing
	_sprite.flip_h = _attack_facing < 0


func _update_facing_rays() -> void:
	_wall_check_head.target_position.x = wall_ray_length * _facing
	_wall_check_chest.target_position.x = wall_ray_length * _facing
	_wall_check_feet.target_position.x = wall_ray_length * _facing
	_wall_check_head.force_raycast_update()
	_wall_check_chest.force_raycast_update()
	_wall_check_feet.force_raycast_update()


## -- Ground: idle / run -----------------------------------------------------

func _update_ground_move(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return

	var axis := _horizontal_input()
	_track_run_time(delta)
	if _try_start_skid(axis):
		return
	var target_speed := axis * run_max_speed
	var accel := run_acceleration if not is_zero_approx(axis) else run_deceleration
	velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	velocity.y = 0.0

	if Input.is_action_pressed(&"move_down"):
		_enter_state(State.CROUCH)
		return

	if _try_launch_jump():
		return

	_state = State.RUN if absf(velocity.x) > 5.0 else State.IDLE


## -- Turn / skid -------------------------------------------------------------

## True when running or standing on the floor and the input points opposite to
## the facing: the turn crouch plays before she faces and runs that way.
func _wants_turn(axis: float) -> bool:
	if _state != State.IDLE and _state != State.RUN:
		return false
	if is_zero_approx(axis) or not is_on_floor():
		return false
	if Input.is_action_pressed(&"move_down"):
		return false
	return (1 if axis > 0.0 else -1) != _facing


## Faces the new direction at once (so attacks and dashes cancelling the turn
## use it) and stops dead for turn_time while the crouch pose plays.
func _begin_turn(direction: int) -> void:
	_facing = direction
	_sprite.flip_h = _facing < 0
	_enter_state(State.TURN)
	velocity.x = 0.0
	_spawn_dust(GroundDust.Kind.TURN)


func _update_turn(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return
	velocity = Vector2.ZERO
	if Input.is_action_pressed(&"move_down"):
		_enter_state(State.CROUCH)
		return
	if _try_launch_jump():
		return
	if _state_time >= turn_time:
		_enter_state(State.IDLE)


## Accumulates the time spent running at (near) full speed on the floor.
func _track_run_time(delta: float) -> void:
	var threshold := run_max_speed * skid_min_speed_ratio
	if _state == State.RUN and absf(velocity.x) >= threshold:
		_run_time += delta
	else:
		_run_time = 0.0


func _try_start_skid(axis: float) -> bool:
	if _state != State.RUN or not is_zero_approx(axis):
		return false
	if _run_time < skid_min_run_time or _jump_buffer_left > 0.0:
		return false
	if Input.is_action_pressed(&"move_down"):
		return false
	_skid_deceleration = absf(velocity.x) / maxf(skid_brake_time, 0.001)
	_enter_state(State.SKID)
	_spawn_dust(GroundDust.Kind.STOP)
	return true


func _update_skid(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return
	var cancelled := (
		not is_zero_approx(_horizontal_input())
		or Input.is_action_pressed(&"move_down")
	)
	if cancelled:
		_enter_state(State.IDLE)
		_update_ground_move(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, _skid_deceleration * delta)
	velocity.y = 0.0
	if _try_launch_jump():
		return
	if _state_time >= skid_brake_time + skid_hold_time:
		_enter_state(State.IDLE)


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
## Called immediately on touch-down by the touch UI (zero added latency).
func request_attack(direction: int) -> void:
	if is_input_locked():
		_request_rest_exit()
		return
	var resolved := direction
	if resolved == 0:
		resolved = _held_vertical_direction()
	_queue_attack(resolved)


## Touch UI: upgrades the attack that just started — while it is still in
## its startup phase, before any hitbox is active — to an up attack instead
## of firing a second attack. A downward swipe does nothing.
## Used when the finger swipes after touching down on the attack button (see
## touch_controls.gd's attack_upgrade_window).
func request_attack_upgrade(direction: int) -> void:
	if direction == 0 or is_input_locked():
		return
	var upgrading_from_neutral := (
		(_state == State.ATTACK and _attack_combo_index == 0 and _attack_phase == PHASE_STARTUP)
		or (_state == State.AIR_ATTACK and _attack_phase == PHASE_STARTUP)
	)
	if direction == -1 and upgrading_from_neutral:
		_start_up_attack()


## Touch UI entry point for the jump button, called directly instead of only
## relying on Input.action_press + is_action_just_pressed: a very quick tap
## can press and release an action within the same frame, which the engine's
## just-pressed edge can miss. This guarantees the jump buffer is never
## dropped by a fast tap. Input.action_press/release still runs alongside
## (see touch_controls.gd) so the held-release variable jump height keeps
## working.
func request_jump() -> void:
	if is_input_locked():
		_request_rest_exit()
		return
	_jump_buffer_left = jump_buffer_time
	_jump_press_pending = true


## Touch UI entry point for the dash button; same same-frame-miss guard as
## request_jump above, calling the same start path the keyboard/gamepad
## dash uses (ground or air, respects cooldown/state/one-air-dash).
func request_dash() -> void:
	if is_input_locked():
		_request_rest_exit()
		return
	_try_start_dash()


func _can_start_attack() -> bool:
	match _state:
		State.IDLE, State.RUN, State.CROUCH, State.JUMP, State.FALL:
			return true
		_:
			return false


func _queue_attack(direction: int) -> void:
	match _state:
		State.ATTACK:
			if _attack_combo_index < 2:
				_attack_buffered_left = attack_buffer_time
			else:
				# Playing the finisher: buffer a combo restart (loop back to
				# hit 1) the same short, timed way -- see
				# _attack_restart_buffered_left.
				_attack_restart_buffered_left = attack_buffer_time
			return
		State.AIR_ATTACK:
			if _attack_phase == PHASE_RECOVERY:
				_restart_air_attack()
			else:
				_air_attack_buffered_left = attack_buffer_time
			return
		State.CROUCH_ATTACK, State.UP_ATTACK, State.DASH, State.WALL_CLING, State.HURT:
			_attack_buffer_left = attack_buffer_time
			_attack_buffer_direction = direction
			return
		_:
			pass

	if not is_on_floor():
		if direction == -1:
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


## Invalidates a pending generic attack buffer (_attack_buffer_left/
## _attack_buffer_direction, used by dash/wall-cling/crouch/up
## states) whenever an attack actually starts through any path. Without
## this, an older press already superseded by a fresher one that started an
## attack directly could still sit in the buffer and fire a second,
## unexpected attack once the new attack ends and the state allows attacking
## again -- one extra action from what is really two separate presses
## resolving out of order.
func _clear_pending_attack_buffer() -> void:
	_attack_buffer_left = 0.0


## -- Combat: ground combo -----------------------------------------------------

func _start_ground_attack() -> void:
	_attack_combo_index = 0
	_attack_buffered_left = 0.0
	_attack_restart_buffered_left = 0.0
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
		velocity.y = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
		_apply_gravity(delta)

	var window := _attack_window_for(_attack_combo_index)
	var startup := _attack_startup_for(_attack_combo_index)
	var t := _state_time

	if t < startup:
		_attack_phase = PHASE_STARTUP
	elif t < startup + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_directional_attack(
				_ground_attack_name(_attack_combo_index), _attack_facing, _attack_combo_index, &"ground"
			)
		if not is_on_floor():
			velocity.x = float(_attack_facing) * attack_forward_step_speed
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _try_launch_jump():
			return

	if t >= window:
		if _attack_buffered_left > 0.0 and _attack_combo_index < 2:
			_attack_combo_index += 1
			_attack_buffered_left = 0.0
			_state_time = 0.0
			_attack_phase = PHASE_STARTUP
		elif _attack_restart_buffered_left > 0.0 and _attack_combo_index >= 2:
			_start_ground_attack()
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


## The finisher (hit 3) has its own, longer windup than hits 1/2 -- see
## attack_finisher_startup_time.
func _attack_startup_for(index: int) -> float:
	return attack_finisher_startup_time if index >= 2 else attack_startup_time


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
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.CROUCH_ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_crouch_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	velocity.y = 0.0

	if _state_time < attack_startup_time:
		pass
	elif _state_time < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_directional_attack(&"attack_crouch", _attack_facing, 0, &"crouch")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _state_time >= crouch_up_attack_window:
			if Input.is_action_pressed(&"move_down") or not _has_standing_headroom():
				_enter_state(State.CROUCH)
			else:
				_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


## -- Combat: up attack (ground or air) -----------------------------------------

func _start_up_attack() -> void:
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.UP_ATTACK)
	_attack_phase = PHASE_STARTUP


func _update_up_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
		velocity.y = 0.0
	else:
		var axis := _horizontal_input()
		velocity.x = move_toward(velocity.x, axis * air_max_speed, air_acceleration * delta)
		_apply_gravity(delta)

	if _state_time < attack_startup_time:
		pass
	elif _state_time < attack_startup_time + attack_active_time:
		if _attack_phase != PHASE_ACTIVE:
			_attack_phase = PHASE_ACTIVE
			_activate_directional_attack(&"attack_up", _attack_facing, 0, &"up")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _state_time >= crouch_up_attack_window:
			_end_generic_attack()


## -- Combat: air attack ---------------------------------------------------------

func _start_air_attack() -> void:
	_air_attack_buffered_left = 0.0
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.AIR_ATTACK)
	_attack_phase = PHASE_STARTUP


func _restart_air_attack() -> void:
	_state_time = 0.0
	_attack_phase = PHASE_STARTUP


func _update_air_attack(delta: float) -> void:
	var axis := _horizontal_input()
	velocity.x = move_toward(velocity.x, axis * air_max_speed, air_acceleration * delta)
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
			_activate_directional_attack(&"attack_air", _attack_facing, 0, &"air")
	else:
		if _attack_phase != PHASE_RECOVERY:
			_attack_phase = PHASE_RECOVERY
			_deactivate_attack_hitbox()
		if _air_attack_buffered_left > 0.0:
			_air_attack_buffered_left = 0.0
			_restart_air_attack()
			return

	if _state_time >= air_attack_recovery:
		_state = State.JUMP if velocity.y < 0.0 else State.FALL


## -- Combat: hits and recoil ---------------------------------------------------------

## Deferred: the hitbox reports from inside a physics query flush, where
## changing areas, bodies or this state is forbidden.
func _on_attack_hit(target: Node2D, attack_name: StringName) -> void:
	_resolve_attack_hit.call_deferred(target, attack_name)


## Any target with a `receive_hit(damage, source_position, attack_name)` method
## can be struck (see Enemy). A landed horizontal slash recoils Luz.
func _resolve_attack_hit(target: Node2D, attack_name: StringName) -> void:
	if _dead or not is_instance_valid(target):
		return
	var struck := false
	if target.has_method(&"receive_hit"):
		struck = target.call(&"receive_hit", attack_damage, global_position, attack_name)
	if struck:
		_start_attack_recoil(target.global_position)
	if struck and target.is_in_group(Enemy.GROUP_ENEMIES):
		add_soul(soul_per_hit)


## Pushes her away from `source` for a moment. Only the lateral attack states
## apply it, and only to horizontal speed, so the double jump and the dash are
## untouched.
func _start_attack_recoil(source: Vector2) -> void:
	if not _is_lateral_attack_state():
		return
	var side := signf(global_position.x - source.x)
	if is_zero_approx(side):
		side = -float(_attack_facing)
	_recoil_velocity = side * attack_recoil_speed
	_recoil_left = attack_recoil_time


func _apply_attack_recoil(delta: float) -> void:
	if _recoil_left <= 0.0:
		return
	_recoil_left = maxf(_recoil_left - delta, 0.0)
	if _is_lateral_attack_state():
		velocity.x = _recoil_velocity


func _is_lateral_attack_state() -> bool:
	return _state == State.ATTACK or _state == State.CROUCH_ATTACK or _state == State.AIR_ATTACK


## -- Combat: hitbox helpers -------------------------------------------------------

func _activate_attack_hitbox(attack_name: StringName, facing: int = 0) -> Dictionary:
	var config := _hitbox_config_for(attack_name)
	var offset: Vector2 = config.offset
	var attack_direction := _facing if facing == 0 else facing
	_attack_hitbox.configure(config.size, Vector2(offset.x * float(attack_direction), offset.y))
	_attack_hitbox.activate(attack_name)
	return config


func _activate_directional_attack(
	attack_name: StringName, facing: int, variant: int, slash_kind: StringName
) -> void:
	var config := _activate_attack_hitbox(attack_name, facing)
	_slash_vfx.play_slash(slash_kind, variant, facing, config.size, config.offset)


func _deactivate_attack_hitbox() -> void:
	_attack_hitbox.deactivate()


func _hitbox_config_for(attack_name: StringName) -> Dictionary:
	match attack_name:
		&"attack_ground_1", &"attack_ground_2", &"attack_ground_3":
			return {size = hitbox_attack_size, offset = Vector2(hitbox_attack_reach_x, hitbox_ground_offset_y)}
		&"attack_crouch":
			return {size = hitbox_attack_size, offset = Vector2(hitbox_attack_reach_x, hitbox_crouch_offset_y)}
		&"attack_air":
			return {size = hitbox_attack_size, offset = Vector2(hitbox_attack_reach_x, hitbox_air_offset_y)}
		&"attack_up":
			return {size = hitbox_up_size, offset = hitbox_up_offset}
		_:
			return {size = hitbox_attack_size, offset = Vector2(hitbox_attack_reach_x, hitbox_ground_offset_y)}


## -- Airborne: jump / fall ----------------------------------------------------

func _update_airborne(delta: float) -> void:
	if _wall_kick_lock_left <= 0.0:
		_apply_air_horizontal_control(delta)

	if Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		velocity.y *= jump_release_multiplier

	_apply_gravity(delta)

	if not is_on_floor():
		if _try_start_wall_cling():
			return
		if _try_launch_jump() or _try_air_jump():
			return

	_state = State.JUMP if velocity.y < 0.0 else State.FALL


## Normal air control, except right after a wall kick: with no horizontal
## input held, it drifts back toward the kicked wall instead of holding
## still, so a wall kick reads as a climb rather than a jump away.
func _apply_air_horizontal_control(delta: float) -> void:
	var input_axis := _horizontal_input()
	if not is_zero_approx(input_axis):
		velocity.x = move_toward(velocity.x, input_axis * air_max_speed, air_acceleration * delta)
		return
	if _wall_kick_pending:
		velocity.x = move_toward(velocity.x, float(_wall_kick_wall_direction) * wall_kick_drift_speed, air_acceleration * delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, air_deceleration * delta)


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


## Spends one air jump on a fresh press once the ground/coyote jump is no
## longer possible. A stale buffered press never gets here: it stays a ground
## jump for the landing. Replaces vy, so the variable-height release applies.
func _try_air_jump() -> bool:
	if not can_double_jump or _air_jumps_left <= 0 or not _jump_pressed_now:
		return false
	if is_on_floor() or _coyote_left > 0.0:
		return false
	_air_jumps_left -= 1
	velocity.y = _double_jump_velocity
	_jump_buffer_left = 0.0
	_sfx_jump.play()
	_enter_state(State.JUMP)
	_restart_jump_animation()
	return true


func _restart_jump_animation() -> void:
	_sprite.stop()
	_play_animation(&"jump")


func _restore_air_actions() -> void:
	_air_dash_used = false
	_air_jumps_left = air_jumps


func unlock_double_jump() -> void:
	can_double_jump = true
	_air_jumps_left = air_jumps
	ability_unlocked.emit(&"double_jump")


func has_double_jump() -> bool:
	return can_double_jump


## -- Dash / slide -------------------------------------------------------------

## Centralized dash trigger (keyboard/gamepad "dash" just-pressed and the
## touch dash button both route here — see request_dash). Ground or air,
## one air dash per airborne period.
func _try_start_dash() -> bool:
	if _dash_cooldown_left > 0.0 or _state == State.DASH:
		return false
	if not _can_dash_from_state():
		return false
	if not is_on_floor() and _air_dash_used:
		return false
	_start_dash()
	return true


func _can_dash_from_state() -> bool:
	match _state:
		State.IDLE, State.RUN, State.CROUCH, State.JUMP, State.FALL, State.FOCUS, State.TURN, State.SKID:
			return true
		State.ATTACK, State.AIR_ATTACK:
			return _attack_phase == PHASE_RECOVERY
		_:
			return false


func _start_dash() -> void:
	_dash_direction = _facing
	_dash_is_air = not is_on_floor()
	if _dash_is_air:
		_air_dash_used = true
	_enter_state(State.DASH)
	velocity.x = float(_dash_direction) * dash_speed
	velocity.y = 0.0


func _update_dash(delta: float) -> void:
	if _dash_is_air:
		_update_air_dash(delta)
		return

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


## Air dash: horizontal only, no gravity for its duration, standing collider
## kept (see _enter_state's low-collider check, which only lowers for a
## ground dash).
func _update_air_dash(delta: float) -> void:
	if is_on_floor():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	velocity.x = float(_dash_direction) * dash_speed
	velocity.y = 0.0

	if Input.is_action_just_pressed(&"jump") and _try_launch_jump():
		return

	if _state_time >= air_dash_duration:
		_enter_state(State.JUMP if velocity.y < 0.0 else State.FALL)


## -- Wall cling / climb --------------------------------------------------------

## True when `ray` hits a collider whose shape is tall and narrow enough to
## be a real wall (not the side of a horizontal platform): at least
## `min_wall_height` tall, and not wider than it is tall.
func _is_wall_ray(ray: RayCast2D) -> bool:
	if not ray.is_colliding():
		return false
	var size := _collider_shape_size(ray.get_collider())
	if size == Vector2.ZERO:
		return false
	return size.y >= min_wall_height and size.y >= size.x


func _collider_shape_size(collider: Object) -> Vector2:
	if collider == null or not (collider is Node):
		return Vector2.ZERO
	for child in (collider as Node).get_children():
		if child is CollisionShape2D:
			var shape := (child as CollisionShape2D).shape
			if shape is RectangleShape2D:
				return (shape as RectangleShape2D).size
	return Vector2.ZERO


func _is_against_climbable_wall() -> bool:
	if not (_is_wall_ray(_wall_check_head) and _is_wall_ray(_wall_check_chest) and _is_wall_ray(_wall_check_feet)):
		return false
	# All three rays must hit the same solid, not three different neighbors
	# that each only partially cover the player's height.
	var collider := _wall_check_chest.get_collider()
	return _wall_check_head.get_collider() == collider and _wall_check_feet.get_collider() == collider


## True while the move pad is held toward `direction` (the wall side), which
## is required to grab or keep a wall cling. The brief post-wall-kick input
## lock doesn't count as "releasing" — the drift back toward the wall during
## that window can still re-cling once contact is made.
func _is_holding_toward_wall(direction: int) -> bool:
	if _wall_kick_lock_left > 0.0:
		return true
	var axis := Input.get_axis(&"move_left", &"move_right")
	return not is_zero_approx(axis) and signf(axis) == float(direction)


func _try_start_wall_cling() -> bool:
	if _wall_recling_lock > 0.0:
		return false
	if velocity.y < -wall_cling_apex_threshold:
		return false
	if not _is_against_climbable_wall():
		return false
	if not _is_holding_toward_wall(_facing):
		return false
	_wall_direction = _facing
	_restore_air_actions()
	_enter_state(State.WALL_CLING)
	return true


func _update_wall_cling(delta: float) -> void:
	if is_on_floor():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	velocity.x = 0.0
	velocity.y = minf(move_toward(velocity.y, wall_slide_speed, wall_slide_acceleration * delta), wall_slide_max_speed)
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
			# Wall kick: push outward and up, briefly lock input, then drift
			# back toward this same wall (see _apply_air_horizontal_control)
			# so it re-clings higher and slides again — a climb by kicking.
			# No re-cling lockout here: climbing depends on re-triggering the
			# cling quickly.
			velocity.x = -float(_wall_direction) * wall_kick_outward_speed
			velocity.y = -wall_kick_vertical_speed
			_wall_kick_lock_left = wall_kick_input_lock_time
			_wall_kick_pending = true
			_wall_kick_wall_direction = _wall_direction
		_sfx_jump.play()
		_enter_state(State.JUMP)
		return

	if not _is_against_climbable_wall():
		_enter_state(State.FALL)
		return

	# Holding away from the wall (or letting the pad go neutral) lets go and
	# falls, with no fixed lockout: _try_start_wall_cling checks the same
	# holding-toward condition every frame, so pushing toward the wall again
	# re-grabs immediately.
	if not _is_holding_toward_wall(_wall_direction):
		_enter_state(State.FALL)


## -- State transitions -------------------------------------------------------

func _enter_state(new_state: State) -> void:
	var previous := _state
	_state = new_state
	_state_time = 0.0
	_run_time = 0.0
	if not _is_lateral_attack_state():
		_recoil_left = 0.0
	if not _is_directional_attack_state():
		_slash_vfx.stop_slash()

	if previous == State.DASH and new_state != State.DASH:
		_dash_cooldown_left = dash_cooldown

	# A dash only keeps the low slide collider on the ground; an air dash
	# keeps the standing collider. _dash_is_air still reflects the dash that
	# is ending when new_state leaves State.DASH (it's only reassigned by
	# the next _start_dash call).
	var was_low := previous == State.CROUCH or previous == State.CROUCH_ATTACK or (previous == State.DASH and not _dash_is_air)
	var is_low := new_state == State.CROUCH or new_state == State.CROUCH_ATTACK or (new_state == State.DASH and not _dash_is_air)
	if is_low and not was_low:
		_set_collider_height(_standing_shape_height * crouch_collider_scale)
	elif was_low and not is_low:
		_set_collider_height(_standing_shape_height)

	if previous == State.FOCUS and new_state != State.FOCUS:
		_end_focus()
	elif new_state == State.FOCUS and previous != State.FOCUS:
		_begin_focus()

	# The post-kick drift-back only applies while airborne; any other state
	# (re-clung, landed, attacked, dashed…) clears it.
	if new_state != State.JUMP and new_state != State.FALL:
		_wall_kick_pending = false


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


## -- Health -----------------------------------------------------------------

func get_health() -> int:
	return _health


func get_max_health() -> int:
	return max_health


func is_at_full_health() -> bool:
	return _health >= max_health


## Restores up to `amount` pips (never past the maximum) and tells listeners.
## Returns how many were actually restored.
func heal(amount: int) -> int:
	if _dead or amount <= 0:
		return 0
	var restored := mini(amount, max_health - _health)
	if restored <= 0:
		return 0
	_health += restored
	health_changed.emit(_health, max_health)
	return restored


## Changes the mask count; health is clamped to it and listeners are told.
func set_max_health(value: int) -> void:
	max_health = maxi(value, 1)
	_health = mini(_health, max_health)
	health_changed.emit(_health, max_health)


## Applies a hit coming from `source_position`. Returns false, changing
## nothing, while invulnerable, dead, meditating or input-locked. A hit
## knocks Luz away from the source, restores her air dash and air jump (like
## Hollow Knight), and starts the i-frames, control lock and hit-stop.
func take_damage(amount: int, source_position: Vector2) -> bool:
	return _apply_damage(amount, source_position, false)


## Like take_damage, for fixed hazards: a surviving hit hit-stops, shakes the
## camera and then fades out, moves Luz to the last safe ground and fades back
## in, with input locked throughout. A lethal hit dies normally instead.
func take_hazard_damage(amount: int, source_position: Vector2) -> bool:
	return _apply_damage(amount, source_position, true)


func _apply_damage(amount: int, source_position: Vector2, hazard: bool, force := false) -> bool:
	if amount <= 0 or _dead:
		return false
	if not force and (_invuln_left > 0.0 or is_input_locked()):
		return false
	_health = maxi(_health - amount, 0)
	health_changed.emit(_health, max_health)
	damaged.emit(amount, _health)
	_cancel_actions_for_hit()
	velocity = _knockback_from(source_position)
	_invuln_left = invulnerability_time
	_hit_stop_left = hit_stop_time
	_sprite.speed_scale = 0.0
	if _health == 0:
		_begin_death()
		return true
	_shake_camera()
	if hazard:
		_begin_safe_return()
	else:
		_hurt_left = hurt_control_lock
		_enter_state(State.HURT)
	return true


## Falling out of the map costs one pip like a hazard hit and then returns her
## to the last safe ground; a lethal fall dies normally instead. Unlike a hit
## it ignores the i-frames and any control lock (Hollow Knight pits always
## hurt), so a fall right after a hit still counts. Returns false only while
## she is already dead or already being returned, so a level may call it on
## every tick she stays below the map.
func fall_out_of_bounds() -> bool:
	if _dead or _return_phase != ReturnPhase.NONE:
		return false
	_end_room_transition()
	if not _apply_damage(1, global_position, true, true):
		return false
	velocity = Vector2.ZERO
	return true


func _knockback_from(source_position: Vector2) -> Vector2:
	var side := signf(global_position.x - source_position.x)
	if is_zero_approx(side):
		side = -float(_facing)
	return Vector2(side * knockback_speed.x, knockback_speed.y)


func _cancel_actions_for_hit() -> void:
	if _state == State.FOCUS:
		_enter_state(State.IDLE)
	_deactivate_attack_hitbox()
	_recoil_left = 0.0
	_attack_combo_index = 0
	_attack_buffered_left = 0.0
	_attack_restart_buffered_left = 0.0
	_air_attack_buffered_left = 0.0
	_attack_buffer_left = 0.0
	_jump_buffer_left = 0.0
	_wall_jump_lock_left = 0.0
	_wall_kick_lock_left = 0.0
	_restore_air_actions()


func _update_damage_timers(delta: float) -> void:
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	if _dead:
		return
	_set_sprite_alpha(_flicker_alpha_now() if _invuln_left > 0.0 else _base_alpha)


func _flicker_alpha_now() -> float:
	var phase := int(floorf(_invuln_left / flicker_interval))
	return flicker_alpha if phase % 2 == 0 else _base_alpha


func _set_sprite_alpha(alpha: float) -> void:
	var tint := _sprite.modulate
	tint.a = alpha
	_sprite.modulate = tint


func _shake_camera() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method(&"shake"):
		camera.call(&"shake", hit_shake_strength, hit_shake_time)


## -- Safe ground / hazard return --------------------------------------------------

## The last floor spot judged safe to come back to (the level start until she
## has stood anywhere safe).
func get_last_safe_ground() -> Vector2:
	return _last_safe_ground if _has_safe_ground else _spawn_position


## Moves Luz to the last safe ground at once, at rest.
func return_to_safe_ground() -> void:
	global_position = get_last_safe_ground()
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	safe_ground_returned.emit()


func _begin_safe_return() -> void:
	velocity = Vector2.ZERO
	_return_phase = ReturnPhase.OUT
	_return_left = maxf(hazard_fade_out, 0.001)
	get_screen_fade()


## The one full-screen veil the player owns. Hazard returns and room
## transitions both drive it, and never at the same time.
func get_screen_fade() -> ScreenFade:
	if _fade == null:
		_fade = ScreenFade.new()
		add_child(_fade)
	return _fade


func _update_return(delta: float) -> void:
	_return_left -= delta
	if _return_phase == ReturnPhase.OUT:
		_fade.set_alpha(1.0 - clampf(_return_left / maxf(hazard_fade_out, 0.001), 0.0, 1.0))
		if _return_left <= 0.0:
			return_to_safe_ground()
			_return_phase = ReturnPhase.IN
			_return_left = maxf(hazard_fade_in, 0.001)
	else:
		_fade.set_alpha(clampf(_return_left / maxf(hazard_fade_in, 0.001), 0.0, 1.0))
		if _return_left <= 0.0:
			_end_safe_return()
	_update_locked(delta)


func _end_safe_return() -> void:
	_return_phase = ReturnPhase.NONE
	if _fade != null:
		_fade.set_alpha(0.0)


func _track_safe_ground(delta: float) -> void:
	var ground := _floor_collider() if is_on_floor() and _state != State.HURT else null
	if ground == null:
		_ground_time = 0.0
		_ground_collider = null
		return
	if ground != _ground_collider:
		_ground_collider = ground
		_ground_time = 0.0
	_ground_time += delta
	if _ground_time >= safe_ground_time and _is_safe_spot(ground):
		_last_safe_ground = global_position
		_has_safe_ground = true


## The solid (layer 1) or one-way (layer 2) body she is standing on.
func _floor_collider() -> CollisionObject2D:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var body := collision.get_collider() as CollisionObject2D
		if body != null and collision.get_normal().y <= -0.7 and (body.get_collision_layer_value(1) or body.get_collision_layer_value(2)):
			return body
	return null


func _is_safe_spot(ground: CollisionObject2D) -> bool:
	var surface := _surface_rect(ground)
	if surface.has_area():
		if global_position.x < surface.position.x + safe_ground_margin or global_position.x > surface.end.x - safe_ground_margin:
			return false
	for node: Node in get_tree().get_nodes_in_group(ContactDamage.HAZARD_GROUP):
		if (node as ContactDamage).get_world_rect().grow(safe_ground_margin).has_point(global_position):
			return false
	return true


## World rect of the body's rectangle shape (no rotation), or an empty rect.
func _surface_rect(body: CollisionObject2D) -> Rect2:
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size := (shape_node.shape as RectangleShape2D).size
			return Rect2(body.global_position + shape_node.position - size * 0.5, size)
	return Rect2()


func _update_hurt(delta: float) -> void:
	_apply_gravity(delta)
	if _hurt_left <= 0.0:
		_end_generic_attack()


func _begin_death() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method(&"cancel_shake"):
		camera.call(&"cancel_shake")
	_dead = true
	_invuln_left = 0.0
	_hurt_left = 0.0
	_set_soul(0)
	_enter_state(State.DEAD)
	died.emit()


func _update_dead(delta: float) -> void:
	_state_time += delta
	velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		_apply_gravity(delta)
	move_and_slide()
	_update_animation()
	var fade := clampf(_state_time / maxf(death_fade_time, 0.001), 0.0, 1.0)
	_set_sprite_alpha(lerpf(_base_alpha, 0.0, fade))
	if _state_time >= death_fade_time:
		_respawn_after_death()


## Wakes Luz at the active checkpoint of this scene (or where the level
## started), with full health, and lets resettable enemies regenerate.
func _respawn_after_death() -> void:
	# Looked up by path: a bare autoload name does not compile in --script
	# runs, which instantiate the player without the project's autoloads.
	var checkpoints := get_node_or_null("/root/CheckpointService")
	var current := get_tree().current_scene
	if checkpoints != null and current != null:
		checkpoints.apply_to_player(self, current.scene_file_path)
	respawn()
	# A damage area she just left still lists her as inside for one physics
	# step, so waking up needs the same grace as a hit.
	_invuln_left = invulnerability_time
	if checkpoints != null:
		checkpoints.reset_resettable_enemies()


func restore_full_health() -> void:
	if _health == max_health:
		return
	_health = max_health
	health_changed.emit(_health, max_health)


## -- Soul and focus heal -------------------------------------------------------

func get_soul() -> int:
	return _soul


func get_max_soul() -> int:
	return max_soul


## Adds soul up to the cap. Only hits that damage an enemy call this.
func add_soul(amount: int) -> void:
	if amount > 0:
		_set_soul(_soul + amount)


func _set_soul(value: int) -> void:
	var clamped := clampi(value, 0, max_soul)
	if clamped == _soul:
		return
	_soul = clamped
	soul_changed.emit(_soul, max_soul)


## True when a focus heal would be worth starting: enough soul and a missing
## pip. The touch Focus button follows this.
func is_focus_available() -> bool:
	return not _dead and _health > 0 and _health < max_health and _soul >= focus_cost


func is_focusing() -> bool:
	return _state == State.FOCUS


## Touch UI entry point: holding the Focus button means focus, same as the
## keyboard and gamepad `focus` action.
func request_focus(pressed: bool) -> void:
	_focus_requested = pressed


func _focus_held() -> bool:
	return _focus_requested or Input.is_action_pressed(&"focus")


func _try_start_focus() -> void:
	if _state != State.IDLE and _state != State.RUN:
		return
	if not _focus_held() or not is_focus_available() or not is_on_floor():
		return
	if is_input_locked() or _jump_buffer_left > 0.0 or not is_zero_approx(_horizontal_input()):
		return
	_enter_state(State.FOCUS)


## Acting cancels focus, like Hollow Knight: move, jump, attack or dash.
func _poll_focus_cancel() -> void:
	if _state != State.FOCUS:
		return
	var acted := (
		_jump_pressed_now
		or Input.is_action_just_pressed(&"attack")
		or Input.is_action_just_pressed(&"dash")
		or not is_zero_approx(_horizontal_input())
	)
	if acted:
		_enter_state(State.IDLE)


func _update_focus(delta: float) -> void:
	velocity = Vector2.ZERO
	if not is_on_floor():
		_enter_state(State.FALL)
		return
	if not _focus_held() or not is_focus_available():
		_enter_state(State.IDLE)
		return
	_focus_left -= delta
	_update_focus_glow()
	if _focus_left <= 0.0:
		_complete_focus()


func _complete_focus() -> void:
	_set_soul(_soul - focus_cost)
	heal(1)
	if _focus_held() and is_focus_available():
		_focus_left = focus_time
		_state_time = 0.0
	else:
		_enter_state(State.IDLE)


func _begin_focus() -> void:
	velocity = Vector2.ZERO
	_focus_left = focus_time
	_update_focus_glow()


func _end_focus() -> void:
	_focus_left = 0.0
	if _focus_glow != null:
		_focus_glow.visible = false


## Placeholder for the missing art: a soft pulsing glow that swells as the
## channel nears completion.
func _update_focus_glow() -> void:
	if _focus_glow == null:
		_focus_glow = Polygon2D.new()
		_focus_glow.z_index = 1
		_focus_glow.position = Vector2(0.0, -24.0)
		var ring := PackedVector2Array()
		for step in 24:
			ring.append(Vector2.from_angle(TAU * float(step) / 24.0) * focus_glow_radius)
		_focus_glow.polygon = ring
		add_child(_focus_glow)
	var progress := 1.0 - clampf(_focus_left / maxf(focus_time, 0.001), 0.0, 1.0)
	_focus_glow.visible = true
	_focus_glow.scale = Vector2.ONE * lerpf(0.6, 1.2, progress)
	_focus_glow.color = Color(1.0, 0.95, 0.75, 0.22 + 0.12 * sin(_state_time * 14.0))


## -- Input lock / meditation ---------------------------------------------------

## True while gameplay input is ignored, either by an explicit lock or because
## the player is meditating.
func is_input_locked() -> bool:
	return _input_locked or _meditating or _dead or _transition_locked or _return_phase != ReturnPhase.NONE


func is_meditating() -> bool:
	return _meditating


func set_input_locked(locked: bool) -> void:
	if _input_locked == locked:
		return
	_input_locked = locked
	if locked:
		clear_transient_state()


## -- Room transitions ---------------------------------------------------------

## Locks input for a room change. A non-zero `walk_direction` (-1 or 1) walks
## her that way at run speed; 0 keeps her momentum instead, for vertical
## openings. Hits are refused while it lasts, like any input lock.
func begin_room_transition(walk_direction: int) -> void:
	_transition_locked = true
	_auto_walk = signi(walk_direction)
	_keep_momentum = _auto_walk == 0
	_cancel_inputs_for_transition()
	if _auto_walk != 0:
		_facing = _auto_walk
	else:
		velocity.x = clampf(velocity.x, -air_max_speed, air_max_speed)


func end_room_transition() -> void:
	_end_room_transition()


func is_in_room_transition() -> bool:
	return _transition_locked


## True while the hazard return owns the screen veil.
func is_returning_to_safe_ground() -> bool:
	return _return_phase != ReturnPhase.NONE


## Stops the auto-walk but keeps the lock.
func stop_auto_walk() -> void:
	_auto_walk = 0


## Puts her feet at `feet`, at rest, facing `facing` (-1 or 1).
func place_for_transition(feet: Vector2, facing: int) -> void:
	global_position = feet
	velocity = Vector2.ZERO
	_facing = 1 if facing >= 0 else -1
	_sprite.flip_h = _facing < 0
	reset_physics_interpolation()


## Makes sure she rises at least `height` px from here (never slows a faster
## rise), so a transition can lift her over the lip of an opening.
func boost_upward(height: float) -> void:
	if height > 0.0:
		velocity.y = minf(velocity.y, -sqrt(2.0 * _rise_gravity * height))


func get_facing() -> int:
	return _facing


func _end_room_transition() -> void:
	if not _transition_locked:
		return
	_transition_locked = false
	_auto_walk = 0
	_cancel_inputs_for_transition()


func _cancel_inputs_for_transition() -> void:
	set_collision_mask_value(2, true)
	_drop_left = 0.0
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_jump_press_pending = false
	_dash_cooldown_left = 0.0
	_wall_jump_lock_left = 0.0
	_wall_kick_lock_left = 0.0
	_wall_kick_pending = false
	_attack_combo_index = 0
	_attack_buffered_left = 0.0
	_attack_restart_buffered_left = 0.0
	_air_attack_buffered_left = 0.0
	_attack_buffer_left = 0.0
	_attack_buffer_direction = 0
	_recoil_left = 0.0
	_deactivate_attack_hitbox()
	_set_collider_height(_standing_shape_height)


## Locks input and lets the player keep processing while the tree is paused,
## so the world can be frozen around a committed rest.
func enter_meditation() -> void:
	if _meditating:
		return
	clear_transient_state()
	_meditating = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	meditation_started.emit()


## Turns the meditating player toward world-space `target_x`. Ignored outside
## meditation so it can never override player-driven facing.
func face_towards(target_x: float) -> void:
	if not _meditating or is_equal_approx(target_x, global_position.x):
		return
	_facing = 1 if target_x > global_position.x else -1
	_sprite.flip_h = _facing < 0


## Forces the meditating player to face `direction` (-1 left, 1 right).
func face_direction(direction: int) -> void:
	if not _meditating or direction == 0:
		return
	_facing = signi(direction)
	_sprite.flip_h = _facing < 0


## Plays one of the rest ritual clips from its first frame. Only valid while
## meditating; the clip owns the pose until another one replaces it.
func play_rest_animation(animation_name: StringName) -> void:
	if not _meditating or not _sprite.sprite_frames.has_animation(animation_name):
		return
	_rest_animation = animation_name
	_sprite.stop()
	_sprite.animation = animation_name
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.speed_scale = 1.0
	_sprite.play(animation_name)


## Seconds one full pass of a clip takes at normal speed.
func get_animation_length(animation_name: StringName) -> float:
	var frames := _sprite.sprite_frames
	if not frames.has_animation(animation_name):
		return 0.0
	var speed := frames.get_animation_speed(animation_name)
	if speed <= 0.0:
		return 0.0
	var total := 0.0
	for i in frames.get_frame_count(animation_name):
		total += frames.get_frame_duration(animation_name, i)
	return total / speed


func exit_meditation() -> void:
	if not _meditating:
		return
	_meditating = false
	_rest_animation = &""
	process_mode = _default_process_mode
	_jump_buffer_left = 0.0
	meditation_finished.emit()


## Cancels every in-flight action and buffered input so control can be
## handed back (or taken away) from a clean idle state.
func clear_transient_state() -> void:
	velocity = Vector2.ZERO
	_transition_locked = false
	_auto_walk = 0
	set_collision_mask_value(2, true)
	_drop_left = 0.0
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_landing_left = 0.0
	_dash_cooldown_left = 0.0
	_restore_air_actions()
	_jump_press_pending = false
	_wall_recling_lock = 0.0
	_wall_jump_lock_left = 0.0
	_wall_kick_lock_left = 0.0
	_wall_kick_pending = false
	_attack_combo_index = 0
	_attack_phase = PHASE_STARTUP
	_attack_buffered_left = 0.0
	_attack_restart_buffered_left = 0.0
	_air_attack_buffered_left = 0.0
	_attack_buffer_left = 0.0
	_attack_buffer_direction = 0
	_recoil_left = 0.0
	_clear_damage_state()
	_set_collider_height(_standing_shape_height)
	_deactivate_attack_hitbox()
	_enter_state(State.IDLE)


func _clear_damage_state() -> void:
	_end_safe_return()
	_hurt_left = 0.0
	_invuln_left = 0.0
	_hit_stop_left = 0.0
	_set_sprite_alpha(_base_alpha)


func _request_rest_exit() -> void:
	if _meditating:
		rest_exit_requested.emit()


func _poll_rest_exit_input() -> void:
	for action in REST_EXIT_ACTIONS:
		if Input.is_action_just_pressed(action):
			rest_exit_requested.emit()
			return


func _on_sprite_animation_finished() -> void:
	if _meditating and _rest_animation != &"":
		rest_animation_finished.emit(_rest_animation)


func _on_sprite_frame_changed() -> void:
	if _meditating and _rest_animation != &"" and _sprite.animation == _rest_animation:
		rest_animation_frame_changed.emit(_rest_animation, _sprite.frame)


func _update_locked(delta: float) -> void:
	if _meditating:
		_poll_rest_exit_input()
	_state_time += delta
	var resting_state := State.IDLE if is_on_floor() else State.FALL
	if _state != resting_state:
		_enter_state(resting_state)

	var fall_speed_before_move := velocity.y
	velocity.x = _locked_horizontal_velocity()
	if is_on_floor():
		velocity.y = 0.0
	else:
		_apply_gravity(delta)
	move_and_slide()
	_after_move(fall_speed_before_move)
	_update_animation()


## Walks at run speed during a doorway transition, keeps momentum during a
## vertical one, and stands still for every other lock.
func _locked_horizontal_velocity() -> float:
	if _transition_locked and _auto_walk != 0:
		_facing = _auto_walk
		return float(_auto_walk) * run_max_speed
	if _transition_locked and _keep_momentum:
		return velocity.x
	return 0.0


## -- Checkpoints / respawn -----------------------------------------------------

## Makes `spawn_position` the point respawn() returns to; does not move the player.
func apply_checkpoint(spawn_position: Vector2) -> void:
	set_checkpoint(spawn_position)


func set_checkpoint(checkpoint: Vector2) -> void:
	_spawn_position = checkpoint


func respawn() -> void:
	_dead = false
	_has_safe_ground = false
	exit_meditation()
	restore_full_health()
	clear_transient_state()
	global_position = _spawn_position
	reset_physics_interpolation()
	_set_collider_height(_standing_shape_height)
	_deactivate_attack_hitbox()
	_restore_air_actions()
	_enter_state(State.IDLE)
	respawned.emit()


## -- Post-move / feedback -------------------------------------------------------

func _after_move(fall_speed_before_move: float) -> void:
	if not _was_on_floor and is_on_floor() and fall_speed_before_move > landing_impact_speed:
		_landing_left = landing_squash_time
		_sfx_land.play()
	if not _was_on_floor and is_on_floor():
		_restore_air_actions()
	if is_on_floor() and (_state == State.JUMP or _state == State.FALL):
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
	_was_on_floor = is_on_floor()


func _update_footsteps(delta: float) -> void:
	if _state != State.RUN or not is_on_floor() or absf(velocity.x) < 70.0:
		_footstep_left = 0.0
		_dust_left = 0.0
		return
	_dust_left -= delta
	if _dust_left <= 0.0:
		_dust_left = footstep_dust_interval
		_spawn_dust(GroundDust.Kind.FOOTSTEP)
	_footstep_left -= delta
	if _footstep_left <= 0.0:
		_sfx_foot.play()
		_footstep_left = clampf(0.30 - absf(velocity.x) / 2600.0, 0.12, 0.26)


## Drops a self-freeing dust effect at her feet, left behind in world space.
## The host is the parent when it is a Node2D, otherwise the current scene;
## the effect is skipped when neither can hold it.
func _spawn_dust(dust_kind: GroundDust.Kind) -> void:
	if ground_dust_scene == null:
		_warn_dust_once("ground_dust_scene is not set; ground dust is skipped.")
		return
	var host := get_parent() as Node2D
	if host == null:
		host = get_tree().current_scene as Node2D
	if host == null:
		_warn_dust_once("no Node2D host for ground dust; it is skipped.")
		return
	var dust := ground_dust_scene.instantiate() as GroundDust
	if dust == null:
		_warn_dust_once("ground_dust_scene root is not a GroundDust; it is skipped.")
		return
	dust.kind = dust_kind
	dust.direction = _facing
	host.add_child(dust)
	dust.global_position = global_position


func _warn_dust_once(message: String) -> void:
	if _dust_warned:
		return
	_dust_warned = true
	push_warning("Player: " + message)


func _update_animation() -> void:
	var animation_facing := _attack_facing if _is_directional_attack_state() else _facing
	_sprite.flip_h = animation_facing < 0
	if _meditating:
		if _rest_animation == &"":
			_play_animation(&"idle")
		return
	match _state:
		State.CROUCH:
			_play_animation(&"crouch")
		State.TURN:
			_play_animation(&"turn")
		State.SKID:
			_play_animation(&"skid")
		State.DASH:
			_play_animation(&"air_dash" if _dash_is_air else &"ground_dash")
		State.JUMP:
			# Both wall-exit branches (jumping away and the climb-by-kicking
			# wall kick) enter State.JUMP; either lockout means this jump
			# originated from a wall push-off, so both show the wall_jump
			# pose for their brief lock window before falling back to the
			# ordinary jump ascent clip.
			var pushed_off_wall := _wall_jump_lock_left > 0.0 or _wall_kick_lock_left > 0.0
			_play_animation(&"wall_jump" if pushed_off_wall else &"jump")
		State.FALL:
			_play_animation(&"fall")
		State.WALL_CLING:
			_play_animation(&"wall_cling")
		State.ATTACK:
			var attack_animation: StringName = [&"attack_1", &"attack_2", &"attack_3"][clampi(_attack_combo_index, 0, 2)]
			_play_animation(attack_animation)
		State.CROUCH_ATTACK:
			_play_animation(&"crouch_attack")
		State.UP_ATTACK:
			# T4d item 4 (iPhone playtest: the up-attack body pose now ends
			# together with its slash -- commit 126d6ff -- but was still
			# DISPLAYED for the rest of the state's recovery: the up_attack
			# clip freezes on its last frame, which is a pointing-up pose,
			# for crouch_up_attack_window - slash_end (~0.38s). Switch to the
			# appropriate airborne/idle animation the instant the slash ends
			# instead of holding that pose.
			var up_attack_slash_end := attack_startup_time + PlayerSlashVfx.TOTAL_DURATION
			if _state_time < up_attack_slash_end:
				_play_animation(&"up_attack")
			elif is_on_floor():
				_play_animation(&"idle")
			else:
				_play_animation(&"fall" if velocity.y >= 0.0 else &"jump")
		State.AIR_ATTACK:
			_play_animation(&"air_attack")
		State.HURT:
			_play_animation(&"fall")
		State.DEAD, State.FOCUS:
			_play_animation(&"idle")
		_:
			if _landing_left > 0.0:
				_play_animation(&"land")
			elif absf(velocity.x) > 35.0:
				_play_animation(&"walk", clampf(absf(velocity.x) / run_max_speed, 0.7, 1.8))
			else:
				_play_animation(&"idle")


## Clip-local speed: always reassigns speed_scale, even if the animation
## itself did not change, so a prior action's speed can never leak forward.
func _play_animation(animation_name: StringName, speed_scale := 1.0) -> void:
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)
	_sprite.speed_scale = speed_scale

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
## Seconds between footstep puffs while running (one per step: two per run cycle).
@export var footstep_dust_interval := 0.29

@export_group("Run")
## Blasphemous reference: 145-169 px/s (mean 157) with near-instant acceleration.
@export var run_max_speed := 157.0
@export var run_acceleration := 3000.0
@export var run_deceleration := 5000.0

@export_group("Turn")
## Two-frame snap pivot with no movement when starting to run opposite to the facing
## or when reversing while running.
@export var turn_time := 0.1

@export_group("Skid")
## Releasing the run input at (near) full speed snaps to a low skid pose,
## brakes linearly to zero, holds the pose, then returns to idle. Input in
## the same direction cancels the skid at once. Input opposite to the facing
## waits for the brake to finish and then pivots (TURN), so the skid is
## never cut short by a reversal.
@export var skid_brake_time := 0.14
## Seconds the pose is held once the brake has finished (~10 frames at 60 fps).
@export var skid_hold_time := 0.17
## Fraction of run_max_speed needed to skid (shorter taps just stop).
@export_range(0.0, 1.0) var skid_min_speed_ratio := 0.9
## Seconds spent at that speed before a release skids (filters taps).
@export var skid_min_run_time := 0.12
## Seconds the run input must stay released before the skid starts. The run
## keeps its speed meanwhile, so a stick or two keys that pass through neutral
## while reversing (or a re-press) go straight to the turn or keep running
## instead of flashing the first frames of a skid. Counts toward skid_brake_time.
@export var skid_release_grace := 0.06

@export_group("Jump")
## Apex height and time-to-apex derive rise gravity and launch velocity
## (Penitent: 87 px of torso travel in 0.45 s, no takeoff anticipation). The
## physics step (60 Hz, semi-implicit Euler) adds ~3.7% to the analytic apex, so
## 84 here gives the measured 87 px in game (74 px for a tap).
@export var jump_height := 84.0
@export var jump_time_to_apex := 0.45
## Releasing jump while rising multiplies the current upward speed by this.
@export var jump_release_multiplier := 0.45
## A tap keeps rising for at least this long before the release cut applies
## (the Penitent's taps all reach ~0.85 of a full jump, cut at 0.25-0.3 s). With
## the defaults a tap peaks at about 73 px.
@export var jump_min_hold_time := 0.25
## Fall gravity over rise gravity: the Penitent falls in 0.41 s after 0.45 s up.
@export var fall_gravity_multiplier := 1.15
@export var max_fall_speed := 900.0
@export var coyote_time := 0.08
@export var jump_buffer_time := 0.10

@export_group("Double Jump")
## Gated ability, off until unlock_double_jump() (the Greece boss reward).
@export var can_double_jump := false
## Rise of an air jump, launched with the same rise gravity as the main jump.
## Same as the main jump (the Penitent has none to copy): the pair keeps the
## old 1:1 ratio, so two jumps climb about 174 px.
@export var double_jump_height := 84.0
## Extra jumps available per airborne period.
@export var air_jumps := 1

@export_group("Air Control")
## Horizontal air speed target. The Penitent keeps its running speed through
## the whole jump (161 +-4 px/s measured), so it equals run_max_speed.
@export var air_max_speed := 157.0
## High enough that a jump from a run keeps its speed with no visible ramp.
@export var air_acceleration := 4000.0
@export var air_deceleration := 2600.0

@export_group("Landing")
## Recovery after a hard standing landing (21 frames of the Penitent). Movement
## and turning are locked; a jump press cancels it from landing_jump_cancel_time.
@export var landing_squash_time := 0.35
@export var landing_jump_cancel_time := 0.18
## Fall speed that plays the landing feedback (dust, sound, short squash).
@export var landing_impact_speed := 150.0
## Fall speed that costs the recovery above (a ~45 px drop or a normal jump).
@export var hard_landing_speed := 300.0
## Landing faster than this fraction of run_max_speed counts as running: no
## recovery, she keeps running.
@export_range(0.0, 1.0) var landing_run_speed_ratio := 0.5

@export_group("Crouch")
@export var crouch_collider_scale := 0.5
@export var crouch_headroom_margin := 4.0

@export_group("Drop Through")
@export var drop_through_time := 0.20

@export_group("Dash")
## Penitent profile (Dash.mov): plateau ~395 px/s. A ground dash is a lean-back
## startup (from rest only, no forward motion), a ramp, a plateau and an
## ease-out; from rest it slides ~129 px, from a run ~138 px.
## Ramp, ease-out and length were fitted to the measured x(t) of Dash.mov (max
## deviation ~7.5 px), not copied from the noisy per-frame speeds.
@export var dash_speed := 395.0
## Slide length: ramp + plateau + ease-out (the plateau is what is left). The
## Penitent's slide pose lasts 0.43-0.47 s.
@export var dash_duration := 0.43
## Lean-back before the slide when starting from (near) rest; no forward motion.
@export var dash_startup_time := 0.08
## Time to go from the speed she had to dash_speed (about 6 frames).
@export var dash_ramp_time := 0.10
## Time spent easing from dash_speed down to dash_end_speed at the end.
@export var dash_ease_time := 0.14
## Speed at the end of the slide; from there she brakes, or keeps running if held.
@export var dash_end_speed := 100.0
## Starting slower than this fraction of run_max_speed counts as "from rest".
@export_range(0.0, 1.0) var dash_rest_speed_ratio := 0.5
@export var dash_cooldown := 0.35
## Air dash: horizontal only, constant dash_speed, gravity suspended for its
## duration, standing collider kept (unlike the ground dash's low slide
## collider). One per airborne period — resets on landing or wall cling. At
## 0.30 s it covers ~118 px (+~12 px of speed bleed), the ground slide's range.
@export var air_dash_duration := 0.30

@export_group("Dash Invulnerability")
## Blasphemous-style i-frames: for the whole dash (lean-back, slide and ease,
## ground and air) enemy contact, enemy projectiles and other non-hazard hits do
## nothing and projectiles pass through her. Fixed hazards (spikes, pits, falling
## out of the map) are NOT blocked: in Blasphemous the dash does not protect from them.
@export var dash_invulnerable := true
## Extra seconds of immunity after the dash ends (0 = none).
@export var dash_invulnerable_grace := 0.0

@export_group("Dash Afterimage")
## Translucent copies of the pose left behind during a dash (see DashAfterimage:
## its scene sets the color, life and alpha). Null disables them.
@export var dash_afterimage_scene: PackedScene = preload("res://scenes/vfx/dash_afterimage.tscn")
## One ghost every ~2 frames (the Penitent shows 4-5 alive at ~0.14 s of life).
@export var afterimage_interval := 0.033

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
## Retuned for the Penitent jump (rise gravity 2006 -> 859 px/s^2): 412 keeps the
## climb of a kick at ~99 px (v^2/(2*rise_gravity)), the same as the old 630 px/s
## under the old gravity, so wall climbs keep their height (but take longer).
@export var wall_kick_vertical_speed := 412.0
## Horizontal input is ignored for this long right after a kick, so the
## outward push reads as a real impulse instead of a vertical hop.
@export var wall_kick_input_lock_time := 0.12
## Air-control target speed used to drift back toward the wall after a kick,
## once the input lock above ends, unless the player holds away from it.
@export var wall_kick_drift_speed := 160.0
## Burst away from the wall, then air_max_speed takes over. Old 300 was tuned
## for a 250 px/s air speed; 220 matches wall_kick_outward_speed.
@export var wall_jump_horizontal_speed := 220.0
## Retuned with the kick above: ~78 px of rise, as the old 560 under the old gravity.
@export var wall_jump_vertical_speed := 366.0
@export var wall_jump_lock_time := 0.15
@export var wall_recling_lockout := 0.2

@export_group("Attack")
## Penitent-matched timings (60 fps reference, seconds, hit-stop excluded).
## Windup of hit 1 from rest (7 frames); after any attack it is the shorter
## chained windup (4 frames).
@export var attack_startup_time := 0.117
@export var attack_chain_startup_time := 0.067
## Finisher (hit 3) windup: sword raised above the head (9-13 frames).
@export var attack_finisher_startup_time := 0.19
## Each attack is one slash: (active, recovery) seconds. The active window is
## when the single hitbox is live and the slash is drawn; it is also the span of
## the sprite's active frames. Recovery ends when the next press is accepted, so
## whiffing hit 1 repeats it every ~0.305 s (windup 0.067 + 0.15 + 0.088).
@export var attack_hit1_phases := Vector2(0.15, 0.088)
@export var attack_hit2_phases := Vector2(0.127, 0.093)
@export var attack_hit3_phases := Vector2(0.10, 0.30)
## Crouch attack: windup 4 f, one sweep (7 f), recovery (cycle 28 f). The up
## attack uses exactly the same rhythm.
@export var crouch_attack_startup_time := 0.067
@export var crouch_attack_phases := Vector2(0.117, 0.283)
@export var up_attack_startup_time := 0.067
@export var up_attack_phases := Vector2(0.117, 0.283)
## Air attack: windup 3-4 f, one diagonal crescent, recovery.
@export var air_attack_startup_time := 0.06
@export var air_attack_phases := Vector2(0.166, 0.173)
## Time after a LANDED hit during which the next press still continues the
## combo, even once the hit's own recovery is over (reference: >= 0.55 s).
@export var attack_chain_window := 0.55
## Hit 3 moves her forward by this many pixels in `attack_lunge_time`, then
## she slides back to where she started over `attack_lunge_return_time`.
## Enemies are not pushed; she may overlap them.
@export var attack_lunge_distance := 40.0
@export var attack_lunge_time := 0.05
@export var attack_lunge_return_time := 0.30
## How long the ONE buffered attack press stays queued before being dropped
## (a press accepted up to ~9 frames before recovery ends). One window shared by
## every buffered press so a burst of taps never fires "one attack too many".
@export var attack_buffer_time := 0.15

@export_group("Attack Feedback")
## Damage one slash deals to whatever it strikes.
@export var attack_damage := 1
## Freeze of Luz, the target and the slash on a landed hit, for ground hits
## 1, 2 and 3 (Penitent: 5-8 f, 6-9 f, ~12 f). Never touches Engine.time_scale.
@export var attack_hit_stop_times := Vector3(0.09, 0.10, 0.20)
## Hit-stop of the crouch, up and air attacks.
@export var attack_other_hit_stop_time := 0.09
## Camera jolt (pixels, toward the attack; negative y is up) for ground hits
## 1, 2, 3 and for the other attacks. It holds for `attack_kick_hold` and then
## snaps back over `attack_kick_decay`.
@export var attack_kick_hit1 := Vector2(9.0, 0.0)
@export var attack_kick_hit2 := Vector2(13.0, -13.0)
@export var attack_kick_hit3 := Vector2(36.0, -18.0)
@export var attack_kick_other := Vector2(9.0, 0.0)
@export var attack_kick_up := Vector2(0.0, -9.0)
@export var attack_kick_hold := Vector3(0.033, 0.05, 0.12)
@export var attack_kick_decay := 0.05
## Spark scene spawned on the struck target (see HitSpark), at this height above its origin.
@export var hit_spark_scene: PackedScene = preload("res://scenes/vfx/hit_spark.tscn")
@export var hit_spark_height := 24.0

@export_group("Attack Hitboxes")
## Penitent-measured reach per phase, as a Rect2 in right-facing local pixels
## (position = top-left corner, x forward, y negative = above the feet; it is
## mirrored by her facing). One box per attack, the bounds of its slash
## (PlayerSlashVfx.slash_bounds) plus a few pixels toward her body, so the visible reach equals the hitbox reach. The finisher's box
## stays where the lunge started (it does not travel with her).
@export var hitbox_hit1 := Rect2(2, -40, 62, 25)
@export var hitbox_hit2 := Rect2(2, -33, 68, 33)
@export var hitbox_hit3 := Rect2(2, -22, 76, 22)
@export var hitbox_crouch := Rect2(2, -18, 75, 18)
@export var hitbox_up := Rect2(2, -102, 41, 64)
@export var hitbox_air := Rect2(2, -22, 73, 22)

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
	"skid": _skid_brake_duration(),
	"attack_1": attack_startup_time + _phase_total(attack_hit1_phases),
	"attack_2": attack_chain_startup_time + _phase_total(attack_hit2_phases),
	"attack_3": attack_finisher_startup_time + _phase_total(attack_hit3_phases),
	"crouch_attack": crouch_attack_startup_time + _phase_total(crouch_attack_phases),
	"up_attack": up_attack_startup_time + _phase_total(up_attack_phases),
	"air_attack": air_attack_startup_time + _phase_total(air_attack_phases),
}, {
	"attack_1": attack_startup_time,
	"attack_2": attack_chain_startup_time,
	"attack_3": attack_finisher_startup_time,
	"crouch_attack": crouch_attack_startup_time,
	"up_attack": up_attack_startup_time,
	"air_attack": air_attack_startup_time,
}, {
	"attack_1": attack_hit1_phases.x,
	"attack_2": attack_hit2_phases.x,
	"attack_3": attack_hit3_phases.x,
	"crouch_attack": crouch_attack_phases.x,
	"up_attack": up_attack_phases.x,
	"air_attack": air_attack_phases.x,
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
var _dash_grace_left := 0.0
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
## Time left of the hard standing landing's recovery (movement locked).
var _landing_left := 0.0
## Seconds a jump release must still wait before it may cut the rise (tap minimum).
var _jump_min_hold_left := 0.0
var _jump_cut_pending := false
var _footstep_left := 0.0
var _dust_left := 0.0
var _run_time := 0.0
var _skid_deceleration := 0.0
## Time the run input has been released while a skid is possible (see skid_release_grace).
var _release_time := 0.0
var _dust_warned := false
var _was_on_floor := false
var _drop_left := 0.0

var _dash_direction := 1
var _dash_from_rest := false
var _dash_start_speed := 0.0
var _dash_slide_started := false
var _afterimage_left := 0.0
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
## The single buffered press: there is never more than one, whichever attack
## is playing, and it only fires once that attack reaches its cancel point.
var _attack_buffer_left := 0.0
## Set by every attack start (also a repeat of the same hit): the next animation
## update replays the attack clip from frame 0, so sprite, hitbox and slash start
## together and a clip that already finished never stays on its last pose.
var _attack_animation_restart := false
var _attack_buffer_direction := 0
## Phase bookkeeping of the current attack: index of the active segment
## (-1 = windup, segment count = recovery) and the windup it started with.
var _attack_segment := -1
var _attack_startup_current := 0.0
## True when this hit began right after another one (shorter windup).
var _attack_chained := false
## Whether the current ground hit struck something: only a landed hit lets the
## combo advance; a whiff repeats hit 1.
var _attack_landed := false
## After a landed hit: combo index a fresh press continues with, and how long
## that is still possible (attack_chain_window).
var _chain_next_index := 0
var _chain_time_left := 0.0
## Position at which the current attack started (the finisher's box and slash
## stay there) and the lunge bookkeeping.
var _attack_origin := Vector2.ZERO
var _attack_segment_rect := Rect2()
var _attack_segment_anchored := false

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
		# A press during the freeze is not lost: it is buffered for the combo.
		if _is_directional_attack_state() and Input.is_action_just_pressed(&"attack"):
			_queue_attack(_held_vertical_direction())
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

	move_and_slide()
	_after_move(fall_speed_before_move)
	_track_safe_ground(delta)
	_update_footsteps(delta)
	_update_animation()
	_update_afterimages(delta)


func _update_shared_timers(delta: float) -> void:
	_landing_left = maxf(_landing_left - delta, 0.0)
	_jump_min_hold_left = maxf(_jump_min_hold_left - delta, 0.0)
	_wall_recling_lock = maxf(_wall_recling_lock - delta, 0.0)
	_wall_jump_lock_left = maxf(_wall_jump_lock_left - delta, 0.0)
	_wall_kick_lock_left = maxf(_wall_kick_lock_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_attack_buffer_left = maxf(_attack_buffer_left - delta, 0.0)
	_chain_time_left = maxf(_chain_time_left - delta, 0.0)

	if _drop_left > 0.0:
		_drop_left -= delta
		if _drop_left <= 0.0:
			set_collision_mask_value(2, true)

	_jump_pressed_now = _jump_press_pending or Input.is_action_just_pressed(&"jump")
	_jump_press_pending = false
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer_left = jump_buffer_time + _landing_cancel_remaining()
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
	# SKID keeps its facing: _update_skid decides between cancel and pivot.
	if _state in [State.TURN, State.SKID, State.DASH, State.WALL_CLING, State.HURT]:
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
	if _landing_left > 0.0:
		# Hard standing landing: planted until the recovery ends (a jump may cancel it).
		axis = 0.0
		velocity.x = 0.0
	_track_run_time(delta)
	if _try_start_skid(axis, delta):
		return
	# Inside the release grace the run keeps its speed (the skid or the turn decides next).
	if _release_time <= 0.0:
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
	if is_zero_approx(axis) or not is_on_floor() or _landing_left > 0.0:
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


func _try_start_skid(axis: float, delta: float) -> bool:
	var can_skid := (
		_state == State.RUN
		and is_zero_approx(axis)
		and _run_time >= skid_min_run_time
		and _jump_buffer_left <= 0.0
		and not Input.is_action_pressed(&"move_down")
	)
	if not can_skid:
		_release_time = 0.0
		return false
	_release_time += delta
	if _release_time < skid_release_grace:
		return false
	_skid_deceleration = absf(velocity.x) / _skid_brake_duration()
	_enter_state(State.SKID)
	_spawn_dust(GroundDust.Kind.STOP)
	return true


## The release grace counts toward skid_brake_time, so the slide from the release
## (grace at full speed, then the linear brake) keeps the same total time.
func _skid_brake_duration() -> float:
	return maxf(skid_brake_time - skid_release_grace, 0.001)


func _update_skid(delta: float) -> void:
	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return
	var axis := _horizontal_input()
	var crouching := Input.is_action_pressed(&"move_down")
	var reversing := not is_zero_approx(axis) and (1 if axis > 0.0 else -1) != _facing
	if reversing and not crouching:
		# A reversal never cuts the brake short: the skid slides to a stop and the
		# pivot takes over from the planted pose (no half skid).
		if _state_time >= _skid_brake_duration():
			_begin_turn(1 if axis > 0.0 else -1)
			return
	elif not is_zero_approx(axis) or crouching:
		_enter_state(State.IDLE)
		_update_ground_move(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, _skid_deceleration * delta)
	velocity.y = 0.0
	if _try_launch_jump():
		return
	if _state_time >= _skid_brake_duration() + skid_hold_time:
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
	_jump_buffer_left = jump_buffer_time + _landing_cancel_remaining()
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
		State.ATTACK, State.AIR_ATTACK, State.CROUCH_ATTACK, State.UP_ATTACK, State.DASH, State.WALL_CLING, State.HURT:
			# One buffer slot, refreshed by every press: mashing can never queue
			# more than one attack, and it fires at the cancel point.
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


static func _phase_total(phases: Vector2) -> float:
	return phases.x + phases.y


## One hitbox phase of an attack: which hitbox rectangle is live, which slash
## stroke is cast with it, how long the phase lasts and whether it stays where
## the attack started (the finisher) instead of travelling with her.
func _segment(
	attack_name: StringName, rect: Rect2, shape: StringName, time: float,
	stroke_time := -1.0, anchored := false
) -> Dictionary:
	return {
		"name": attack_name, "rect": rect, "shape": shape, "time": time,
		"stroke": time if stroke_time < 0.0 else stroke_time, "anchored": anchored,
	}


## Hitbox segments of a ground combo hit (index 0..2): always exactly one.
func get_ground_segments(index: int) -> Array:
	match index:
		0:
			return [_segment(&"attack_ground_1", hitbox_hit1, &"attack_1", attack_hit1_phases.x)]
		1:
			return [_segment(&"attack_ground_2", hitbox_hit2, &"attack_2", attack_hit2_phases.x)]
		_:
			return [_segment(&"attack_ground_3", hitbox_hit3, &"attack_3", attack_hit3_phases.x, -1.0, true)]


func get_crouch_segments() -> Array:
	return [_segment(&"attack_crouch", hitbox_crouch, &"crouch_attack", crouch_attack_phases.x)]


func get_up_segments() -> Array:
	return [_segment(&"attack_up", hitbox_up, &"up_attack", up_attack_phases.x)]


func get_air_segments() -> Array:
	return [_segment(&"attack_air", hitbox_air, &"air_attack", air_attack_phases.x)]


func get_ground_phases(index: int) -> Vector2:
	match index:
		0:
			return attack_hit1_phases
		1:
			return attack_hit2_phases
		_:
			return attack_hit3_phases


## Windup of a ground hit: hit 1 from rest is longer than a chained one.
func get_ground_startup(index: int, chained: bool) -> float:
	if index >= 2:
		return attack_finisher_startup_time
	if index == 1 or chained:
		return attack_chain_startup_time
	return attack_startup_time


## Moves through the windup, the active segments and the recovery of the
## current attack from `_state_time`, switching the hitbox and slash on every
## segment change.
func _apply_attack_segments(segments: Array, startup: float) -> void:
	var index := -1
	if _state_time >= startup:
		index = segments.size()
		var cursor := startup
		for i in segments.size():
			cursor += float(segments[i]["time"])
			if _state_time < cursor:
				index = i
				break
	if index == _attack_segment:
		return
	_attack_segment = index
	if index < 0:
		_attack_phase = PHASE_STARTUP
	elif index >= segments.size():
		_attack_phase = PHASE_RECOVERY
		_deactivate_attack_hitbox()
	else:
		_attack_phase = PHASE_ACTIVE
		_enter_attack_segment(segments[index])


func _enter_attack_segment(segment: Dictionary) -> void:
	var rect: Rect2 = segment["rect"]
	_attack_segment_rect = rect
	_attack_segment_anchored = segment["anchored"]
	_place_attack_hitbox()
	_attack_hitbox.activate(segment["name"])
	if segment["shape"] != &"" and float(segment["stroke"]) > 0.0:
		_slash_vfx.play_slash(segment["shape"], _attack_facing, PlayerSlashVfx.slash_time(segment["shape"], float(segment["time"])))


## Puts the live hitbox on the segment rectangle. An anchored segment keeps
## its world position while she lunges.
func _place_attack_hitbox() -> void:
	var center := _attack_segment_rect.get_center()
	var x := center.x * float(_attack_facing)
	if _attack_segment_anchored:
		x -= global_position.x - _attack_origin.x
	_attack_hitbox.configure(_attack_segment_rect.size, Vector2(x, center.y))


func _reset_attack_progress(startup: float) -> void:
	_attack_animation_restart = true
	_attack_segment = -1
	_attack_phase = PHASE_STARTUP
	_attack_startup_current = startup
	_attack_origin = global_position
	_attack_segment_anchored = false
	_deactivate_attack_hitbox()


## -- Combat: ground combo -----------------------------------------------------

## Starts the combo. A fresh press continues a combo whose last hit landed
## within attack_chain_window, otherwise it starts at hit 1 from rest.
func _start_ground_attack(index := -1, chained := false) -> void:
	if index < 0:
		var resumes := _chain_time_left > 0.0
		index = _chain_next_index if resumes else 0
		chained = resumes
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.ATTACK)
	_begin_ground_hit(index, chained)


func _begin_ground_hit(index: int, chained: bool) -> void:
	_attack_combo_index = index
	_attack_chained = chained
	_attack_landed = false
	_chain_time_left = 0.0
	_state_time = 0.0
	_reset_attack_progress(get_ground_startup(index, chained))


func _update_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
		velocity.y = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
		_apply_gravity(delta)

	var phases := get_ground_phases(_attack_combo_index)
	_apply_attack_segments(get_ground_segments(_attack_combo_index), _attack_startup_current)
	if _attack_combo_index >= 2 and is_on_floor():
		_apply_lunge(delta)
	if _attack_segment_anchored and _attack_phase == PHASE_ACTIVE:
		_place_attack_hitbox()
	if _attack_phase == PHASE_RECOVERY and _try_launch_jump():
		return

	if _state_time >= _attack_startup_current + _phase_total(phases):
		if _attack_buffer_left > 0.0:
			_attack_buffer_left = 0.0
			if _attack_combo_index < 2:
				# Only a landed hit lets the combo advance; a whiff repeats hit 1.
				_begin_ground_hit(_attack_combo_index + 1 if _attack_landed else 0, true)
			else:
				_begin_ground_hit(0, true)
		else:
			_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


## Finisher lunge: forward by attack_lunge_distance over attack_lunge_time from
## the first active frame, then back to where she started. Nothing is pushed.
func _apply_lunge(delta: float) -> void:
	var since := _state_time - _attack_startup_current
	if since < 0.0:
		return
	var facing := float(_attack_facing)
	if since < attack_lunge_time:
		velocity.x = facing * attack_lunge_distance / maxf(attack_lunge_time, 0.001)
		return
	var advanced := (global_position.x - _attack_origin.x) * facing
	if advanced <= 0.5:
		return
	var speed := minf(attack_lunge_distance / maxf(attack_lunge_return_time, 0.001), advanced / maxf(delta, 0.001))
	velocity.x = -facing * speed


## -- Combat: crouch attack -----------------------------------------------------

func _start_crouch_attack() -> void:
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.CROUCH_ATTACK)
	_reset_attack_progress(crouch_attack_startup_time)


func _update_crouch_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, run_deceleration * delta)
	velocity.y = 0.0

	_apply_attack_segments(get_crouch_segments(), crouch_attack_startup_time)
	if _state_time >= crouch_attack_startup_time + _phase_total(crouch_attack_phases):
		if Input.is_action_pressed(&"move_down") or not _has_standing_headroom():
			_enter_state(State.CROUCH)
		else:
			_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)


## -- Combat: up attack (ground or air) -----------------------------------------

func _start_up_attack() -> void:
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.UP_ATTACK)
	_reset_attack_progress(up_attack_startup_time)


func _update_up_attack(delta: float) -> void:
	if is_on_floor():
		velocity.x = 0.0
		velocity.y = 0.0
	else:
		var axis := _horizontal_input()
		velocity.x = move_toward(velocity.x, axis * air_max_speed, air_acceleration * delta)
		_apply_gravity(delta)

	_apply_attack_segments(get_up_segments(), up_attack_startup_time)
	if _state_time >= up_attack_startup_time + _phase_total(up_attack_phases):
		_end_generic_attack()


## -- Combat: air attack ---------------------------------------------------------

func _start_air_attack() -> void:
	_clear_pending_attack_buffer()
	_capture_attack_facing()
	_enter_state(State.AIR_ATTACK)
	_reset_attack_progress(air_attack_startup_time)


func _restart_air_attack() -> void:
	_state_time = 0.0
	_reset_attack_progress(air_attack_startup_time)


func _update_air_attack(delta: float) -> void:
	var axis := _horizontal_input()
	velocity.x = move_toward(velocity.x, axis * air_max_speed, air_acceleration * delta)
	_apply_gravity(delta)

	if is_on_floor():
		_deactivate_attack_hitbox()
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	_apply_attack_segments(get_air_segments(), air_attack_startup_time)
	if _state_time >= air_attack_startup_time + _phase_total(air_attack_phases):
		if _attack_buffer_left > 0.0:
			_attack_buffer_left = 0.0
			_restart_air_attack()
		else:
			_state = State.JUMP if velocity.y < 0.0 else State.FALL


## -- Combat: hits and feedback ---------------------------------------------------

## Deferred: the hitbox reports from inside a physics query flush, where
## changing areas, bodies or this state is forbidden.
func _on_attack_hit(target: Node2D, attack_name: StringName) -> void:
	_resolve_attack_hit.call_deferred(target, attack_name)


## Any target with a `receive_hit(damage, source_position, attack_name)` method
## can be struck (see Enemy). A landed slash freezes the exchange, jolts the
## camera and throws sparks; it never pushes her or the target.
func _resolve_attack_hit(target: Node2D, attack_name: StringName) -> void:
	if _dead or not is_instance_valid(target):
		return
	var struck := false
	if target.has_method(&"receive_hit"):
		struck = target.call(&"receive_hit", attack_damage, global_position, attack_name)
	if struck:
		_on_attack_landed(target, attack_name)
	if struck and target.is_in_group(Enemy.GROUP_ENEMIES):
		add_soul(soul_per_hit)


## Tier of a landed attack: 0..2 ground hits 1-3, 3 crouch/air, 4 up.
func _attack_tier(attack_name: StringName) -> int:
	match attack_name:
		&"attack_ground_1":
			return 0
		&"attack_ground_2":
			return 1
		&"attack_ground_3":
			return 2
		&"attack_up":
			return 4
		_:
			return 3


func get_hit_stop_for(tier: int) -> float:
	match tier:
		0:
			return attack_hit_stop_times.x
		1:
			return attack_hit_stop_times.y
		2:
			return attack_hit_stop_times.z
		_:
			return attack_other_hit_stop_time


func _on_attack_landed(target: Node2D, attack_name: StringName) -> void:
	var tier := _attack_tier(attack_name)
	if tier <= 2 and _state == State.ATTACK:
		_attack_landed = true
		if _attack_combo_index < 2:
			_chain_next_index = _attack_combo_index + 1
			_chain_time_left = attack_chain_window
	var stop := get_hit_stop_for(tier)
	if stop > 0.0:
		_hit_stop_left = maxf(_hit_stop_left, stop)
		_sprite.speed_scale = 0.0
		_slash_vfx.freeze(stop)
		if target.has_method(&"freeze"):
			target.call(&"freeze", stop)
	_spawn_hit_spark(target, tier, stop)
	_kick_cameras(tier)


func _spawn_hit_spark(target: Node2D, tier: int, stop: float) -> void:
	if hit_spark_scene == null:
		return
	var host := get_parent() as Node2D
	if host == null:
		host = get_tree().current_scene as Node2D
	if host == null:
		return
	var spark := hit_spark_scene.instantiate() as HitSpark
	if spark == null:
		return
	spark.direction = _attack_facing
	spark.intensity = (tier + 1) if tier <= 2 else 1
	host.add_child(spark)
	spark.global_position = target.global_position + Vector2(0.0, -hit_spark_height)
	spark.freeze(stop)


## Jolts whichever camera is current (the player Camera2D or the RoomCamera).
func _kick_cameras(tier: int) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or not camera.has_method(&"kick"):
		return
	var amplitude := attack_kick_other
	var hold := attack_kick_hold.x
	match tier:
		0:
			amplitude = attack_kick_hit1
		1:
			amplitude = attack_kick_hit2
			hold = attack_kick_hold.y
		2:
			amplitude = attack_kick_hit3
			hold = attack_kick_hold.z
		4:
			amplitude = attack_kick_up
	camera.call(&"kick", Vector2(amplitude.x * float(_attack_facing), amplitude.y), hold, attack_kick_decay)


func _deactivate_attack_hitbox() -> void:
	_attack_hitbox.deactivate()


## -- Airborne: jump / fall ----------------------------------------------------

func _update_airborne(delta: float) -> void:
	if _wall_kick_lock_left <= 0.0:
		_apply_air_horizontal_control(delta)

	_update_jump_release()
	_apply_gravity(delta)

	if not is_on_floor():
		if _try_start_wall_cling():
			return
		if _try_launch_jump() or _try_air_jump():
			return

	_state = State.JUMP if velocity.y < 0.0 else State.FALL


## Variable jump height: releasing the button while rising cuts the climb, but
## never before jump_min_hold_time (a tap still reaches the Penitent's ~0.85 of a
## full jump); an earlier release is applied once the minimum has elapsed.
func _update_jump_release() -> void:
	if velocity.y >= 0.0:
		_jump_cut_pending = false
		return
	if Input.is_action_just_released(&"jump"):
		_jump_cut_pending = true
	if _jump_cut_pending and _jump_min_hold_left <= 0.0:
		_jump_cut_pending = false
		velocity.y *= jump_release_multiplier


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
	if _landing_cancel_remaining() > 0.0:
		return false
	if is_on_floor():
		_spawn_dust(GroundDust.Kind.TAKEOFF)
	velocity.y = _jump_velocity
	_begin_jump_rise()
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
	_begin_jump_rise()
	_jump_buffer_left = 0.0
	_sfx_jump.play()
	_enter_state(State.JUMP)
	_restart_jump_animation()
	return true


## Starts the tap-minimum window of a ground or air jump (wall kicks keep their
## own fixed impulses, so they never wait).
func _begin_jump_rise() -> void:
	_jump_min_hold_left = jump_min_hold_time
	_jump_cut_pending = false


## Seconds until a jump press may cancel the standing landing recovery (0 when
## there is no recovery or it can already be cancelled).
func _landing_cancel_remaining() -> float:
	if _landing_left <= 0.0:
		return 0.0
	var elapsed := landing_squash_time - _landing_left
	return maxf(landing_jump_cancel_time - elapsed, 0.0)


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
	var carried := absf(velocity.x) if signf(velocity.x) == float(_dash_direction) else 0.0
	_dash_from_rest = not _dash_is_air and carried < run_max_speed * dash_rest_speed_ratio
	_dash_start_speed = 0.0 if _dash_from_rest else minf(carried, dash_speed)
	_dash_slide_started = false
	_afterimage_left = 0.0
	_enter_state(State.DASH)
	velocity.x = float(_dash_direction) * (dash_speed if _dash_is_air else _dash_start_speed)
	velocity.y = 0.0


## Seconds of lean-back before the slide moves (only when dashing from rest).
func _dash_startup() -> float:
	return dash_startup_time if _dash_from_rest else 0.0


## True from the first frame of the slide (after the lean-back).
func _dash_sliding() -> bool:
	return _state == State.DASH and not _dash_is_air and _state_time >= _dash_startup()


## Ground slide speed `t` seconds after the slide started: ramp, plateau, ease-out.
func _dash_speed_at(t: float) -> float:
	var ramp := maxf(dash_ramp_time, 0.001)
	var ease_time := maxf(dash_ease_time, 0.001)
	var ease_start := maxf(dash_duration - ease_time, ramp)
	if t < ramp:
		return lerpf(_dash_start_speed, dash_speed, t / ramp)
	if t < ease_start:
		return dash_speed
	return lerpf(dash_speed, dash_end_speed, clampf((t - ease_start) / ease_time, 0.0, 1.0))


func _update_dash(delta: float) -> void:
	if _dash_is_air:
		_update_air_dash(delta)
		return

	if not is_on_floor():
		_enter_state(State.FALL)
		_update_airborne(delta)
		return

	if Input.is_action_just_pressed(&"jump") and _try_launch_jump():
		return

	velocity.y = 0.0
	var slide_t := _state_time - _dash_startup()
	if slide_t < 0.0:
		velocity.x = 0.0
		return
	if not _dash_slide_started:
		_dash_slide_started = true
		_spawn_dust(GroundDust.Kind.DASH_START)
	velocity.x = float(_dash_direction) * _dash_speed_at(slide_t)

	if slide_t >= dash_duration:
		_spawn_dust(GroundDust.Kind.DASH_END)
		if _has_standing_headroom():
			_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		else:
			_enter_state(State.CROUCH)


## Air dash: horizontal only, no gravity for its duration, standing collider
## kept (see _enter_state's low-collider check, which only lowers for a
## ground dash).
func _update_air_dash(_delta: float) -> void:
	if is_on_floor():
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
		return

	velocity.x = float(_dash_direction) * dash_speed
	velocity.y = 0.0

	if Input.is_action_just_pressed(&"jump") and _try_launch_jump():
		return

	if _state_time >= air_dash_duration:
		_enter_state(State.JUMP if velocity.y < 0.0 else State.FALL)


## One translucent copy of the current pose every afterimage_interval while she
## slides or air dashes, added right behind her in the same parent.
func _update_afterimages(delta: float) -> void:
	var dashing := _state == State.DASH and (_dash_is_air or _dash_sliding())
	if not dashing or dash_afterimage_scene == null:
		_afterimage_left = 0.0
		return
	_afterimage_left -= delta
	if _afterimage_left > 0.0:
		return
	_afterimage_left += afterimage_interval
	var host := get_parent() as Node2D
	var ghost := dash_afterimage_scene.instantiate() as DashAfterimage
	if host == null or ghost == null:
		if ghost != null:
			ghost.free()
		return
	var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	host.add_child(ghost)
	host.move_child(ghost, get_index())
	ghost.setup(_sprite, texture)


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
		_jump_min_hold_left = 0.0
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
	if new_state != State.IDLE and new_state != State.RUN:
		_landing_left = 0.0
	_run_time = 0.0
	_release_time = 0.0
	if not _is_directional_attack_state():
		_slash_vfx.stop_slash()

	if previous == State.DASH and new_state != State.DASH:
		_dash_cooldown_left = dash_cooldown
		_dash_grace_left = dash_invulnerable_grace

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


## True during the whole dash (and its grace): non-hazard hits are ignored.
func is_dash_invulnerable() -> bool:
	return dash_invulnerable and (_state == State.DASH or _dash_grace_left > 0.0)


func _apply_damage(amount: int, source_position: Vector2, hazard: bool, force := false) -> bool:
	if amount <= 0 or _dead:
		return false
	if not hazard and not force and is_dash_invulnerable():
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
	_attack_combo_index = 0
	_attack_buffer_left = 0.0
	_jump_buffer_left = 0.0
	_wall_jump_lock_left = 0.0
	_wall_kick_lock_left = 0.0
	_restore_air_actions()


func _update_damage_timers(delta: float) -> void:
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	_dash_grace_left = maxf(_dash_grace_left - delta, 0.0)
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
	_attack_buffer_left = 0.0
	_attack_buffer_direction = 0
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
	_attack_buffer_left = 0.0
	_attack_buffer_direction = 0
	_clear_damage_state()
	_set_collider_height(_standing_shape_height)
	_deactivate_attack_hitbox()
	_enter_state(State.IDLE)


func _clear_damage_state() -> void:
	_dash_grace_left = 0.0
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
	var landed := not _was_on_floor and is_on_floor()
	if landed and fall_speed_before_move > landing_impact_speed:
		_sfx_land.play()
		_spawn_dust(GroundDust.Kind.LANDING)
	if landed:
		_restore_air_actions()
	if is_on_floor() and (_state == State.JUMP or _state == State.FALL):
		_enter_state(State.RUN if absf(velocity.x) > 5.0 else State.IDLE)
	if landed and _is_hard_standing_landing(fall_speed_before_move):
		# Standing landing: planted for the recovery. A running landing keeps running.
		_landing_left = landing_squash_time
		velocity.x = 0.0
	_was_on_floor = is_on_floor()


func _is_hard_standing_landing(fall_speed: float) -> bool:
	if fall_speed < hard_landing_speed or _state == State.HURT:
		return false
	return absf(velocity.x) < run_max_speed * landing_run_speed_ratio


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
	var instance := ground_dust_scene.instantiate()
	var dust := instance as GroundDust
	if dust == null:
		# Not a GroundDust root: free the instance so it does not leak.
		instance.free()
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
			# Braking frames first; the hold part is the real idle (the skid sheet's
			# standing slots drew a puffier, darker hair than the idle).
			_play_animation(&"skid" if _state_time < _skid_brake_duration() else &"idle")
		State.DASH:
			if _dash_is_air:
				_play_animation(&"air_dash")
			else:
				# Frozen on the first pose during the lean-back, then it plays.
				_play_animation(&"ground_dash", 1.0 if _dash_sliding() else 0.0)
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
			# A chained hit 1 has a shorter windup than the clip was timed for.
			var windup_speed := 1.0
			if _attack_combo_index == 0 and _attack_chained and _attack_phase == PHASE_STARTUP:
				windup_speed = attack_startup_time / maxf(attack_chain_startup_time, 0.001)
			_play_attack_animation(attack_animation, windup_speed)
		State.CROUCH_ATTACK:
			_play_attack_animation(&"crouch_attack")
		State.UP_ATTACK:
			_play_attack_animation(&"up_attack")
		State.AIR_ATTACK:
			_play_attack_animation(&"air_attack")
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


## Plays an attack clip, replaying it from its first frame whenever a new attack
## (or a repeat of the same one) has just started.
func _play_attack_animation(animation_name: StringName, speed_scale := 1.0) -> void:
	if _attack_animation_restart:
		_attack_animation_restart = false
		_sprite.play(animation_name)
		_sprite.set_frame_and_progress(0, 0.0)
	_play_animation(animation_name, speed_scale)


## Clip-local speed: always reassigns speed_scale, even if the animation
## itself did not change, so a prior action's speed can never leak forward.
func _play_animation(animation_name: StringName, speed_scale := 1.0) -> void:
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)
	_sprite.speed_scale = speed_scale

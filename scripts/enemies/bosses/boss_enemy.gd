@tool
class_name BossEnemy
extends Enemy

## Reusable base of the arena bosses. It owns what every boss does the same way
## (the contract a BossArena expects, engage gating, the telegraph / active /
## recover attack lifecycle, multi-phase thresholds, stagger and stun, the final
## blow, the corpse, the reset, audio cues, projectile pooling) and leaves the
## attacks and the movement to subclasses.
##
## State machine: IDLE (waiting for the arena) -> FIGHT (movement between attacks)
## -> ATTACK (TELEGRAPH -> ACTIVE -> RECOVER) -> FIGHT ..., with FLINCH, STAGGER,
## STUN (interrupt anything), TRANSITION (the phase beat) and DEFEATED.
##
## Writing a boss: declare an `enum` of attacks (the base only knows `int` ids),
## then override the hooks you need. Nothing here has to be overridden wholesale:
##   - `_choose_next_action()` picks an attack when the fight delay elapses (use
##     `_draw_attack(weights)` for a weighted draw that skips the last attack).
##   - `_update_fight(delta)` moves the boss between attacks; `_tick(delta)` runs
##     every physics frame in any state (a beat clock, a noise meter).
##   - `_telegraph_time`, `_active_time`, `_recover_time` give the durations of an
##     attack (the telegraph is never shorter than MIN_TELEGRAPH).
##   - `_begin_attack_phase`, `_update_attack_phase` and `_end_attack_phase` run
##     the attack itself; `_end_attack_phase` also runs when the attack is cut
##     short (interrupt, stagger, stun, transition, defeat), so cleanup lives there.
##   - Phases come from `phase_thresholds`, or from the subclass's own events with
##     `phases_from_health` off and `_advance_phase()` / `_enter_phase(n)`.
##   - Multi-part bosses: hurtbox children forward `receive_hit` to the boss; return 0
##     from `_root_layer()` when the root itself must not be hit.
##   - `_on_phase_entered`, `_on_transition_started`, `_on_stunned`,
##     `_clear_hazards` and `_accepts_hit` cover phases, punish windows and reset.
## Timers are accumulated in physics time inside `_think`, so the base hit-stop
## pauses them. `receive_hit` and the arena-facing methods are final in spirit:
## override them only to add behavior and call `super`.
##
## Placeholder visuals only: the silhouette is a polygon under `Visual/Body`.

signal phase_changed(phase: int)
signal defeated
## A hit cancelled a telegraph. `attack` is the attack that was winding up.
signal attack_interrupted(attack: int)
## The defeat collapse finished and the corpse lies still at its final position.
signal corpse_settled
## A sound cue fired. `cue` is the node name under `Sfx`, fired even when its
## stream is empty, so tools and tests can follow the events.
signal sfx_cue(cue: StringName)

enum State { IDLE, FIGHT, ATTACK, FLINCH, STAGGER, STUN, TRANSITION, DEFEATED }
enum AttackPhase { TELEGRAPH, ACTIVE, RECOVER }

const NO_ATTACK := -1
## No telegraph is shorter than this: it must be readable on a phone.
const MIN_TELEGRAPH := 0.35
const FIRST_PHASE := 1
## What `phase_two_threshold` reads when the boss has a single phase.
const NO_THRESHOLD := -1.0
const NEVER := -1.0e9
const PLAYER_CENTER_OFFSET := Vector2(0.0, -29.0)
const STAGGER_TINT := Color(0.72, 0.75, 0.95)
const STUN_TINT := Color(1.0, 0.85, 0.45)
const FLINCH_TINT := Color(1.0, 0.55, 0.55)
## Radians per second of the flinch shake.
const FLINCH_SHAKE_RATE := 90.0
## Beat pulse of the transition glow, radians per second.
const TRANSITION_PULSE_RATE := 10.0
## Forward slump (radians) and squash of the corpse pose.
const CORPSE_TILT := 0.45
const CORPSE_SQUASH_Y := 0.6
const FLASH_FADE_IN := 0.04
const CUE_INTRO := &"Intro"
const CUE_PHASE_CHANGE := &"PhaseChange"
const CUE_STUN := &"Stun"
const CUE_FLINCH := &"Flinch"
const CUE_STAGGER := &"Stagger"
const CUE_DEFEAT := &"Defeat"

@export_group("Movement")
## Luz farther than this (in sight) wakes the boss when no arena drives it.
@export var wake_distance := 640.0
## Seconds an awake boss waits before its first move (and after a reset).
@export var opening_delay := 0.6
## Fallback half width of the arena when no arena limits were fed.
@export var arena_half_width := 400.0

@export_group("Pacing")
## Seconds spent moving between two attacks, drawn from this range.
@export var fight_delay_min := 0.6
@export var fight_delay_max := 1.2

@export_group("Phases")
## Health ratios (descending) where a new phase starts, for example [0.66, 0.33]
## gives three phases. Empty: one phase. The arena draws a notch for each.
@export var phase_thresholds := PackedFloat32Array()
## Off: health never changes the phase; the subclass calls `_advance_phase()` or
## `_enter_phase()` from its own events (a head dies). The thresholds still
## feed the bar notches.
@export var phases_from_health := true
## The beat when a phase starts: the boss glows and does not attack, but can be hit.
@export var phase_transition_time := 1.0

@export_group("Stagger")
## This many hits inside `stagger_window` seconds stagger the boss (0 disables it).
@export var stagger_hits := 0
@export var stagger_window := 2.5
@export var stagger_time := 1.5

@export_group("Interrupt")
## Super armor: a hit during a telegraph never cancels it. Turn it off to let a
## hit cancel the wind-up (the boss flinches and then goes back to the fight).
@export var super_armor := true
@export var interrupt_flinch_time := 0.25
## After an interrupt the telegraphs hold firm for this long (poise).
@export var interrupt_cooldown := 3.0
## Sideways shake of the flinch, in pixels.
@export var interrupt_shake := 3.0

@export_group("Defeat")
## Seconds the boss takes to slump into the corpse pose after the killing blow.
@export var defeat_time := 0.9

@export_group("Final Blow")
## Real seconds the whole world freezes on the killing blow (0 skips it).
@export var final_freeze_time := 0.25
## Real seconds of slow motion after the freeze (0 skips it).
@export var final_slowmo_time := 0.5
@export_range(0.05, 1.0) var final_slowmo_scale := 0.3
## Peak opacity of the white screen flash (0 turns it off).
@export_range(0.0, 1.0) var final_flash_peak := 0.85
## Real seconds the flash takes to fade out.
@export var final_flash_time := 0.35
@export var final_shake_strength := 10.0
@export var final_shake_time := 0.7

@export_group("Camera Shakes")
## Strength is in pixels (the RoomCamera caps it at its `shake_max_strength`).
@export var phase_shake_strength := 5.0
@export var phase_shake_time := 0.6

@export_group("Randomness")
## 0 randomizes. Tests set `rng` directly or fix this seed.
@export var rng_seed := 0

## The arena reads this name for the bar notch: the first threshold, or
## NO_THRESHOLD (no notch) for a single-phase boss.
var phase_two_threshold: float:
	get:
		return phase_thresholds[0] if phase_thresholds.size() > 0 else NO_THRESHOLD

var rng := RandomNumberGenerator.new()

var _state := State.IDLE
var _state_left := 0.0
var _attack := NO_ATTACK
var _last_attack := NO_ATTACK
var _attack_phase := AttackPhase.TELEGRAPH
var _attack_open := false
var _phase := FIRST_PHASE
var _clock := 0.0
var _half_width := 13.0
var _luz: Player
var _manual_engage := false
var _engaged := false
var _intro_left := 0.0
var _has_arena_limits := false
var _arena_left := 0.0
var _arena_right := 0.0
var _transition_pending := false
var _interrupt_left := 0.0
var _hittable := true
var _defeat_left := 0.0
var _play_defeat := false
var _hit_ring := PackedFloat32Array()
var _ring_index := 0
var _cues: Dictionary = {}
var _projectile_pools: Dictionary = {}
var _hit_areas: Dictionary = {}

@onready var _telegraph: BossTelegraph = get_node_or_null("Telegraph") as BossTelegraph
@onready var _flash_layer: ScreenFlash = get_node_or_null("FinalFlash") as ScreenFlash
@onready var _sfx: Node = get_node_or_null("Sfx")


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is RectangleShape2D:
		_half_width = (body.shape as RectangleShape2D).size.x * 0.5
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed
	var silhouette := get_node_or_null("Visual/Body") as Polygon2D
	if _telegraph != null and silhouette != null:
		_telegraph.bind_body(silhouette)
	if _sfx != null:
		for cue: Node in _sfx.get_children():
			_cues[cue.name] = cue
	_reset_hit_ring()
	if _dead:
		_enter_state(State.DEFEATED)
	else:
		_set_hittable(true)
		_enter_state(State.IDLE, opening_delay)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_clock += delta
	_intro_left = maxf(_intro_left - delta, 0.0)
	super._physics_process(delta)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Untyped: a pooled projectile may already be freed with its new parent.
	for pool: Array in _projectile_pools.values():
		for projectile in pool:
			if is_instance_valid(projectile) and projectile.get_parent() != self and not projectile.is_queued_for_deletion():
				projectile.queue_free()


## -- Public API (the arena contract) -----------------------------------------

func get_state() -> State:
	return _state


func get_attack_phase() -> AttackPhase:
	return _attack_phase


func get_phase() -> int:
	return _phase


## The attack in progress (or the last one), NO_ATTACK before the first.
func get_attack() -> int:
	return _attack


func get_state_time_left() -> float:
	return _state_left


func get_telegraph() -> BossTelegraph:
	return _telegraph


func get_luz() -> Player:
	return _luz


func is_telegraphing() -> bool:
	return _state == State.ATTACK and _attack_phase == AttackPhase.TELEGRAPH


func is_stunned() -> bool:
	return _state == State.STUN


func is_intro_playing() -> bool:
	return _intro_left > 0.0


## An arena feeds the boss its real left and right wall x, so `_arena_bounds`
## and `_clamp_to_arena` use them instead of the fallback around the boss.
func set_arena_limits(left_x: float, right_x: float) -> void:
	_has_arena_limits = true
	_arena_left = minf(left_x, right_x)
	_arena_right = maxf(left_x, right_x)


func clear_arena_limits() -> void:
	_has_arena_limits = false


## True: the boss stays idle until `engage()` (or a hit) and ignores `wake_distance`.
func set_manual_engage(enabled: bool) -> void:
	_manual_engage = enabled
	_engaged = false


## Under manual engage the boss is untouchable until the arena wakes it; once
## engaged it stays hittable, whatever state it is in, until a reset.
func _awaiting_arena() -> bool:
	return _manual_engage and not _engaged


## Idle at full health in phase one: nothing to reset.
func is_fresh() -> bool:
	return _state == State.IDLE and _phase == FIRST_PHASE and _health == max_health


## Marks the arena-entry reveal over `duration` seconds while the boss waits in
## IDLE (the arena calls it when the fight starts, with its engage delay). Never
## for a corpse. Timers and behavior are untouched; `_on_intro` is the art hook.
func play_intro(duration: float) -> void:
	if _dead or _state != State.IDLE or duration <= 0.0:
		return
	_intro_left = duration
	play_cue(CUE_INTRO)
	_on_intro(duration)


## Leaves IDLE for the fight without waiting for Luz to come close.
func engage() -> void:
	_intro_left = 0.0
	_engaged = true
	if _state == State.IDLE and not _dead:
		_begin_fight()


## Starts `attack` from any state except defeat. Used by the fight loop and tests.
func start_attack(attack: int) -> void:
	if _dead:
		return
	_close_attack_phase()
	_attack = attack
	_last_attack = attack
	_enter_state(State.ATTACK)
	_set_attack_phase(AttackPhase.TELEGRAPH)


## Stuns the boss for `duration` seconds: whatever it was doing is cut short, it
## stays hittable and goes back to the fight afterwards. For punish windows owned
## by the subclass (overheat, wall crash). Returns false when it cannot apply
## (a corpse, still awaiting the arena, or during the phase beat).
func stun(duration: float) -> bool:
	if _dead or duration <= 0.0 or _state == State.IDLE or _state == State.TRANSITION:
		return false
	if _state == State.STUN:
		_state_left = maxf(_state_left, duration)
		return true
	_chain_cleanup()
	velocity.x = 0.0
	_enter_state(State.STUN, duration)
	play_cue(CUE_STUN)
	_on_stunned(duration)
	return true


func clear_projectiles() -> void:
	for pool: Array in _projectile_pools.values():
		for projectile: EnemyProjectile in pool:
			projectile.deactivate()


func active_projectile_count() -> int:
	return get_active_projectiles().size()


func get_active_projectiles() -> Array[EnemyProjectile]:
	var active: Array[EnemyProjectile] = []
	for pool: Array in _projectile_pools.values():
		for projectile: EnemyProjectile in pool:
			if projectile.is_active():
				active.append(projectile)
	return active


func set_ai_active(active: bool) -> void:
	super.set_ai_active(active)
	if not active:
		clear_projectiles()
		_clear_hazards()


## Registers the hit, then checks the phase thresholds and the stagger window.
## A killing blow plays the final-blow moment, then the boss slumps into a corpse.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if not _hittable or _awaiting_arena() or not _accepts_hit(damage, source_position):
		return false
	_play_defeat = not _dead and damage > 0 and _health - damage <= 0
	var landed := super.receive_hit(damage, source_position, attack_name)
	_play_defeat = false
	if not landed:
		return false
	if _dead:
		_play_final_blow()
		defeated.emit()
		return true
	engage()
	_check_phases()
	_register_stagger_hit()
	_try_transition()
	_try_interrupt()
	return true


## Defeat: a fresh kill slumps over `defeat_time`; a corpse restored by the
## registry or the arena (the boss was beaten earlier) lies there at once. Either
## way it stays, dimmed, harmless and out of every hit and reset.
func make_corpse_at(at: Vector2, facing: int) -> void:
	# The registry restores a corpse while the base `_ready` is still running:
	# `_ready` finishes the job then.
	if is_node_ready():
		_close_attack_phase()
		_clear_telegraph()
		clear_projectiles()
		_clear_hazards()
	super.make_corpse_at(at, facing)
	_defeat_left = defeat_time if _play_defeat else 0.0
	if is_node_ready():
		_enter_state(State.DEFEATED)


## -- Hooks for bosses -----------------------------------------------------------

## Runs every physics frame in every state of a living boss, before anything else
## (Luz may be missing). For clocks and meters that must never pause.
func _tick(_delta: float) -> void:
	pass


## Moves the boss between attacks (sets `velocity.x`). May call `start_attack`.
func _update_fight(_delta: float) -> void:
	velocity.x = 0.0


## When the fight delay elapses: the attack id to start, or NO_ATTACK to keep
## moving for another `_fight_delay()`.
func _choose_next_action() -> int:
	return NO_ATTACK


## Seconds of movement before the next `_choose_next_action()`.
func _fight_delay() -> float:
	return rng.randf_range(minf(fight_delay_min, fight_delay_max), maxf(fight_delay_min, fight_delay_max))


## Durations of an attack. The telegraph is raised to MIN_TELEGRAPH if shorter.
func _telegraph_time(_attack_id: int) -> float:
	return 0.6


func _active_time(_attack_id: int) -> float:
	return 0.1


func _recover_time(_attack_id: int) -> float:
	return 0.5


## Called once as `phase` of `attack` begins, after its timer was set (arm a
## hitbox, plan a marker, launch a projectile).
func _begin_attack_phase(_attack_id: int, _phase_id: AttackPhase) -> void:
	pass


## Called every frame of an attack phase, after `velocity.x` was zeroed (set it
## here for an attack that moves). It may call `stun` or `start_attack`.
func _update_attack_phase(_attack_id: int, _phase_id: AttackPhase, _delta: float) -> void:
	pass


## Called once as `phase` of `attack` ends: when its timer elapses, and when the
## attack is cut short (interrupt, stagger, stun, transition, defeat, reset).
func _end_attack_phase(_attack_id: int, _phase_id: AttackPhase) -> void:
	pass


## A new phase was reached (2 and up), at the moment the threshold is crossed. The
## transition beat starts later, as soon as the boss is not mid-strike.
func _on_phase_entered(_phase_id: int) -> void:
	pass


## The beat of `phase` just started (the boss is idle and glowing for
## `phase_transition_time`).
func _on_transition_started(_phase_id: int) -> void:
	pass


## `stun` was applied (the attack was already cut short): clear what the
## subclass left in the world.
func _on_stunned(_duration: float) -> void:
	pass


## The stun timer ran out, right before the boss returns to the fight.
func _on_stun_ended() -> void:
	pass


## Remove every hazard of the subclass (hitboxes, markers, pillars of fire). Runs
## on defeat, on reset and when the AI is switched off. It may run while the base
## `_ready` is still finishing, so touch only nodes that already exist.
func _clear_hazards() -> void:
	pass


## False refuses a hit (it returns false to the attacker and changes nothing).
func _accepts_hit(_damage: int, _source_position: Vector2) -> bool:
	return true


## The arena reveal started (`play_intro`): the art hook.
func _on_intro(_duration: float) -> void:
	pass


## Where the boss looks while it is idle, fighting, flinching or in a transition.
## Override to keep a facing (or to never turn).
func _update_facing() -> void:
	if _state == State.IDLE or _state == State.FIGHT or _state == State.FLINCH or _state == State.TRANSITION:
		_face_luz()


func _reset_ai() -> void:
	if not is_node_ready():
		return
	var previous_phase := _phase
	_close_attack_phase()
	_phase = FIRST_PHASE
	_transition_pending = false
	_attack = NO_ATTACK
	_last_attack = NO_ATTACK
	_interrupt_left = 0.0
	_defeat_left = 0.0
	_play_defeat = false
	_engaged = false
	_intro_left = 0.0
	_hit_areas.clear()
	visible = true
	# A settled corpse switches its processing off: a checkpoint must revive it.
	set_physics_process(true)
	if _visual != null:
		_visual.position = Vector2.ZERO
		_visual.rotation = 0.0
		_visual.z_index = 0
		_visual.modulate = Color.WHITE
		_visual.scale = Vector2(float(_facing), 1.0)
	_clear_telegraph()
	clear_projectiles()
	_hittable = true
	_set_hittable(true)
	_set_contact(true)
	_reset_hit_ring()
	_clear_hazards()
	_enter_state(State.IDLE, opening_delay)
	if previous_phase > FIRST_PHASE:
		phase_changed.emit(FIRST_PHASE)


func _on_player_found(player: Node) -> void:
	_luz = player as Player


## Bosses are never pushed: a hit must not freeze their timers either.
func _start_recoil(_source_position: Vector2) -> void:
	pass


func _apply_visual() -> void:
	if _visual == null:
		return
	_visual.scale = Vector2(float(_facing), 1.0)
	_visual.z_index = 0
	if _dead or _state == State.DEFEATED:
		_pose_corpse(_defeat_progress())
		return
	match _state:
		State.STAGGER:
			_visual.modulate = STAGGER_TINT
		State.STUN:
			_visual.modulate = STUN_TINT
		State.FLINCH:
			_visual.modulate = FLINCH_TINT
		_:
			_visual.modulate = Color.WHITE


## Slumps while `_defeat_left` runs down, then rests once on the floor (a kill in
## mid-air falls first) and stops processing.
func _update_corpse(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	_defeat_left = maxf(_defeat_left - delta, 0.0)
	_apply_visual()
	if _defeat_left <= 0.0 and is_on_floor():
		_settle_corpse()


## -- State machine --------------------------------------------------------------

func _think(delta: float) -> void:
	_tick(delta)
	_interrupt_left = maxf(_interrupt_left - delta, 0.0)
	if _luz == null or not is_instance_valid(_luz):
		velocity.x = 0.0
		return
	_update_facing()
	_try_transition()
	match _state:
		State.IDLE:
			_update_idle(delta)
		State.FIGHT:
			_update_fight_state(delta)
		State.ATTACK:
			_update_attack(delta)
		State.FLINCH:
			_update_flinch(delta)
		State.STAGGER:
			_update_stagger(delta)
		State.STUN:
			_update_stun(delta)
		State.TRANSITION:
			_update_transition(delta)


func _enter_state(state: State, duration := 0.0) -> void:
	_leave_state(state)
	_state = state
	_state_left = duration
	_apply_visual()


## Cleans up what the state we are leaving left behind.
func _leave_state(next: State) -> void:
	match _state:
		State.ATTACK:
			if next != State.ATTACK:
				_close_attack_phase()
				_clear_telegraph()
		State.TRANSITION:
			_clear_telegraph()
		State.FLINCH:
			if _visual != null:
				_visual.position.x = 0.0


func _begin_fight() -> void:
	_enter_state(State.FIGHT, _fight_delay())


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	if _manual_engage or _luz_distance() > wake_distance:
		return
	_state_left -= delta
	if _state_left <= 0.0:
		engage()


func _update_fight_state(delta: float) -> void:
	_update_fight(delta)
	if _state != State.FIGHT:
		return
	_state_left -= delta
	if _state_left > 0.0:
		return
	var next := _choose_next_action()
	if next == NO_ATTACK:
		_state_left = _fight_delay()
		return
	start_attack(next)


## -- Attack lifecycle ---------------------------------------------------------------

func _update_attack(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	var phase := _attack_phase
	_update_attack_phase(_attack, phase, delta)
	if _state != State.ATTACK or _attack_phase != phase:
		return
	if _state_left > 0.0:
		return
	match phase:
		AttackPhase.TELEGRAPH:
			_set_attack_phase(AttackPhase.ACTIVE)
		AttackPhase.ACTIVE:
			_set_attack_phase(AttackPhase.RECOVER)
		AttackPhase.RECOVER:
			_close_attack_phase()
			_begin_fight()


func _set_attack_phase(attack_phase: AttackPhase) -> void:
	_close_attack_phase()
	_attack_phase = attack_phase
	_attack_open = true
	match attack_phase:
		AttackPhase.TELEGRAPH:
			_state_left = maxf(_telegraph_time(_attack), MIN_TELEGRAPH)
			velocity.x = 0.0
		AttackPhase.ACTIVE:
			_state_left = _active_time(_attack)
			_clear_telegraph()
		AttackPhase.RECOVER:
			_state_left = _recover_time(_attack)
	_begin_attack_phase(_attack, attack_phase)


## Ends the open phase once (the subclass hook runs exactly once per phase).
func _close_attack_phase() -> void:
	if not _attack_open:
		return
	_attack_open = false
	_end_attack_phase(_attack, _attack_phase)


## Cuts the current attack short for a stun: the phase hook runs via `_enter_state`.
func _chain_cleanup() -> void:
	_clear_telegraph()


## A weighted draw from `weights` (one entry per attack id, in enum order) that
## skips the attack used last. When that leaves nothing, a repeat is allowed;
## NO_ATTACK when every weight is zero. Draws from `rng` only when it can pick.
func _draw_attack(weights: PackedFloat32Array) -> int:
	var total := _weight_total(weights, _last_attack)
	var excluded := _last_attack
	if total <= 0.0:
		excluded = NO_ATTACK
		total = _weight_total(weights, excluded)
	if total <= 0.0:
		return NO_ATTACK
	var roll := rng.randf() * total
	for i: int in weights.size():
		roll -= _weight_of(weights, i, excluded)
		if roll < 0.0:
			return i
	return NO_ATTACK


func _weight_total(weights: PackedFloat32Array, excluded: int) -> float:
	var total := 0.0
	for i: int in weights.size():
		total += _weight_of(weights, i, excluded)
	return total


func _weight_of(weights: PackedFloat32Array, index: int, excluded: int) -> float:
	if index == excluded or index >= weights.size():
		return 0.0
	return maxf(weights[index], 0.0)


## -- Interrupt, stagger, stun ---------------------------------------------------------

## Only the wind-up can be cancelled: once the strike left (ACTIVE, RECOVER) a hit
## is just damage. Stagger and the phase beat win because they change the state
## before this runs.
func _is_interruptible() -> bool:
	return not super_armor and _interrupt_left <= 0.0 and not _dead and is_telegraphing()


func _try_interrupt() -> void:
	if not _is_interruptible():
		return
	var interrupted := _attack
	_interrupt_left = interrupt_cooldown
	velocity.x = 0.0
	_enter_state(State.FLINCH, interrupt_flinch_time)
	play_cue(CUE_FLINCH)
	attack_interrupted.emit(interrupted)


func _update_flinch(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	if _visual != null:
		_visual.position.x = sin(_clock * FLINCH_SHAKE_RATE) * interrupt_shake
	if _state_left <= 0.0:
		_begin_fight()


func _register_stagger_hit() -> void:
	if _state == State.STAGGER or _state == State.STUN or stagger_hits <= 0:
		return
	if _hit_ring.size() != stagger_hits:
		_reset_hit_ring()
	_hit_ring[_ring_index] = _clock
	_ring_index = (_ring_index + 1) % stagger_hits
	# The slot about to be overwritten holds the oldest of the last N hits.
	if _clock - _hit_ring[_ring_index] <= stagger_window:
		_enter_stagger()


func _enter_stagger() -> void:
	_reset_hit_ring()
	velocity.x = 0.0
	_enter_state(State.STAGGER, stagger_time)
	play_cue(CUE_STAGGER)


func _update_stagger(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	if _state_left <= 0.0:
		_reset_hit_ring()
		_begin_fight()


func _update_stun(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	if _state_left <= 0.0:
		_on_stun_ended()
		if _state == State.STUN:
			_begin_fight()


func _reset_hit_ring() -> void:
	_hit_ring.resize(maxi(stagger_hits, 1))
	_hit_ring.fill(NEVER)
	_ring_index = 0


## -- Phases -------------------------------------------------------------------------------

## Every threshold crossed since the last check starts a phase (one big hit can
## cross several). Each emits `phase_changed` once and queues the transition beat.
func _check_phases() -> void:
	if not phases_from_health:
		return
	while _phase - FIRST_PHASE < phase_thresholds.size():
		var threshold := phase_thresholds[_phase - FIRST_PHASE]
		if float(_health) > float(max_health) * threshold:
			return
		_advance_phase()


## The phase change of a threshold crossing, for event-driven phases: moves to the
## next phase (see `_enter_phase`). A corpse never changes phase.
func _advance_phase() -> void:
	_enter_phase(_phase + 1)


## Sets `phase` (2 and up; lower or equal to the current one is ignored), emits
## `phase_changed`, queues the transition beat and calls `_on_phase_entered`.
func _enter_phase(phase: int) -> void:
	if _dead or phase <= _phase:
		return
	_phase = phase
	_transition_pending = true
	phase_changed.emit(_phase)
	_on_phase_entered(_phase)


## Starts the transition beat once, as soon as nothing is mid-strike. The boss
## stays hittable throughout; a stagger, a stun or an active attack only postpone it.
func _try_transition() -> void:
	if not _transition_pending or _dead:
		return
	if _state == State.STAGGER or _state == State.STUN or _state == State.TRANSITION or _state == State.IDLE:
		return
	if _state == State.ATTACK and _attack_phase == AttackPhase.ACTIVE:
		return
	_transition_pending = false
	velocity.x = 0.0
	_enter_state(State.TRANSITION, phase_transition_time)
	play_cue(CUE_PHASE_CHANGE)
	_shake(phase_shake_strength, phase_shake_time)
	_on_transition_started(_phase)


func _update_transition(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	if _telegraph != null:
		_telegraph.set_glow(Color.WHITE, 0.5 + 0.5 * sin(_clock * TRANSITION_PULSE_RATE))
	if _state_left <= 0.0:
		_begin_fight()


## -- Targetability ----------------------------------------------------------------------

## The collision layer of the root body while it is hittable. A multi-part boss
## whose parts are the hurtboxes returns 0 here: the root is then never hit
## directly, yet `_set_hittable` and `_reset_ai` restore exactly this value.
func _root_layer() -> int:
	return ENEMY_LAYER


## Off-screen, underground or untargetable: no root collision layer and
## `receive_hit` refuses every hit, whether it comes from the body or from a part.
## `_set_hittable(true)` restores `_root_layer()`.
func _set_hittable(on: bool) -> void:
	_hittable = on
	collision_layer = _root_layer() if on and not _dead else 0


func is_hittable() -> bool:
	return _hittable


func _set_contact(on: bool) -> void:
	if _contact != null:
		_contact.set_deferred(&"monitoring", on and not _dead)


## -- Corpse and final blow ---------------------------------------------------------------

## 0 standing, 1 fully slumped.
func _defeat_progress() -> float:
	if defeat_time <= 0.0:
		return 1.0
	var t := 1.0 - clampf(_defeat_left / defeat_time, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Slumped forward and squashed, dimmed like any enemy corpse.
func _pose_corpse(progress: float) -> void:
	_visual.scale = Vector2(float(_facing), lerpf(1.0, CORPSE_SQUASH_Y, progress))
	_visual.rotation = float(_facing) * CORPSE_TILT * progress
	_visual.modulate = Color.WHITE.lerp(CORPSE_TINT, progress)
	_visual.z_index = -1 if progress >= 1.0 else 0


func _settle_corpse() -> void:
	_defeat_left = 0.0
	_apply_visual()
	set_physics_process(false)
	corpse_settled.emit()


## The killing blow as a moment: white flash, the world freezes, slow motion, a
## strong shake. The slow motion is restored by SceneTree timers (BossFeel), never
## by this node, so freeing the boss or the arena cannot leave it stuck.
func _play_final_blow() -> void:
	play_cue(CUE_DEFEAT)
	if final_flash_peak > 0.0 and _flash_layer != null:
		_flash_layer.flash(final_flash_peak, FLASH_FADE_IN, final_flash_time)
	BossFeel.shake_camera(get_viewport(), final_shake_strength, final_shake_time)
	if final_freeze_time > 0.0 or final_slowmo_time > 0.0:
		BossFeel.slow_motion(get_tree(), final_freeze_time, final_slowmo_time, final_slowmo_scale)


## -- Audio cues ---------------------------------------------------------------------------

## Plays the player named `cue` under `Sfx` and announces it. A slot with no
## stream (the default) stays silent, so a missing sound is never an error.
func play_cue(cue: StringName) -> void:
	sfx_cue.emit(cue)
	var player := _cues.get(cue) as AudioStreamPlayer2D
	if player != null and player.stream != null:
		player.play()


func get_cue_player(cue: StringName) -> AudioStreamPlayer2D:
	return _cues.get(cue) as AudioStreamPlayer2D


func _shake(strength: float, duration: float) -> void:
	BossFeel.shake_camera(get_viewport(), strength, duration)


## -- Luz, facing and the arena ---------------------------------------------------------

func _luz_valid() -> bool:
	return is_instance_valid(_luz)


func _luz_distance() -> float:
	return global_position.distance_to(_luz.global_position)


func _distance_x() -> float:
	return absf(_luz.global_position.x - global_position.x)


## Luz's x, or the boss's own when Luz is missing or freed.
func _luz_x() -> float:
	return _luz.global_position.x if _luz_valid() else global_position.x


## Luz's feet are within `tolerance` of the boss's: same level, not on a platform
## above or a pit below.
func _luz_level(tolerance: float) -> bool:
	return absf(_luz.global_position.y - global_position.y) <= tolerance


func _dir_to_luz() -> int:
	if not _luz_valid():
		return _facing
	var side := signf(_luz.global_position.x - global_position.x)
	return int(side) if side != 0.0 else _facing


func _face_luz() -> void:
	set_facing(_dir_to_luz())


## Turns the boss to `dir` (-1 left, 1 right).
func set_facing(dir: int) -> void:
	var wanted := 1 if dir >= 0 else -1
	if wanted != _facing:
		_facing = wanted
		_apply_visual()


## Unit vector from `from` to the middle of Luz's body (facing when she is missing).
func _aim_at_luz(from: Vector2) -> Vector2:
	if not _luz_valid():
		return Vector2(float(_facing), 0.0)
	var to_luz := _luz.global_position + PLAYER_CENTER_OFFSET - from
	if to_luz.length_squared() < 1.0:
		return Vector2(float(_facing), 0.0)
	return to_luz.normalized()


## Left and right wall x: the arena's limits when fed, else around the boss.
func _arena_bounds() -> Vector2:
	if _has_arena_limits:
		return Vector2(_arena_left, _arena_right)
	return Vector2(global_position.x - arena_half_width, global_position.x + arena_half_width)


## `x` kept inside the arena with `margin` px to the walls (the body half width by default).
func _clamp_to_arena(x: float, margin := -1.0) -> float:
	var bounds := _arena_bounds()
	var gap := _half_width if margin < 0.0 else margin
	return clampf(x, bounds.x + gap, maxf(bounds.y - gap, bounds.x + gap))


func _wall_touching(dir: int) -> bool:
	return is_on_wall() and get_wall_normal().x * float(dir) < 0.0


func _clear_telegraph() -> void:
	if _telegraph != null:
		_telegraph.clear()


## -- Hitboxes -------------------------------------------------------------------------------

## Arms or disarms an `Area2D` hitbox (deferred: it may happen inside a physics
## callback). Arming starts a new activation: Luz can be hurt once more.
func _set_hitbox(area: Area2D, on: bool) -> void:
	if area == null:
		return
	if on:
		_hit_areas.erase(area.get_instance_id())
	area.set_deferred(&"monitoring", on)


## Hurts Luz at most once per activation of `area`. Her own damage gate decides
## about dash i-frames and i-frames after a hit. True on the frame that landed.
func _hurt_luz_once(area: Area2D, damage: int) -> bool:
	if area == null or not area.monitoring or _hit_areas.has(area.get_instance_id()):
		return false
	for body: Node2D in area.get_overlapping_bodies():
		var player := body as Player
		if player != null and player.take_damage(damage, global_position):
			_hit_areas[area.get_instance_id()] = true
			return true
	return false


## -- Projectile pool ------------------------------------------------------------------------

## Fires a pooled projectile of `scene` from `from` along `direction` (normalized).
## The projectile points along its flight. Pools grow on demand, one per scene.
func _launch_projectile(scene: PackedScene, from: Vector2, direction: Vector2, speed: float) -> EnemyProjectile:
	var projectile := _acquire_projectile(scene)
	projectile.rotation = direction.angle()
	projectile.launch(from, direction, speed)
	return projectile


## Makes `count` projectiles of `scene` ready ahead of time.
func _prewarm_projectiles(scene: PackedScene, count: int) -> void:
	var pool := _pool_for(scene)
	while pool.size() < count:
		pool.append(_make_projectile(scene))


func _acquire_projectile(scene: PackedScene) -> EnemyProjectile:
	var pool := _pool_for(scene)
	for projectile: EnemyProjectile in pool:
		if not projectile.is_active():
			return projectile
	var extra := _make_projectile(scene)
	pool.append(extra)
	return extra


func _pool_for(scene: PackedScene) -> Array:
	if not _projectile_pools.has(scene):
		_projectile_pools[scene] = []
	return _projectile_pools[scene]


## Projectiles live beside the boss, not under it: a child would inherit its
## modulate and visibility (a flash, a fade, a hidden boss) and vanish with it.
## They are born under the boss (the parent may still be busy adding its children)
## and moved next frame.
func _make_projectile(scene: PackedScene) -> EnemyProjectile:
	var projectile := scene.instantiate() as EnemyProjectile
	_configure_projectile(projectile)
	add_child(projectile)
	_rehome_projectile.call_deferred(projectile)
	return projectile


## Called once for each new projectile, before it enters the tree. The default
## makes it stop on one-way tops and ignore Luz's slash (she must dodge it).
func _configure_projectile(projectile: EnemyProjectile) -> void:
	projectile.stops_on_one_ways = true
	projectile.breakable_by_attacks = false


func _rehome_projectile(projectile: EnemyProjectile) -> void:
	var home := get_parent()
	if is_instance_valid(projectile) and home != null and projectile.get_parent() == self:
		projectile.reparent(home, false)

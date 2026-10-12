@tool
class_name ArtemisBoss
extends Enemy

## Artemis, the Greece zone boss: a huntress who kites melee-only Luz. She keeps
## a preferred distance, hops back when Luz closes in, dodges some slashes and
## feints, and punishes standing still with arrows. Every attack is telegraphed
## (never under 0.35 s) and ends in a recovery window that is Luz's opening.
##
## State machine: IDLE -> REPOSITION <-> BACKSTEP / DODGE / FEINT / ATTACK, with
## STAGGER (interrupts anything) and DEFEATED. An attack runs TELEGRAPH ->
## ACTIVE -> RECOVER. To add an attack: extend `Attack`, then give it a case in
## `_telegraph_time`, `_active_time`, `_recover_time`, `_animate_telegraph`,
## `_fire_attack` and `_choose_attack`.
##
## She is a normal enemy for the base class (hits, flash, registry, checkpoint
## reset) except she is never pushed and leaves no corpse. Placeholder visuals
## only; the animation contract replaces them without touching this logic.

signal phase_changed(phase: int)
signal defeated

enum State { IDLE, REPOSITION, BACKSTEP, DODGE, FEINT, ATTACK, STAGGER, DEFEATED }
enum AttackPhase { TELEGRAPH, ACTIVE, RECOVER }
enum Attack { AIMED_SHOT }

const ARROW_SCENE := preload("res://scenes/enemies/bosses/artemis_arrow.tscn")
const ARROW_POOL_SIZE := 4
## No telegraph is shorter than this: it must be readable on a phone.
const MIN_TELEGRAPH := 0.35
const AIM_LINE_LENGTH := 520.0
const PHASE_ONE := 1
const PHASE_TWO := 2
## Seconds between ledge and wall probes while she walks.
const PROBE_INTERVAL := 0.05
const LEDGE_AHEAD := 8.0
const WALL_PROBE_HEIGHT := -24.0
const PLAYER_CENTER_OFFSET := Vector2(0.0, -29.0)
const STAGGER_TINT := Color(0.72, 0.75, 0.95)
const NEVER := -1.0e9

@export_group("Movement")
## Luz farther than this (in sight) wakes her up.
@export var wake_distance := 640.0
@export var opening_delay := 0.6
@export var kite_min_distance := 180.0
@export var kite_max_distance := 260.0
@export var kite_speed := 150.0
@export var reposition_min_time := 0.6
@export var reposition_max_time := 1.2
## Luz closer than this makes her hop away.
@export var backstep_trigger_distance := 90.0
@export var backstep_speed := 320.0
@export var backstep_time := 0.28
@export var backstep_hop := 240.0
@export var backstep_cooldown := 2.0
@export var ledge_probe_depth := 12.0

@export_group("Dodge")
## Chance to hop away from the startup of a Luz attack.
@export_range(0.0, 1.0) var dodge_chance := 0.3
@export var dodge_cooldown := 3.0
@export var dodge_speed := 380.0
@export var dodge_time := 0.25
@export var dodge_hop := 200.0
## She only reacts to an attack that starts this close.
@export var dodge_react_distance := 200.0

@export_group("Feint")
@export_range(0.0, 1.0) var feint_chance := 0.25
@export var feint_cooldown := 6.0
@export var feint_speed := 360.0
## She stops this far from Luz: just outside her melee range.
@export var feint_stop_distance := 80.0
@export var feint_max_time := 1.2
@export var feint_retreat_speed := 300.0
@export var feint_retreat_time := 0.35

@export_group("Stagger")
## This many hits inside `stagger_window` seconds stagger her.
@export var stagger_hits := 6
@export var stagger_window := 2.5
@export var stagger_time := 1.5

@export_group("Aimed Shot")
@export_range(0.35, 2.0) var shot_telegraph_time := 0.6
## The aim freezes this long before the arrow, so a dash or jump answers it.
@export var shot_aim_lock_time := 0.15
@export var shot_active_time := 0.1
@export var shot_recover_time := 0.5
@export var arrow_speed := 420.0

@export_group("Phases")
## Phase two starts at this share of her health or below.
@export_range(0.0, 1.0) var phase_two_threshold := 0.5
## Recoveries are this much of their phase-one length in phase two.
@export_range(0.1, 1.0) var phase_two_recover_scale := 0.85

@export_group("Defeat")
@export var defeat_time := 0.9
@export var defeat_rise := 24.0

@export_group("Randomness")
## 0 randomizes. Tests set `rng` directly or fix this seed.
@export var rng_seed := 0

@onready var _floor_probe: RayCast2D = $FloorProbe
@onready var _wall_probe: RayCast2D = $WallProbe
@onready var _muzzle: Marker2D = $Visual/Bow/Muzzle
@onready var _telegraph: BossTelegraph = $Telegraph

var rng := RandomNumberGenerator.new()

var _state := State.IDLE
var _state_left := 0.0
var _attack := Attack.AIMED_SHOT
var _attack_phase := AttackPhase.TELEGRAPH
var _phase := PHASE_ONE
var _clock := 0.0
var _half_width := 13.0
var _luz: Player
var _was_luz_attacking := false
var _aim_dir := Vector2.RIGHT
var _move_dir := 1
var _hop_speed := 0.0
var _feint_retreating := false
var _backstep_left := 0.0
var _dodge_left := 0.0
var _feint_left := 0.0
var _probe_left := 0.0
var _probe_dir := 0
var _probe_blocked := false
var _hit_ring := PackedFloat32Array()
var _ring_index := 0
var _defeat_left := 0.0
var _play_defeat := false
var _pool: Array[EnemyProjectile] = []


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var body := $CollisionShape2D as CollisionShape2D
	if body.shape is RectangleShape2D:
		_half_width = (body.shape as RectangleShape2D).size.x * 0.5
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed
	_telegraph.bind_body($Visual/Body as Polygon2D)
	for i: int in ARROW_POOL_SIZE:
		_pool.append(_make_arrow())
	_reset_hit_ring()
	if not _dead:
		_enter_state(State.IDLE, opening_delay)


func _physics_process(delta: float) -> void:
	_clock += delta
	super._physics_process(delta)


## -- Public API --------------------------------------------------------------

func get_state() -> State:
	return _state


func get_attack_phase() -> AttackPhase:
	return _attack_phase


func get_phase() -> int:
	return _phase


func get_aim_direction() -> Vector2:
	return _aim_dir


func is_telegraphing() -> bool:
	return _state == State.ATTACK and _attack_phase == AttackPhase.TELEGRAPH


func get_telegraph() -> BossTelegraph:
	return _telegraph


## Leaves IDLE for the fight without waiting for Luz to come close.
func engage() -> void:
	if _state == State.IDLE:
		_begin_reposition()


## Starts `attack` from any state except defeat. Used by the chooser and by tests.
func start_attack(attack: Attack) -> void:
	if _dead:
		return
	_attack = attack
	_enter_state(State.ATTACK)
	_set_attack_phase(AttackPhase.TELEGRAPH)


func clear_arrows() -> void:
	for arrow: EnemyProjectile in _pool:
		arrow.deactivate()


func active_arrow_count() -> int:
	var count := 0
	for arrow: EnemyProjectile in _pool:
		count += 1 if arrow.is_active() else 0
	return count


func get_active_arrows() -> Array[EnemyProjectile]:
	var arrows: Array[EnemyProjectile] = []
	for arrow: EnemyProjectile in _pool:
		if arrow.is_active():
			arrows.append(arrow)
	return arrows


func set_ai_active(active: bool) -> void:
	super.set_ai_active(active)
	if not active:
		clear_arrows()


## Registers the hit, then checks the phase threshold and the stagger window.
## A killing blow plays the defeat beat instead of leaving a corpse.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	_play_defeat = not _dead and damage > 0 and _health - damage <= 0
	var landed := super.receive_hit(damage, source_position, attack_name)
	_play_defeat = false
	if not landed:
		return false
	if _dead:
		defeated.emit()
		return true
	engage()
	_check_phase_two()
	_register_stagger_hit()
	return true


## Defeat: no corpse. A fresh kill fades out; a kill restored by the registry
## (she was beaten earlier) just stays hidden.
func make_corpse_at(at: Vector2, facing: int) -> void:
	clear_arrows()
	_enter_state(State.DEFEATED)
	super.make_corpse_at(at, facing)
	_defeat_left = defeat_time if _play_defeat else 0.0
	if not _play_defeat:
		_hide_for_good()


## -- Hooks -----------------------------------------------------------------------

func _reset_ai() -> void:
	if not is_node_ready():
		return
	var was_phase_two := _phase == PHASE_TWO
	_phase = PHASE_ONE
	_defeat_left = 0.0
	_play_defeat = false
	visible = true
	_visual.position = Vector2.ZERO
	clear_arrows()
	_telegraph.clear()
	_backstep_left = 0.0
	_dodge_left = 0.0
	_feint_left = 0.0
	_was_luz_attacking = false
	_reset_hit_ring()
	_enter_state(State.IDLE, opening_delay)
	if was_phase_two:
		phase_changed.emit(PHASE_ONE)


func _on_player_found(player: Node) -> void:
	_luz = player as Player
	_floor_probe.add_exception(player as CollisionObject2D)
	_wall_probe.add_exception(player as CollisionObject2D)


## Bosses are never pushed: a hit must not freeze her timers either.
func _start_recoil(_source_position: Vector2) -> void:
	pass


func _apply_visual() -> void:
	if _visual == null:
		return
	_visual.scale = Vector2(float(_facing), 1.0)
	_visual.z_index = 0
	match _state:
		State.STAGGER:
			_visual.modulate = STAGGER_TINT
		State.DEFEATED:
			_visual.modulate = Color(1.0, 1.0, 1.0, _defeat_alpha())
		_:
			_visual.modulate = Color.WHITE


func _update_corpse(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	_defeat_left -= delta
	_visual.position.y = -defeat_rise * (1.0 - _defeat_alpha())
	_apply_visual()
	if _defeat_left <= 0.0:
		_hide_for_good()


## -- State machine ---------------------------------------------------------------

func _think(delta: float) -> void:
	_tick_cooldowns(delta)
	if _luz == null or not is_instance_valid(_luz):
		velocity.x = 0.0
		return
	var luz_started_attack := _poll_luz_attack()
	if _state != State.STAGGER:
		_face_luz()
	if luz_started_attack and _can_dodge() and _try_dodge():
		return
	match _state:
		State.IDLE:
			_update_idle(delta)
		State.REPOSITION:
			_update_reposition(delta)
		State.BACKSTEP, State.DODGE:
			_update_hop(delta)
		State.FEINT:
			_update_feint(delta)
		State.ATTACK:
			_update_attack(delta)
		State.STAGGER:
			_update_stagger(delta)


func _enter_state(state: State, duration := 0.0) -> void:
	if _state == State.ATTACK and state != State.ATTACK and _telegraph != null:
		_telegraph.clear()
	_state = state
	_state_left = duration
	_apply_visual()


func _begin_reposition() -> void:
	_enter_state(State.REPOSITION, rng.randf_range(reposition_min_time, reposition_max_time))


func _tick_cooldowns(delta: float) -> void:
	_backstep_left = maxf(_backstep_left - delta, 0.0)
	_dodge_left = maxf(_dodge_left - delta, 0.0)
	_feint_left = maxf(_feint_left - delta, 0.0)
	_probe_left -= delta


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	if _luz_distance() > wake_distance:
		return
	_state_left -= delta
	if _state_left <= 0.0:
		_begin_reposition()


func _update_reposition(delta: float) -> void:
	_state_left -= delta
	var dist := _distance_x()
	if dist < backstep_trigger_distance and _backstep_left <= 0.0 and _try_backstep():
		return
	_kite(dist)
	if _state_left <= 0.0:
		_pick_next_action()


## Holds the preferred distance: away when Luz is near, toward her when far.
func _kite(dist: float) -> void:
	var dir := 0
	if dist < kite_min_distance:
		dir = -_dir_to_luz()
	elif dist > kite_max_distance:
		dir = _dir_to_luz()
	if dir == 0 or (is_on_floor() and _blocked_ahead(dir)):
		velocity.x = 0.0
		return
	velocity.x = float(dir) * kite_speed


func _pick_next_action() -> void:
	if _try_feint():
		return
	start_attack(_choose_attack())


## One place to weigh attacks by distance and avoid repeats once there are more.
func _choose_attack() -> Attack:
	return Attack.AIMED_SHOT


## -- Backstep and dodge ---------------------------------------------------------

func _try_backstep() -> bool:
	var away := -_dir_to_luz()
	if not _hop_is_safe(away, backstep_speed * backstep_time):
		return false
	_backstep_left = backstep_cooldown
	_start_hop(State.BACKSTEP, away, backstep_speed, backstep_hop, backstep_time)
	return true


func _can_dodge() -> bool:
	return _state == State.REPOSITION or _state == State.FEINT


## Rolls only when the dodge is actually available, so a seeded run is stable.
func _try_dodge() -> bool:
	if _dodge_left > 0.0 or _distance_x() > dodge_react_distance:
		return false
	if rng.randf() >= dodge_chance:
		return false
	var away := -_dir_to_luz()
	if not _hop_is_safe(away, dodge_speed * dodge_time):
		return false
	_dodge_left = dodge_cooldown
	_start_hop(State.DODGE, away, dodge_speed, dodge_hop, dodge_time)
	return true


func _start_hop(state: State, dir: int, speed: float, hop: float, time: float) -> void:
	_move_dir = dir
	_hop_speed = speed
	velocity.y = -hop
	_enter_state(state, time)


func _update_hop(delta: float) -> void:
	_state_left -= delta
	velocity.x = float(_move_dir) * _hop_speed
	if _state_left <= 0.0 or _wall_touching(_move_dir):
		velocity.x = 0.0
		_begin_reposition()


## True once per Luz attack: the frame its startup begins.
func _poll_luz_attack() -> bool:
	var starting := _luz.is_attack_starting()
	var rising := starting and not _was_luz_attacking
	_was_luz_attacking = starting
	return rising


## -- Feint ---------------------------------------------------------------------

func _try_feint() -> bool:
	if _feint_left > 0.0 or rng.randf() >= feint_chance:
		return false
	if _blocked_ahead(_dir_to_luz()):
		return false
	_feint_left = feint_cooldown
	_feint_retreating = false
	_enter_state(State.FEINT, feint_max_time)
	return true


func _update_feint(delta: float) -> void:
	_state_left -= delta
	var toward := _dir_to_luz()
	if _feint_retreating:
		_retreat_from_feint(-toward)
		return
	if _distance_x() <= feint_stop_distance or _state_left <= 0.0 or _blocked_ahead(toward):
		_feint_retreating = true
		_state_left = feint_retreat_time
		velocity.x = 0.0
		return
	velocity.x = float(toward) * feint_speed


func _retreat_from_feint(away: int) -> void:
	velocity.x = 0.0 if _blocked_ahead(away) else float(away) * feint_retreat_speed
	if _state_left <= 0.0:
		_begin_reposition()


## -- Attacks ---------------------------------------------------------------------

func _update_attack(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	match _attack_phase:
		AttackPhase.TELEGRAPH:
			_animate_telegraph()
			if _state_left <= 0.0:
				_set_attack_phase(AttackPhase.ACTIVE)
		AttackPhase.ACTIVE:
			if _state_left <= 0.0:
				_set_attack_phase(AttackPhase.RECOVER)
		AttackPhase.RECOVER:
			if _state_left <= 0.0:
				_begin_reposition()


func _set_attack_phase(attack_phase: AttackPhase) -> void:
	_attack_phase = attack_phase
	match attack_phase:
		AttackPhase.TELEGRAPH:
			_state_left = _telegraph_time(_attack)
			velocity.x = 0.0
		AttackPhase.ACTIVE:
			_state_left = _active_time(_attack)
			_telegraph.clear()
			_fire_attack(_attack)
		AttackPhase.RECOVER:
			_state_left = _recover_time(_attack) * _recover_scale()


func _telegraph_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return maxf(shot_telegraph_time, MIN_TELEGRAPH)
	return MIN_TELEGRAPH


func _active_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return shot_active_time
	return 0.0


func _recover_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return shot_recover_time
	return 0.0


func _recover_scale() -> float:
	return phase_two_recover_scale if _phase == PHASE_TWO else 1.0


func _animate_telegraph() -> void:
	match _attack:
		Attack.AIMED_SHOT:
			_animate_aimed_shot()


func _fire_attack(attack: Attack) -> void:
	match attack:
		Attack.AIMED_SHOT:
			_launch_arrow(_muzzle.global_position, _aim_dir)


## Follows Luz until the last `shot_aim_lock_time`, then holds the line.
func _animate_aimed_shot() -> void:
	var total := _telegraph_time(Attack.AIMED_SHOT)
	var locked := _state_left <= shot_aim_lock_time
	if not locked:
		_aim_dir = _aim_at_luz()
	_telegraph.show_aim_line(_muzzle.global_position, _aim_dir, AIM_LINE_LENGTH, BossTelegraph.RANGED_COLOR, locked)
	_telegraph.set_glow(BossTelegraph.RANGED_COLOR, 1.0 - clampf(_state_left / total, 0.0, 1.0))


func _aim_at_luz() -> Vector2:
	var to_luz := _luz.global_position + PLAYER_CENTER_OFFSET - _muzzle.global_position
	if to_luz.length_squared() < 1.0:
		return Vector2(float(_facing), 0.0)
	return to_luz.normalized()


## -- Arrows ----------------------------------------------------------------------

func _launch_arrow(from: Vector2, direction: Vector2) -> void:
	var arrow := _acquire_arrow()
	arrow.rotation = direction.angle()
	arrow.launch(from, direction, arrow_speed)


func _acquire_arrow() -> EnemyProjectile:
	for arrow: EnemyProjectile in _pool:
		if not arrow.is_active():
			return arrow
	var extra := _make_arrow()
	_pool.append(extra)
	return extra


func _make_arrow() -> EnemyProjectile:
	var arrow := ARROW_SCENE.instantiate() as EnemyProjectile
	add_child(arrow)
	return arrow


## -- Stagger and phases ------------------------------------------------------------

func _check_phase_two() -> void:
	if _phase == PHASE_TWO:
		return
	if float(_health) <= float(max_health) * phase_two_threshold:
		_phase = PHASE_TWO
		phase_changed.emit(PHASE_TWO)


func _register_stagger_hit() -> void:
	if _state == State.STAGGER or stagger_hits <= 0:
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


func _update_stagger(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	if _state_left <= 0.0:
		_reset_hit_ring()
		_begin_reposition()


func _reset_hit_ring() -> void:
	_hit_ring.resize(maxi(stagger_hits, 1))
	_hit_ring.fill(NEVER)
	_ring_index = 0


## -- Helpers -------------------------------------------------------------------

func _luz_distance() -> float:
	return global_position.distance_to(_luz.global_position)


func _distance_x() -> float:
	return absf(_luz.global_position.x - global_position.x)


func _dir_to_luz() -> int:
	var side := signf(_luz.global_position.x - global_position.x)
	return int(side) if side != 0.0 else _facing


func _face_luz() -> void:
	var dir := _dir_to_luz()
	if dir != _facing:
		_facing = dir
		_apply_visual()


func _defeat_alpha() -> float:
	if defeat_time <= 0.0:
		return 0.0
	return clampf(_defeat_left / defeat_time, 0.0, 1.0)


func _hide_for_good() -> void:
	visible = false
	set_physics_process(false)


## -- Walls and ledges ----------------------------------------------------------

## A step in `dir` on the ground would meet a wall or run out of floor. Cached
## for PROBE_INTERVAL so walking costs two rays every few frames, not every one.
func _blocked_ahead(dir: int) -> bool:
	if _probe_left <= 0.0 or dir != _probe_dir:
		_probe_dir = dir
		_probe_left = PROBE_INTERVAL
		var reach := _half_width + LEDGE_AHEAD
		_probe_blocked = _wall_in_way(dir, reach) or not _floor_at(dir, reach)
	return _probe_blocked


## A whole hop of `distance` px has floor under its end and no wall before it.
func _hop_is_safe(dir: int, distance: float) -> bool:
	if not is_on_floor():
		return false
	var reach := _half_width + distance
	return not _wall_in_way(dir, reach) and _floor_at(dir, reach)


func _floor_at(dir: int, ahead: float) -> bool:
	_floor_probe.position = Vector2(float(dir) * ahead, -4.0)
	_floor_probe.target_position = Vector2(0.0, 4.0 + ledge_probe_depth)
	_floor_probe.force_raycast_update()
	return _floor_probe.is_colliding()


func _wall_in_way(dir: int, reach: float) -> bool:
	_wall_probe.position = Vector2(0.0, WALL_PROBE_HEIGHT)
	_wall_probe.target_position = Vector2(float(dir) * reach, 0.0)
	_wall_probe.force_raycast_update()
	return _wall_probe.is_colliding()


func _wall_touching(dir: int) -> bool:
	return is_on_wall() and get_wall_normal().x * float(dir) < 0.0

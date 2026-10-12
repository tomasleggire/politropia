@tool
class_name ArtemisBoss
extends Enemy

## Artemis, the Greece zone boss: a huntress who kites melee-only Luz. She keeps
## a preferred distance, hops back when Luz closes in, dodges some slashes and
## feints, and punishes standing still with arrows. Every attack is telegraphed
## (never under 0.35 s) and ends in a recovery window that is Luz's opening.
##
## State machine: IDLE -> REPOSITION <-> BACKSTEP / DODGE / FEINT / ATTACK / VAULT,
## with STAGGER (interrupts anything), TRANSITION (the phase-two beat) and
## DEFEATED. An attack runs TELEGRAPH -> ACTIVE -> RECOVER. To add an attack:
## extend `Attack`, then give it a case in `_telegraph_time`, `_active_time`,
## `_recover_time`, `_animate_telegraph` and `_fire_attack` (plus `_begin_telegraph`,
## `_update_active` and `_end_active` when it needs setup, per-frame work or
## cleanup), and a weight in each `weights_*` array, phase one and `_p2` (one entry
## per `Attack`, in enum order); `_choose_attack` reads them and needs no change.
## Phase two recoveries shrink by `phase_two_recover_scale` automatically. To let
## an attack start a string, add it to `CHAIN_TABLE`.
##
## Phase two ("Full Moon"): a short transition beat, shorter recoveries, chained
## strings, the moon dive and the spectral stag. Both phases: the cornered vault
## (see `_start_vault`): pinned against a wall or ledge with Luz in her face she
## jumps over her, and that takes priority over the dagger; the dagger stays the
## anti-turtle everywhere else.
##
## She is a normal enemy for the base class (hits, flash, registry, checkpoint
## reset) except she is never pushed and leaves no corpse. Placeholder visuals
## only; the animation contract replaces them without touching this logic.

signal phase_changed(phase: int)
signal defeated

enum State { IDLE, REPOSITION, BACKSTEP, DODGE, FEINT, ATTACK, STAGGER, DEFEATED, TRANSITION, VAULT }
enum AttackPhase { TELEGRAPH, ACTIVE, RECOVER }
enum Attack { AIMED_SHOT, FAN, RAIN, DAGGER, MOON_DIVE, STAG }
enum VaultPhase { CROUCH, AIR, LAND }
enum Band { FAR, MID, NEAR }

const ARROW_SCENE := preload("res://scenes/enemies/bosses/artemis_arrow.tscn")
## Arrows kept ready at start; rain adds what its zones need.
const ARROW_POOL_SIZE := 8
const NO_ATTACK := -1
## No telegraph is shorter than this: it must be readable on a phone.
const MIN_TELEGRAPH := 0.35
const AIM_LINE_LENGTH := 520.0
const FAN_LINE_LENGTH := 300.0
const RAIN_LINE_LENGTH := 140.0
## Rain arrows are packed this far apart across a zone (the arrow is 10 px wide).
const RAIN_ARROW_STEP := 10.0
const RAIN_MARKER_HEIGHT := 8.0
## Floor markers show after this long, so the sky aim reads first.
const RAIN_MARKER_DELAY := 0.2
const DAGGER_REACH := 40.0
const DAGGER_DAMAGE := 1
const DIVE_DAMAGE := 1
## The dive hitbox centre above the boss origin (matches the scene).
const DIVE_BOX_Y := -28.0
## Gap kept between a landing or dive point and a wall.
const WALL_MARGIN := 4.0
## Beat pulse of the transition glow, radians per second.
const TRANSITION_PULSE_RATE := 10.0
const CROUCH_SCALE := 0.8
## A vault that has not landed this long after its computed flight is cut short.
const VAULT_FLIGHT_SLACK := 0.5
## Attack -> [follow-up attack, hop back first]. Only attacks with a short punish
## window start a string; phase two only. SHOT -> backstep -> RAIN, FAN -> MOON_DIVE
## and DAGGER (after its flip) -> SHOT. Never the same attack twice.
const CHAIN_TABLE := {
	Attack.AIMED_SHOT: [Attack.RAIN, true],
	Attack.FAN: [Attack.MOON_DIVE, false],
	Attack.DAGGER: [Attack.AIMED_SHOT, false],
}
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

@export_group("Fan Volley")
@export_range(0.35, 2.0) var fan_telegraph_time := 0.45
@export var fan_aim_lock_time := 0.15
@export var fan_active_time := 0.1
@export var fan_recover_time := 0.4
## Arrows per volley (at most BossTelegraph.LINE_POOL_SIZE).
@export_range(1, 5) var fan_count := 3
## Angle between neighbouring arrows, in degrees. The fan is centred on Luz.
@export var fan_spread_degrees := 15.0

@export_group("Arrow Rain")
@export_range(0.35, 3.0) var rain_telegraph_time := 0.8
@export var rain_active_time := 0.1
## The punish window while she lands.
@export var rain_recover_time := 0.9
@export_range(1, 8) var rain_zone_count := 3
@export var rain_zone_width := 56.0
## Free floor between zones: wide enough to walk into.
@export var rain_gap_width := 64.0
## Arrows start this far above the floor.
@export var rain_height := 260.0
@export var rain_arrow_speed := 520.0
## How far a wall can be from Luz (rain, dive clamp, stag run, vault landing);
## also the reach when no wall is found.
@export var arena_half_width := 400.0

@export_group("Dagger Slash")
## Luz this close (in x) for `dagger_trigger_time` forces the next attack.
@export var dagger_trigger_distance := 70.0
@export var dagger_trigger_time := 0.6
@export_range(0.35, 1.0) var dagger_telegraph_time := 0.35
@export var dagger_active_time := 0.12
## Only used when a wall or ledge blocks the backflip.
@export var dagger_recover_time := 0.15
@export var dagger_flip_speed := 340.0
@export var dagger_flip_hop := 300.0
@export var dagger_flip_time := 0.35

@export_group("Moon Dive")
## Phase two. She leaps out of view, a silver marker follows Luz's x, locks, and
## she dives onto it. While off-screen she cannot be hit and deals no damage.
@export var dive_leap_time := 0.4
@export var dive_track_time := 0.6
## The marker holds still this long before the dive: Luz's time to dash away.
@export_range(0.35, 2.0) var dive_lock_time := 0.4
@export var dive_speed := 900.0
## How far above the floor she drops from.
@export var dive_height := 360.0
@export var dive_marker_width := 56.0
## The impact hitbox stays armed this long after she lands.
@export var dive_impact_time := 0.1
## Stuck in the ground: the big punish window. Never shortened in phase two.
@export var dive_stuck_time := 1.2

@export_group("Spectral Stag")
## Phase two. An edge glow warns, then a silver stag charges wall to wall from
## the wall farthest from Luz. Jump or dash it. She stands casting meanwhile.
@export_range(0.35, 2.0) var stag_telegraph_time := 0.8
@export var stag_active_time := 0.1
@export var stag_recover_time := 0.6
@export var stag_speed := 520.0

@export_group("Cornered Vault")
## Her back this close to a wall or ledge counts as cornered.
@export var vault_wall_distance := 48.0
## Luz this close (in x) for `vault_trigger_time` while she is cornered makes
## her vault. A hit while cornered does too.
@export var vault_trigger_distance := 110.0
@export var vault_trigger_time := 0.4
@export_range(0.35, 1.0) var vault_telegraph_time := 0.35
## Rise above her start, well over Luz's body (about 58 px).
@export var vault_apex_height := 130.0
## She lands this far past Luz, kept inside the arena.
@export var vault_land_distance := 80.0
@export var vault_recover_time := 0.3
@export var vault_cooldown := 4.0
## Off by default (accessible): the vault is an escape, not an attack.
@export var vault_contact_damage := false

@export_group("Chains")
## Phase two: after a recovery she may skip the reposition and follow up at once.
@export_range(0.0, 1.0) var chain_chance := 0.5
## Attacks in one string, the first included; then a normal reposition is forced.
@export_range(1, 6) var chain_max_length := 3

@export_group("Attack Weights")
## One weight per `Attack` (aimed shot, fan, rain, dagger, moon dive, stag) for
## Luz farther than `kite_max_distance`, between the kite distances, and closer
## than `kite_min_distance`. The attack she just used is never drawn again. The
## `_p2` tables replace these in phase two; the dive and stag are 0 in phase one.
@export var weights_far := PackedFloat32Array([3.0, 3.0, 2.0, 0.0, 0.0, 0.0])
@export var weights_mid := PackedFloat32Array([3.0, 3.0, 2.0, 0.0, 0.0, 0.0])
@export var weights_near := PackedFloat32Array([1.0, 1.0, 0.0, 4.0, 0.0, 0.0])
@export var weights_far_p2 := PackedFloat32Array([2.0, 2.0, 1.0, 0.0, 2.0, 2.0])
@export var weights_mid_p2 := PackedFloat32Array([2.0, 2.0, 1.0, 0.0, 2.0, 2.0])
@export var weights_near_p2 := PackedFloat32Array([1.0, 1.0, 0.0, 4.0, 1.0, 1.0])

@export_group("Phases")
## Phase two starts at this share of her health or below.
@export_range(0.0, 1.0) var phase_two_threshold := 0.5
## Recoveries are this much of their phase-one length in phase two.
@export_range(0.1, 1.0) var phase_two_recover_scale := 0.85
## The beat when phase two starts: she glows and does not attack, but can be hit.
@export var phase_two_transition_time := 1.0

@export_group("Defeat")
@export var defeat_time := 0.9
@export var defeat_rise := 24.0

@export_group("Randomness")
## 0 randomizes. Tests set `rng` directly or fix this seed.
@export var rng_seed := 0

@onready var _floor_probe: RayCast2D = $FloorProbe
@onready var _wall_probe: RayCast2D = $WallProbe
@onready var _dagger: Area2D = $DaggerHitbox
@onready var _muzzle: Marker2D = $Visual/Bow/Muzzle
@onready var _telegraph: BossTelegraph = $Telegraph
@onready var _dive_hitbox: Area2D = $DiveHitbox
@onready var _stag: SpectralStag = $SpectralStag

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
var _last_attack := NO_ATTACK
var _luz_close_time := 0.0
var _dagger_on := false
var _dagger_hit := false
var _rain_x := PackedFloat32Array()
var _rain_count := 0
var _hittable := true
var _transition_pending := false
var _chain_next := NO_ATTACK
var _chain_hop := false
var _chain_length := 0
var _dive_on := false
var _dive_offscreen := false
var _dive_locked := false
var _dive_hit := false
var _dive_x := 0.0
var _stag_dir := 1
var _stag_wall_x := 0.0
var _stag_far_x := 0.0
var _vault_phase := VaultPhase.CROUCH
var _vault_left := 0.0
var _vault_close_time := 0.0
var _vault_dir := 1
var _vault_vx := 0.0
var _vault_elapsed := 0.0
var _crouching := false


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
	_rain_x.resize(BossTelegraph.MARKER_POOL_SIZE)
	for i: int in maxi(ARROW_POOL_SIZE, mini(rain_zone_count, BossTelegraph.MARKER_POOL_SIZE) * _rain_arrows_per_zone()):
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


func get_attack() -> Attack:
	return _attack


## True while the dagger hitbox is armed (the ACTIVE part of the slash).
func is_dagger_active() -> bool:
	return _dagger_on


## True once Luz has stayed within `dagger_trigger_distance` long enough.
func is_dagger_forced() -> bool:
	return _luz_close_time > dagger_trigger_time


## The floor zones of the current rain, as world rectangles (for tests and HUD).
func get_rain_zones() -> Array[Rect2]:
	var zones: Array[Rect2] = []
	for i: int in _rain_count:
		zones.append(_rain_zone_rect(i))
	return zones


## True while she is off-screen in a moon dive: unhittable and harmless.
func is_offscreen() -> bool:
	return _dive_offscreen


## The x the moon dive aims at (it follows Luz until `is_dive_locked`).
func get_dive_x() -> float:
	return _dive_x


## True while the impact hitbox of the dive is armed.
func is_dive_hitbox_armed() -> bool:
	return _dive_hitbox.monitoring


func is_dive_locked() -> bool:
	return _dive_locked


func get_stag() -> SpectralStag:
	return _stag


func get_vault_phase() -> VaultPhase:
	return _vault_phase


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
	_chain_length = 1
	_chain_next = NO_ATTACK
	_begin_attack(attack)


func _begin_attack(attack: Attack) -> void:
	if _dead:
		return
	_restore_from_dive()
	_attack = attack
	_last_attack = attack
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
		_stag.deactivate()


## Registers the hit, then checks the phase threshold and the stagger window.
## A killing blow plays the defeat beat instead of leaving a corpse.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if not _hittable:
		return false
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
	_try_transition()
	_try_vault_on_hit()
	return true


## Defeat: no corpse. A fresh kill fades out; a kill restored by the registry
## (she was beaten earlier) just stays hidden.
func make_corpse_at(at: Vector2, facing: int) -> void:
	clear_arrows()
	_stag.deactivate()
	_set_dagger(false)
	# Dead first, so leaving a dive or a vault cannot re-arm her collision or contact.
	super.make_corpse_at(at, facing)
	_enter_state(State.DEFEATED)
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
	# A defeat fade switches her AI off for good: a checkpoint must revive it.
	set_physics_process(true)
	_visual.position = Vector2.ZERO
	clear_arrows()
	_stag.deactivate()
	_telegraph.clear()
	_set_dagger(false)
	_restore_from_dive()
	_hittable = true
	_set_hittable(true)
	_set_contact(true)
	_crouching = false
	_transition_pending = false
	_chain_next = NO_ATTACK
	_chain_length = 0
	_vault_left = 0.0
	_vault_close_time = 0.0
	_last_attack = NO_ATTACK
	_luz_close_time = 0.0
	_rain_count = 0
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
	_visual.scale = Vector2(float(_facing), CROUCH_SCALE if _crouching else 1.0)
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
	_track_luz_closeness(delta)
	var luz_started_attack := _poll_luz_attack()
	if _state != State.STAGGER:
		_face_luz()
	_try_transition()
	if luz_started_attack and _can_dodge() and _try_dodge():
		return
	if _poll_vault(delta):
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
		State.TRANSITION:
			_update_transition(delta)
		State.VAULT:
			_update_vault(delta)


func _enter_state(state: State, duration := 0.0) -> void:
	if _telegraph != null:
		_leave_state(state)
	_state = state
	_state_left = duration
	_apply_visual()


## Cleans up what the state we are leaving left behind.
func _leave_state(next: State) -> void:
	match _state:
		State.ATTACK:
			if next != State.ATTACK:
				_telegraph.clear()
				_set_dagger(false)
				_restore_from_dive()
		State.TRANSITION:
			_telegraph.clear()
		State.VAULT:
			_telegraph.clear()
			_crouching = false
			_set_contact(true)


func _begin_reposition() -> void:
	_chain_next = NO_ATTACK
	_chain_length = 0
	_enter_state(State.REPOSITION, rng.randf_range(reposition_min_time, reposition_max_time))


func _tick_cooldowns(delta: float) -> void:
	_backstep_left = maxf(_backstep_left - delta, 0.0)
	_dodge_left = maxf(_dodge_left - delta, 0.0)
	_feint_left = maxf(_feint_left - delta, 0.0)
	_probe_left -= delta
	_vault_left = maxf(_vault_left - delta, 0.0)


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


## A cornered Luz-in-her-face beats the dagger: she vaults away instead.
func _pick_next_action() -> void:
	if is_dagger_forced() and _vault_left <= 0.0 and _is_cornered():
		_start_vault()
		return
	if is_dagger_forced() and _last_attack != Attack.DAGGER:
		start_attack(Attack.DAGGER)
		return
	if _try_feint():
		return
	start_attack(_choose_attack())


## Time Luz spends inside dagger range; leaving it starts the count over.
func _track_luz_closeness(delta: float) -> void:
	if _distance_x() < dagger_trigger_distance:
		_luz_close_time += delta
	else:
		_luz_close_time = 0.0


## A forced dagger first; otherwise a weighted draw from the table of Luz's
## distance band that skips the attack she used last.
func _choose_attack() -> Attack:
	var choice := _draw_attack(_band_weights(_distance_band()))
	_last_attack = choice
	return choice


func _distance_band() -> Band:
	var dist := _distance_x()
	if dist > kite_max_distance:
		return Band.FAR
	return Band.MID if dist >= kite_min_distance else Band.NEAR


func _band_weights(band: Band) -> PackedFloat32Array:
	var phase_two := _phase == PHASE_TWO
	match band:
		Band.FAR:
			return weights_far_p2 if phase_two else weights_far
		Band.MID:
			return weights_mid_p2 if phase_two else weights_mid
	return weights_near_p2 if phase_two else weights_near


func _draw_attack(weights: PackedFloat32Array) -> Attack:
	if is_dagger_forced() and _last_attack != Attack.DAGGER:
		return Attack.DAGGER
	var total := 0.0
	for i: int in Attack.size():
		total += _weight_of(weights, i)
	if total <= 0.0:
		return Attack.AIMED_SHOT if _last_attack != Attack.AIMED_SHOT else Attack.FAN
	var roll := rng.randf() * total
	for i: int in Attack.size():
		roll -= _weight_of(weights, i)
		if roll < 0.0:
			return i as Attack
	return Attack.AIMED_SHOT


func _weight_of(weights: PackedFloat32Array, index: int) -> float:
	if index == _last_attack or index >= weights.size():
		return 0.0
	return maxf(weights[index], 0.0)


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
		if not _start_chain():
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
			_update_active(delta)
			if _state_left <= 0.0:
				_set_attack_phase(AttackPhase.RECOVER)
		AttackPhase.RECOVER:
			if _state_left <= 0.0:
				_finish_attack()


func _update_active(delta: float) -> void:
	match _attack:
		Attack.DAGGER:
			_poll_dagger()
		Attack.MOON_DIVE:
			_update_dive_fall(delta)


## After the recovery: the next link of a string, or back to repositioning.
func _finish_attack() -> void:
	if _chain_next != NO_ATTACK and _chain_hop:
		_chain_hop = false
		if _try_chain_hop():
			return
	if not _start_chain():
		_begin_reposition()


func _set_attack_phase(attack_phase: AttackPhase) -> void:
	_attack_phase = attack_phase
	if attack_phase != AttackPhase.ACTIVE:
		_set_dagger(false)
	match attack_phase:
		AttackPhase.TELEGRAPH:
			_state_left = _telegraph_time(_attack)
			velocity.x = 0.0
			_begin_telegraph(_attack)
		AttackPhase.ACTIVE:
			_state_left = _active_time(_attack)
			_telegraph.clear()
			_fire_attack(_attack)
		AttackPhase.RECOVER:
			_state_left = _recover_time(_attack) * _recover_scale(_attack)
			_roll_chain()
			_end_active(_attack)


func _telegraph_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return maxf(shot_telegraph_time, MIN_TELEGRAPH)
		Attack.FAN:
			return maxf(fan_telegraph_time, MIN_TELEGRAPH)
		Attack.RAIN:
			return maxf(rain_telegraph_time, MIN_TELEGRAPH)
		Attack.DAGGER:
			return maxf(dagger_telegraph_time, MIN_TELEGRAPH)
		Attack.MOON_DIVE:
			return dive_leap_time + dive_track_time + maxf(dive_lock_time, MIN_TELEGRAPH)
		Attack.STAG:
			return maxf(stag_telegraph_time, MIN_TELEGRAPH)
	return MIN_TELEGRAPH


func _active_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return shot_active_time
		Attack.FAN:
			return fan_active_time
		Attack.RAIN:
			return rain_active_time
		Attack.DAGGER:
			return dagger_active_time
		Attack.MOON_DIVE:
			return dive_height / maxf(dive_speed, 1.0) + dive_impact_time
		Attack.STAG:
			return stag_active_time
	return 0.0


func _recover_time(attack: Attack) -> float:
	match attack:
		Attack.AIMED_SHOT:
			return shot_recover_time
		Attack.FAN:
			return fan_recover_time
		Attack.RAIN:
			return rain_recover_time
		Attack.DAGGER:
			return dagger_recover_time
		Attack.MOON_DIVE:
			return dive_stuck_time
		Attack.STAG:
			return stag_recover_time
	return 0.0


## Phase two shortens every recovery, except the dive's stuck window: the big
## punish stays at least as long as in phase one.
func _recover_scale(attack: Attack) -> float:
	if _phase != PHASE_TWO or attack == Attack.MOON_DIVE:
		return 1.0
	return phase_two_recover_scale


func _animate_telegraph() -> void:
	match _attack:
		Attack.AIMED_SHOT:
			_animate_aimed_shot()
		Attack.FAN:
			_animate_fan()
		Attack.RAIN:
			_animate_rain()
		Attack.DAGGER:
			_animate_dagger()
		Attack.MOON_DIVE:
			_animate_moon_dive()
		Attack.STAG:
			_animate_stag()


func _fire_attack(attack: Attack) -> void:
	match attack:
		Attack.AIMED_SHOT:
			_launch_arrow(_muzzle.global_position, _aim_dir)
		Attack.FAN:
			_fire_fan()
		Attack.RAIN:
			_fire_rain()
		Attack.DAGGER:
			_swing_dagger()
		Attack.MOON_DIVE:
			_begin_dive_fall()
		Attack.STAG:
			_summon_stag()


## Follows Luz until the last `shot_aim_lock_time`, then holds the line.
func _animate_aimed_shot() -> void:
	var total := _telegraph_time(Attack.AIMED_SHOT)
	var locked := _state_left <= shot_aim_lock_time
	if not locked:
		_aim_dir = _aim_at_luz()
	_telegraph.show_aim_line(_muzzle.global_position, _aim_dir, AIM_LINE_LENGTH, BossTelegraph.RANGED_COLOR, locked)
	_telegraph.set_glow(BossTelegraph.RANGED_COLOR, 1.0 - clampf(_state_left / total, 0.0, 1.0))


## -- Fan volley ----------------------------------------------------------------

func _fan_count() -> int:
	return clampi(fan_count, 1, BossTelegraph.LINE_POOL_SIZE)


## Angle of arrow `index` from the aim line; the fan is centred on it.
func _fan_angle(index: int) -> float:
	return (float(index) - float(_fan_count() - 1) * 0.5) * deg_to_rad(fan_spread_degrees)


## Tracks Luz like the aimed shot, but draws one short line per arrow, so the
## fan reads as a spread and not as a single shot.
func _animate_fan() -> void:
	var total := _telegraph_time(Attack.FAN)
	var locked := _state_left <= fan_aim_lock_time
	if not locked:
		_aim_dir = _aim_at_luz()
	for i: int in _fan_count():
		_telegraph.show_aim_line(_muzzle.global_position, _aim_dir.rotated(_fan_angle(i)), FAN_LINE_LENGTH, BossTelegraph.RANGED_COLOR, locked, i)
	_telegraph.set_glow(BossTelegraph.RANGED_COLOR, 1.0 - clampf(_state_left / total, 0.0, 1.0))


func _fire_fan() -> void:
	for i: int in _fan_count():
		_launch_arrow(_muzzle.global_position, _aim_dir.rotated(_fan_angle(i)))


## -- Arrow rain -----------------------------------------------------------------

func _begin_telegraph(attack: Attack) -> void:
	match attack:
		Attack.RAIN:
			_plan_rain()
		Attack.MOON_DIVE:
			_begin_dive()
		Attack.STAG:
			_plan_stag()


func _rain_arrows_per_zone() -> int:
	return maxi(ceili(rain_zone_width / RAIN_ARROW_STEP), 1)


func _rain_zone_rect(index: int) -> Rect2:
	return Rect2(_rain_x[index], global_position.y - RAIN_MARKER_HEIGHT, rain_zone_width, RAIN_MARKER_HEIGHT)


## Lays zones around Luz, one gap apart. Zones that would leave the arena are
## dropped, so what remains always has gaps she can walk into.
func _plan_rain() -> void:
	var bounds := _arena_bounds()
	var count := mini(rain_zone_count, BossTelegraph.MARKER_POOL_SIZE)
	var pitch := rain_zone_width + rain_gap_width
	var half := rain_zone_width * 0.5
	var center := clampf(_luz_x(), bounds.x + half, maxf(bounds.y - half, bounds.x + half))
	_rain_count = 0
	for i: int in count:
		var x0 := center + (float(i) - float(count - 1) * 0.5) * pitch - half
		if x0 >= bounds.x and x0 + rain_zone_width <= bounds.y:
			_rain_x[_rain_count] = x0
			_rain_count += 1
	# A lone zone in a room too narrow to stand beside it would trap Luz.
	if _rain_count == 1 and bounds.y - bounds.x < rain_zone_width + rain_gap_width:
		_rain_count = 0


## Left and right wall x around Luz, found with the wall probe from her column
## at the boss's floor height; `arena_half_width` when no wall is in reach.
func _arena_bounds() -> Vector2:
	var from := Vector2(_luz_x(), global_position.y + WALL_PROBE_HEIGHT)
	return Vector2(_wall_x(from, -1), _wall_x(from, 1))


## Luz's x, or her own when Luz is missing or freed (an external `start_attack`).
func _luz_x() -> float:
	return _luz.global_position.x if is_instance_valid(_luz) else global_position.x


## The probe is moved for the cast and put back, so later local probes are intact.
func _wall_x(from: Vector2, dir: int) -> float:
	var home := _wall_probe.position
	_wall_probe.global_position = from
	_wall_probe.target_position = Vector2(float(dir) * arena_half_width, 0.0)
	_wall_probe.force_raycast_update()
	var x := from.x + float(dir) * arena_half_width
	if _wall_probe.is_colliding():
		x = _wall_probe.get_collision_point().x
	_wall_probe.position = home
	return x


## She aims at the sky; the floor markers appear a moment later and pulse
## faster as the arrows near.
func _animate_rain() -> void:
	var total := _telegraph_time(Attack.RAIN)
	var progress := 1.0 - clampf(_state_left / total, 0.0, 1.0)
	_telegraph.show_aim_line(_muzzle.global_position, Vector2.UP, RAIN_LINE_LENGTH, BossTelegraph.RANGED_COLOR, true)
	_telegraph.set_glow(BossTelegraph.RANGED_COLOR, progress)
	if total * progress < minf(RAIN_MARKER_DELAY, total - MIN_TELEGRAPH):
		return
	var pulse := 0.5 + 0.5 * sin(_clock * lerpf(8.0, 24.0, progress))
	var alpha := lerpf(BossTelegraph.MARKER_ALPHA, 0.7, progress) * (0.75 + 0.25 * pulse)
	for i: int in _rain_count:
		_telegraph.show_floor_marker(i, _rain_zone_rect(i), BossTelegraph.RANGED_COLOR, alpha)


func _fire_rain() -> void:
	var per_zone := _rain_arrows_per_zone()
	var start_y := global_position.y - rain_height
	for i: int in _rain_count:
		for k: int in per_zone:
			var along := 0.5 if per_zone == 1 else float(k) / float(per_zone - 1)
			var x := _rain_x[i] + RAIN_ARROW_STEP * 0.5 + along * (rain_zone_width - RAIN_ARROW_STEP)
			_launch_arrow(Vector2(x, start_y), Vector2.DOWN, rain_arrow_speed)


## -- Dagger slash -------------------------------------------------------------------

func _animate_dagger() -> void:
	var total := _telegraph_time(Attack.DAGGER)
	_telegraph.set_glow(BossTelegraph.MELEE_COLOR, 1.0 - clampf(_state_left / total, 0.0, 1.0))


func _swing_dagger() -> void:
	_dagger_hit = false
	_dagger.position.x = float(_facing) * DAGGER_REACH
	_dagger.scale.x = float(_facing)
	_set_dagger(true)
	_luz_close_time = 0.0


func _set_dagger(on: bool) -> void:
	_dagger_on = on
	_dagger.set_deferred(&"monitoring", on)
	($DaggerHitbox/Slash as Polygon2D).visible = on


## Hurts Luz once per slash. Her own damage gate decides about dash i-frames
## and i-frames after a hit.
func _poll_dagger() -> void:
	if _attack != Attack.DAGGER or not _dagger_on or _dagger_hit or not _dagger.monitoring:
		return
	for body: Node2D in _dagger.get_overlapping_bodies():
		var player := body as Player
		if player != null and player.take_damage(DAGGER_DAMAGE, global_position):
			_dagger_hit = true


## The dagger has no punish window: she backflips away right after the swing.
## Pinned against a wall or ledge she only gets the short recovery. The moon
## dive ends its fall here: she is stuck in the ground and hittable again.
func _end_active(attack: Attack) -> void:
	if attack == Attack.MOON_DIVE:
		_end_dive()
	if attack != Attack.DAGGER:
		return
	var away := -_dir_to_luz()
	if not _hop_is_safe(away, dagger_flip_speed * dagger_flip_time):
		return
	_backstep_left = backstep_cooldown
	_start_hop(State.BACKSTEP, away, dagger_flip_speed, dagger_flip_hop, dagger_flip_time)


func _aim_at_luz() -> Vector2:
	if not is_instance_valid(_luz):
		return Vector2(float(_facing), 0.0)
	var to_luz := _luz.global_position + PLAYER_CENTER_OFFSET - _muzzle.global_position
	if to_luz.length_squared() < 1.0:
		return Vector2(float(_facing), 0.0)
	return to_luz.normalized()


## -- Chained strings (phase two) ------------------------------------------------

## Decided as a recovery starts: maybe a follow-up from `CHAIN_TABLE`, drawn from
## the injected rng only when a link is actually possible.
func _roll_chain() -> void:
	_chain_next = NO_ATTACK
	_chain_hop = false
	if _phase != PHASE_TWO or _chain_length >= chain_max_length or not CHAIN_TABLE.has(_attack):
		return
	if rng.randf() >= chain_chance:
		return
	var link: Array = CHAIN_TABLE[_attack]
	_chain_next = link[0]
	_chain_hop = link[1]


## Starts the pending follow-up at once, without a reposition in between.
func _start_chain() -> bool:
	if _chain_next == NO_ATTACK or _phase != PHASE_TWO:
		_chain_next = NO_ATTACK
		return false
	var next := _chain_next as Attack
	_chain_next = NO_ATTACK
	_chain_length += 1
	_begin_attack(next)
	return true


## A string's hop back (SHOT -> backstep -> RAIN). Skipped when it is unsafe.
func _try_chain_hop() -> bool:
	var away := -_dir_to_luz()
	if not _hop_is_safe(away, backstep_speed * backstep_time):
		return false
	_backstep_left = backstep_cooldown
	_start_hop(State.BACKSTEP, away, backstep_speed, backstep_hop, backstep_time)
	return true


## -- Phase transition -------------------------------------------------------------

## Starts the transition beat once, as soon as nothing is mid-strike. She stays
## hittable throughout; a stagger or an active attack only postpones it.
func _try_transition() -> void:
	if not _transition_pending or _dead:
		return
	if _state == State.STAGGER or _state == State.TRANSITION or _state == State.VAULT:
		return
	if _state == State.ATTACK and _attack_phase == AttackPhase.ACTIVE:
		return
	_transition_pending = false
	_chain_next = NO_ATTACK
	velocity.x = 0.0
	_enter_state(State.TRANSITION, phase_two_transition_time)


func _update_transition(delta: float) -> void:
	velocity.x = 0.0
	_state_left -= delta
	_telegraph.set_glow(BossTelegraph.MOON_COLOR, 0.5 + 0.5 * sin(_clock * TRANSITION_PULSE_RATE))
	if _state_left <= 0.0:
		_begin_reposition()


## -- Targetability ---------------------------------------------------------------

## Off-screen or mid-dive she cannot be hit: no collision layer and no hits.
func _set_hittable(on: bool) -> void:
	_hittable = on
	collision_layer = ENEMY_LAYER if on and not _dead else 0


func _set_contact(on: bool) -> void:
	if _contact != null:
		_contact.set_deferred(&"monitoring", on and not _dead)


## -- Moon dive (phase two) -----------------------------------------------------------

func _begin_dive() -> void:
	_dive_on = true
	_dive_offscreen = false
	_dive_locked = false
	_dive_x = global_position.x


## Leap (she rises out of view), track (the marker follows Luz), lock (it holds).
func _animate_moon_dive() -> void:
	var elapsed := _telegraph_time(Attack.MOON_DIVE) - _state_left
	if elapsed < dive_leap_time:
		var rise := clampf(elapsed / dive_leap_time, 0.0, 1.0)
		_visual.position.y = -dive_height * rise * rise
		_telegraph.set_glow(BossTelegraph.MOON_COLOR, rise)
		return
	_vanish_for_dive()
	_dive_locked = elapsed >= dive_leap_time + dive_track_time
	if not _dive_locked:
		_dive_x = _clamped_dive_x()
	var pulse := 0.75 + 0.25 * sin(_clock * (24.0 if _dive_locked else 8.0))
	var alpha := (0.8 if _dive_locked else BossTelegraph.MARKER_ALPHA) * pulse
	var rect := Rect2(_dive_x - dive_marker_width * 0.5, global_position.y - RAIN_MARKER_HEIGHT, dive_marker_width, RAIN_MARKER_HEIGHT)
	_telegraph.show_floor_marker(0, rect, BossTelegraph.MOON_COLOR, alpha)


func _vanish_for_dive() -> void:
	if _dive_offscreen:
		return
	_dive_offscreen = true
	_visual.visible = false
	_set_hittable(false)
	_set_contact(false)
	_telegraph.set_glow(BossTelegraph.MOON_COLOR, 0.0)


## Luz's x kept inside the arena with room for her body.
func _clamped_dive_x() -> float:
	var bounds := _arena_bounds()
	var margin := _half_width + WALL_MARGIN
	return clampf(_luz_x(), bounds.x + margin, maxf(bounds.y - margin, bounds.x + margin))


## She reappears high above the locked x and drops; the hitbox falls with her.
func _begin_dive_fall() -> void:
	global_position.x = _dive_x
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	_visual.position.y = -dive_height
	_visual.visible = true
	_dive_hit = false
	_set_dive_hitbox(true)
	_dive_hitbox.position.y = DIVE_BOX_Y - dive_height


func _update_dive_fall(delta: float) -> void:
	_visual.position.y = minf(_visual.position.y + dive_speed * delta, 0.0)
	_dive_hitbox.position.y = DIVE_BOX_Y + _visual.position.y
	_poll_dive()


func _set_dive_hitbox(on: bool) -> void:
	_dive_hitbox.set_deferred(&"monitoring", on)
	($DiveHitbox/Impact as Polygon2D).visible = on


## Hurts Luz once per dive; her own damage gate handles dash i-frames.
func _poll_dive() -> void:
	if _dive_hit or not _dive_hitbox.monitoring or not is_instance_valid(_luz):
		return
	if _dive_hitbox.overlaps_body(_luz) and _luz.take_damage(DIVE_DAMAGE, global_position):
		_dive_hit = true


## Stuck in the ground she is hittable again, but her body stays harmless.
func _end_dive() -> void:
	_dive_offscreen = false
	_visual.position.y = 0.0
	_set_dive_hitbox(false)
	_set_hittable(true)


## Undoes every dive effect; safe to call at any time.
func _restore_from_dive() -> void:
	if not _dive_on:
		return
	_dive_on = false
	_dive_offscreen = false
	_dive_locked = false
	_visual.position.y = 0.0
	_visual.visible = true
	_set_dive_hitbox(false)
	_set_hittable(true)
	_set_contact(true)


## -- Spectral stag (phase two) -------------------------------------------------------

## Side rule: the stag appears at the wall FARTHEST from Luz, so it crosses the
## whole arena (and her) with the most warning. Locked when the cast begins.
func _plan_stag() -> void:
	var bounds := _arena_bounds()
	var luz_x := _luz_x()
	_stag_dir = 1 if luz_x - bounds.x >= bounds.y - luz_x else -1
	_stag_wall_x = bounds.x if _stag_dir > 0 else bounds.y
	_stag_far_x = (bounds.y if _stag_dir > 0 else bounds.x) - float(_stag_dir) * SpectralStag.WIDTH * 0.5


func _animate_stag() -> void:
	var progress := 1.0 - clampf(_state_left / _telegraph_time(Attack.STAG), 0.0, 1.0)
	_telegraph.set_glow(BossTelegraph.MOON_COLOR, progress)
	var pulse := 0.75 + 0.25 * sin(_clock * lerpf(8.0, 24.0, progress))
	var x := _stag_wall_x if _stag_dir > 0 else _stag_wall_x - SpectralStag.WIDTH
	var rect := Rect2(x, global_position.y - SpectralStag.HEIGHT, SpectralStag.WIDTH, SpectralStag.HEIGHT)
	_telegraph.show_floor_marker(0, rect, BossTelegraph.MOON_COLOR, lerpf(BossTelegraph.MARKER_ALPHA, 0.7, progress) * pulse)


func _summon_stag() -> void:
	var from := Vector2(_stag_wall_x + float(_stag_dir) * SpectralStag.WIDTH * 0.5, global_position.y)
	_stag.launch(from, _stag_dir, stag_speed, _stag_far_x, _luz)


## -- Cornered vault ---------------------------------------------------------------------

## Her back is within `vault_wall_distance` of a wall or ledge (on the ground).
func _is_cornered() -> bool:
	if not is_on_floor() or not is_instance_valid(_luz):
		return false
	var back := -_dir_to_luz()
	var reach := _half_width + vault_wall_distance
	return _wall_in_way(back, reach) or not _floor_at(back, reach)


## Never in STAGGER or TRANSITION, during an attack's ACTIVE part or its moon dive,
## while already vaulting, on cooldown, or off the ground.
func _vault_allowed() -> bool:
	if _dead or _vault_left > 0.0 or not is_on_floor() or not is_instance_valid(_luz):
		return false
	match _state:
		State.REPOSITION, State.BACKSTEP, State.DODGE, State.FEINT:
			return true
		State.ATTACK:
			return _attack_phase != AttackPhase.ACTIVE and _attack != Attack.MOON_DIVE
	return false


## Luz in her face while she is cornered, long enough, makes her vault.
func _poll_vault(delta: float) -> bool:
	if not _vault_allowed() or _distance_x() > vault_trigger_distance or not _is_cornered():
		_vault_close_time = 0.0
		return false
	_vault_close_time += delta
	if _vault_close_time < vault_trigger_time:
		return false
	_start_vault()
	return true


func _try_vault_on_hit() -> void:
	if _vault_allowed() and _is_cornered():
		_start_vault()


func _start_vault() -> void:
	_vault_left = vault_cooldown
	_vault_close_time = 0.0
	_chain_next = NO_ATTACK
	_vault_dir = _dir_to_luz()
	_vault_phase = VaultPhase.CROUCH
	_crouching = true
	_set_contact(vault_contact_damage)
	velocity.x = 0.0
	_enter_state(State.VAULT, maxf(vault_telegraph_time, MIN_TELEGRAPH))
	_apply_visual()


func _update_vault(delta: float) -> void:
	_state_left -= delta
	match _vault_phase:
		VaultPhase.CROUCH:
			velocity.x = 0.0
			var total := maxf(vault_telegraph_time, MIN_TELEGRAPH)
			_telegraph.set_glow(BossTelegraph.VAULT_COLOR, 1.0 - clampf(_state_left / total, 0.0, 1.0))
			if _state_left <= 0.0:
				_launch_vault()
		VaultPhase.AIR:
			_vault_elapsed += delta
			velocity.x = _vault_vx
			var landed := _vault_elapsed > delta * 3.0 and is_on_floor() and velocity.y >= 0.0
			if landed or _state_left <= 0.0:
				_land_vault()
		VaultPhase.LAND:
			velocity.x = 0.0
			if _state_left <= 0.0:
				_begin_reposition()


## A ballistic arc from gravity: launch speed for the apex, flight time for the
## landing point, so the horizontal speed is fixed and the jump deterministic.
func _launch_vault() -> void:
	var bounds := _arena_bounds()
	var margin := _half_width + WALL_MARGIN
	var target := clampf(_luz_x() + float(_vault_dir) * vault_land_distance, bounds.x + margin, maxf(bounds.y - margin, bounds.x + margin))
	var launch_speed := sqrt(2.0 * gravity * vault_apex_height)
	var flight := 2.0 * launch_speed / gravity
	_vault_vx = (target - global_position.x) / flight
	velocity = Vector2(_vault_vx, -launch_speed)
	_vault_phase = VaultPhase.AIR
	_vault_elapsed = 0.0
	_state_left = flight + VAULT_FLIGHT_SLACK
	_crouching = false
	_telegraph.clear()
	_apply_visual()


func _land_vault() -> void:
	_vault_phase = VaultPhase.LAND
	_state_left = vault_recover_time
	velocity.x = 0.0


## -- Arrows ----------------------------------------------------------------------

## `speed` 0 means the aimed-shot `arrow_speed`.
func _launch_arrow(from: Vector2, direction: Vector2, speed := 0.0) -> void:
	var arrow := _acquire_arrow()
	arrow.rotation = direction.angle()
	arrow.launch(from, direction, speed if speed > 0.0 else arrow_speed)


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
		_transition_pending = true
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
	_chain_next = NO_ATTACK
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

class_name BlindBeastBoss
extends BossEnemy

## "El Topo", the optional library boss: a perception fight. The beast is blind. It
## hears and feels Luz, burrows, and erupts under the last place she made noise.
## The right answer is to slow down: make a noise in one place, walk away quietly
## and punish it where it comes up.
##
## Noise model (polled from the player's public API, nothing in `player.gd` changes):
##   LOUD  landing after being airborne, a dash starting, an attack swing starting,
##         and Hyperfocus. Each records a noise spot (Luz's x) and draws a ripple.
##   QUIET walking, standing, the jump take-off.
##   STILL grounded, slower than `still_speed`, no loud action for `still_grace`.
##
## Loop: BURROWED (untargetable, a small dirt mound) -> tunnels to the newest noise
## -> cracks (telegraph) -> eruption column -> EXPOSED (hittable; long and disoriented
## when the column missed, short when it hit Luz) -> digs in again. After
## `patience_time` of silence it probes the arena with telegraphed eruptions.
##
## Code names stay creature-neutral: a different creature is only a re-skin.
## Every hazard lives in `_field`, a top level node that never follows the boss.
## `_clear_hazards()` removes all of them.

signal noise_heard(x: float, kind: StringName)
signal surfaced
signal buried
## Hyperfocus dragged the beast out of the ground (the bonus, never required).
signal hyperfocus_forced

enum Attack {
	ERUPTION,
	PROBE,
	CLAW_COUNTER,
	BRAILLE_RIDGE,
	DEBRIS_TOSS,
	TREMOR_PULSE,
	CHAIN_ERUPTION,
}

const ATTACK_COUNT := 7
## The first phase in which each attack (in enum order) may be drawn.
const ATTACK_MIN_PHASE: Array[int] = [1, 1, 1, 2, 2, 3, 3]
## Telegraph floors above the base MIN_TELEGRAPH.
const CLAW_MIN_TELEGRAPH := 0.4
const RIDGE_MIN_TELEGRAPH := 0.7

const KIND_LANDING := &"landing"
const KIND_DASH := &"dash"
const KIND_SWING := &"swing"
const KIND_HYPERFOCUS := &"hyperfocus"

const CUE_HEARD := &"Heard"
const CUE_DIG := &"Dig"
const CUE_ERUPT := &"Erupt"
const CUE_CLAW := &"Claw"
const CUE_RIDGE := &"Ridge"
const CUE_DEBRIS := &"Debris"
const CUE_PULSE := &"Pulse"

## Luz's body, from her collision shape (feet at the node origin).
const LUZ_BODY_SIZE := Vector2(29.0, 46.0)
const LIGHT_LAYER := 30
const OPEN_EYES_SIGNAL := &"open_eyes_activated"

## Braille cells as six dots in reading order (1 2 3 on the left, 4 5 6 on the
## right): `#` is a raised dot. A word is its cells with one flat slot between.
const BRAILLE_LETTERS := {
	"L": "###...",
	"U": "#.#..#",
	"Z": "#.#.##",
	"O": "#.#.#.",
	"J": ".#.##.",
}
const FLAT_CELL := "......"
const MIN_SLOT_WIDTH := 20.0
## Spike timing (seconds) and the share of its height at which it already hurts.
const SPIKE_RISE := 0.08
const SPIKE_RETRACT := 0.15
const SPIKE_HURT_FROM := 0.4
const SPIKE_HIT_SHARE := 0.8

const RIPPLE_COLOR := Color(0.72, 0.88, 1.0)
const DIRT_COLOR := Color(0.42, 0.3, 0.22)
const DIRT_DARK := Color(0.22, 0.15, 0.12)
const RIDGE_FLAT_COLOR := Color(0.5, 0.42, 0.36)
const ROCK_COLOR := Color(0.55, 0.5, 0.46)
const MOUND_HALF_WIDTH := 17.0
const MOUND_HEIGHT := 11.0
const MOUND_STEPS := 8
const FOOTPRINT_HEIGHT := 10.0
## Vertical jitter of a crack's zigzag, from left to right.
const CRACK_ZIGZAG: Array[float] = [0.0, -4.0, 3.0, -5.0, 4.0, -3.0, 0.0]
const RIPPLE_MIN_RADIUS := 10.0
const RIPPLE_MAX_RADIUS := 80.0
const RIPPLE_SQUASH := 0.28
const LIGHT_FADE_RATE := 0.8
const FAR_AWAY := 1.0e9
## Closing in on a noise spot by less than this (px) is not progress.
const TUNNEL_PROGRESS_STEP := 0.5

## Art. Clip names are the contract of docs/bosses/BLIND_BEAST_ANIMATIONS.md.
const MIN_CLIP_TIME := 0.05
## The slam frame outlives the first moments of the pulse: it is held, never a timer.
const SLAM_STRIKE_TIME := 0.3
const PLACEHOLDERS: Array[String] = ["Body", "Nose", "Claws"]
const CLIP_SPEEDS := {
	"exposed_idle": 8.0, "dazed": 8.0, "emerge": 12.0, "dig_in": 12.0,
	"claw_windup": 12.0, "claw_strike": 12.0, "claw_recover": 12.0,
	"slam_windup": 12.0, "slam_strike": 12.0, "phase_change": 8.0, "intro": 8.0, "defeat": 8.0,
}
## Clips that repeat; every other clip plays once and holds its last frame.
const LOOPING_CLIPS := ["exposed_idle", "dazed"]
## Contract clip -> candidates, closest first, for a clip with no art yet (then `exposed_idle`).
const CLIP_FALLBACKS := {
	"claw_windup": ["slam_windup"], "claw_strike": ["claw_windup"], "claw_recover": ["claw_strike"],
	"slam_windup": ["claw_windup"], "slam_strike": ["slam_windup"],
}
## Hazard art, in px on screen: the mound is this wide, the pulse and the rocks fit these boxes.
const MOUND_ART_WIDTH := 40.0
const PULSE_ART_SIZE := Vector2(40.0, 24.0)
const ROCK_ART_FACTOR := 1.8
const ROCK_SPIN := 6.0
const DUST_WIDTH := 40.0
## The scratch lines of the claw warning pulse between white and this red tint.
const CLAW_WARNING_TINT := Color(1.0, 0.45, 0.4)
## Radians per second of the pulse that warns of the claw: the zone fill and the sprite tint share it.
const CLAW_WARNING_PULSE := 14.0
const CRACK_MIN_ALPHA := 0.35

@export_group("Art")
## The animation manifest of his sprite sheets. Without it (or without its sheets) he
## keeps the placeholder polygons.
@export_file("*.json") var animation_manifest := "res://assets/enemies/blind_beast/animation_manifest.json"

@export_group("Noise")
## How many noise spots the beast remembers (a chain eruption walks through them).
@export var noise_memory := 3
## Luz must be airborne this long for her landing to count as loud.
@export var landing_min_air_time := 0.15
## Grounded and slower than this (px/s) is quiet enough to be still.
@export var still_speed := 20.0
## Seconds after a loud action before Luz can count as still.
@export var still_grace := 0.3
## How long a ripple stays on the floor.
@export var ripple_time := 1.6
## Seconds without hearing anything before the beast probes the arena.
@export var patience_time := 4.0

@export_group("Burrow")
@export var tunnel_speed := 220.0
## Distance to the noise spot that counts as arrived.
@export var arrive_tolerance := 6.0
## Seconds the beast sinks, already untargetable, before it is only a mound.
@export var dig_in_time := 0.3
@export var dig_depth := 40.0
## Off hides the dirt mound that betrays where it is (default on, for fairness).
@export var show_mound := true
## Seconds between two decisions while it is underground.
@export var think_interval := 0.1
## Seconds the tunnel may make no headway toward a noise spot (a wall, a step, no
## limits) before he erupts where he is. A normal tunnel always closes in, so
## crossing the whole arena never trips it.
@export var stuck_tunnel_time := 3.0

@export_group("Eruption")
## The cracks warn this long before the column bursts.
@export var crack_time := 0.5
@export var column_size := Vector2(56.0, 90.0)
@export var column_active_time := 0.3
@export var column_rise_time := 0.1
@export var column_damage := 1
## Exposed seconds when the column hit Luz.
@export var exposed_hit_time := 0.8
## Disoriented seconds when the column missed (the long punish window).
@export var missed_stun_time := 1.8
@export var eruption_shake := 3.0

@export_group("Probe")
## Evenly spaced eruptions that sweep across the arena after a long silence.
@export var probe_count := 3
## Seconds between two bursts of the sweep.
@export var probe_gap := 0.4
@export var probe_exposed_time := 1.2

@export_group("Claw Counter")
## Red telegraph (never under 0.4 s).
@export var claw_telegraph_time := 0.45
@export var claw_active_time := 0.15
@export var claw_recover_time := 0.5
## A swing this close to the exposed beast (px) draws a counter.
@export var claw_reach := 150.0
@export var claw_zone_size := Vector2(120.0, 60.0)
@export var claw_damage := 1

@export_group("Braille Ridge")
## Words raised along the floor. Letters: L U Z O J.
@export var ridge_words := PackedStringArray(["LUZ", "OJO"])
@export var ridge_slot_width := 44.0
## Every slot shows its bump this long first (never under 0.7 s).
@export var ridge_telegraph_time := 0.8
## Seconds between two slots rising, in reading order.
@export var ridge_step := 0.06
@export var ridge_spike_height := 64.0
@export var ridge_spike_hold := 0.4
@export var ridge_recover_time := 0.6
@export var ridge_damage := 1

@export_group("Debris Toss")
@export var debris_count := 3
## Distance (px) between the landing spots around the eruption.
@export var debris_spread := 110.0
## Seconds a rock flies; its floor marker shows for all of it.
@export var debris_flight_time := 0.8
@export var debris_gravity := 1100.0
@export var debris_radius := 22.0
@export var debris_damage := 1

@export_group("Tremor Pulse")
@export var tremor_telegraph_time := 0.7
@export var pulse_speed := 260.0
## Half width (px) of the pulse as it passes Luz.
@export var pulse_half_width := 12.0
## Fast eruptions that track Luz when the pulse felt her.
@export var chase_count := 3
@export var chase_crack_time := 0.4
@export var chase_gap := 0.15
## Seconds it stays surfaced and confused when the pulse felt nothing.
@export var tremor_confused_time := 1.2
@export var tremor_shake := 4.0

@export_group("Chain Eruption")
@export var chain_interval := 0.45
@export var chain_crack_time := 0.55

@export_group("Hyperfocus")
## Dazed seconds when Hyperfocus drags it up (a bonus, never a requirement).
@export var hyperfocus_stun_time := 1.2
@export var hyperfocus_cooldown := 8.0

@export_group("Light")
## A dark overlay in the last phase. Cosmetic only: no mechanic depends on it.
@export var dim_light_in_final_phase := true
@export_range(0.0, 0.6) var dim_alpha := 0.28

@export_group("Attack Weights")
## One entry per `Attack` in enum order. An attack never draws before its phase.
@export var weights_phase_one := PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
@export var weights_phase_two := PackedFloat32Array([3.0, 0.0, 0.0, 2.0, 2.0, 0.0, 0.0])
@export var weights_phase_three := PackedFloat32Array([2.0, 0.0, 0.0, 1.5, 2.0, 2.0, 2.0])

var _noise: Array[NoiseSpot] = []
var _ripples: Array[Ripple] = []
var _cracks: Array[Crack] = []
var _columns: Array[Column] = []
var _rocks: Array[Rock] = []
var _pulses: Array[Pulse] = []
var _ridge_slots: Array[RidgeSlot] = []
var _seq_xs: Array[float] = []
var _seq_gap := 0.0
var _seq_time := 0.0
var _seq_next := 0
var _ridge_time := 0.0
var _claw_zone := Rect2()
var _claw_visible := false
var _claw_hit := false
var _chase_active := false
var _chase_waiting_burst := false
var _chase_clock := 0.0
var _chase_done := 0
var _chase_crack: Crack
var _attack_x := 0.0
var _last_burst_x := 0.0
var _column_hit_luz := false
var _exposed := false
var _digging := false
var _dig_left := 0.0
var _silence := 0.0
var _since_noise := FAR_AWAY
var _best_gap := FAR_AWAY
var _stuck_time := 0.0
var _erupt_in_place := false
var _hyperfocus_left := 0.0
var _swing_x := 0.0
var _swing_pending := false
var _luz_air_time := 0.0
var _luz_was_dashing := false
var _luz_was_swinging := false
var _floor_y := 0.0
var _field: Node2D
var _overlay: CanvasLayer
var _overlay_rect: ColorRect
var _catalog: BossAnimationCatalog
var _art_on := false
var _sprite_scale := 1.0
var _sprite_fx: BossSpriteFx
var _hazard_art: BlindBeastHazardArt
## The contract clip last requested through `_play` (not the fallback it resolved to).
var _clip: StringName = &""
## True while the drawn eruption shows him rising out of the ground (still untargetable).
var _emerging := false
## True while the intro clip shows him although he is burrowed.
var _intro_shown := false

@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D


## One remembered loud spot (Luz's x). `answered` once an eruption went for it.
class NoiseSpot extends RefCounted:
	var x := 0.0
	var kind := &""
	var answered := false


class Ripple extends RefCounted:
	var x := 0.0
	var age := 0.0


## Cracks on the floor: `dur` is how long they warn, `slot` the order in a sequence.
class Crack extends RefCounted:
	var x := 0.0
	var age := 0.0
	var dur := 0.5
	var slot := 0


class Column extends RefCounted:
	var x := 0.0
	var age := 0.0
	var hurt := false


## A tossed rock: it flies `flight` seconds and lands at `landing_x` on the floor.
class Rock extends RefCounted:
	var alt := false
	var origin := Vector2.ZERO
	var landing_x := 0.0
	var age := 0.0
	var flight := 0.8
	var rise_speed := 0.0


class Pulse extends RefCounted:
	var x := 0.0
	var previous_x := 0.0
	var dir := 1


class RidgeSlot extends RefCounted:
	var x := 0.0
	var width := 40.0
	var raised := false
	var height := 0.0
	var hurt := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_floor_y = global_position.y
	_build_field()
	_setup_sprite()
	_set_contact(false)
	if _dead:
		_show_corpse()
	else:
		_bury()


## -- Public API -------------------------------------------------------------------

## Records a loud spot at `x` (a ripple appears, the beast will go there). The
## polling of Luz calls this; tests and tools may too.
func register_noise(x: float, kind: StringName = &"") -> void:
	var spot := NoiseSpot.new()
	spot.x = _clamp_to_arena(x, _noise_margin())
	spot.kind = kind
	_noise.append(spot)
	while _noise.size() > maxi(noise_memory, 1):
		_noise.pop_front()
	var ripple := Ripple.new()
	ripple.x = spot.x
	_ripples.append(ripple)
	_since_noise = 0.0
	_silence = 0.0
	_reset_tunnel_progress()
	if kind == KIND_SWING:
		_swing_x = spot.x
		_swing_pending = true
	play_cue(CUE_HEARD)
	noise_heard.emit(spot.x, kind)


## Underground or sinking: untargetable.
func is_burrowed() -> bool:
	return not _exposed


## Above ground and hittable.
func is_exposed() -> bool:
	return _exposed


## Grounded, slow and quiet: invisible to the tremor.
func is_luz_still() -> bool:
	return _luz_valid() and _luz.is_on_floor() and absf(_luz.velocity.x) < still_speed and _since_noise >= still_grace


func get_noise_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for spot: NoiseSpot in _noise:
		xs.append(spot.x)
	return xs


func get_noise_kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for spot: NoiseSpot in _noise:
		kinds.append(spot.kind)
	return kinds


func get_crack_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for crack: Crack in _cracks:
		xs.append(crack.x)
	return xs


func get_column_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for column: Column in _columns:
		xs.append(column.x)
	return xs


func get_rock_landing_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for rock: Rock in _rocks:
		xs.append(rock.landing_x)
	return xs


func get_pulse_xs() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	for pulse: Pulse in _pulses:
		xs.append(pulse.x)
	return xs


## One dictionary per slot: `x`, `width`, `raised` and `height` (0 flat, 1 full spike).
func get_ridge_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot: RidgeSlot in _ridge_slots:
		slots.append({"x": slot.x, "width": slot.width, "raised": slot.raised, "height": slot.height})
	return slots


func get_claw_zone() -> Rect2:
	return _claw_zone


func is_claw_zone_visible() -> bool:
	return _claw_visible


## Hazards in the world right now (ripples count: they are drawn on the floor).
func hazard_count() -> int:
	var count := _ripples.size() + _cracks.size() + _columns.size() + _rocks.size() + _pulses.size() + _ridge_slots.size()
	count += 1 if _claw_visible else 0
	count += 1 if _overlay != null else 0
	return count


func has_light_overlay() -> bool:
	return _overlay != null


func get_light_layer() -> int:
	return _overlay.layer if _overlay != null else 0


func get_hyperfocus_cooldown_left() -> float:
	return _hyperfocus_left


func is_chasing() -> bool:
	return _chase_active


## -- Base hooks -------------------------------------------------------------------

func _tick(delta: float) -> void:
	_since_noise += delta
	_hyperfocus_left = maxf(_hyperfocus_left - delta, 0.0)
	if _state == State.FIGHT:
		_silence += delta
	if is_on_floor():
		_floor_y = global_position.y
	if _state != State.IDLE and _state != State.DEFEATED and not _dead:
		_poll_luz_actions(delta)
	_age_ripples(delta)
	_age_cracks(delta)
	_update_columns(delta)
	_update_rocks(delta)
	_update_light(delta)
	_update_intro_art()
	_sync_sprite()
	_sync_hazard_art()
	if _field != null:
		_field.queue_redraw()


func _fight_delay() -> float:
	return think_interval


func _update_fight(delta: float) -> void:
	velocity.x = 0.0
	if _exposed and not _digging:
		_start_dig_in()
	if _digging:
		_update_dig_in(delta)
		return
	_tunnel_toward_noise(delta)


func _choose_next_action() -> int:
	if _exposed or _digging:
		return NO_ATTACK
	var index := _pending_noise_index()
	if index >= 0:
		if absf(_noise[index].x - global_position.x) > arrive_tolerance + 1.0:
			if _stuck_time < stuck_tunnel_time:
				return NO_ATTACK
			_erupt_in_place = true
			return Attack.ERUPTION
		var drawn := _draw_attack(_attack_weights())
		return Attack.ERUPTION if drawn == NO_ATTACK else drawn
	if _silence >= patience_time:
		return Attack.PROBE
	return NO_ATTACK


func _telegraph_time(attack_id: int) -> float:
	match attack_id:
		Attack.CLAW_COUNTER:
			return maxf(claw_telegraph_time, CLAW_MIN_TELEGRAPH)
		Attack.BRAILLE_RIDGE:
			return maxf(ridge_telegraph_time, RIDGE_MIN_TELEGRAPH)
		Attack.TREMOR_PULSE:
			return maxf(tremor_telegraph_time, MIN_TELEGRAPH)
		Attack.CHAIN_ERUPTION:
			return maxf(chain_crack_time, MIN_TELEGRAPH)
	return maxf(crack_time, MIN_TELEGRAPH)


func _active_time(attack_id: int) -> float:
	match attack_id:
		Attack.PROBE, Attack.CHAIN_ERUPTION:
			return float(maxi(_seq_xs.size() - 1, 0)) * _seq_gap + column_active_time
		Attack.CLAW_COUNTER:
			return claw_active_time
		Attack.BRAILLE_RIDGE:
			return float(maxi(_ridge_slots.size() - 1, 0)) * ridge_step + SPIKE_RISE + ridge_spike_hold + SPIKE_RETRACT
		Attack.TREMOR_PULSE:
			return _pulse_travel_time() + _chase_budget()
	return column_active_time


func _recover_time(attack_id: int) -> float:
	match attack_id:
		Attack.PROBE:
			return probe_exposed_time
		Attack.CLAW_COUNTER:
			return claw_recover_time
		Attack.BRAILLE_RIDGE:
			return ridge_recover_time
	# A miss stuns right away: this window only exists when the column hit Luz.
	return exposed_hit_time


func _begin_attack_phase(attack_id: int, phase_id: AttackPhase) -> void:
	match phase_id:
		AttackPhase.TELEGRAPH:
			_begin_telegraph(attack_id)
		AttackPhase.ACTIVE:
			_begin_active(attack_id)
		AttackPhase.RECOVER:
			_begin_recover(attack_id)


func _update_attack_phase(attack_id: int, phase_id: AttackPhase, delta: float) -> void:
	match phase_id:
		AttackPhase.TELEGRAPH:
			_update_telegraph(attack_id)
		AttackPhase.ACTIVE:
			_update_active(attack_id, delta)
		AttackPhase.RECOVER:
			_update_recover(attack_id)


func _end_attack_phase(_attack_id: int, phase_id: AttackPhase) -> void:
	if phase_id == AttackPhase.ACTIVE:
		_linger_claw()
		_clear_sequences()


## Whatever cut the attack short (stun, phase beat, flinch, defeat), its own
## cracks, spikes and pulses go with it. Rocks already in the air still land.
func _leave_state(next: State) -> void:
	if _state == State.ATTACK and next != State.ATTACK:
		_clear_sequences()
	super._leave_state(next)


func _on_phase_entered(phase_id: int) -> void:
	if phase_id >= 3 and dim_light_in_final_phase:
		_ensure_overlay()


func _on_transition_started(_phase_id: int) -> void:
	_clear_sequences()
	_surface()


func _on_stunned(_duration: float) -> void:
	_clear_sequences()
	_surface()


func _update_facing() -> void:
	if _state != State.IDLE and _state != State.FIGHT and _state != State.TRANSITION:
		return
	if not _noise.is_empty():
		set_facing(1 if _noise[_noise.size() - 1].x >= global_position.x else -1)


func _clear_hazards() -> void:
	_clear_sequences()
	_ripples.clear()
	_rocks.clear()
	_free_overlay()
	_sync_hazard_art()
	if _field != null:
		_field.queue_redraw()


func _reset_ai() -> void:
	super._reset_ai()
	if not is_node_ready():
		return
	_noise.clear()
	_silence = 0.0
	_since_noise = FAR_AWAY
	_erupt_in_place = false
	_reset_tunnel_progress()
	_hyperfocus_left = 0.0
	_swing_pending = false
	_luz_air_time = 0.0
	_luz_was_dashing = false
	_luz_was_swinging = false
	_column_hit_luz = false
	_floor_y = global_position.y
	_bury()


func make_corpse_at(at: Vector2, facing: int) -> void:
	super.make_corpse_at(at, facing)
	_show_corpse()


func _on_player_found(player: Node) -> void:
	super._on_player_found(player)
	# Hyperfocus is a bonus: a player without the signal is simply never dazed.
	if player.has_signal(OPEN_EYES_SIGNAL) and not player.is_connected(OPEN_EYES_SIGNAL, _on_open_eyes):
		player.connect(OPEN_EYES_SIGNAL, _on_open_eyes)


## -- Listening to Luz -------------------------------------------------------------

## Edge detection on the player's public API: one noise per loud action.
func _poll_luz_actions(delta: float) -> void:
	if not _luz_valid():
		return
	if _luz.is_on_floor():
		if _luz_air_time >= landing_min_air_time:
			register_noise(_luz.global_position.x, KIND_LANDING)
		_luz_air_time = 0.0
	else:
		_luz_air_time += delta
	var dashing := _luz.is_dash_invulnerable()
	if dashing and not _luz_was_dashing:
		register_noise(_luz.global_position.x, KIND_DASH)
	_luz_was_dashing = dashing
	var swinging := _luz.is_attack_starting()
	if swinging and not _luz_was_swinging:
		register_noise(_luz.global_position.x, KIND_SWING)
	_luz_was_swinging = swinging


func _on_open_eyes() -> void:
	if _dead or _state == State.IDLE or _state == State.DEFEATED:
		return
	register_noise(_luz_x(), KIND_HYPERFOCUS)
	if _exposed or _hyperfocus_left > 0.0 or _state == State.TRANSITION:
		return
	if stun(hyperfocus_stun_time):
		_hyperfocus_left = hyperfocus_cooldown
		hyperfocus_forced.emit()


## The newest noise nobody went for yet, or -1.
func _pending_noise_index() -> int:
	var index := _noise.size() - 1
	if index >= 0 and not _noise[index].answered:
		return index
	return -1


func _answer_noise() -> void:
	for spot: NoiseSpot in _noise:
		spot.answered = true


func _newest_noise_x() -> float:
	return _noise[_noise.size() - 1].x if not _noise.is_empty() else global_position.x


## Keeps a noise spot (and so a column) away from the walls, where the body could
## never arrive.
func _noise_margin() -> float:
	return maxf(_half_width, column_size.x * 0.5)


func _attack_weights() -> PackedFloat32Array:
	var source := weights_phase_one
	if _phase == 2:
		source = weights_phase_two
	elif _phase >= 3:
		source = weights_phase_three
	var weights := PackedFloat32Array()
	weights.resize(ATTACK_COUNT)
	weights.fill(0.0)
	for i: int in mini(ATTACK_COUNT, source.size()):
		if ATTACK_MIN_PHASE[i] <= _phase:
			weights[i] = source[i]
	# The probe answers silence and the claw answers a swing: neither is drawn.
	weights[Attack.PROBE] = 0.0
	weights[Attack.CLAW_COUNTER] = 0.0
	if _noise.size() < 2:
		weights[Attack.CHAIN_ERUPTION] = 0.0
	return weights


## -- Burrowed movement ------------------------------------------------------------

func _tunnel_toward_noise(delta: float) -> void:
	var index := _pending_noise_index()
	if index < 0:
		return
	var gap := _noise[index].x - global_position.x
	if absf(gap) <= arrive_tolerance:
		return
	if absf(gap) < _best_gap - TUNNEL_PROGRESS_STEP:
		_best_gap = absf(gap)
		_stuck_time = 0.0
	else:
		_stuck_time += delta
	velocity.x = signf(gap) * minf(tunnel_speed, absf(gap) / maxf(delta, 0.001))


func _reset_tunnel_progress() -> void:
	_best_gap = FAR_AWAY
	_stuck_time = 0.0


func _start_dig_in() -> void:
	_exposed = false
	_digging = true
	_dig_left = dig_in_time
	_set_hittable(false)
	_puff(BlindBeastHazardArt.DIG_DIRT, global_position.x)
	play_cue(CUE_DIG)


func _update_dig_in(delta: float) -> void:
	_dig_left -= delta
	var progress := 1.0 if dig_in_time <= 0.0 else 1.0 - clampf(_dig_left / dig_in_time, 0.0, 1.0)
	# The drawn `dig_in` is already cut at the floor line: it must not sink as well.
	if _visual != null and not _art_on:
		_visual.position.y = dig_depth * progress
	if _dig_left <= 0.0:
		_digging = false
		_hide_body()
		buried.emit()


func _bury() -> void:
	_exposed = false
	_digging = false
	_set_hittable(false)
	_set_contact(false)
	_hide_body()


func _hide_body() -> void:
	_emerging = false
	_intro_shown = false
	if _visual != null:
		_visual.visible = false
		_visual.position.y = 0.0


func _surface() -> void:
	var was_buried := not _exposed
	_exposed = true
	_digging = false
	_emerging = false
	if _visual != null:
		_visual.visible = true
		_visual.position.y = 0.0
	_set_hittable(true)
	if was_buried:
		surfaced.emit()


func _surface_at(x: float) -> void:
	global_position.x = _clamp_to_arena(x, _half_width)
	_surface()


func _show_corpse() -> void:
	_exposed = true
	_digging = false
	_emerging = false
	_set_hittable(false)
	if _visual != null:
		_visual.visible = true
		_visual.position.y = 0.0


## -- Attack lifecycle -------------------------------------------------------------

func _begin_telegraph(attack_id: int) -> void:
	_silence = 0.0
	_column_hit_luz = false
	_reset_tunnel_progress()
	match attack_id:
		Attack.ERUPTION, Attack.DEBRIS_TOSS:
			_plan_single_eruption()
		Attack.PROBE:
			_plan_probe()
		Attack.CLAW_COUNTER:
			_plan_claw()
		Attack.BRAILLE_RIDGE:
			_answer_noise()
			_plan_ridge()
			if _ridge_slots.is_empty():
				# Nothing valid to raise: a plain eruption answers the noise.
				_attack = Attack.ERUPTION
				_plan_single_eruption()
		Attack.TREMOR_PULSE:
			_answer_noise()
			_surface_at(global_position.x)
		Attack.CHAIN_ERUPTION:
			_plan_chain()


func _begin_active(attack_id: int) -> void:
	match attack_id:
		Attack.ERUPTION:
			_burst_single()
			_start_emerge()
		Attack.DEBRIS_TOSS:
			_burst_single()
			_start_emerge()
			_toss_debris(_attack_x)
		Attack.PROBE, Attack.CHAIN_ERUPTION:
			_seq_time = 0.0
			_seq_next = 0
		Attack.CLAW_COUNTER:
			_claw_hit = false
			play_cue(CUE_CLAW)
		Attack.BRAILLE_RIDGE:
			_ridge_time = 0.0
			play_cue(CUE_RIDGE)
		Attack.TREMOR_PULSE:
			_launch_pulses()


func _begin_recover(attack_id: int) -> void:
	match attack_id:
		Attack.ERUPTION, Attack.DEBRIS_TOSS, Attack.CHAIN_ERUPTION, Attack.TREMOR_PULSE:
			_surface_at(_last_burst_x)
			_swing_pending = false
			if not _column_hit_luz:
				stun(missed_stun_time)
		Attack.PROBE:
			_surface_at(_last_burst_x)
			_swing_pending = false


func _update_telegraph(attack_id: int) -> void:
	if _telegraph == null or not _exposed:
		return
	if attack_id == Attack.CLAW_COUNTER or attack_id == Attack.TREMOR_PULSE:
		_telegraph.set_glow(BossTelegraph.MELEE_COLOR, 0.5 + 0.4 * sin(_clock * 14.0))


func _update_active(attack_id: int, delta: float) -> void:
	match attack_id:
		Attack.PROBE, Attack.CHAIN_ERUPTION:
			_update_sequence(delta)
		Attack.CLAW_COUNTER:
			_update_claw()
		Attack.BRAILLE_RIDGE:
			_update_ridge(delta)
		Attack.TREMOR_PULSE:
			_update_tremor(delta)


## An exposed beast that has just hit Luz hears the next swing and counters it.
func _update_recover(attack_id: int) -> void:
	var can_counter := attack_id == Attack.PROBE or (attack_id != Attack.CLAW_COUNTER and attack_id != Attack.BRAILLE_RIDGE and _column_hit_luz)
	if can_counter and _exposed and _swing_pending and absf(_swing_x - global_position.x) <= claw_reach:
		start_attack(Attack.CLAW_COUNTER)


## -- Eruption, probe and chain -----------------------------------------------------

func _plan_single_eruption() -> void:
	_attack_x = global_position.x if _erupt_in_place else _newest_noise_x()
	_erupt_in_place = false
	_answer_noise()
	_add_crack(_attack_x, maxf(crack_time, MIN_TELEGRAPH), 0)


func _burst_single() -> void:
	_cracks.clear()
	_attack_x = clampf(_attack_x, _arena_bounds().x, _arena_bounds().y)
	global_position.x = _clamp_to_arena(_attack_x, _half_width)
	_spawn_column(_attack_x)


func _plan_probe() -> void:
	var bounds := _arena_bounds()
	var margin := _noise_margin()
	var count := maxi(probe_count, 1)
	var xs: Array[float] = []
	for i: int in count:
		xs.append(lerpf(bounds.x + margin, bounds.y - margin, float(i + 1) / float(count + 1)))
	if rng.randf() < 0.5:
		xs.reverse()
	_plan_sequence(xs, probe_gap, maxf(crack_time, MIN_TELEGRAPH))


func _plan_chain() -> void:
	var xs: Array[float] = []
	for spot: NoiseSpot in _noise:
		xs.append(spot.x)
	if xs.is_empty():
		xs.append(global_position.x)
	_answer_noise()
	_plan_sequence(xs, chain_interval, maxf(chain_crack_time, MIN_TELEGRAPH))


## Every crack shows at once; each burst follows `gap` after the previous one, so
## the later cracks warn for longer than the first.
func _plan_sequence(xs: Array[float], gap: float, first_warning: float) -> void:
	_seq_xs = xs
	_seq_gap = gap
	_seq_time = 0.0
	_seq_next = 0
	for i: int in xs.size():
		_add_crack(xs[i], first_warning + float(i) * gap, i)


func _update_sequence(delta: float) -> void:
	_seq_time += delta
	while _seq_next < _seq_xs.size() and _seq_time >= float(_seq_next) * _seq_gap:
		_remove_crack_slot(_seq_next)
		_spawn_column(_seq_xs[_seq_next])
		_seq_next += 1


func _add_crack(x: float, duration: float, slot: int) -> void:
	var crack := Crack.new()
	crack.x = x
	crack.dur = duration
	crack.slot = slot
	_cracks.append(crack)


func _remove_crack_slot(slot: int) -> void:
	for i: int in range(_cracks.size() - 1, -1, -1):
		if _cracks[i].slot == slot:
			_cracks.remove_at(i)


func _spawn_column(x: float) -> void:
	var column := Column.new()
	column.x = x
	_columns.append(column)
	_last_burst_x = x
	_puff(BlindBeastHazardArt.DUST, x)
	play_cue(CUE_ERUPT)
	_shake(eruption_shake, 0.2)


func _age_cracks(delta: float) -> void:
	for crack: Crack in _cracks:
		crack.age += delta


func _update_columns(delta: float) -> void:
	for i: int in range(_columns.size() - 1, -1, -1):
		var column := _columns[i]
		column.age += delta
		if column.age >= column_active_time:
			_columns.remove_at(i)
			continue
		if not column.hurt and _rect_hits_luz(_column_rect(column)):
			if _hurt_luz(column_damage, Vector2(column.x, _floor_y)):
				column.hurt = true
				_column_hit_luz = true


func _column_rect(column: Column) -> Rect2:
	var grow := 1.0 if column_rise_time <= 0.0 else clampf(column.age / column_rise_time, 0.0, 1.0)
	var height := column_size.y * grow
	return Rect2(column.x - column_size.x * 0.5, _floor_y - height, column_size.x, height)


## -- Claw counter -----------------------------------------------------------------

## The claw aims where the swing came from, not where Luz stands now.
func _plan_claw() -> void:
	var origin := _swing_x
	_swing_pending = false
	_claw_zone = Rect2(origin - claw_zone_size.x * 0.5, _floor_y - claw_zone_size.y, claw_zone_size.x, claw_zone_size.y)
	_claw_visible = true
	set_facing(1 if origin >= global_position.x else -1)


func _update_claw() -> void:
	if _claw_hit or not _rect_hits_luz(_claw_zone):
		return
	_claw_hit = _hurt_luz(claw_damage, Vector2(_claw_zone.get_center().x, _floor_y))


## -- Braille ridge ----------------------------------------------------------------

func _plan_ridge() -> void:
	_ridge_slots.clear()
	_ridge_time = 0.0
	var bounds := _arena_bounds()
	var width := bounds.y - bounds.x
	var pattern := _ridge_pattern(int(width / MIN_SLOT_WIDTH))
	if pattern.is_empty():
		return
	var count := pattern.length()
	var slot_width := clampf(width / float(count), MIN_SLOT_WIDTH, maxf(ridge_slot_width, MIN_SLOT_WIDTH))
	var start := (bounds.x + bounds.y) * 0.5 - float(count) * slot_width * 0.5
	for i: int in count:
		var slot := RidgeSlot.new()
		slot.width = slot_width
		slot.x = start + (float(i) + 0.5) * slot_width
		slot.raised = pattern[i] == "#"
		_ridge_slots.append(slot)


## The cells of one valid word, never longer than `max_slots` (what fits between the
## walls at the minimum slot width). A word that fits is preferred; else the
## pattern is cut. Empty when no word is valid or nothing fits.
func _ridge_pattern(max_slots: int) -> String:
	var patterns: Array[String] = []
	for word: String in ridge_words:
		var pattern := _word_pattern(word)
		if not pattern.is_empty():
			patterns.append(pattern)
	if patterns.is_empty() or max_slots < 1:
		return ""
	var fitting: Array[String] = patterns.filter(func(pattern: String) -> bool: return pattern.length() <= max_slots)
	if not fitting.is_empty():
		return fitting[rng.randi() % fitting.size()]
	return patterns[rng.randi() % patterns.size()].left(max_slots)


## Braille cells of `word` with a flat slot between letters; empty when the word
## has no letter of the table.
func _word_pattern(word: String) -> String:
	var cells := PackedStringArray()
	var known := false
	for letter: String in word.strip_edges().to_upper():
		known = known or BRAILLE_LETTERS.has(letter)
		cells.append(String(BRAILLE_LETTERS.get(letter, FLAT_CELL)))
	return ".".join(cells) if known else ""


func _update_ridge(delta: float) -> void:
	_ridge_time += delta
	for i: int in _ridge_slots.size():
		var slot := _ridge_slots[i]
		if not slot.raised:
			continue
		slot.height = _spike_profile(_ridge_time - float(i) * ridge_step)
		if slot.hurt or slot.height < SPIKE_HURT_FROM:
			continue
		var height := ridge_spike_height * slot.height
		var rect := Rect2(slot.x - slot.width * 0.5 * SPIKE_HIT_SHARE, _floor_y - height, slot.width * SPIKE_HIT_SHARE, height)
		if _rect_hits_luz(rect):
			slot.hurt = _hurt_luz(ridge_damage, Vector2(slot.x, _floor_y))


## 0 before the slot's turn, 1 while the spike is up, 0 again once it retracted.
func _spike_profile(local_time: float) -> float:
	if local_time < 0.0:
		return 0.0
	if local_time < SPIKE_RISE:
		return local_time / SPIKE_RISE
	var held := local_time - SPIKE_RISE
	if held < ridge_spike_hold:
		return 1.0
	return clampf(1.0 - (held - ridge_spike_hold) / SPIKE_RETRACT, 0.0, 1.0)


## -- Debris toss ------------------------------------------------------------------

func _toss_debris(center_x: float) -> void:
	var bounds := _arena_bounds()
	var origin := Vector2(center_x, _floor_y - column_size.y)
	var flight := maxf(debris_flight_time, MIN_TELEGRAPH)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for i: int in maxi(debris_count, 0):
		var rock := Rock.new()
		var reach := debris_spread * float(1 + i / 2)
		rock.alt = i % 2 == 1
		rock.landing_x = clampf(center_x + side * reach, bounds.x + debris_radius, bounds.y - debris_radius)
		rock.origin = origin
		rock.flight = flight
		# Solves y(flight) = floor for a parabola that starts at the column top.
		rock.rise_speed = (_floor_y - origin.y - 0.5 * debris_gravity * flight * flight) / flight
		_rocks.append(rock)
		side = -side
	play_cue(CUE_DEBRIS)


func _update_rocks(delta: float) -> void:
	for i: int in range(_rocks.size() - 1, -1, -1):
		var rock := _rocks[i]
		rock.age += delta
		if rock.age >= rock.flight:
			_land_rock(rock)
			_rocks.remove_at(i)


func _land_rock(rock: Rock) -> void:
	_puff(BlindBeastHazardArt.ROCK_IMPACT, rock.landing_x)
	var size := debris_radius * 2.0
	if _rect_hits_luz(Rect2(rock.landing_x - debris_radius, _floor_y - size, size, size)):
		_hurt_luz(debris_damage, Vector2(rock.landing_x, _floor_y))


func _rock_position(rock: Rock) -> Vector2:
	var t := rock.age
	var x := lerpf(rock.origin.x, rock.landing_x, clampf(t / rock.flight, 0.0, 1.0))
	return Vector2(x, rock.origin.y + rock.rise_speed * t + 0.5 * debris_gravity * t * t)


## -- Tremor pulse -----------------------------------------------------------------

func _launch_pulses() -> void:
	_chase_active = false
	for dir: int in [-1, 1]:
		var pulse := Pulse.new()
		pulse.x = global_position.x
		pulse.previous_x = pulse.x
		pulse.dir = dir
		_pulses.append(pulse)
	play_cue(CUE_PULSE)
	_shake(tremor_shake, 0.3)


func _update_tremor(delta: float) -> void:
	if _chase_active:
		_update_chase(delta)
		return
	var bounds := _arena_bounds()
	for i: int in range(_pulses.size() - 1, -1, -1):
		var pulse := _pulses[i]
		pulse.previous_x = pulse.x
		pulse.x += float(pulse.dir) * pulse_speed * delta
		if _pulse_feels_luz(pulse):
			_start_chase()
			return
		if pulse.x < bounds.x - 8.0 or pulse.x > bounds.y + 8.0:
			_pulses.remove_at(i)
	if _pulses.is_empty():
		stun(tremor_confused_time)


## It feels her only when she is grounded and not still as the pulse passes.
func _pulse_feels_luz(pulse: Pulse) -> bool:
	if not _luz_valid() or not _luz.is_on_floor() or is_luz_still():
		return false
	var low := minf(pulse.previous_x, pulse.x) - pulse_half_width
	var high := maxf(pulse.previous_x, pulse.x) + pulse_half_width
	return _luz.global_position.x >= low and _luz.global_position.x <= high


func _start_chase() -> void:
	_pulses.clear()
	_chase_active = true
	_chase_waiting_burst = false
	_chase_clock = 0.0
	_chase_done = 0
	_bury()


func _update_chase(delta: float) -> void:
	_chase_clock -= delta
	if _chase_clock > 0.0:
		return
	if _chase_waiting_burst:
		_burst_chase()
	elif _chase_done < chase_count:
		_start_chase_crack()
	else:
		_state_left = 0.0


## Each fast eruption goes where Luz really is as its crack appears.
func _start_chase_crack() -> void:
	var warning := maxf(chase_crack_time, MIN_TELEGRAPH)
	_chase_crack = Crack.new()
	_chase_crack.x = _clamp_to_arena(_luz_x(), _noise_margin())
	_chase_crack.dur = warning
	_cracks.append(_chase_crack)
	_chase_waiting_burst = true
	_chase_clock = warning


func _burst_chase() -> void:
	_cracks.erase(_chase_crack)
	_spawn_column(_chase_crack.x)
	_chase_done += 1
	_chase_waiting_burst = false
	_chase_clock = column_active_time + chase_gap


func _pulse_travel_time() -> float:
	var bounds := _arena_bounds()
	return maxf(global_position.x - bounds.x, bounds.y - global_position.x) / maxf(pulse_speed, 1.0) + 0.15


func _chase_budget() -> float:
	var one := maxf(chase_crack_time, MIN_TELEGRAPH) + column_active_time + chase_gap
	return float(chase_count) * one + 0.2


## -- Cleanup ----------------------------------------------------------------------

## Removes what a single attack owns. Rocks and ripples are not part of it.
func _clear_sequences() -> void:
	_cracks.clear()
	_columns.clear()
	_pulses.clear()
	_ridge_slots.clear()
	_seq_xs.clear()
	_seq_next = 0
	_claw_visible = false
	_claw_zone = Rect2()
	_chase_active = false
	_chase_waiting_burst = false
	_chase_crack = null


func _age_ripples(delta: float) -> void:
	for i: int in range(_ripples.size() - 1, -1, -1):
		_ripples[i].age += delta
		if _ripples[i].age >= ripple_time:
			_ripples.remove_at(i)


## -- Hurting Luz ------------------------------------------------------------------

func _luz_rect() -> Rect2:
	return Rect2(_luz.global_position + Vector2(-LUZ_BODY_SIZE.x * 0.5, -LUZ_BODY_SIZE.y), LUZ_BODY_SIZE)


func _rect_hits_luz(rect: Rect2) -> bool:
	return _luz_valid() and rect.intersects(_luz_rect())


## True on the frame the hit landed: Luz's own gate refuses it during dash
## i-frames and after a hit.
func _hurt_luz(damage: int, source: Vector2) -> bool:
	return _luz_valid() and _luz.take_damage(damage, source)


## -- Dimmed light -----------------------------------------------------------------

func _ensure_overlay() -> void:
	if _overlay != null or _dead:
		return
	_overlay = CanvasLayer.new()
	# Below the HUD (40) and the boss bar (41): purely a cosmetic tint.
	_overlay.layer = LIGHT_LAYER
	_overlay_rect = ColorRect.new()
	_overlay_rect.color = Color(0.02, 0.02, 0.08, 0.0)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_overlay_rect)
	add_child(_overlay)


func _free_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = null
	_overlay_rect = null


func _update_light(delta: float) -> void:
	if _phase >= 3 and dim_light_in_final_phase and _overlay == null:
		_ensure_overlay()
	if _overlay_rect == null:
		return
	var alpha := move_toward(_overlay_rect.color.a, dim_alpha, LIGHT_FADE_RATE * delta)
	_overlay_rect.color = Color(_overlay_rect.color, alpha)


## -- Drawing ----------------------------------------------------------------------

func _build_field() -> void:
	_field = Node2D.new()
	_field.name = "Hazards"
	_field.top_level = true
	_field.z_index = 1
	add_child(_field)
	_field.draw.connect(_draw_hazards)


func _draw_hazards() -> void:
	if _field == null:
		return
	var y := _floor_y
	_draw_ripples(y)
	_draw_mound(y)
	_draw_ridge(y)
	_draw_cracks(y)
	_draw_rock_markers(y)
	_draw_columns(y)
	_draw_claw()
	_draw_pulses(y)
	_draw_rocks()


func _draw_ripples(y: float) -> void:
	for i: int in _ripples.size():
		var ripple := _ripples[i]
		var t := clampf(ripple.age / ripple_time, 0.0, 1.0)
		var newest := i == _ripples.size() - 1
		var alpha := (1.0 - t) * (1.0 if newest else 0.5)
		var radius := lerpf(RIPPLE_MIN_RADIUS, RIPPLE_MAX_RADIUS, t)
		_field.draw_set_transform(Vector2(ripple.x, y), 0.0, Vector2(1.0, RIPPLE_SQUASH))
		_field.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(RIPPLE_COLOR, alpha), 3.0 if newest else 2.0)
		_field.draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 24, Color(RIPPLE_COLOR, alpha * 0.7), 2.0)
		_field.draw_set_transform_matrix(Transform2D.IDENTITY)


func _mound_visible() -> bool:
	return show_mound and not _exposed and not _digging and not _dead and not _emerging and not _intro_shown


func _draw_mound(y: float) -> void:
	if not _mound_visible():
		return
	var moving := absf(velocity.x) > 1.0
	if not _has_hazard_art(BoomboxEffectArt.PROPS, BlindBeastHazardArt.MOUND):
		var height := MOUND_HEIGHT + (sin(_clock * 12.0) * 1.5 if moving else 0.0)
		var points := PackedVector2Array()
		for i: int in MOUND_STEPS + 1:
			var angle := PI + PI * float(i) / float(MOUND_STEPS)
			points.append(Vector2(global_position.x + cos(angle) * MOUND_HALF_WIDTH, y + sin(angle) * height))
		_field.draw_colored_polygon(points, DIRT_COLOR)
		_field.draw_polyline(points, DIRT_DARK, 2.0)
	if moving:
		var trail := -signf(velocity.x) * (MOUND_HALF_WIDTH + 6.0)
		_field.draw_circle(Vector2(global_position.x + trail, y - 3.0), 3.0, DIRT_COLOR)
		_field.draw_circle(Vector2(global_position.x + trail * 1.7, y - 2.0), 2.0, DIRT_COLOR)


func _draw_cracks(y: float) -> void:
	var half := column_size.x * 0.5
	var crack_art := _has_hazard_art(BoomboxEffectArt.PROPS, BlindBeastHazardArt.CRACK)
	for crack: Crack in _cracks:
		var progress := clampf(crack.age / crack.dur, 0.0, 1.0)
		var color := BossTelegraph.MELEE_COLOR
		_field.draw_rect(Rect2(crack.x - half, y - FOOTPRINT_HEIGHT, half * 2.0, FOOTPRINT_HEIGHT), Color(color, 0.2 + 0.4 * progress))
		_field.draw_rect(Rect2(crack.x - half, y - column_size.y, half * 2.0, column_size.y), Color(color, 0.1 + 0.2 * progress), false, 1.5)
		if crack_art:
			continue
		var points := PackedVector2Array()
		for i: int in CRACK_ZIGZAG.size():
			var x := crack.x - half + half * 2.0 * float(i) / float(CRACK_ZIGZAG.size() - 1)
			points.append(Vector2(x, y - 2.0 + CRACK_ZIGZAG[i] * (0.5 + progress)))
		_field.draw_polyline(points, Color(color, 0.7 + 0.3 * progress), 3.0)


func _draw_columns(y: float) -> void:
	if _has_hazard_art(BoomboxEffectArt.FX, BlindBeastHazardArt.COLUMN):
		return
	for column: Column in _columns:
		var rect := _column_rect(column)
		var points := PackedVector2Array([
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			Vector2(rect.end.x - rect.size.x * 0.12, rect.position.y),
			Vector2(rect.position.x + rect.size.x * 0.12, rect.position.y),
		])
		_field.draw_colored_polygon(points, DIRT_COLOR)
		_field.draw_polyline(PackedVector2Array([points[0], points[3], points[2], points[1]]), BossTelegraph.MELEE_COLOR, 3.0)


func _draw_claw() -> void:
	if not _claw_visible:
		return
	var color := BossTelegraph.MELEE_COLOR
	var alpha := 0.25 + 0.15 * sin(_clock * CLAW_WARNING_PULSE) if is_telegraphing() else 0.7
	if _has_hazard_art(BoomboxEffectArt.CLAW_FX, BlindBeastHazardArt.CLAW):
		# The swipe is drawn; only the warning keeps its zone fill under the scratch lines.
		if is_telegraphing():
			_field.draw_rect(_claw_zone, Color(color, alpha))
		return
	_field.draw_rect(_claw_zone, Color(color, alpha))
	_field.draw_rect(_claw_zone, color, false, 2.0)
	for i: int in 3:
		var x := _claw_zone.position.x + _claw_zone.size.x * (0.25 + 0.25 * float(i))
		_field.draw_line(Vector2(x - 10.0, _claw_zone.position.y), Vector2(x + 10.0, _claw_zone.end.y), color, 3.0)


func _draw_ridge(y: float) -> void:
	for slot: RidgeSlot in _ridge_slots:
		var half := slot.width * 0.5
		if slot.height > 0.0:
			if _has_hazard_art(BoomboxEffectArt.PROPS, BlindBeastHazardArt.SPIKE):
				continue
			var top := y - ridge_spike_height * slot.height
			_field.draw_colored_polygon(PackedVector2Array([Vector2(slot.x - half, y), Vector2(slot.x + half, y), Vector2(slot.x, top)]), Color(0.95, 0.9, 0.85))
			_field.draw_polyline(PackedVector2Array([Vector2(slot.x - half, y), Vector2(slot.x, top), Vector2(slot.x + half, y)]), BossTelegraph.MELEE_COLOR, 3.0)
			continue
		var bump := 12.0 if slot.raised else 6.0
		var fill := RIDGE_FLAT_COLOR
		if slot.raised:
			fill = BossTelegraph.MELEE_COLOR.lerp(Color.WHITE, 0.3 + 0.25 * sin(_clock * 10.0))
		var points := PackedVector2Array()
		for i: int in MOUND_STEPS + 1:
			var angle := PI + PI * float(i) / float(MOUND_STEPS)
			points.append(Vector2(slot.x + cos(angle) * half * 0.85, y + sin(angle) * bump))
		_field.draw_colored_polygon(points, fill)
		_field.draw_polyline(points, DIRT_DARK, 2.0)


func _draw_rock_markers(y: float) -> void:
	for rock: Rock in _rocks:
		var progress := clampf(rock.age / rock.flight, 0.0, 1.0)
		_field.draw_set_transform(Vector2(rock.landing_x, y), 0.0, Vector2(1.0, 0.3))
		_field.draw_circle(Vector2.ZERO, debris_radius, Color(BossTelegraph.RANGED_COLOR, 0.25 + 0.4 * progress))
		_field.draw_arc(Vector2.ZERO, debris_radius, 0.0, TAU, 24, BossTelegraph.RANGED_COLOR, 3.0)
		_field.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_rocks() -> void:
	if _has_hazard_art(BoomboxEffectArt.PROPS, BlindBeastHazardArt.ROCK):
		return
	for rock: Rock in _rocks:
		var at := _rock_position(rock)
		_field.draw_circle(at, debris_radius * 0.7, ROCK_COLOR)
		_field.draw_arc(at, debris_radius * 0.7, 0.0, TAU, 16, DIRT_DARK, 2.0)


func _draw_pulses(y: float) -> void:
	if _has_hazard_art(BoomboxEffectArt.FX, BlindBeastHazardArt.PULSE):
		return
	for pulse: Pulse in _pulses:
		var trail := -float(pulse.dir) * 28.0
		var points := PackedVector2Array([
			Vector2(pulse.x + trail, y),
			Vector2(pulse.x - float(pulse.dir) * 4.0, y - 20.0),
			Vector2(pulse.x + float(pulse.dir) * 8.0, y),
		])
		_field.draw_colored_polygon(points, Color(BossTelegraph.RANGED_COLOR, 0.8))
		_field.draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), BossTelegraph.RANGED_COLOR, 3.0)


## -- Sprite ---------------------------------------------------------------------------

## Shows the sprite and hides the placeholder polygons when the manifest has art; with
## none he looks exactly as before. The props and effects are independent of it: each
## hazard dresses itself when its clip exists and keeps its placeholder when not.
func _setup_sprite() -> void:
	if _sprite == null:
		return
	_catalog = BossAnimationCatalog.new(animation_manifest, CLIP_FALLBACKS, CLIP_SPEEDS, LOOPING_CLIPS, &"exposed_idle")
	_hazard_art = BlindBeastHazardArt.new(_catalog)
	_art_on = _catalog.has_art()
	_sprite.visible = _art_on
	_set_placeholders_visible(not _art_on)
	if not _art_on:
		return
	_sprite.sprite_frames = _catalog.build_sprite_frames()
	_sprite.offset = _catalog.sprite_offset()
	_sprite_scale = _catalog.sprite_scale()
	_visual.move_child(_sprite, 0)
	_bind_sprite_fx()
	_clip = &""
	_apply_visual()


func _set_placeholders_visible(on: bool) -> void:
	for node_name: String in PLACEHOLDERS:
		var node := _visual.get_node_or_null(node_name) as CanvasItem if _visual != null else null
		if node != null:
			node.visible = on


## The hit flash and the telegraph glow are drawn by a shader on the sprite itself, so
## they follow its exact silhouette; the polygon overlays stay hidden.
func _bind_sprite_fx() -> void:
	_sprite_fx = BossSpriteFx.new(_sprite)
	if _flash != null:
		_flash.visible = false
	if _telegraph != null:
		_telegraph.bind_sprite_fx(_sprite_fx)


## With art the flash is the sprite's own; without it, the white polygon as always.
func _set_flash_visible(visible_now: bool) -> void:
	if _sprite_fx != null:
		_sprite_fx.set_flash(visible_now)
		return
	super._set_flash_visible(visible_now)


## True while the hit flash shows, on the sprite or on the placeholder.
func is_flash_visible() -> bool:
	if _sprite_fx != null:
		return _sprite_fx.is_flashing()
	return _flash != null and _flash.visible


func has_art() -> bool:
	return _art_on


## The contract clip last requested.
func get_clip() -> StringName:
	return _clip


func _apply_visual() -> void:
	super._apply_visual()
	_cancel_visual_pose()
	_sync_sprite()


## The drawn clips already carry the slump of the corpse, so the sprite undoes `Visual`'s
## tilt and squash; only the facing flip is left on it.
func _cancel_visual_pose() -> void:
	if not _art_on or _visual == null:
		return
	var pose := Transform2D(_visual.rotation, _visual.scale, 0.0, Vector2.ZERO)
	var wanted := Transform2D(0.0, Vector2(_visual.scale.x, 1.0), 0.0, Vector2.ZERO)
	var basis := pose.affine_inverse() * wanted
	_sprite.transform = Transform2D(basis.x * _sprite_scale, basis.y * _sprite_scale, _sprite.position)


func _has_clip(clip: StringName) -> bool:
	return _art_on and _sprite.sprite_frames.has_animation(clip)


## Plays the contract clip `clip` (or the closest drawn one) stretched to last
## `duration` seconds (0: default speed). A corpse restored from an earlier run shows
## the last frame at once.
func _play(clip: StringName, duration := 0.0) -> void:
	if not _art_on:
		return
	_clip = clip
	var resolved := _catalog.resolve_clip(clip)
	if resolved.is_empty():
		return
	var frames := _sprite.sprite_frames
	var count := frames.get_frame_count(resolved)
	var fps := frames.get_animation_speed(resolved)
	var fit := 1.0
	if duration > 0.0 and count > 0 and fps > 0.0:
		fit = (float(count) / fps) / duration
	_sprite.play(resolved, fit)
	if _state == State.DEFEATED and _defeat_left <= 0.0:
		_sprite.pause()
		_sprite.frame = count - 1


## Picks the clip for what the state machine is doing and plays it when it changes. A
## pure read of the logic: no state or timer is touched.
func _sync_sprite() -> void:
	# A new attack enters ATTACK before its first phase opens: its timers are stale.
	if not _art_on or (_state == State.ATTACK and not _attack_open):
		return
	var request := _clip_request()
	if request[0] != _clip:
		_play(request[0], request[1])


## [clip, duration] for the current state; duration 0 plays at the clip's own speed.
func _clip_request() -> Array:
	match _state:
		State.DEFEATED:
			return [&"defeat", defeat_time]
		State.STUN:
			return [&"dazed", 0.0]
		State.TRANSITION:
			return [&"phase_change", phase_transition_time]
		State.ATTACK:
			return _attack_clip_request()
		State.IDLE:
			if _intro_left > 0.0:
				return [&"intro", _intro_left]
		State.FIGHT:
			if _digging:
				return [&"dig_in", dig_in_time]
	return [&"exposed_idle", 0.0]


func _attack_clip_request() -> Array:
	match _attack:
		Attack.CLAW_COUNTER:
			match _attack_phase:
				AttackPhase.TELEGRAPH:
					return [&"claw_windup", maxf(_telegraph_time(_attack), MIN_CLIP_TIME)]
				AttackPhase.ACTIVE:
					return [&"claw_strike", maxf(claw_active_time, MIN_CLIP_TIME)]
			return [&"claw_recover", maxf(_state_left, MIN_CLIP_TIME)]
		Attack.TREMOR_PULSE:
			match _attack_phase:
				AttackPhase.TELEGRAPH:
					return [&"slam_windup", maxf(_telegraph_time(_attack), MIN_CLIP_TIME)]
				AttackPhase.ACTIVE:
					return [&"slam_strike", SLAM_STRIKE_TIME]
		Attack.ERUPTION, Attack.DEBRIS_TOSS:
			if _attack_phase == AttackPhase.ACTIVE and _emerging:
				return [&"emerge", maxf(column_active_time, MIN_CLIP_TIME)]
	return [&"exposed_idle", 0.0]


## The drawn eruption shows him rising through the column. He is still burrowed for the
## rules (`is_burrowed`, untargetable): only the picture changes.
func _start_emerge() -> void:
	if not _has_clip(&"emerge") or _visual == null:
		return
	_emerging = true
	_visual.visible = true
	_visual.position.y = 0.0


## The intro clip shows the old man turning into the beast although he is burrowed; when
## the intro is over he goes under again.
func _on_intro(_duration: float) -> void:
	if _dead or not _has_clip(&"intro") or _visual == null:
		return
	_intro_shown = true
	_visual.visible = true


func _update_intro_art() -> void:
	if _intro_shown and _intro_left <= 0.0:
		_intro_shown = false
		if not _exposed:
			_hide_body()


## -- Hazard art -------------------------------------------------------------------------

func _has_hazard_art(key: String, clip: StringName) -> bool:
	return _hazard_art != null and _hazard_art.has_clip(key, clip)


## One sprite per live hazard that has art; the placeholders of the others stay.
func _sync_hazard_art() -> void:
	if _hazard_art == null or _field == null:
		return
	var mound: Array = [self] if _mound_visible() else []
	_hazard_art.sync(_field, &"mound", mound, _make_mound, _place_mound)
	_hazard_art.sync(_field, &"crack", _cracks, _make_crack, _place_crack)
	_hazard_art.sync(_field, &"column", _columns, _make_column, _place_column)
	_hazard_art.sync(_field, &"spike", _rising_slots(), _make_spike, _place_spike)
	_hazard_art.sync(_field, &"rock", _rocks, _make_rock, _place_rock)
	_hazard_art.sync(_field, &"pulse", _pulses, _make_pulse, _place_pulse)
	_hazard_art.sync(_field, &"claw", [self] if _claw_visible else [], _make_claw, _place_claw)


## The braille slots that are spikes right now (the flat and telegraphed ones are drawn).
func _rising_slots() -> Array:
	return _ridge_slots.filter(func(slot: RidgeSlot) -> bool: return slot.raised and slot.height > 0.0)


func _make_mound(_item: Variant) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.PROPS, BlindBeastHazardArt.MOUND, Vector2(MOUND_ART_WIDTH, MOUND_ART_WIDTH), BoomboxHazard.ArtFit.WIDTH)


func _place_mound(_item: Variant, sprite: AnimatedSprite2D) -> void:
	_hazard_art.stand_on_floor(sprite, BoomboxEffectArt.PROPS, BlindBeastHazardArt.MOUND, global_position.x, _floor_y)


func _make_crack(_item: Variant) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.PROPS, BlindBeastHazardArt.CRACK, Vector2(column_size.x, column_size.x), BoomboxHazard.ArtFit.WIDTH)


## The crack opens as the warning runs down; the floor footprint under it keeps its red.
func _place_crack(crack: Crack, sprite: AnimatedSprite2D) -> void:
	_hazard_art.stand_on_floor(sprite, BoomboxEffectArt.PROPS, BlindBeastHazardArt.CRACK, crack.x, _floor_y)
	sprite.modulate.a = lerpf(CRACK_MIN_ALPHA, 1.0, clampf(crack.age / crack.dur, 0.0, 1.0))


func _make_column(_item: Variant) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.FX, BlindBeastHazardArt.COLUMN, column_size, BoomboxHazard.ArtFit.STRETCH)


## The art fills the box that hurts, rising with it, and follows the column's own clock.
func _place_column(column: Column, sprite: AnimatedSprite2D) -> void:
	var rect := _column_rect(column)
	sprite.scale = BoomboxHazard.art_scale(_hazard_art.art_size(BoomboxEffectArt.FX, BlindBeastHazardArt.COLUMN), rect.size, BoomboxHazard.ArtFit.STRETCH)
	sprite.position = rect.get_center()
	_hazard_art.show_progress(sprite, column.age / maxf(column_active_time, 0.001))


func _make_spike(_item: Variant) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.PROPS, BlindBeastHazardArt.SPIKE, Vector2.ONE, BoomboxHazard.ArtFit.STRETCH)


## The spike fills the box that hurts (`SPIKE_HIT_SHARE` of the slot wide, as tall as it is raised).
func _place_spike(slot: RidgeSlot, sprite: AnimatedSprite2D) -> void:
	var box := Vector2(slot.width * SPIKE_HIT_SHARE, ridge_spike_height * slot.height)
	sprite.scale = BoomboxHazard.art_scale(_hazard_art.art_size(BoomboxEffectArt.PROPS, BlindBeastHazardArt.SPIKE), box, BoomboxHazard.ArtFit.STRETCH)
	sprite.position = Vector2(slot.x, _floor_y - box.y * 0.5)


func _make_rock(rock: Rock) -> AnimatedSprite2D:
	var clip := BlindBeastHazardArt.ROCK_ALT if rock.alt and _has_hazard_art(BoomboxEffectArt.PROPS, BlindBeastHazardArt.ROCK_ALT) else BlindBeastHazardArt.ROCK
	return _hazard_art.fit_sprite(BoomboxEffectArt.PROPS, clip, Vector2.ONE * debris_radius * ROCK_ART_FACTOR, BoomboxHazard.ArtFit.CONTAIN)


func _place_rock(rock: Rock, sprite: AnimatedSprite2D) -> void:
	sprite.position = _rock_position(rock)
	sprite.rotation = rock.age * ROCK_SPIN


func _make_pulse(pulse: Pulse) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.FX, BlindBeastHazardArt.PULSE, PULSE_ART_SIZE, BoomboxHazard.ArtFit.STRETCH, pulse.dir < 0)


## The ripple travels along the floor, opening to the side it moves to.
func _place_pulse(pulse: Pulse, sprite: AnimatedSprite2D) -> void:
	_hazard_art.stand_on_floor(sprite, BoomboxEffectArt.FX, BlindBeastHazardArt.PULSE, pulse.x, _floor_y)


func _make_claw(_item: Variant) -> AnimatedSprite2D:
	return _hazard_art.fit_sprite(BoomboxEffectArt.CLAW_FX, BlindBeastHazardArt.CLAW, _claw_zone.size, BoomboxHazard.ArtFit.WIDTH, _facing < 0)


## The swipe stands on the floor centred on the zone: the scratch lines pulse red while he
## telegraphs, then the strike and follow-through frames run across the active time.
func _place_claw(_item: Variant, sprite: AnimatedSprite2D) -> void:
	_hazard_art.stand_on_floor(sprite, BoomboxEffectArt.CLAW_FX, BlindBeastHazardArt.CLAW, _claw_zone.get_center().x, _floor_y)
	_hazard_art.show_frame(sprite, _claw_frame(sprite.sprite_frames.get_frame_count(BlindBeastHazardArt.CLAW)))
	sprite.modulate = CLAW_WARNING_TINT.lerp(Color.WHITE, 0.5 - 0.5 * sin(_clock * CLAW_WARNING_PULSE)) if is_telegraphing() else Color.WHITE


## Frame 0 warns; the frames up to the last but one are the strike, spread over the active
## time; the last one is the lingering remnant.
func _claw_frame(count: int) -> int:
	if is_telegraphing():
		return 0
	var strike_frames := maxi(count - 2, 1)
	var progress := clampf(1.0 - _state_left / maxf(claw_active_time, 0.001), 0.0, 1.0)
	return clampi(1 + int(progress * float(strike_frames)), 0, maxi(count - 2, 0))


## The last frame of the swipe lingers where the claw struck (cosmetic only: no zone, no timer).
func _linger_claw() -> void:
	if _hazard_art == null or _field == null or not _claw_visible:
		return
	_hazard_art.linger(_field, BoomboxEffectArt.CLAW_FX, BlindBeastHazardArt.CLAW, Vector2(_claw_zone.get_center().x, _floor_y), _claw_zone.size.x, _facing < 0)


## A one-shot dust, dirt or rock puff on the floor at `x` (nothing without that art).
func _puff(clip: StringName, x: float) -> void:
	if _hazard_art == null or _field == null or not _has_hazard_art(BoomboxEffectArt.FX, clip):
		return
	_hazard_art.puff(_field, BoomboxEffectArt.FX, clip, Vector2(x, _floor_y), DUST_WIDTH)

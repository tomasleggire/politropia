class_name BoomboxTeacherBoss
extends BossEnemy

## "El Profesor", the library main boss: a teacher with a boombox for a head and a
## RHYTHM fight. Grounded, theatrical, he never dodges and never jumps. A beat clock
## (90 / 110 / 132 bpm by phase) drives everything: every telegraph ends on a beat,
## every strike starts on a beat, and the metronome (head pulse plus a ring at his
## feet) makes the tempo readable with no audio.
##
## He plays PHRASES (two to four attacks, back to back on the beat grid), rests one
## bar while walking to a mid-range spot, and every third phrase is the phase FINALE.
## After a finale he OVERHEATS (a stun): the main punish window. He can be hit at any
## time; super armor keeps his telegraphs firm.
##
## Hazards are `BoomboxHazard` boxes in the world, polled against Luz's live hurtbox.
## Designer doc: docs/bosses/BOOMBOX_TEACHER.md.

## A beat of the clock. `index` counts from 1 after the fight starts.
signal beat(index: int)
## A phrase was planned: the attacks it plays, in order, and whether it is the finale.
signal phrase_started(attacks: Array, finale: bool)

enum Attack { THRUST, BRIEFCASE, KICK, SOUND_WAVE, NOTE_BOUNCE, DICTATION, BASS_DROP }
enum Height { HIGH, LOW }

const WAVE_LOW := 0
const WAVE_HIGH := 1
const WAVE_REST := 2

const CUE_BEAT := &"Beat"
const CUE_OVERHEAT := &"Overheat"
const CUE_THRUST := &"Thrust"
const CUE_THROW := &"Throw"
const CUE_KICK := &"Kick"
const CUE_WAVE := &"Wave"
const CUE_NOTE := &"Note"
const CUE_LETTER := &"Letter"
const CUE_BASS_DROP := &"BassDrop"

## Every Nth beat is the strong one (a bigger ring).
const ACCENT_EVERY := 4
const NO_PIP := -1
const MIN_COLUMNS := 4
const MAX_COLUMNS := 9
const BOARD_LABEL_SIZE := Vector2(220.0, 26.0)
const MARKER_SLOT_FLASH := 15
const DICTATION_DIM_ALPHA := 0.22
const DICTATION_LIT_ALPHA := 0.8
const WALK_GAIN := 6.0
const WALK_DEADZONE := 3.0
## Hazards are the same box height as the thing they draw; these are the feet-relative
## y ranges (negative is up) of the melee bands.
const KICK_BAND := Vector2(-50.0, -4.0)
const BRIEFCASE_ORIGIN_GAP := 6.0
const MIN_RECOVER := 0.12
const WAVE_WEIGHT_LOW := 0.4
const WAVE_WEIGHT_HIGH := 0.4
const WAVE_WEIGHT_REST := 0.2
## Eight beats of waves in the Encore: high, low, a rest to land, repeated.
const ENCORE_WAVES: Array[int] = [WAVE_HIGH, WAVE_LOW, WAVE_REST, WAVE_HIGH, WAVE_LOW, WAVE_REST, WAVE_HIGH, WAVE_LOW]

## Fallbacks and limits for the tunables a designer can plausibly break.
const DEFAULT_BPM: Array[float] = [90.0, 110.0, 132.0]
const DEFAULT_OVERHEAT: Array[float] = [2.2, 2.0, 1.8]
const MIN_BPM := 30.0
const MAX_BPM := 300.0
const MIN_OVERHEAT := 0.1
const MIN_NOTE_PHYSICS := 1.0
## The recovery after sound waves never waits longer than this many beats.
const WAVE_CLEAR_MAX_BEATS := 12

const RING_MIN := 10.0
const RING_MAX := 44.0
const RING_ACCENT_MAX := 66.0
const RING_FLATTEN := 0.22
const BEAT_COLOR := Color(0.95, 0.85, 0.45)
const ACCENT_COLOR := Color(1.0, 0.6, 0.2)
const LOW_WAVE_COLOR := Color(1.0, 0.72, 0.25)
const HIGH_WAVE_COLOR := Color(0.35, 0.85, 1.0)
const NOTE_COLOR := Color(0.95, 0.45, 0.95)
const BRIEFCASE_COLOR := Color(0.62, 0.4, 0.22)
const LETTER_COLOR := Color(0.9, 0.9, 0.78)
const SHOCK_COLOR := Color(1.0, 0.45, 0.15)
const PIP_SPACING := 15.0
const PIP_Y_LOW := -84.0
const PIP_Y_HIGH := -100.0
const PIP_SIZE := 10.0
const STEAM_PUFFS := 5
const STEAM_COLOR := Color(0.92, 0.95, 1.0)
const HEAD_LIFT := 10.0

## Art. Clip names are the contract of docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md.
const WALK_CLIP_SPEED := 1.0
const THROW_RELEASE_TIME := 0.15
const THROW_CATCH_TIME := 0.3
const MIN_CLIP_TIME := 0.05
const NO_EVENT := -1.0e9
## Effect art, in px on screen: the overheat steam sits just over the boombox, the spark
## marks the bass slam, the chalk dust puffs where a letter lands.
const STEAM_ART_POSITION := Vector2(0.0, -100.0)
const STEAM_ART_WIDTH := 40.0
const STEAM_ART_Z := 1
const SPARK_WIDTH := 40.0
const SPARK_LIFT := 14.0
const DUST_WIDTH := 34.0
const BOARD_CHALK_OUTLINE := 4
## The slam clip lasts the shock plus this hold, so the strike frame outlives the shock a little.
const BASS_SLAM_HOLD := 0.08
const PLACEHOLDERS: Array[String] = ["Body", "Tie", "Pointer", "Head"]
const CLIP_SPEEDS := {
	"idle": 8.0, "walk": 10.0, "intro": 8.0, "phase_change": 8.0, "overheat": 8.0, "defeat": 8.0,
	"thrust_high_windup": 12.0, "thrust_high_strike": 12.0, "thrust_high_recover": 12.0,
	"thrust_low_windup": 12.0, "thrust_low_strike": 12.0, "thrust_low_recover": 12.0,
	"throw_windup": 12.0, "throw_release": 12.0, "throw_wait": 8.0, "throw_catch": 12.0,
	"kick_windup": 12.0, "kick_strike": 12.0, "kick_recover": 12.0,
	"conduct": 8.0, "lecture": 4.0, "notes": 4.0, "bass_lift": 12.0, "bass_slam": 12.0,
}
## Clips that repeat; every other clip plays once and holds its last frame.
const LOOPING_CLIPS := ["idle", "walk", "overheat", "conduct", "lecture", "notes"]
## Contract clip -> candidates, closest first, for a clip with no art yet (then `idle`).
const CLIP_FALLBACKS := {
	"thrust_high_windup": ["thrust_low_windup"], "thrust_low_windup": ["thrust_high_windup"],
	"thrust_high_strike": ["thrust_high_windup", "thrust_low_strike"], "thrust_low_strike": ["thrust_low_windup", "thrust_high_strike"],
	"thrust_high_recover": ["thrust_high_strike"], "thrust_low_recover": ["thrust_low_strike"],
	"throw_release": ["throw_windup"], "throw_wait": ["idle"], "throw_catch": ["throw_wait"],
	"kick_strike": ["kick_windup"], "kick_recover": ["kick_strike"],
	"notes": ["conduct"], "lecture": ["conduct"], "bass_slam": ["bass_lift"],
}

## The phrase table by phase: [weight, [attacks]]. A later phase adds attacks, it
## never removes the earlier ones, and an attack never shows up before its phase.
const PHRASES := {
	1: [
		[3.0, [Attack.THRUST, Attack.BRIEFCASE]],
		[3.0, [Attack.THRUST, Attack.THRUST]],
		[2.0, [Attack.BRIEFCASE, Attack.THRUST]],
		[1.0, [Attack.THRUST, Attack.BRIEFCASE, Attack.THRUST, Attack.THRUST]],
	],
	2: [
		[2.0, [Attack.THRUST, Attack.BRIEFCASE]],
		[2.0, [Attack.THRUST, Attack.SOUND_WAVE]],
		[2.0, [Attack.BRIEFCASE, Attack.SOUND_WAVE]],
		[3.0, [Attack.SOUND_WAVE, Attack.NOTE_BOUNCE]],
		[2.0, [Attack.NOTE_BOUNCE, Attack.THRUST, Attack.BRIEFCASE]],
		[1.0, [Attack.SOUND_WAVE, Attack.THRUST, Attack.NOTE_BOUNCE, Attack.BRIEFCASE]],
	],
	3: [
		[2.0, [Attack.THRUST, Attack.SOUND_WAVE]],
		[3.0, [Attack.DICTATION, Attack.THRUST]],
		[3.0, [Attack.SOUND_WAVE, Attack.BASS_DROP]],
		[2.0, [Attack.NOTE_BOUNCE, Attack.DICTATION]],
		[2.0, [Attack.BASS_DROP, Attack.THRUST, Attack.BRIEFCASE]],
		[1.0, [Attack.THRUST, Attack.SOUND_WAVE, Attack.DICTATION, Attack.BASS_DROP]],
	],
}

@export_group("Beat")
## Beats per minute of phases one, two and three (empty: 90, 110, 132; clamped to 30..300).
@export var bpm_by_phase := PackedFloat32Array([90.0, 110.0, 132.0])
## Seconds the metronome pulse takes to fade after a beat.
@export var pulse_time := 0.28
## Head size gained on a beat (a fraction).
@export var head_pulse := 0.14

@export_group("Structure")
## Off: the fight loop never starts an attack by itself; tests call `start_attack`.
@export var auto_phrases := true
## Beats of walking between two phrases (one bar).
@export var rest_beats := 4
## Beats before the very first phrase.
@export var opening_beats := 2
## Every Nth phrase of a phase is its finale (0 or less: no finales, no overheat).
@export var finale_every := 3
## Seconds of overheat after the finale of phase one, two and three (empty: 2.2, 2.0, 1.8).
@export var overheat_times := PackedFloat32Array([2.2, 2.0, 1.8])
@export var walk_speed := 70.0
## Distance he keeps from Luz while resting.
@export var mid_range := 105.0
## Luz closer than this at the end of a rest gets a kick.
@export var kick_range := 50.0

@export_group("Telegraphs")
## Whole beats (at least; the 0.35 s floor may add one) each wind-up lasts.
@export var thrust_telegraph_beats := 1
@export var briefcase_telegraph_beats := 2
@export var kick_telegraph_beats := 1
@export var wave_telegraph_beats := 4
@export var note_telegraph_beats := 2
@export var dictation_telegraph_beats := 4
@export var bass_telegraph_beats := 2

@export_group("Pointer Thrust")
@export var thrust_reach := 120.0
@export var thrust_chain_max := 3
@export var thrust_strike_time := 0.18
## Feet-relative y range (top, bottom) of each height. High is standing height
## (crouch under it); low sweeps the feet (jump it).
@export var thrust_high_band := Vector2(-46.0, -30.0)
@export var thrust_low_band := Vector2(-14.0, 0.0)

@export_group("Briefcase")
## How far it flies before it turns back, at most (a wall shortens it).
@export var briefcase_reach := 360.0
@export var briefcase_size := Vector2(30.0, 22.0)
## Height of its centre above his feet (torso: crouching does not avoid it).
@export var briefcase_height := 28.0

@export_group("Kick")
@export var kick_reach := 64.0
@export var kick_active_time := 0.2

@export_group("Sound Waves")
@export var wave_speed := 340.0
@export var wave_width := 24.0
@export var wave_low_height := 22.0
## Height of the underside of a high wave above the floor (above a standing Luz).
@export var wave_high_clearance := 50.0
@export var wave_high_height := 30.0
## Pattern length in beats; both are raised to at least 1 (max never below min).
@export var wave_min_beats := 4
@export var wave_max_beats := 8

@export_group("Notes")
## Notes per throw; both are raised to at least 1 (max never below min).
@export var note_count_min := 2
@export var note_count_max := 3
@export var note_speed := 180.0
@export var note_gravity := 900.0
## How high a note rises from its bounce to its apex.
@export var note_apex := 85.0
@export var note_radius := 10.0

@export_group("Dictation")
## Height of the blackboard centre above the floor.
@export var board_height := 230.0
@export var board_size := Vector2(240.0, 70.0)
@export var dictation_text := "in English please!"
@export var letter_fall_time := 0.45
@export var letter_size := 30.0
## Distance between the outer columns and the walls.
@export var column_margin := 70.0
@export var column_spacing_min := 100.0

@export_group("Bass Drop")
## Height of the ground shock above the floor: Luz must be higher at that instant.
@export var shock_height := 34.0
@export var shock_time := 0.22

@export_group("Art")
## The animation manifest of his sprite sheets. Without it (or without its sheets) he
## keeps the placeholder polygons.
@export_file("*.json") var animation_manifest := "res://assets/enemies/boombox_teacher/animation_manifest.json"

@export_group("Hazards")
@export var hazard_damage := 1
## A note's flight never makes the boss wait more than this many beats (at least 1).
@export var max_clear_beats := 4

## The phase whose bpm the clock plays. It follows `_phase` only when the transition
## beat starts, which never happens during a strike, so no attack changes tempo.
var _tempo_phase := FIRST_PHASE
var _beat_running := false
var _beat_index := 0
var _beat_left := 0.0
var _pulse := 0.0
var _accent := false
var _opening := true
var _skip_kick := false
var _phrase: Array = []
var _phrase_count := 0
var _last_phrase := -1
var _finale_phrase := false
var _overheat_pending := false
var _pending_step := {}
var _step := {}
var _anchor_beat := 0
var _event_cursor := 0
var _telegraph_total := 1.0
var _attack_visuals_on := false
var _hazards: Array[BoomboxHazard] = []
var _board: Node2D
var _pips := PackedInt32Array()
var _pip_lit := NO_PIP
var _pip_spent := 0
var _columns := PackedFloat32Array()
var _column_alpha := PackedFloat32Array()
var _steam_left := 0.0
var _head_rest := Vector2.ZERO
var _attack_log: Array[int] = []
var _catalog: BossAnimationCatalog
var _art_on := false
var _sprite_scale := 1.0
var _sprite_fx: BossSpriteFx
var _effects: BoomboxEffectArt
var _steam_sprite: AnimatedSprite2D
## The contract clip last requested through `_play` (not the fallback it resolved to).
var _clip: StringName = &""
## `_clock` when the last attack event (strike, release...) fired.
var _event_clock := NO_EVENT

@onready var _head: Node2D = get_node_or_null("Visual/Head") as Node2D
@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if _head != null:
		_head_rest = _head.position
	_setup_sprite()


func _exit_tree() -> void:
	super._exit_tree()
	if not Engine.is_editor_hint():
		_retire_hazards(false)


func _draw() -> void:
	if Engine.is_editor_hint():
		return
	_draw_metronome()
	_draw_pips()
	_draw_steam()


## -- Public API (tests and designers) --------------------------------------------

func is_beat_running() -> bool:
	return _beat_running


func get_beat_index() -> int:
	return _beat_index


func get_bpm() -> float:
	var table: Array = Array(bpm_by_phase) if not bpm_by_phase.is_empty() else DEFAULT_BPM
	return clampf(float(table[clampi(_tempo_phase - FIRST_PHASE, 0, table.size() - 1)]), MIN_BPM, MAX_BPM)


## Seconds between two beats at the current phase.
func get_beat_interval() -> float:
	return 60.0 / maxf(get_bpm(), 1.0)


## Seconds until the next beat (a full interval before the clock runs).
func get_beat_left() -> float:
	return _beat_left if _beat_running else get_beat_interval()


func get_attack_log() -> Array[int]:
	return _attack_log


func clear_attack_log() -> void:
	_attack_log.clear()


func get_step() -> Dictionary:
	return _step


## Sets the parameters (`heights`, `pattern`, `count`) the next `start_attack` of the
## same attack uses, instead of drawing them.
func plan_step(step: Dictionary) -> void:
	_pending_step = step


func get_hazards() -> Array[BoomboxHazard]:
	var live: Array[BoomboxHazard] = []
	for hazard: BoomboxHazard in _hazards:
		if is_instance_valid(hazard) and hazard.is_alive():
			live.append(hazard)
	return live


func hazard_count() -> int:
	return get_hazards().size()


func get_board() -> Node2D:
	return _board


func get_columns() -> PackedFloat32Array:
	return _columns


func get_wave_pips() -> PackedInt32Array:
	return _pips


func get_phrase_remaining() -> int:
	return _phrase.size()


func is_overheat_pending() -> bool:
	return _overheat_pending


func is_finale_phrase() -> bool:
	return _finale_phrase


## Horizontal distance of one note hop (bounce to bounce).
func note_hop_distance() -> float:
	return note_speed * _note_hop_time()


## The finale of `phase` as the attacks it plays, in order.
func finale_attacks(phase: int) -> Array[int]:
	var attacks: Array[int] = []
	for step: Dictionary in _finale_steps(phase):
		attacks.append(int(step["attack"]))
	return attacks


## The overheat duration for the current phase.
func overheat_duration() -> float:
	var table: Array = Array(overheat_times) if not overheat_times.is_empty() else DEFAULT_OVERHEAT
	return maxf(float(table[clampi(_phase - FIRST_PHASE, 0, table.size() - 1)]), MIN_OVERHEAT)


## Starts the beat clock with the next beat one interval away.
func start_beat_clock() -> void:
	_beat_running = true
	_beat_index = 0
	_beat_left = get_beat_interval()


func engage() -> void:
	if _state == State.IDLE and not _dead and not _beat_running:
		start_beat_clock()
	super.engage()


func start_attack(attack: int) -> void:
	if _dead:
		return
	_close_attack_phase()
	_hide_attack_visuals()
	_step = _take_step(attack)
	_attack_log.append(attack)
	if not _beat_running:
		start_beat_clock()
	super.start_attack(attack)


func make_corpse_at(at: Vector2, facing: int) -> void:
	_stop_beat_clock()
	super.make_corpse_at(at, facing)


## -- Beat clock ------------------------------------------------------------------------

func _tick(delta: float) -> void:
	_pulse = maxf(_pulse - delta / maxf(pulse_time, 0.01), 0.0)
	_steam_left = maxf(_steam_left - delta, 0.0)
	_apply_head_pose()
	_sync_sprite()
	_update_steam_art()
	if _attack_visuals_on and _state != State.ATTACK:
		_hide_attack_visuals()
	queue_redraw()
	if not _beat_running:
		return
	_beat_left -= delta
	while _beat_left <= 0.0:
		_beat_left += get_beat_interval()
		_beat_index += 1
		_on_beat()


func _on_beat() -> void:
	_pulse = 1.0
	_accent = _beat_index % ACCENT_EVERY == 0
	play_cue(CUE_BEAT)
	beat.emit(_beat_index)
	if _state != State.ATTACK:
		return
	if _attack_phase == AttackPhase.TELEGRAPH and _beat_index == _anchor_beat - 1 and not _pips.is_empty():
		_pip_lit = 0
	elif _attack_phase == AttackPhase.ACTIVE:
		_dispatch_events()


func _stop_beat_clock() -> void:
	_beat_running = false
	_beat_left = 0.0
	_pulse = 0.0


## Seconds from now to the `n`th next beat (n >= 1).
func _time_to_beat(n: int) -> float:
	return get_beat_left() + float(n - 1) * get_beat_interval()


## A time ending on a beat, at least `minimum` away.
func _beat_aligned(minimum: float) -> float:
	var n := 1
	while _time_to_beat(n) < minimum:
		n += 1
	return _time_to_beat(n)


func _apply_head_pose() -> void:
	if _head == null:
		return
	var lift := HEAD_LIFT if _state == State.ATTACK and _step.get("attack", NO_ATTACK) == Attack.BASS_DROP and _attack_phase == AttackPhase.TELEGRAPH else 0.0
	_head.scale = Vector2.ONE * (1.0 + head_pulse * _pulse * (1.6 if _accent else 1.0))
	_head.position = _head_rest + Vector2(0.0, -lift)


## -- Durations ---------------------------------------------------------------------------

## Whole beats to the strike: the time to the Nth next beat, raised one beat at a time
## while it would be shorter than the minimum telegraph. Remembers the beat it ends on.
func _telegraph_time(attack_id: int) -> float:
	var beats := maxi(_telegraph_beats(attack_id), 1)
	while _time_to_beat(beats) < MIN_TELEGRAPH:
		beats += 1
	_anchor_beat = _beat_index + beats
	return _time_to_beat(beats)


func _telegraph_beats(attack_id: int) -> int:
	match attack_id:
		Attack.THRUST:
			return thrust_telegraph_beats
		Attack.BRIEFCASE:
			return briefcase_telegraph_beats
		Attack.KICK:
			return kick_telegraph_beats
		Attack.SOUND_WAVE:
			return wave_telegraph_beats
		Attack.NOTE_BOUNCE:
			return note_telegraph_beats
		Attack.DICTATION:
			return dictation_telegraph_beats
		Attack.BASS_DROP:
			return bass_telegraph_beats
	return 1


func _active_time(attack_id: int) -> float:
	var interval := get_beat_interval()
	match attack_id:
		Attack.THRUST:
			return float(_event_count() - 1) * interval + thrust_strike_time + 0.1
		Attack.BRIEFCASE:
			return 4.0 * interval
		Attack.KICK:
			return kick_active_time
		Attack.SOUND_WAVE, Attack.NOTE_BOUNCE:
			return float(_event_count() - 1) * interval + 0.1
		Attack.DICTATION:
			return float(_event_count() - 1) * interval + letter_fall_time + 0.1
		Attack.BASS_DROP:
			return shock_time + 0.08
	return 0.1


## Every recovery ends on a beat, so the next telegraph starts on the grid. Waves wait
## until they left the arena (the overheat must never start under a wave) and notes at
## most `max_clear_beats`; both waits are capped, whatever the arena size.
func _recover_time(attack_id: int) -> float:
	match attack_id:
		Attack.SOUND_WAVE:
			return _clear_wait(_wave_travel_time(), WAVE_CLEAR_MAX_BEATS)
		Attack.NOTE_BOUNCE:
			return _clear_wait(_note_travel_time(), maxi(max_clear_beats, 1))
		Attack.BASS_DROP:
			return _beat_aligned(get_beat_interval())
	return _beat_aligned(MIN_RECOVER)


## A beat-aligned wait for something that needs `travel` seconds to leave, `cap` beats
## at most (a non-finite travel counts as one beat).
func _clear_wait(travel: float, cap: int) -> float:
	var beats := 1
	if is_finite(travel):
		beats = clampi(ceili(travel / get_beat_interval()), 1, cap)
	return _beat_aligned(maxf(_time_to_beat(beats), MIN_RECOVER))


func _wave_travel_time() -> float:
	var bounds := _arena_bounds()
	return maxf(global_position.x - bounds.x, bounds.y - global_position.x) / maxf(wave_speed, 1.0)


func _note_travel_time() -> float:
	var bounds := _arena_bounds()
	return maxf(global_position.x - bounds.x, bounds.y - global_position.x) / maxf(note_speed, 1.0)


func _note_gravity() -> float:
	return maxf(note_gravity, MIN_NOTE_PHYSICS)


func _note_rise_speed() -> float:
	return sqrt(2.0 * _note_gravity() * maxf(note_apex, MIN_NOTE_PHYSICS))


func _note_hop_time() -> float:
	return 2.0 * _note_rise_speed() / _note_gravity()


## -- Phrases and the fight loop ---------------------------------------------------------

func _fight_delay() -> float:
	if _overheat_pending or not _phrase.is_empty() or _skip_kick:
		return 0.0
	if _opening:
		_opening = false
		return _time_to_beat(maxi(opening_beats, 1))
	return _time_to_beat(maxi(rest_beats, 1))


func _update_fight(_delta: float) -> void:
	if _overheat_pending:
		_overheat_pending = false
		stun(overheat_duration())
		return
	if not _phrase.is_empty() or _skip_kick or not _luz_valid():
		velocity.x = 0.0
		return
	_walk_to_mid_range()


func _walk_to_mid_range() -> void:
	global_position.x = _clamp_to_arena(global_position.x)
	var wanted := _clamp_to_arena(_luz.global_position.x - float(_dir_to_luz()) * mid_range)
	var gap := wanted - global_position.x
	var limit := absf(walk_speed)
	velocity.x = clampf(gap * WALK_GAIN, -limit, limit) if absf(gap) > WALK_DEADZONE else 0.0


func _choose_next_action() -> int:
	if not auto_phrases:
		return NO_ATTACK
	if _phrase.is_empty():
		if _kick_due():
			_skip_kick = true
			_pending_step = {"attack": Attack.KICK}
			return Attack.KICK
		_skip_kick = false
		_plan_phrase()
	return _pop_step()


## Luz is hugging him at the end of a rest.
func _kick_due() -> bool:
	return not _skip_kick and _luz_valid() and _distance_x() <= kick_range and _luz_level(40.0)


func _plan_phrase() -> void:
	_phrase_count += 1
	_finale_phrase = finale_every > 0 and _phrase_count % finale_every == 0
	_phrase = _finale_steps(_phase) if _finale_phrase else _regular_steps()
	var attacks: Array[int] = []
	for step: Dictionary in _phrase:
		attacks.append(int(step["attack"]))
	phrase_started.emit(attacks, _finale_phrase)


func _pop_step() -> int:
	if _phrase.is_empty():
		_phrase = _regular_steps()
	var step: Dictionary = _phrase.pop_front()
	_pending_step = step
	if _phrase.is_empty() and _finale_phrase:
		_overheat_pending = true
	return int(step["attack"])


func _regular_steps() -> Array:
	var table: Array = PHRASES[clampi(_phase, 1, 3)]
	var weights := PackedFloat32Array()
	for entry: Array in table:
		weights.append(float(entry[0]))
	if _last_phrase >= 0 and _last_phrase < weights.size() and weights.size() > 1:
		weights[_last_phrase] = 0.0
	_last_phrase = _pick_weighted(weights)
	var steps: Array = []
	for attack: int in (table[_last_phrase] as Array)[1]:
		steps.append(_make_step(attack))
	return steps


## The signature phrase of a phase: the lesson, the listening, the encore.
func _finale_steps(phase: int) -> Array:
	match clampi(phase, 1, 3):
		1:
			return [_make_step(Attack.THRUST, thrust_chain_max), _make_step(Attack.BRIEFCASE)]
		2:
			return [_make_step(Attack.SOUND_WAVE, wave_max_beats)]
	return [
		_make_step(Attack.DICTATION),
		{"attack": Attack.SOUND_WAVE, "pattern": ENCORE_WAVES.duplicate()},
		_make_step(Attack.BASS_DROP),
	]


## The parameters of one attack: the height of each thrust, the wave pattern, the
## number of notes. `size` forces the length of a chain or a sequence (0 draws it).
func _make_step(attack: int, size := 0) -> Dictionary:
	match attack:
		Attack.THRUST:
			var length := size if size > 0 else rng.randi_range(1, maxi(thrust_chain_max, 1))
			var first := rng.randi_range(0, 1)
			var heights: Array[int] = []
			for i: int in length:
				heights.append((first + i) % 2)
			return {"attack": attack, "heights": heights}
		Attack.SOUND_WAVE:
			var shortest := maxi(wave_min_beats, 1)
			var beats := size if size > 0 else rng.randi_range(shortest, maxi(wave_max_beats, shortest))
			return {"attack": attack, "pattern": _make_wave_pattern(beats)}
		Attack.NOTE_BOUNCE:
			var fewest := maxi(note_count_min, 1)
			return {"attack": attack, "count": rng.randi_range(fewest, maxi(note_count_max, fewest))}
	return {"attack": attack}


## Low waves are jumped and high waves are stood under, so the pattern leaves Luz time
## to land: at most two lows in a row, and a high never follows a low without a rest.
func _make_wave_pattern(length: int) -> Array[int]:
	var pattern: Array[int] = []
	var low_run := 0
	for i: int in maxi(length, 1):
		var previous := pattern[i - 1] if i > 0 else WAVE_REST
		var weights := PackedFloat32Array([WAVE_WEIGHT_LOW, WAVE_WEIGHT_HIGH, WAVE_WEIGHT_REST if i > 0 else 0.0])
		if previous == WAVE_LOW:
			weights[WAVE_HIGH] = 0.0
		if low_run >= 2:
			weights[WAVE_LOW] = 0.0
		var pick := _pick_weighted(weights)
		low_run = low_run + 1 if pick == WAVE_LOW else 0
		pattern.append(pick)
	return pattern


func _pick_weighted(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for weight: float in weights:
		total += maxf(weight, 0.0)
	if total <= 0.0:
		return weights.size() - 1
	var roll := rng.randf() * total
	for i: int in weights.size():
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			return i
	return weights.size() - 1


func _take_step(attack: int) -> Dictionary:
	if int(_pending_step.get("attack", NO_ATTACK)) == attack:
		var step := _pending_step
		_pending_step = {}
		return step
	return _make_step(attack)


## -- Attack phases ------------------------------------------------------------------------

func _begin_attack_phase(attack_id: int, phase_id: AttackPhase) -> void:
	match phase_id:
		AttackPhase.TELEGRAPH:
			_begin_telegraph(attack_id)
		AttackPhase.ACTIVE:
			_begin_active(attack_id)
	_sync_sprite()


func _update_attack_phase(attack_id: int, phase_id: AttackPhase, _delta: float) -> void:
	if phase_id != AttackPhase.TELEGRAPH or _telegraph == null:
		return
	var progress := 1.0 - clampf(_state_left / maxf(_telegraph_total, 0.01), 0.0, 1.0)
	var is_melee := attack_id == Attack.THRUST or attack_id == Attack.KICK
	_telegraph.set_glow(BossTelegraph.MELEE_COLOR if is_melee else BossTelegraph.RANGED_COLOR, 0.25 + 0.75 * progress)
	if attack_id == Attack.BASS_DROP:
		_telegraph.show_floor_marker(MARKER_SLOT_FLASH, _floor_strip(6.0), BossTelegraph.RANGED_COLOR, 0.2 + 0.6 * _pulse)


func _end_attack_phase(_attack_id: int, phase_id: AttackPhase) -> void:
	if phase_id == AttackPhase.ACTIVE:
		_retire_hazards(true)
		_hide_attack_visuals()


func _begin_telegraph(attack_id: int) -> void:
	_attack_visuals_on = true
	_event_cursor = 0
	_telegraph_total = _state_left
	_pip_lit = NO_PIP
	_pip_spent = 0
	match attack_id:
		Attack.THRUST:
			_show_thrust_line(_heights()[0])
		Attack.BRIEFCASE:
			_show_throw_line()
		Attack.KICK:
			_show_kick_marker()
		Attack.SOUND_WAVE:
			_pips = PackedInt32Array(_step["pattern"])
		Attack.NOTE_BOUNCE:
			_show_floor_line()
		Attack.DICTATION:
			_open_dictation()
		Attack.BASS_DROP:
			play_cue(CUE_BASS_DROP)


func _begin_active(attack_id: int) -> void:
	_event_cursor = 1
	if attack_id == Attack.DICTATION:
		_refresh_columns()
	_fire_event(0)


func _event_count() -> int:
	match int(_step.get("attack", NO_ATTACK)):
		Attack.THRUST:
			return _heights().size()
		Attack.SOUND_WAVE:
			return (_step["pattern"] as Array).size()
		Attack.NOTE_BOUNCE:
			return int(_step["count"])
		Attack.DICTATION:
			return _columns.size()
	return 1


## Fires every event whose beat has come: event k belongs to the beat `anchor + k`.
func _dispatch_events() -> void:
	var due := _beat_index - _anchor_beat
	while _event_cursor <= due and _event_cursor < _event_count():
		_fire_event(_event_cursor)
		_event_cursor += 1
	_sync_sprite()


func _fire_event(k: int) -> void:
	_event_clock = _clock
	match int(_step.get("attack", NO_ATTACK)):
		Attack.THRUST:
			_fire_thrust(k)
		Attack.BRIEFCASE:
			_throw_briefcase()
		Attack.KICK:
			_spawn_kick()
		Attack.SOUND_WAVE:
			_fire_wave(k)
		Attack.NOTE_BOUNCE:
			_throw_note(k)
		Attack.DICTATION:
			_release_letter(k)
		Attack.BASS_DROP:
			_spawn_shock()


## -- Pointer thrust, kick ---------------------------------------------------------------

func _heights() -> Array:
	return _step.get("heights", [Height.HIGH])


func _band_of(height: int) -> Vector2:
	return thrust_high_band if height == Height.HIGH else thrust_low_band


func _front_x() -> float:
	return global_position.x + float(_facing) * _half_width


func _show_thrust_line(height: int) -> void:
	if _telegraph == null:
		return
	var band := _band_of(height)
	var origin := Vector2(_front_x(), global_position.y + (band.x + band.y) * 0.5)
	_telegraph.show_aim_line(origin, Vector2(float(_facing), 0.0), thrust_reach, BossTelegraph.MELEE_COLOR, true)


func _fire_thrust(k: int) -> void:
	play_cue(CUE_THRUST)
	var band := _band_of(int(_heights()[k]))
	var centre := Vector2(_front_x() + float(_facing) * thrust_reach * 0.5, global_position.y + (band.x + band.y) * 0.5)
	var hazard := _spawn_hazard(centre, Vector2(thrust_reach * 0.5, absf(band.y - band.x) * 0.5), BossTelegraph.MELEE_COLOR)
	hazard.look = BoomboxHazard.Look.POINTER
	hazard.dir = _facing
	hazard.lifetime = thrust_strike_time
	hazard.bound = true
	if k + 1 < _heights().size():
		_show_thrust_line(int(_heights()[k + 1]))
	elif _telegraph != null:
		_telegraph.hide_aim_line()


func _kick_rect() -> Rect2:
	var width := kick_reach
	var left := _front_x() if _facing > 0 else _front_x() - width
	return Rect2(Vector2(left, global_position.y + KICK_BAND.x), Vector2(width, KICK_BAND.y - KICK_BAND.x))


func _show_kick_marker() -> void:
	if _telegraph == null:
		return
	var area := _kick_rect()
	_telegraph.show_floor_marker(0, Rect2(area.position.x, global_position.y - 6.0, area.size.x, 6.0), BossTelegraph.MELEE_COLOR)


func _spawn_kick() -> void:
	play_cue(CUE_KICK)
	var area := _kick_rect()
	var hazard := _spawn_hazard(area.get_center(), area.size * 0.5, BossTelegraph.MELEE_COLOR)
	hazard.lifetime = kick_active_time
	hazard.bound = true


## -- Briefcase, notes -------------------------------------------------------------------------

func _show_throw_line() -> void:
	if _telegraph == null:
		return
	var origin := Vector2(_front_x(), global_position.y - briefcase_height)
	_telegraph.show_aim_line(origin, Vector2(float(_facing), 0.0), briefcase_reach, BossTelegraph.RANGED_COLOR, true)


func _throw_briefcase() -> void:
	play_cue(CUE_THROW)
	var interval := get_beat_interval()
	var bounds := _arena_bounds()
	var start := Vector2(_front_x() + float(_facing) * BRIEFCASE_ORIGIN_GAP, global_position.y - briefcase_height)
	var far_x := clampf(start.x + float(_facing) * briefcase_reach, bounds.x + briefcase_size.x, bounds.y - briefcase_size.x)
	var hazard := _spawn_hazard(start, briefcase_size * 0.5, BRIEFCASE_COLOR)
	hazard.motion = BoomboxHazard.Motion.BOOMERANG
	hazard.far_point = Vector2(far_x, start.y)
	hazard.out_time = 2.0 * interval
	hazard.back_time = 2.0 * interval
	hazard.home = Callable(self, &"_briefcase_home")
	_dress(hazard, BoomboxEffectArt.PROPS, &"briefcase_spin", BoomboxHazard.ArtFit.WIDTH)


func _briefcase_home() -> Vector2:
	return Vector2(global_position.x, global_position.y - briefcase_height)


func _show_floor_line() -> void:
	if _telegraph == null:
		return
	var origin := Vector2(_front_x(), global_position.y - note_radius)
	_telegraph.show_aim_line(origin, Vector2(float(_facing), 0.0), briefcase_reach, BossTelegraph.RANGED_COLOR, true)


## Every note leaves along the floor toward the side Luz was on when the first one
## left, hops with a parabola and despawns at the walls.
func _throw_note(k: int) -> void:
	play_cue(CUE_NOTE)
	var bounds := _arena_bounds()
	if k == 0:
		_step["dir"] = _dir_to_luz()
	var side := int(_step.get("dir", _facing))
	var ground := global_position.y - note_radius
	var hazard := _spawn_hazard(Vector2(global_position.x + float(side) * (_half_width + note_radius + BRIEFCASE_ORIGIN_GAP), ground), Vector2(note_radius, note_radius), NOTE_COLOR)
	hazard.look = BoomboxHazard.Look.DISC
	hazard.motion = BoomboxHazard.Motion.LINEAR
	var rise_speed := _note_rise_speed()
	hazard.velocity = Vector2(float(side) * note_speed, -rise_speed)
	hazard.gravity = _note_gravity()
	hazard.bounce_speed = rise_speed
	hazard.floor_y = ground
	hazard.wall_left = bounds.x
	hazard.wall_right = bounds.y
	hazard.lifetime = 30.0
	_dress(hazard, BoomboxEffectArt.PROPS, &"note_pair" if k % 2 == 1 else &"note")


## -- Sound waves ----------------------------------------------------------------------------

func _fire_wave(k: int) -> void:
	_pip_spent = k + 1
	_pip_lit = k + 1 if k + 1 < _pips.size() else NO_PIP
	var kind := int((_step["pattern"] as Array)[k])
	if kind == WAVE_REST:
		return
	play_cue(CUE_WAVE)
	var bounds := _arena_bounds()
	var high := kind == WAVE_HIGH
	var height := wave_high_height if high else wave_low_height
	var bottom := wave_high_clearance if high else 0.0
	var centre_y := global_position.y - bottom - height * 0.5
	for side: int in [-1, 1]:
		var from := Vector2(global_position.x + float(side) * (_half_width + wave_width * 0.5), centre_y)
		var hazard := _spawn_hazard(from, Vector2(wave_width * 0.5, height * 0.5), HIGH_WAVE_COLOR if high else LOW_WAVE_COLOR)
		hazard.motion = BoomboxHazard.Motion.LINEAR
		hazard.velocity = Vector2(float(side) * wave_speed, 0.0)
		hazard.wall_left = bounds.x
		hazard.wall_right = bounds.y
		hazard.lifetime = 30.0
		_dress(hazard, BoomboxEffectArt.FX, &"wave_high" if high else &"wave_low", BoomboxHazard.ArtFit.STRETCH, side < 0)


## -- Blackboard dictation -----------------------------------------------------------------

func _open_dictation() -> void:
	_columns = _make_columns()
	_column_alpha = PackedFloat32Array()
	_column_alpha.resize(_columns.size())
	_column_alpha.fill(DICTATION_DIM_ALPHA)
	_free_board()
	_board = _make_board()
	_refresh_columns()


func _make_columns() -> PackedFloat32Array:
	var bounds := _arena_bounds()
	var left := bounds.x + column_margin
	var span := maxf(bounds.y - column_margin - left, 0.0)
	var fit := span / maxf(column_spacing_min, 1.0)
	var count := clampi(int(fit) + 1, MIN_COLUMNS, MAX_COLUMNS) if is_finite(fit) else MAX_COLUMNS
	var columns := PackedFloat32Array()
	for i: int in count:
		columns.append(left + span * float(i) / float(count - 1))
	return columns


func _make_board() -> Node2D:
	var bounds := _arena_bounds()
	var board := Node2D.new()
	board.top_level = true
	board.z_index = 2
	var texture := _effects.blackboard() if _effects != null else null
	board.add_child(_board_backdrop(texture))
	board.add_child(_board_label(texture != null))
	_world_parent().add_child(board)
	board.global_position = Vector2((bounds.x + bounds.y) * 0.5, global_position.y - board_height)
	return board


## The blackboard art as wide as `board_size` (its proportions kept), or the flat green
## placeholder rectangle without art.
func _board_backdrop(texture: Texture2D) -> Node2D:
	if texture != null:
		var art := Sprite2D.new()
		art.name = "Art"
		art.texture = texture
		art.texture_filter = BoomboxEffectArt.FILTER
		art.scale = Vector2.ONE * (board_size.x / float(texture.get_width()))
		return art
	var frame := Polygon2D.new()
	var half := board_size * 0.5
	frame.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	frame.color = Color(0.1, 0.28, 0.2)
	return frame


## The dictated text; chalk (off-white, dark outline) over the blackboard art, plain white without it.
func _board_label(chalk: bool) -> Label:
	var label := Label.new()
	label.name = "Text"
	label.text = dictation_text
	label.size = BOARD_LABEL_SIZE
	label.position = Vector2(-BOARD_LABEL_SIZE.x * 0.5, -BOARD_LABEL_SIZE.y * 0.5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", BoomboxHazard.CHALK_COLOR if chalk else Color.WHITE)
	if chalk:
		label.add_theme_color_override(&"font_outline_color", BoomboxHazard.CHALK_OUTLINE_COLOR)
		label.add_theme_constant_override(&"outline_size", BOARD_CHALK_OUTLINE)
	return label


func _free_board() -> void:
	if is_instance_valid(_board):
		_board.queue_free()
	_board = null


func _refresh_columns() -> void:
	if _telegraph == null:
		return
	var width := letter_size + 10.0
	for i: int in _columns.size():
		_telegraph.show_floor_marker(i, Rect2(_columns[i] - width * 0.5, global_position.y - 6.0, width, 6.0), BossTelegraph.RANGED_COLOR, _column_alpha[i])


## The letter of column `k` starts to fall and its marker brightens, in reading order.
func _release_letter(k: int) -> void:
	if k >= _columns.size():
		return
	play_cue(CUE_LETTER)
	_column_alpha[k] = DICTATION_LIT_ALPHA
	_refresh_columns()
	var letters := dictation_text.replace(" ", "")
	var ground := global_position.y - letter_size * 0.5
	var top := global_position.y - board_height + board_size.y * 0.5 + letter_size * 0.5
	var hazard := _spawn_hazard(Vector2(_columns[k], top), Vector2(letter_size, letter_size) * 0.5, LETTER_COLOR)
	hazard.look = BoomboxHazard.Look.CHALK if _art_on else BoomboxHazard.Look.GLYPH
	hazard.glyph = letters[k % maxi(letters.length(), 1)] if not letters.is_empty() else ""
	hazard.motion = BoomboxHazard.Motion.LINEAR
	hazard.velocity = Vector2(0.0, (ground - top) / maxf(letter_fall_time, MIN_TELEGRAPH))
	hazard.floor_y = ground
	hazard.despawn_at_floor = true
	hazard.lifetime = 10.0
	if _effects != null and _effects.has_clip(BoomboxEffectArt.FX, &"chalk_dust"):
		hazard.touched_floor.connect(_puff_chalk_dust)


## A puff of chalk where a letter lands.
func _puff_chalk_dust(at: Vector2) -> void:
	_effects.puff(_world_parent(), BoomboxEffectArt.FX, &"chalk_dust", at, DUST_WIDTH)


## -- Bass drop ------------------------------------------------------------------------------------

func _floor_strip(height: float) -> Rect2:
	var bounds := _arena_bounds()
	return Rect2(bounds.x, global_position.y - height, bounds.y - bounds.x, height)


func _spawn_shock() -> void:
	play_cue(CUE_BASS_DROP)
	_shake(phase_shake_strength, phase_shake_time * 0.5)
	var area := _floor_strip(shock_height)
	var hazard := _spawn_hazard(area.get_center(), area.size * 0.5, SHOCK_COLOR)
	hazard.lifetime = shock_time
	hazard.bound = true
	_dress_shock(hazard)
	_spark_at_slam()


## Ground crests along the whole band that hurts.
func _dress_shock(hazard: BoomboxHazard) -> void:
	if _effects == null:
		return
	for crest: AnimatedSprite2D in _effects.floor_sprites(BoomboxEffectArt.FX, &"bass_shock", hazard.half_extents * 2.0):
		hazard.attach_art(crest)


## The spark punctuates the slam, on the floor in front of him where the boombox lands.
func _spark_at_slam() -> void:
	if _effects != null:
		_effects.puff(_world_parent(), BoomboxEffectArt.PROPS, &"spark", Vector2(_front_x(), global_position.y - SPARK_LIFT), SPARK_WIDTH)


## -- Hazards ----------------------------------------------------------------------------------------

## Hazards live beside the boss: a child would move, flip and flash with it.
func _world_parent() -> Node:
	var parent := get_parent()
	return parent if parent != null else self


func _spawn_hazard(centre: Vector2, half_extents: Vector2, color: Color) -> BoomboxHazard:
	_prune_hazards()
	var hazard := BoomboxHazard.new()
	hazard.half_extents = half_extents
	hazard.color = color
	hazard.damage = hazard_damage
	hazard.target = _luz
	hazard.position = centre
	_world_parent().add_child(hazard)
	_hazards.append(hazard)
	return hazard


func _prune_hazards() -> void:
	var live: Array[BoomboxHazard] = []
	for hazard: BoomboxHazard in _hazards:
		if is_instance_valid(hazard) and hazard.is_alive():
			live.append(hazard)
	_hazards = live


## Frees the hazards (only the ones bound to an attack when `only_bound`).
func _retire_hazards(only_bound: bool) -> void:
	for hazard: BoomboxHazard in _hazards:
		if is_instance_valid(hazard) and (hazard.bound or not only_bound):
			hazard.retire()
	_prune_hazards()


func _hide_attack_visuals() -> void:
	_attack_visuals_on = false
	_pips = PackedInt32Array()
	_pip_lit = NO_PIP
	_pip_spent = 0
	_columns = PackedFloat32Array()
	_free_board()
	_clear_telegraph()


func _clear_hazards() -> void:
	_retire_hazards(false)
	_hide_attack_visuals()


## -- Phases, overheat, reset ------------------------------------------------------------------------

func _on_phase_entered(_phase_id: int) -> void:
	_phrase.clear()
	_phrase_count = 0
	_last_phrase = -1
	_finale_phrase = false
	_skip_kick = false
	_pending_step = {}


## The transition beat never starts during a strike: the new phase's tempo begins here,
## so every attack keeps the tempo it was telegraphed with.
func _on_transition_started(_phase_id: int) -> void:
	_tempo_phase = _phase


func _on_stunned(duration: float) -> void:
	_steam_left = duration
	play_cue(CUE_OVERHEAT)


func _on_stun_ended() -> void:
	_steam_left = 0.0


func _reset_ai() -> void:
	super._reset_ai()
	_tempo_phase = FIRST_PHASE
	_stop_beat_clock()
	_beat_index = 0
	_accent = false
	_opening = true
	_skip_kick = false
	_phrase.clear()
	_phrase_count = 0
	_last_phrase = -1
	_finale_phrase = false
	_overheat_pending = false
	_pending_step = {}
	_step = {}
	_steam_left = 0.0
	_event_clock = NO_EVENT
	_attack_log.clear()
	_apply_head_pose()
	queue_redraw()


## -- Sprite ---------------------------------------------------------------------------------

## Shows the sprite and hides the placeholder polygons when the manifest has art; with
## none he looks exactly as before. The metronome head swell is dropped with art (the
## head is baked into the frames): the floor ring still pulses on every beat.
func _setup_sprite() -> void:
	if _sprite == null:
		return
	_catalog = BossAnimationCatalog.new(animation_manifest, CLIP_FALLBACKS, CLIP_SPEEDS, LOOPING_CLIPS)
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
	_setup_effect_art()
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


## The props, effects and blackboard the manifest draws: each hazard dresses itself with
## them when they exist and keeps its placeholder when not.
func _setup_effect_art() -> void:
	_effects = BoomboxEffectArt.new(_catalog)
	_steam_sprite = _effects.sprite(BoomboxEffectArt.FX, &"steam", Vector2.ONE * (STEAM_ART_WIDTH / maxf(_effects.content(BoomboxEffectArt.FX, &"steam").x, 1.0)))
	if _steam_sprite == null:
		return
	_steam_sprite.position = STEAM_ART_POSITION
	_steam_sprite.z_index = STEAM_ART_Z
	_steam_sprite.visible = false
	add_child(_steam_sprite)


## The drawn steam loops over the boombox while he is overheated (it replaces the code-drawn puffs).
func _update_steam_art() -> void:
	if _steam_sprite != null:
		_steam_sprite.visible = _steam_left > 0.0 and not _dead


## Dresses `hazard` with the drawn `clip` of `key`, fitted to its box; no art keeps the placeholder.
func _dress(hazard: BoomboxHazard, key: String, clip: StringName, fit := BoomboxHazard.ArtFit.CONTAIN, flip := false) -> void:
	if _effects == null:
		return
	var sprite := _effects.fit_sprite(key, clip, hazard.half_extents * 2.0, fit, flip)
	if sprite != null:
		hazard.attach_art(sprite)


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
			return [&"overheat", 0.0]
		State.TRANSITION:
			return [&"phase_change", phase_transition_time]
		State.ATTACK:
			return _attack_clip_request()
		State.IDLE:
			if _intro_left > 0.0:
				return [&"intro", _intro_left]
		State.FIGHT:
			if absf(velocity.x) >= WALK_CLIP_SPEED:
				return [&"walk", 0.0]
	return [&"idle", 0.0]


func _attack_clip_request() -> Array:
	match _attack:
		Attack.THRUST:
			return _thrust_clip_request()
		Attack.BRIEFCASE:
			return _briefcase_clip_request()
		Attack.KICK:
			match _attack_phase:
				AttackPhase.TELEGRAPH:
					return [&"kick_windup", _telegraph_total]
				AttackPhase.ACTIVE:
					return [&"kick_strike", kick_active_time]
			return [&"kick_recover", maxf(_state_left, MIN_CLIP_TIME)]
		Attack.SOUND_WAVE:
			return _beat_loop_request(&"conduct")
		Attack.NOTE_BOUNCE:
			return _beat_loop_request(&"notes")
		Attack.DICTATION:
			return _beat_loop_request(&"lecture")
		Attack.BASS_DROP:
			match _attack_phase:
				AttackPhase.TELEGRAPH:
					return [&"bass_lift", _telegraph_total]
				AttackPhase.ACTIVE:
					return [&"bass_slam", shock_time + BASS_SLAM_HOLD]
			return [&"bass_slam", 0.0]
	return [&"idle", 0.0]


## One cycle of a looping clip per beat while the pattern lasts, then back to idle.
func _beat_loop_request(clip: StringName) -> Array:
	if _attack_phase == AttackPhase.RECOVER:
		return [&"idle", 0.0]
	return [clip, get_beat_interval()]


func _thrust_clip_request() -> Array:
	var heights := _heights()
	if _attack_phase == AttackPhase.TELEGRAPH:
		return [_thrust_clip(int(heights[0]), "windup"), _telegraph_total]
	if _attack_phase == AttackPhase.ACTIVE:
		var index := clampi(_event_cursor - 1, 0, heights.size() - 1)
		if _clock - _event_clock < thrust_strike_time:
			return [_thrust_clip(int(heights[index]), "strike"), thrust_strike_time]
		if index + 1 < heights.size():
			return [_thrust_clip(int(heights[index + 1]), "windup"), maxf(_time_to_beat(1), MIN_CLIP_TIME)]
		return [_thrust_clip(int(heights[index]), "recover"), maxf(_state_left, MIN_CLIP_TIME)]
	return [_thrust_clip(int(heights[heights.size() - 1]), "recover"), maxf(_state_left, MIN_CLIP_TIME)]


func _thrust_clip(height: int, part: String) -> StringName:
	return StringName("thrust_%s_%s" % ["high" if height == Height.HIGH else "low", part])


## Release, the empty-handed wait while it flies and the catch when it comes home.
func _briefcase_clip_request() -> Array:
	match _attack_phase:
		AttackPhase.TELEGRAPH:
			return [&"throw_windup", _telegraph_total]
		AttackPhase.ACTIVE:
			if _clock - _event_clock < THROW_RELEASE_TIME:
				return [&"throw_release", THROW_RELEASE_TIME]
			if _state_left <= THROW_CATCH_TIME:
				return [&"throw_catch", THROW_CATCH_TIME]
			return [&"throw_wait", 0.0]
	return [&"idle", 0.0]


## -- Placeholder drawing ----------------------------------------------------------------------------

## A ring at his feet that grows and fades on every beat, bigger and brighter on the
## strong one: the tempo with no audio.
func _draw_metronome() -> void:
	if not _beat_running or _dead:
		return
	var grow := 1.0 - _pulse
	var radius := lerpf(RING_MIN, RING_ACCENT_MAX if _accent else RING_MAX, grow)
	var color := ACCENT_COLOR if _accent else BEAT_COLOR
	color.a = _pulse * (0.95 if _accent else 0.6)
	draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(1.0, RING_FLATTEN))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, color, 3.0 if _accent else 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The coming waves as a row over his head: low pips sit lower, high ones higher, rests
## are dots. The next wave to leave is outlined (it lights one beat before it goes).
func _draw_pips() -> void:
	if _pips.is_empty():
		return
	var start_x := -float(_pips.size() - 1) * PIP_SPACING * 0.5
	for i: int in _pips.size():
		var x := start_x + float(i) * PIP_SPACING
		var kind := _pips[i]
		if kind == WAVE_REST:
			draw_circle(Vector2(x, (PIP_Y_LOW + PIP_Y_HIGH) * 0.5), 2.0, Color(0.7, 0.7, 0.75, 0.6))
			continue
		var high := kind == WAVE_HIGH
		var color := HIGH_WAVE_COLOR if high else LOW_WAVE_COLOR
		if i < _pip_spent:
			color = Color(color.darkened(0.6), 0.45)
		var box := Rect2(Vector2(x - PIP_SIZE * 0.5, (PIP_Y_HIGH if high else PIP_Y_LOW) - PIP_SIZE * 0.5), Vector2(PIP_SIZE, PIP_SIZE))
		draw_rect(box, color)
		if i == _pip_lit:
			draw_rect(box.grow(3.0), Color.WHITE, false, 2.0)


func _draw_steam() -> void:
	if _steam_left <= 0.0 or _dead or _steam_sprite != null:
		return
	for i: int in STEAM_PUFFS:
		var rise := fposmod(_clock * 38.0 + float(i) * 17.0, 56.0)
		var drift := sin(_clock * 2.0 + float(i) * 1.7) * 9.0
		var fade := 1.0 - rise / 56.0
		draw_circle(Vector2(drift + (float(i) - 2.0) * 5.0, -68.0 - rise), 4.0 + 3.0 * (1.0 - fade), Color(STEAM_COLOR, 0.55 * fade))

extends SceneTree
## El Profesor (Boombox Teacher boss): the beat clock and its tempo per phase, strikes
## that start on a beat, the avoidance of every attack (crouch or jump the thrusts, jump
## the low waves, stay grounded for the high ones, be airborne for the bass drop), the
## wave pattern rules, the dictation columns, phrases and finales, the overheat punish
## window, the arena limits, the tempo that never changes in the middle of an attack,
## degenerate designer values, a boss with no arena limits, real dashes through the
## hazards, the reset, and the one-drag prefab with its defeat.
## Run: godot --headless --path . --script res://tests/boombox_teacher_boss_test.gd
## Exits 0 when every check passes, 1 otherwise.

const BOSS_SCENE := "res://scenes/enemies/bosses/boombox_teacher.tscn"
const PREFAB_SCENE := "res://scenes/enemies/bosses/boombox_teacher_boss_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 600.0
## Game seconds run per real second (physics frames then last that much longer).
## Timing cases run at 1; the long fights and avoidance runs at the faster default.
const FAST_SCALE := 3.0
const TIMING_CASES := [
	"case_beat_clock_and_tempo", "case_strikes_start_on_a_beat", "case_minimum_telegraph_at_high_tempo",
	"case_tempo_holds_in_telegraph", "case_tempo_holds_in_active", "case_dash_through_hazards",
	"case_art_thrust_and_briefcase_clips", "case_art_thrust_streak",
]
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LUZ_START := Vector2(-400.0, 0.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const BOSS_AT := Vector2(300.0, 0.0)
const LIMITS := Vector2(-434.0, 434.0)
const HIT_FROM := Vector2(100.0, 0.0)
const ROOM := &"A"
const BOSS_ID := &"library_boombox_teacher"
## Luz's feet this high above the floor: clear of every low hazard, inside the high waves.
const AIR_HEIGHT := 70.0
const MAX_ATTACK_FRAMES := 1500
const MAX_CYCLE_FRAMES := 9000
const FAST_BPM := 240.0
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.3, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const ART_DIR := "user://boombox_teacher_art_fixture"
const ART_MANIFEST := ART_DIR + "/animation_manifest.json"
const NO_ART_MANIFEST := ART_DIR + "/missing.json"
const ART_CELL := 4
const ART_COLUMNS := 4
## Content boxes (sheet px) the fixture manifest declares for the effect clips.
const FIXTURE_PROPS := {"briefcase_spin": [100, 120], "note": [60, 90], "note_pair": [90, 90], "spark": [80, 80]}
const FIXTURE_FX := {"wave_low": [100, 130], "wave_high": [100, 130], "bass_shock": [240, 70], "chalk_dust": [100, 80], "steam": [150, 150]}
const FIXTURE_THRUST := {"thrust_streak": [300, 45]}
const FIXTURE_BOARD := Vector2(120.0, 40.0)
const PLACEHOLDER_NODES := ["Visual/Body", "Visual/Tie", "Visual/Pointer", "Visual/Head"]

const CHECKS := {
	"case_prefab_is_one_drag": 15,
	"case_beat_clock_and_tempo": 17,
	"case_strikes_start_on_a_beat": 32,
	"case_minimum_telegraph_at_high_tempo": 6,
	"case_thrust_heights": 10,
	"case_briefcase": 8,
	"case_kick": 8,
	"case_low_and_high_waves": 10,
	"case_wave_pattern_rules": 8,
	"case_notes": 6,
	"case_dictation": 14,
	"case_bass_drop": 9,
	"case_phase_one_cycle": 17,
	"case_phase_two_cycle": 12,
	"case_phase_three_cycle": 14,
	"case_kick_when_hugged": 4,
	"case_stays_inside_the_arena": 4,
	"case_tempo_holds_in_telegraph": 10,
	"case_tempo_holds_in_active": 24,
	"case_degenerate_tunables": 10,
	"case_no_arena_limits": 5,
	"case_dash_through_hazards": 10,
	"case_reset_clears_every_hazard": 12,
	"case_arena_reset_after_luz_dies": 5,
	"case_defeat_through_the_arena": 16,
	"case_art_absent_keeps_the_placeholders": 12,
	"case_art_shows_the_sprite": 12,
	"case_art_glow_and_flash_on_the_sprite": 10,
	"case_art_thrust_and_briefcase_clips": 18,
	"case_art_other_attack_clips": 5,
	"case_art_state_clips": 15,
	"case_art_scale_relation": 6,
	"case_art_hazards_wear_the_sprites": 17,
	"case_art_thrust_streak": 16,
	"case_art_steam_over_the_boombox": 6,
	"case_art_effects_without_a_content_box": 7,
	"case_art_dictation_on_chalk": 11,
	"case_art_absent_hazards_stay_placeholders": 7,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player
var _boss: BoomboxTeacherBoss
var _arena: BossArena
var _beat_frames: Array[int] = []
var _crouch_height := 0.0
var _scale := FAST_SCALE


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	_scale = 1.0 if TIMING_CASES.has(case_name) else FAST_SCALE
	await call(case_name)
	_cleanup()
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func _on_watchdog() -> void:
	Engine.time_scale = 1.0
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


func finish() -> void:
	var complete := _problems.is_empty() and checks == _expected_total
	if complete and failed.is_empty():
		print("PASS %d/%d" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("FAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("FAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


# -- Rig and helpers ------------------------------------------------------------------

func _registry() -> Node:
	return root.get_node("EnemyRegistry")


func _progress() -> Node:
	return root.get_node("BossProgress")


func _build_world() -> void:
	_cleanup()
	root.get_node("CheckpointService").clear()
	_registry().clear()
	_progress().clear()
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(-482.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(434.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = LUZ_START
	_rig.add_child(_player)
	_player.set_max_health(30)
	_player.heal(30)
	_player.set_checkpoint(LUZ_START)
	current_scene = _rig
	Engine.time_scale = _scale


func _tune(boss: BoomboxTeacherBoss) -> void:
	boss.rng_seed = 7
	boss.hit_stop_time = 0.0
	boss.final_freeze_time = 0.0
	boss.final_slowmo_time = 0.0
	boss.phase_transition_time = 0.3
	boss.defeat_time = 0.2


func _build_rig(configure := Callable()) -> void:
	_build_world()
	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as BoomboxTeacherBoss
	_tune(_boss)
	_boss.position = BOSS_AT
	_boss.auto_phrases = false
	_boss.walk_speed = 0.0
	if configure.is_valid():
		configure.call(_boss)
	_rig.add_child(_boss)
	_boss.set_manual_engage(true)


func _awake_boss(configure := Callable()) -> void:
	await _build_rig(configure)
	await _frames(3)
	_boss.set_arena_limits(LIMITS.x, LIMITS.y)
	_boss.engage()
	_record_beats()


func _build_arena() -> void:
	_build_world()
	_arena = (load(PREFAB_SCENE) as PackedScene).instantiate() as BossArena
	for key: String in ARENA_TIMINGS:
		_arena.set(key, ARENA_TIMINGS[key])
	_rig.add_child(_arena)
	_boss = _arena.get_boss() as BoomboxTeacherBoss
	_tune(_boss)


func _cleanup() -> void:
	BossFeel.cancel()
	Engine.time_scale = 1.0
	Input.action_release(&"move_down")
	if is_instance_valid(_rig):
		if current_scene == _rig:
			current_scene = null
		_rig.free()
	_rig = null
	_player = null
	_boss = null
	_arena = null
	_registry().clear()
	_progress().clear()
	root.get_node("MusicManager").stop_music()


func _frames(n: int) -> void:
	for i: int in n:
		await physics_frame


## Game seconds one physics frame lasts at the current time scale.
func _dt() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## Waits `seconds` of game time.
func _wait(seconds: float) -> void:
	await _frames(ceili(seconds / _dt()))


func _record_beats() -> void:
	_beat_frames.clear()
	_boss.beat.connect(func(_index: int) -> void: _beat_frames.append(Engine.get_physics_frames()))


## Frames between `frame` and the closest recorded beat.
func _gap_to_beat(frame: int) -> int:
	var best := 1000000
	for beat_frame: int in _beat_frames:
		best = mini(best, absi(frame - beat_frame))
	return best


func _hit(damage := 1) -> bool:
	return _boss.receive_hit(damage, HIT_FROM, &"attack_1")


## Frames from now until the boss is in `phase_id` of its attack (-1 on timeout).
func _frames_until_phase(phase_id: BossEnemy.AttackPhase, limit := 900) -> int:
	var frames := 0
	while _boss.get_attack_phase() != phase_id and frames < limit:
		await physics_frame
		frames += 1
	return frames if frames < limit else -1


## Runs `step` against Luz standing `dx` px from the boss in `pose` (stand, crouch or
## air) and returns the health she lost. Her pose is held through the whole attack and
## until its last hazard is gone.
func _avoid(step: Dictionary, dx: float, pose: String) -> int:
	await _awake_boss()
	await _frames(2)
	_player.global_position = Vector2(_boss.global_position.x + dx, 0.0)
	_player.velocity = Vector2.ZERO
	var before := _player.get_health()
	_boss.plan_step(step)
	_boss.start_attack(int(step["attack"]))
	if pose == "crouch":
		Input.action_press(&"move_down")
		await _frames(15)
		_crouch_height = BoomboxHazard.luz_rect(_player).size.y
	var guard := 0
	while (_boss.get_state() == BossEnemy.State.ATTACK or _boss.hazard_count() > 0) and guard < MAX_ATTACK_FRAMES:
		if pose == "air":
			_player.global_position.y = -AIR_HEIGHT
			_player.velocity = Vector2.ZERO
		await physics_frame
		guard += 1
	Input.action_release(&"move_down")
	return before - _player.get_health()


func _thrust(height: int) -> Dictionary:
	return {"attack": BoomboxTeacherBoss.Attack.THRUST, "heights": [height]}


func _wave(kind: int) -> Dictionary:
	return {"attack": BoomboxTeacherBoss.Attack.SOUND_WAVE, "pattern": [kind]}


func _hazard_nodes() -> int:
	var count := 0
	for child: Node in _rig.get_children():
		if child is BoomboxHazard and not child.is_queued_for_deletion():
			count += 1
	return count


# -- Cases ------------------------------------------------------------------------------

func case_prefab_is_one_drag() -> void:
	_build_arena()
	await _frames(20)
	check(_arena.get_boss() == _boss and _boss != null, "the arena finds the boss as its direct child")
	check(_arena.boss_name == "El Profesor", "the arena carries the Spanish boss name")
	check(_boss.enemy_id == BOSS_ID, "the boss has the unique enemy_id")
	check(not _arena.reward_enabled, "the reward is off")
	check(_boss.max_health == 36 and _boss.super_armor and _boss.knockback_resistance == 1.0, "36 HP, super armor and no knockback")
	check(_boss.phase_thresholds == PackedFloat32Array([0.66, 0.33]), "three phases at 66 and 33 percent")
	check(_arena.get_state() == BossArena.FightState.ARMED and not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "the arena is armed and the boss untouchable before the fight")
	check(_boss._arena_bounds() == Vector2(-468.0, 468.0), "the arena fed the boss its real walls")
	check(is_equal_approx(_boss.max_health * _boss.phase_two_threshold, 36 * 0.66), "the bar notch is the first threshold")
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(15)
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "entering the trigger starts the fight")
	check(_arena.get_bar().get_name_text() == "El Profesor", "the health bar shows El Profesor")
	check(_arena.get_bar().get_extra_notch_ratios() == PackedFloat32Array([0.33]), "the bar gets the second notch")
	await _frames(40)
	check(_boss.get_state() != BossEnemy.State.IDLE and _boss.is_beat_running(), "the arena engaged the boss and the beat clock runs")
	check(_arena.are_doors_closed(), "the doors close for the fight")
	check(_boss.is_in_group(Enemy.GROUP_RESETTABLE), "the boss follows the checkpoint contract")


func case_beat_clock_and_tempo() -> void:
	await _build_rig()
	await _frames(3)
	_boss.set_arena_limits(LIMITS.x, LIMITS.y)
	check(not _boss.is_beat_running(), "the clock waits for the fight")
	var cues: Array[String] = []
	_boss.sfx_cue.connect(func(cue: StringName) -> void: cues.append(String(cue)))
	var accents: Array[bool] = []
	_boss.beat.connect(func(index: int) -> void: accents.append(index % 4 == 0 and _boss._accent))
	_record_beats()
	_boss.engage()
	check(_boss.is_beat_running() and _boss.get_beat_index() == 0, "engage starts the clock")
	await _wait(4.2)
	var first := _interval_frames()
	check(first.size() >= 3 and _all_close(first, 60.0 / 90.0), "phase one ticks at 90 bpm (%s)" % [first])
	check(cues.has("Beat"), "every beat plays the Beat cue")
	check(accents.size() >= 4 and accents[3], "the fourth beat is the accent")
	var before_phase := _beat_frames.size()
	_hit(13)
	check(_boss.get_phase() == 2, "13 hits reach phase two")
	await _wait(3.0)
	var second := _interval_frames(before_phase + 2)
	check(second.size() >= 3 and _all_close(second, 60.0 / 110.0), "phase two ticks at 110 bpm (%s)" % [second])
	before_phase = _beat_frames.size()
	_hit(12)
	check(_boss.get_phase() == 3, "12 more hits reach phase three")
	await _wait(3.0)
	var third := _interval_frames(before_phase + 2)
	check(third.size() >= 3 and _all_close(third, 60.0 / 132.0), "phase three ticks at 132 bpm (%s)" % [third])
	check(_boss.get_beat_interval() < 60.0 / 110.0 and 60.0 / 110.0 < 60.0 / 90.0, "each phase beats faster than the one before")
	# Reset stops the clock again.
	_boss.reset_to_spawn()
	check(not _boss.is_beat_running() and _boss.get_beat_index() == 0, "a reset stops and rewinds the clock")
	check(is_equal_approx(_boss.get_beat_interval(), 60.0 / 90.0), "a reset returns to the phase one tempo")
	await _frames(30)
	var count := _beat_frames.size()
	await _frames(60)
	check(_beat_frames.size() == count, "no beat fires while the boss awaits the arena")
	# The metronome: the ring and the head pulse follow every beat.
	_boss.engage()
	await _wait(_boss.get_beat_interval() + 2.0 * _dt())
	var head := _boss.get_node("Visual/Head") as Node2D
	check(_boss._pulse > 0.0 and head.scale.x > 1.0, "a beat pulses the head and the ring")
	check(_boss._pulse < 1.0, "the pulse fades between beats")
	check(_boss.get_node("Visual/Head") != null and _boss.get_node("Visual/Body") != null, "the boombox head and the body exist")
	check(cues.has("Beat") and not cues.has("Overheat"), "no overheat cue without a finale")


## Frame distances between consecutive beats, in seconds (from beat `from` on).
func _interval_frames(from := 0) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(maxi(from, 1), _beat_frames.size()):
		out.append(float(_beat_frames[i] - _beat_frames[i - 1]) * _dt())
	return out


func _all_close(values: Array[float], wanted: float) -> bool:
	for value: float in values:
		if absf(value - wanted) > _dt() * 1.6:
			return false
	return true


func case_strikes_start_on_a_beat() -> void:
	await _awake_boss()
	await _frames(3)
	var A := BoomboxTeacherBoss.Attack
	for attack: int in [A.THRUST, A.BRIEFCASE, A.KICK, A.SOUND_WAVE, A.NOTE_BOUNCE, A.DICTATION, A.BASS_DROP]:
		var name := String(A.keys()[attack])
		_boss.start_attack(attack)
		var started := Engine.get_physics_frames()
		var waited := await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
		var active_frame := Engine.get_physics_frames()
		check(waited > 0, "%s reaches its active phase" % name)
		check(float(active_frame - started) * _dt() >= BossEnemy.MIN_TELEGRAPH, "%s telegraphs for at least 0.35 s" % name)
		check(_gap_to_beat(active_frame) <= 2, "%s strikes on a beat (%d frames off)" % [name, _gap_to_beat(active_frame)])
	# Every telegraph is the time to a whole number of next beats.
	var interval := _boss.get_beat_interval()
	_boss.start_attack(A.THRUST)
	var beats_long := (_boss.get_state_time_left() - _boss.get_beat_left()) / interval
	check(absf(beats_long - roundf(beats_long)) < 0.02, "a telegraph ends on a beat (%.3f beats past the next one)" % beats_long)
	check(_boss.get_state_time_left() <= interval + 0.001, "a one-beat telegraph is at most one interval")
	check(_boss.is_telegraphing(), "start_attack opens in the telegraph")
	var log := _boss.get_attack_log()
	check(log.size() == 8 and log[0] == A.THRUST and log[6] == A.BASS_DROP, "every attack was logged in order")
	check(log.back() == A.THRUST, "the log keeps the latest attack last")
	await _frames(2)
	check(_boss.get_telegraph() != null and _boss.get_telegraph().is_glowing(), "the telegraph glows during the wind-up")
	check(_boss.is_beat_running(), "the clock kept running")
	_boss.start_attack(A.KICK)
	check(_boss.get_step()["attack"] == A.KICK, "the step follows the attack in progress")
	check(_boss.get_telegraph().is_floor_marker_visible(0), "the kick marks its floor range")
	check(_boss.get_phase() == 1, "the strikes ran in phase one")
	check(_boss.get_health() == _boss.max_health, "the boss lost no health")


func case_minimum_telegraph_at_high_tempo() -> void:
	await _awake_boss(func(boss: BoomboxTeacherBoss) -> void: boss.bpm_by_phase = PackedFloat32Array([FAST_BPM, FAST_BPM, FAST_BPM]))
	await _frames(3)
	var interval := _boss.get_beat_interval()
	check(is_equal_approx(interval, 0.25) and interval < BossEnemy.MIN_TELEGRAPH, "240 bpm beats are shorter than the minimum telegraph")
	_boss.start_attack(BoomboxTeacherBoss.Attack.THRUST)
	var started := Engine.get_physics_frames()
	check(_boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH, "a one-beat telegraph is raised to at least 0.35 s")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	var frame := Engine.get_physics_frames()
	check(float(frame - started) * _dt() >= BossEnemy.MIN_TELEGRAPH - _dt(), "it lasted at least 0.35 s")
	check(_gap_to_beat(frame) <= 2, "the longer telegraph still ends on a beat")
	check(_boss.hazard_count() == 1, "the thrust spawned one hazard")
	var hazard := _boss.get_hazards()[0]
	check(hazard.bound and hazard.get_rect().size.x >= _boss.thrust_reach - 0.1, "it is bound to the attack and as long as the reach")


func case_thrust_heights() -> void:
	var high := BoomboxTeacherBoss.Height.HIGH
	var low := BoomboxTeacherBoss.Height.LOW
	var distance := -85.0
	check(await _avoid(_thrust(high), distance, "stand") > 0, "a high thrust hurts a standing Luz")
	check(await _avoid(_thrust(high), distance, "crouch") == 0, "crouching under a high thrust avoids it")
	check(_crouch_height < 30.0, "Luz really crouched (%.0f px tall)" % _crouch_height)
	check(await _avoid(_thrust(low), distance, "stand") > 0, "a low thrust hurts a standing Luz")
	check(await _avoid(_thrust(low), distance, "crouch") > 0, "crouching does not avoid a low thrust")
	check(await _avoid(_thrust(low), distance, "air") == 0, "jumping a low thrust avoids it")
	check(await _avoid(_thrust(high), distance, "air") == 0, "a high thrust passes under a jumping Luz")
	check(await _avoid(_thrust(high), -220.0, "stand") == 0, "Luz beyond the reach is safe")
	# A chain: alternating heights, each shown on the line during the beat before it.
	await _awake_boss()
	var chain := {"attack": BoomboxTeacherBoss.Attack.THRUST, "heights": [high, low, high]}
	_boss.plan_step(chain)
	_boss.start_attack(BoomboxTeacherBoss.Attack.THRUST)
	var line_y: Array[float] = []
	var seen_hazards := 0
	var last_count := 0
	var guard := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		await physics_frame
		guard += 1
		var telegraph := _boss.get_telegraph()
		if telegraph.is_aim_line_visible() and (line_y.is_empty() or not is_equal_approx(line_y.back(), telegraph._lines[0].get_point_position(0).y)):
			line_y.append(telegraph._lines[0].get_point_position(0).y)
		var count := _boss.hazard_count()
		if count > last_count:
			seen_hazards += 1
		last_count = count
	check(seen_hazards == 3, "a three thrust chain spawned three thrusts (%d)" % seen_hazards)
	check(line_y.size() == 3 and line_y[0] < line_y[1] and line_y[2] < line_y[1], "the red line showed high, low, high in turn (%s)" % [line_y])


func case_briefcase() -> void:
	var step := {"attack": BoomboxTeacherBoss.Attack.BRIEFCASE}
	check(await _avoid(step, -200.0, "stand") > 0, "the briefcase hurts a standing Luz in its way")
	check(await _avoid(step, -200.0, "crouch") > 0, "crouching does not avoid it (torso height)")
	check(await _avoid(step, -200.0, "air") == 0, "jumping the briefcase avoids it")
	check(await _avoid(step, -200.0 - 330.0, "stand") == 0, "Luz beyond its reach is safe")
	await _awake_boss()
	_player.global_position = Vector2(-380.0, 0.0)
	_boss.plan_step(step)
	_boss.start_attack(BoomboxTeacherBoss.Attack.BRIEFCASE)
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	var xs: Array[float] = []
	var guard := 0
	while _boss.hazard_count() > 0 and guard < MAX_ATTACK_FRAMES:
		xs.append(_boss.get_hazards()[0].position.x)
		await physics_frame
		guard += 1
	var interval := _boss.get_beat_interval()
	check(xs.size() > 0 and xs.min() < _boss.global_position.x - 250.0, "the briefcase flies out about its reach (%.0f)" % (xs.min() if xs.size() > 0 else 0.0))
	check(absf(float(xs.size()) * _dt() - 4.0 * interval) < 0.15, "it flies out two beats and back two beats (%.2f s)" % (float(xs.size()) * _dt()))
	check(xs.size() > 0 and xs.back() > _boss.global_position.x - 90.0, "it comes back to him before it vanishes (%.0f)" % (xs.back() if xs.size() > 0 else 0.0))
	check(_boss.hazard_count() == 0, "the briefcase is gone at the end")


func case_kick() -> void:
	var step := {"attack": BoomboxTeacherBoss.Attack.KICK}
	check(await _avoid(step, -40.0, "stand") > 0, "the kick hurts a hugging Luz")
	check(await _avoid(step, -40.0, "air") == 0, "jumping the kick avoids it")
	check(await _avoid(step, -140.0, "stand") == 0, "stepping back avoids the kick")
	await _awake_boss()
	_boss.start_attack(BoomboxTeacherBoss.Attack.KICK)
	await _frames(3)
	check(_boss.get_telegraph().is_glowing(), "the kick glows during its wind-up")
	var started := Engine.get_physics_frames()
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	check(float(Engine.get_physics_frames() - started) * _dt() >= BossEnemy.MIN_TELEGRAPH - _dt(), "the kick telegraph lasts at least 0.35 s")
	check(_boss.hazard_count() == 1 and _boss.get_hazards()[0].bound, "the kick spawns one bound hitbox")
	await _wait(_boss.kick_active_time + 0.2)
	check(_boss.hazard_count() == 0, "the kick hitbox is short lived")
	check(_boss.get_attack_phase() != BossEnemy.AttackPhase.ACTIVE, "the kick active phase ended")


func case_low_and_high_waves() -> void:
	var low := BoomboxTeacherBoss.WAVE_LOW
	var high := BoomboxTeacherBoss.WAVE_HIGH
	check(await _avoid(_wave(low), -300.0, "stand") > 0, "a low wave hurts a standing Luz")
	check(await _avoid(_wave(low), -300.0, "air") == 0, "jumping a low wave avoids it")
	check(await _avoid(_wave(low), 100.0, "stand") > 0, "waves also travel to the other side")
	check(await _avoid(_wave(high), -300.0, "stand") == 0, "a high wave passes over a standing Luz")
	check(await _avoid(_wave(high), -300.0, "crouch") == 0, "a high wave passes over a crouching Luz")
	check(await _avoid(_wave(high), -300.0, "air") > 0, "jumping into a high wave hurts")
	await _awake_boss()
	_boss.plan_step({"attack": BoomboxTeacherBoss.Attack.SOUND_WAVE, "pattern": [low, high, BoomboxTeacherBoss.WAVE_REST, low]})
	_boss.start_attack(BoomboxTeacherBoss.Attack.SOUND_WAVE)
	await _frames(5)
	check(_boss.get_wave_pips() == PackedInt32Array([low, high, BoomboxTeacherBoss.WAVE_REST, low]), "the telegraph shows the pattern as pips")
	check(_boss.hazard_count() == 0, "no wave leaves during the telegraph")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(3)
	var hazards := _boss.get_hazards()
	check(hazards.size() == 2 and hazards[0].velocity.x == -hazards[1].velocity.x, "the first wave leaves in both directions")
	var low_top: float = hazards[0].get_rect().position.y
	await _wait(_boss.get_beat_interval())
	var highs := _boss.get_hazards().filter(func(h: BoomboxHazard) -> bool: return h.get_rect().end.y < -40.0)
	check(highs.size() == 2 and highs[0].get_rect().end.y < low_top + 20.0 and highs[0].get_rect().position.y > -80.0 - 0.1, "the second wave is high, 50 to 80 px above the floor")


func case_wave_pattern_rules() -> void:
	await _awake_boss()
	var low := BoomboxTeacherBoss.WAVE_LOW
	var high := BoomboxTeacherBoss.WAVE_HIGH
	var rest := BoomboxTeacherBoss.WAVE_REST
	var runs_ok := true
	var high_after_low := false
	var lengths_ok := true
	var first_rest := false
	var saw_all := {low: false, high: false, rest: false}
	for length: int in [4, 5, 6, 7, 8, 8, 8, 8, 8, 8]:
		for repeat: int in 30:
			var pattern := _boss._make_wave_pattern(length)
			lengths_ok = lengths_ok and pattern.size() == length
			first_rest = first_rest or pattern[0] == rest
			for i: int in pattern.size():
				saw_all[pattern[i]] = true
				if i >= 2 and pattern[i] == low and pattern[i - 1] == low and pattern[i - 2] == low:
					runs_ok = false
				if i >= 1 and pattern[i] == high and pattern[i - 1] == low:
					high_after_low = true
	check(lengths_ok, "a pattern has one entry per beat")
	check(runs_ok, "never three low waves in a row (one jump covers two)")
	check(not high_after_low, "a high wave never follows a low one without a rest to land")
	check(not first_rest, "a pattern never opens on a rest")
	check(saw_all[low] and saw_all[high] and saw_all[rest], "the draw uses low waves, high waves and rests")
	var encore := BoomboxTeacherBoss.ENCORE_WAVES
	check(encore.size() == 8, "the Encore sequence is eight beats long")
	var encore_ok := true
	for i: int in encore.size():
		if i >= 1 and encore[i] == high and encore[i - 1] == low:
			encore_ok = false
	check(encore_ok and encore.count(low) == 3 and encore.count(high) == 3, "the Encore alternates high and low with a rest to land")
	check(_boss.wave_min_beats == 4 and _boss.wave_max_beats == 8, "waves run four to eight beats")


func case_notes() -> void:
	await _awake_boss()
	var hop := _boss.note_hop_distance()
	var start_x := _boss.global_position.x - (13.0 + _boss.note_radius + BoomboxTeacherBoss.BRIEFCASE_ORIGIN_GAP)
	check(hop > 100.0 and hop < 250.0, "a note hop is a readable distance (%.0f px)" % hop)
	var step := {"attack": BoomboxTeacherBoss.Attack.NOTE_BOUNCE, "count": 3}
	var apex_x := start_x - hop * 0.5
	check(await _avoid(step, apex_x - _boss.global_position.x, "stand") == 0, "standing under the apex of the hop avoids every note")
	var bounce_x := start_x - hop
	check(await _avoid(step, bounce_x - _boss.global_position.x, "stand") > 0, "standing where a note bounces hurts")
	check(await _avoid(step, bounce_x - _boss.global_position.x, "air") == 0, "jumping the bounce avoids the note")
	await _awake_boss()
	_player.global_position = Vector2(apex_x, 0.0)
	_boss.plan_step(step)
	_boss.start_attack(BoomboxTeacherBoss.Attack.NOTE_BOUNCE)
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(3)
	check(_boss.hazard_count() == 1 and _boss.get_hazards()[0].velocity.x < 0.0, "the first note leaves toward Luz")
	var guard := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		await physics_frame
		guard += 1
	await _wait(5.0)
	check(_boss.hazard_count() == 0, "the notes despawn at the walls")


func case_dictation() -> void:
	await _awake_boss()
	var step := {"attack": BoomboxTeacherBoss.Attack.DICTATION}
	_boss.plan_step(step)
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	var columns := _boss.get_columns()
	check(columns.size() >= 4 and columns.size() <= 9, "the dictation has four to nine columns (%d)" % columns.size())
	var sorted := true
	var inside := true
	for i: int in columns.size():
		sorted = sorted and (i == 0 or columns[i] > columns[i - 1])
		inside = inside and columns[i] > LIMITS.x and columns[i] < LIMITS.y
	check(sorted and inside, "the columns run left to right inside the arena")
	var board := _boss.get_board()
	check(board != null and absf(board.global_position.x) < 1.0 and board.global_position.y < -150.0, "a blackboard appears above the arena centre")
	var label := board.get_node("Text") as Label
	check(label.text == "in English please!", "the blackboard reads: in English please!")
	var markers_visible := true
	for i: int in columns.size():
		markers_visible = markers_visible and _boss.get_telegraph().is_floor_marker_visible(i)
	check(markers_visible, "every column shows its floor marker during the wind-up")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	check(_boss.hazard_count() == 1 and absf(_boss.get_hazards()[0].position.x - columns[0]) < 1.0, "the first letter falls on the leftmost column")
	check(_boss.letter_fall_time >= BossEnemy.MIN_TELEGRAPH, "a letter takes at least 0.35 s to land")
	var fall_frames := 0
	var tracked := _boss.get_hazards()[0]
	while is_instance_valid(tracked) and tracked.is_alive() and fall_frames < 120:
		await physics_frame
		fall_frames += 1
	check(float(fall_frames + 2) * _dt() >= 0.4, "the letter fell for about %.2f s" % (float(fall_frames + 2) * _dt()))
	var order: Array[float] = [columns[0]]
	var seen := {}
	var guard := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		for hazard: BoomboxHazard in _boss.get_hazards():
			if not seen.has(hazard.get_instance_id()):
				seen[hazard.get_instance_id()] = true
				order.append(hazard.position.x)
		await physics_frame
		guard += 1
	var in_order := true
	for i: int in range(1, order.size()):
		in_order = in_order and order[i] > order[i - 1]
	check(in_order and order.size() == columns.size(), "the letters fall in reading order, one per column (%d of %d)" % [order.size(), columns.size()])
	check(_boss.get_board() == null and _boss.hazard_count() == 0, "the board and the letters are gone at the end")
	# Hurt under a column, safe between two.
	await _awake_boss()
	_boss.plan_step(step)
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	var cols := _boss.get_columns()
	var target := cols[3]
	_player.global_position = Vector2(target, 0.0)
	var before := _player.get_health()
	var guard2 := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard2 < MAX_ATTACK_FRAMES:
		await physics_frame
		guard2 += 1
	check(_player.get_health() < before, "a letter hurts Luz standing under its column")
	await _awake_boss()
	_boss.plan_step(step)
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	cols = _boss.get_columns()
	var gap_x := (cols[3] + cols[4]) * 0.5
	var before_gap := _player.get_health()
	guard2 = 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard2 < MAX_ATTACK_FRAMES:
		_player.global_position = Vector2(gap_x, 0.0)
		_player.velocity = Vector2.ZERO
		await physics_frame
		guard2 += 1
	check(_player.get_health() == before_gap, "standing between two columns is safe")
	# The dictation adapts to the walls it is given.
	await _awake_boss()
	_boss.set_arena_limits(-200.0, 200.0)
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	var narrow := _boss.get_columns()
	check(narrow[0] > -200.0 and narrow[narrow.size() - 1] < 200.0 and narrow.size() >= 4, "a narrower arena gets narrower columns")
	check(absf(_boss.get_board().global_position.x) < 1.0, "the board follows the arena centre")


func case_bass_drop() -> void:
	var step := {"attack": BoomboxTeacherBoss.Attack.BASS_DROP}
	check(await _avoid(step, -250.0, "stand") > 0, "the ground shock hurts a grounded Luz")
	check(await _avoid(step, -250.0, "air") == 0, "being airborne avoids the ground shock")
	check(await _avoid(step, 110.0, "stand") > 0, "the shock covers the whole arena, both sides of the boss")
	await _awake_boss()
	_boss.start_attack(BoomboxTeacherBoss.Attack.BASS_DROP)
	var started := Engine.get_physics_frames()
	await _frames(5)
	check(_boss.get_telegraph().is_floor_marker_visible(BoomboxTeacherBoss.MARKER_SLOT_FLASH), "the whole floor flashes during the wind-up")
	var head := _boss.get_node("Visual/Head") as Node2D
	check(head.position.y < -50.0 - 1.0, "he lifts the boombox")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	var active_frame := Engine.get_physics_frames()
	check(float(active_frame - started) * _dt() >= 2.0 * _boss.get_beat_interval() - 0.1, "the wind-up lasts two beats")
	await _frames(2)
	var shock := _boss.get_hazards()[0]
	check(absf(shock.get_rect().size.x - (LIMITS.y - LIMITS.x)) < 1.0, "the shock spans the whole arena (%.0f px)" % shock.get_rect().size.x)
	check(shock.get_rect().size.y >= 30.0 and shock.bound, "the shock is a bound band above the floor")
	await _wait(_boss.get_beat_interval() * 2.0)
	check(_boss.hazard_count() == 0, "the shock does not linger")


## Plays a whole fight cycle of `phase` at a fast tempo with Luz out of the way (and
## healed every frame, the point is the structure): the phrases planned, the stun after
## the finale and the attacks seen.
func _play_cycle(phase: int, hit_in_stun := false) -> Dictionary:
	await _build_rig(func(boss: BoomboxTeacherBoss) -> void:
		boss.auto_phrases = true
		boss.walk_speed = 70.0
		boss.bpm_by_phase = PackedFloat32Array([FAST_BPM, FAST_BPM, FAST_BPM]))
	await _frames(3)
	_boss.set_arena_limits(LIMITS.x, LIMITS.y)
	_boss.engage()
	if phase == 2:
		_hit(13)
	elif phase == 3:
		_hit(25)
	var phrases: Array = []
	_boss.phrase_started.connect(func(attacks: Array, finale: bool) -> void: phrases.append({"attacks": attacks.duplicate(), "finale": finale}))
	var cues: Array[String] = []
	_boss.sfx_cue.connect(func(cue: StringName) -> void: cues.append(String(cue)))
	var result := {"phrases": phrases, "cues": cues, "stun_frames": 0, "hit_ok": false, "log_at_stun": [], "hazards_at_stun": -1, "min_x": 1.0e9, "max_x": -1.0e9, "min_y": 0.0}
	var started_stun := false
	for frame: int in MAX_CYCLE_FRAMES:
		_player.heal(30)
		var x := _boss.global_position.x
		result["min_x"] = minf(result["min_x"], x)
		result["max_x"] = maxf(result["max_x"], x)
		result["min_y"] = minf(result["min_y"], _boss.global_position.y)
		await physics_frame
		if _boss.is_stunned():
			if not started_stun:
				started_stun = true
				result["log_at_stun"] = _boss.get_attack_log().duplicate()
				result["hazards_at_stun"] = _boss.hazard_count()
				if hit_in_stun:
					var health := _boss.get_health()
					result["hit_ok"] = _hit() and _boss.get_health() == health - 1 and _boss.get_state() == BossEnemy.State.STUN
			result["stun_frames"] += 1
		elif started_stun:
			break
	result["log"] = _boss.get_attack_log().duplicate()
	return result


func _cycle_basics(result: Dictionary, finale: Array[int], overheat: float, label: String) -> void:
	var phrases: Array = result["phrases"]
	check(phrases.size() >= 3, "%s: three phrases were played (%d)" % [label, phrases.size()])
	var lengths_ok := true
	for i: int in mini(phrases.size(), 3):
		var entry: Dictionary = phrases[i]
		if i < 2 and (entry["finale"] or (entry["attacks"] as Array).size() < 2 or (entry["attacks"] as Array).size() > 4):
			lengths_ok = false
	check(lengths_ok, "%s: the first two phrases are plain, of two to four attacks" % label)
	check(phrases.size() >= 3 and phrases[2]["finale"] and phrases[2]["attacks"] == finale, "%s: the third phrase is the finale %s" % [label, finale])
	check(result["stun_frames"] > 0, "%s: the finale is followed by the overheat" % label)
	check(absf(float(result["stun_frames"]) * _dt() - overheat) < 0.15, "%s: the overheat lasts about %.1f s (%.2f)" % [label, overheat, float(result["stun_frames"]) * _dt()])
	check(result["cues"].has("Overheat"), "%s: the Overheat cue fired" % label)
	check(result["hazards_at_stun"] == 0, "%s: no hazard is left when the overheat starts" % label)
	var last_attack: int = (result["log_at_stun"] as Array).back() if not (result["log_at_stun"] as Array).is_empty() else -9
	check(last_attack == finale.back(), "%s: the overheat follows the last attack of the finale" % label)
	check(result["min_x"] >= LIMITS.x + 12.0 and result["max_x"] <= LIMITS.y - 12.0 and result["min_y"] > -1.0, "%s: the boss stayed inside the arena and on the floor (%.0f to %.0f)" % [label, result["min_x"], result["max_x"]])


func case_phase_one_cycle() -> void:
	var A := BoomboxTeacherBoss.Attack
	var result := await _play_cycle(1, true)
	_cycle_basics(result, [A.THRUST, A.BRIEFCASE], 2.2, "phase 1")
	check(result["hit_ok"], "phase 1: he takes hits during the overheat and it does not end")
	var allowed := [A.THRUST, A.BRIEFCASE, A.KICK]
	var only_early := true
	for attack: int in result["log"]:
		only_early = only_early and allowed.has(attack)
	check(only_early, "phase 1 plays only thrusts, briefcases and kicks (%s)" % [result["log"]])
	var plain: Array = result["phrases"]
	check(plain.size() >= 2 and plain[0]["attacks"] != plain[1]["attacks"], "no phrase repeats right away")
	var thrusts := 0
	for attack: int in result["log"]:
		thrusts += 1 if attack == A.THRUST else 0
	check(thrusts >= 3, "phase 1 plays thrusts (%d)" % thrusts)
	check(_boss.get_phase() == 1 and _boss.get_state() != BossEnemy.State.TRANSITION, "no phase change happened")
	check(_boss.get_health() == _boss.max_health - 1, "only the one overheat hit landed")
	check(BoomboxTeacherBoss.PHRASES[1].size() >= 3 and BoomboxTeacherBoss.PHRASES.size() == 3, "the phrase table has three phases")
	check(_boss.super_armor, "a hit never interrupts a telegraph")


func case_phase_two_cycle() -> void:
	var A := BoomboxTeacherBoss.Attack
	var result := await _play_cycle(2)
	_cycle_basics(result, [A.SOUND_WAVE], 2.0, "phase 2")
	var allowed := [A.THRUST, A.BRIEFCASE, A.KICK, A.SOUND_WAVE, A.NOTE_BOUNCE]
	var no_later := true
	for attack: int in result["log"]:
		no_later = no_later and allowed.has(attack)
	check(no_later, "phase 2 never plays blackboard or bass drop (%s)" % [result["log"]])
	check(result["log"].has(A.SOUND_WAVE), "phase 2 plays sound waves")
	check(_boss.get_phase() == 2, "the cycle ran in phase two")


func case_phase_three_cycle() -> void:
	var A := BoomboxTeacherBoss.Attack
	var result := await _play_cycle(3)
	_cycle_basics(result, [A.DICTATION, A.SOUND_WAVE, A.BASS_DROP], 1.8, "phase 3")
	check(result["log"].has(A.DICTATION) and result["log"].has(A.BASS_DROP), "phase 3 plays the dictation and the bass drop")
	check(_boss.get_phase() == 3, "the cycle ran in phase three")
	check(_boss.finale_attacks(3) == [A.DICTATION, A.SOUND_WAVE, A.BASS_DROP], "the Encore is dictation, waves, bass drop")
	check(_boss.finale_attacks(1) == [A.THRUST, A.BRIEFCASE] and _boss.finale_attacks(2) == [A.SOUND_WAVE], "the other finales are the Lesson and the Listening")
	check(_boss.overheat_times[0] > _boss.overheat_times[2] and is_equal_approx(_boss.overheat_times[0], 2.2) and is_equal_approx(_boss.overheat_times[2], 1.8), "the overheat shrinks from 2.2 s to 1.8 s")


func case_kick_when_hugged() -> void:
	await _awake_boss(func(boss: BoomboxTeacherBoss) -> void:
		boss.auto_phrases = true
		boss.walk_speed = 70.0)
	for frame: int in 600:
		_player.global_position = Vector2(_boss.global_position.x - 40.0, 0.0)
		_player.velocity = Vector2.ZERO
		_player.heal(30)
		await physics_frame
		if _boss.get_attack_log().size() >= 2:
			break
	var log := _boss.get_attack_log()
	check(log.size() >= 2 and log[0] == BoomboxTeacherBoss.Attack.KICK, "hugging Luz gets a kick at the end of the rest")
	check(log.size() >= 2 and log[1] != BoomboxTeacherBoss.Attack.KICK, "the kick is followed by the phrase, not another kick")
	await _awake_boss(func(boss: BoomboxTeacherBoss) -> void:
		boss.auto_phrases = true
		boss.walk_speed = 70.0)
	await _wait(2.5)
	check(not _boss.get_attack_log().has(BoomboxTeacherBoss.Attack.KICK), "a distant Luz gets no kick")
	check(_boss.get_attack_log().size() >= 1, "he plays a phrase instead")


func case_stays_inside_the_arena() -> void:
	await _awake_boss(func(boss: BoomboxTeacherBoss) -> void: boss.walk_speed = 70.0)
	_boss.global_position.x = -400.0
	_player.global_position = Vector2(-350.0, 0.0)
	for frame: int in 300:
		_player.global_position = Vector2(-350.0, 0.0)
		_player.velocity = Vector2.ZERO
		await physics_frame
	check(_boss.global_position.x >= LIMITS.x + 12.0, "he walks left but stops at the wall (%.1f)" % _boss.global_position.x)
	check(_boss.global_position.x < -405.0, "he did walk toward the clamp (%.1f)" % _boss.global_position.x)
	_boss.global_position.x = 400.0
	for frame: int in 300:
		_player.global_position = Vector2(350.0, 0.0)
		_player.velocity = Vector2.ZERO
		await physics_frame
	check(_boss.global_position.x <= LIMITS.y - 12.0, "he stops at the right wall (%.1f)" % _boss.global_position.x)
	_boss.global_position.x = 900.0
	await _frames(3)
	check(_boss.global_position.x <= LIMITS.y - 12.0, "a boss placed outside is pulled back in")


## Plays `step` while a threshold is crossed: `cross_hits` land once `after_events`
## events fired (-1: ten frames into the telegraph), on a boss that first took `pre_hits`.
## Returns what the clock and the events did until the transition beat started.
func _crossing_run(step: Dictionary, pre_hits: int, cross_hits: int, after_events: int) -> Dictionary:
	await _awake_boss()
	await _frames(3)
	if pre_hits > 0:
		_hit(pre_hits)
		await _wait(0.8)
	var event_frames: Array[int] = []
	var intervals: Array[float] = []
	var result := {"old": _boss.get_beat_interval(), "crossed": false, "phase_at_cross": -1}
	_boss.plan_step(step)
	_boss.start_attack(int(step["attack"]))
	var seen := {}
	var frames := 0
	while frames < MAX_CYCLE_FRAMES:
		await physics_frame
		frames += 1
		_player.heal(30)
		var fresh := false
		for hazard: BoomboxHazard in _boss.get_hazards():
			if not seen.has(hazard.get_instance_id()):
				seen[hazard.get_instance_id()] = true
				fresh = true
		if fresh:
			event_frames.append(Engine.get_physics_frames())
		if _boss.get_state() == BossEnemy.State.ATTACK:
			intervals.append(_boss.get_beat_interval())
		elif _boss.get_state() == BossEnemy.State.TRANSITION:
			break
		var due := frames == 10 if after_events < 0 else event_frames.size() >= after_events
		if not result["crossed"] and due:
			result["crossed"] = true
			result["phase_at_cross"] = int(_boss.get_attack_phase())
			_hit(cross_hits)
	result["event_frames"] = event_frames
	result["intervals"] = intervals
	result["state_at_end"] = int(_boss.get_state())
	result["hazards_at_end"] = _boss.hazard_count()
	var mark := _beat_frames.size()
	await _wait(2.0)
	result["new_gaps"] = _interval_frames(mark + 1)
	result["new_interval"] = _boss.get_beat_interval()
	return result


func _tempo_kept(result: Dictionary) -> bool:
	var intervals: Array[float] = result["intervals"]
	for value: float in intervals:
		if not is_equal_approx(value, float(result["old"])):
			return false
	return not intervals.is_empty()


func _tempo_changed_after(result: Dictionary, bpm: float) -> bool:
	var gaps: Array[float] = result["new_gaps"]
	return is_equal_approx(float(result["new_interval"]), 60.0 / bpm) and gaps.size() >= 2 and _all_close(gaps, 60.0 / bpm)


func _event_gaps(result: Dictionary) -> Array[float]:
	var gaps: Array[float] = []
	var frames: Array[int] = result["event_frames"]
	for i: int in range(1, frames.size()):
		gaps.append(float(frames[i] - frames[i - 1]) * _dt())
	return gaps


func _events_on_beat(result: Dictionary) -> bool:
	var frames: Array[int] = result["event_frames"]
	for frame: int in frames:
		if _gap_to_beat(frame) > 2:
			return false
	return true


func _event_count(result: Dictionary) -> int:
	return (result["event_frames"] as Array[int]).size()


func case_tempo_holds_in_telegraph() -> void:
	var low := BoomboxTeacherBoss.WAVE_LOW
	var high := BoomboxTeacherBoss.WAVE_HIGH
	var waves := {"attack": BoomboxTeacherBoss.Attack.SOUND_WAVE, "pattern": [high, low, high]}
	var run := await _crossing_run(waves, 0, 13, -1)
	check(run["crossed"] and run["phase_at_cross"] == BossEnemy.AttackPhase.TELEGRAPH and _boss.get_phase() == 2, "phase two is reached in the middle of a wave wind-up")
	check(run["state_at_end"] == BossEnemy.State.TRANSITION and _event_count(run) == 0 and run["hazards_at_end"] == 0, "the wind-up is cut at the transition beat before any wave fires")
	check(_tempo_kept(run), "the wind-up keeps its tempo until the transition beat")
	check(_boss.get_wave_pips().is_empty(), "the cut wind-up leaves no pips behind")
	check(_tempo_changed_after(run, 110.0), "the 110 bpm tempo starts after the transition beat")
	var dictation := {"attack": BoomboxTeacherBoss.Attack.DICTATION}
	run = await _crossing_run(dictation, 13, 12, -1)
	check(run["crossed"] and run["phase_at_cross"] == BossEnemy.AttackPhase.TELEGRAPH and _boss.get_phase() == 3, "phase three is reached in the middle of a dictation wind-up")
	check(run["state_at_end"] == BossEnemy.State.TRANSITION and _event_count(run) == 0 and run["hazards_at_end"] == 0, "the dictation is cut at the transition beat before any letter falls")
	check(_tempo_kept(run), "the dictation wind-up keeps the phase two tempo")
	check(_boss.get_board() == null and _boss.get_columns().is_empty(), "the cut dictation takes its board and columns down")
	check(_tempo_changed_after(run, 132.0), "the 132 bpm tempo starts after the transition beat")


func case_tempo_holds_in_active() -> void:
	var low := BoomboxTeacherBoss.WAVE_LOW
	var high := BoomboxTeacherBoss.Height.HIGH
	var down := BoomboxTeacherBoss.Height.LOW
	var thrusts := {"attack": BoomboxTeacherBoss.Attack.THRUST, "heights": [high, down, high]}
	var waves := {"attack": BoomboxTeacherBoss.Attack.SOUND_WAVE, "pattern": [low, low, low, low]}
	var runs := [
		["sound waves into phase two", waves, 0, 13, 4, 2, 110.0],
		["thrust chain into phase two", thrusts, 0, 13, 3, 2, 110.0],
		["sound waves into phase three", waves, 13, 12, 4, 3, 132.0],
		["thrust chain into phase three", thrusts, 13, 12, 3, 3, 132.0],
	]
	for entry: Array in runs:
		var label: String = entry[0]
		var run := await _crossing_run(entry[1], entry[2], entry[3], 1)
		var gaps := _event_gaps(run)
		check(run["crossed"] and run["phase_at_cross"] == BossEnemy.AttackPhase.ACTIVE and _boss.get_phase() == entry[5], "%s: the threshold falls during the strike" % label)
		check(_event_count(run) == entry[4], "%s: every event still fires (%d of %d)" % [label, _event_count(run), entry[4]])
		check(gaps.size() == entry[4] - 1 and _all_close(gaps, float(run["old"])), "%s: the events stay one telegraphed beat apart (%s)" % [label, gaps])
		check(_events_on_beat(run), "%s: every event fires on a beat" % label)
		check(_tempo_kept(run), "%s: the beat interval never changes during the attack" % label)
		check(run["state_at_end"] == BossEnemy.State.TRANSITION and _tempo_changed_after(run, entry[6]), "%s: the new tempo starts at the transition beat, after the last event" % label)


## Plausible but degenerate designer values: the boss keeps attacking and never errors.
func case_degenerate_tunables() -> void:
	await _build_rig(func(boss: BoomboxTeacherBoss) -> void:
		boss.auto_phrases = true
		boss.walk_speed = 70.0
		boss.finale_every = 0
		boss.bpm_by_phase = PackedFloat32Array()
		boss.overheat_times = PackedFloat32Array()
		boss.wave_min_beats = 0
		boss.wave_max_beats = -3
		boss.note_count_min = 0
		boss.note_count_max = -1
		boss.column_spacing_min = 0.0
		boss.max_clear_beats = 0
		boss.note_gravity = 0.0
		boss.note_apex = -5.0
		boss.rest_beats = 0
		boss.opening_beats = -2
		boss.thrust_chain_max = 0
		boss.thrust_telegraph_beats = 0
		boss.briefcase_telegraph_beats = 0
		boss.wave_telegraph_beats = -1
		boss.note_telegraph_beats = 0
		boss.dictation_telegraph_beats = 0
		boss.bass_telegraph_beats = 0)
	await _frames(3)
	_boss.set_arena_limits(LIMITS.x, LIMITS.y)
	_boss.engage()
	_hit(25)
	var tally := {"phrases": 0, "finales": 0}
	_boss.phrase_started.connect(func(_attacks: Array, finale: bool) -> void:
		tally["phrases"] += 1
		tally["finales"] += 1 if finale else 0)
	var stunned := false
	for frame: int in MAX_CYCLE_FRAMES:
		_player.heal(30)
		await physics_frame
		stunned = stunned or _boss.is_stunned()
		if _boss.get_attack_log().size() >= 14:
			break
	check(_boss.get_attack_log().size() >= 14, "the boss keeps attacking with degenerate values (%d attacks)" % _boss.get_attack_log().size())
	check(tally["phrases"] >= 3 and tally["finales"] == 0, "finale_every 0 means no finales (%d of %d phrases)" % [tally["finales"], tally["phrases"]])
	check(not stunned and not _boss.is_overheat_pending(), "no finale, so no overheat")
	check(_boss.get_phase() == 3 and is_equal_approx(_boss.get_bpm(), 132.0), "an empty bpm table falls back to 90, 110, 132")
	check(is_equal_approx(_boss.overheat_duration(), 1.8), "an empty overheat table falls back to 2.2, 2.0, 1.8")
	var waves_ok := true
	var notes_ok := true
	for i: int in 30:
		waves_ok = waves_ok and (_boss._make_step(BoomboxTeacherBoss.Attack.SOUND_WAVE)["pattern"] as Array).size() >= 1
		notes_ok = notes_ok and int(_boss._make_step(BoomboxTeacherBoss.Attack.NOTE_BOUNCE)["count"]) >= 1
	check(waves_ok, "a wave pattern is never empty")
	check(notes_ok, "a note throw has at least one note")
	var columns := _boss._make_columns()
	check(columns.size() >= 4 and columns.size() <= 9, "a zero column spacing still gives four to nine columns (%d)" % columns.size())
	check(is_finite(_boss._note_hop_time()) and _boss._note_hop_time() > 0.0, "a zero note gravity keeps a finite hop")
	_boss.bpm_by_phase = PackedFloat32Array([1.0e9])
	var fast := _boss.get_bpm()
	_boss.bpm_by_phase = PackedFloat32Array([0.0])
	check(fast == BoomboxTeacherBoss.MAX_BPM and _boss.get_bpm() == BoomboxTeacherBoss.MIN_BPM, "the bpm is clamped to a playable range")


## A boss that never got arena limits (the base falls back to a box around him).
func case_no_arena_limits() -> void:
	var A := BoomboxTeacherBoss.Attack
	await _build_rig()
	await _frames(3)
	_boss.engage()
	var interval := _boss.get_beat_interval()
	_boss.plan_step({"attack": A.SOUND_WAVE, "pattern": [BoomboxTeacherBoss.WAVE_LOW, BoomboxTeacherBoss.WAVE_REST, BoomboxTeacherBoss.WAVE_LOW]})
	_boss.start_attack(A.SOUND_WAVE)
	var guard := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		_player.heal(30)
		await physics_frame
		guard += 1
	check(_boss.get_state() != BossEnemy.State.ATTACK, "sound waves end and he leaves the recovery with no arena limits (%d frames)" % guard)
	_boss.start_attack(A.DICTATION)
	await _frames(3)
	var columns := _boss.get_columns()
	var finite := true
	for x: float in columns:
		finite = finite and is_finite(x)
	check(columns.size() >= 4 and columns.size() <= 9 and finite, "the dictation finds four to nine finite columns (%d)" % columns.size())
	guard = 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		_player.heal(30)
		await physics_frame
		guard += 1
	check(_boss.get_state() != BossEnemy.State.ATTACK, "the dictation ends with no arena limits (%d frames)" % guard)
	_boss.arena_half_width = 1.0e12
	var cap := float(BoomboxTeacherBoss.WAVE_CLEAR_MAX_BEATS + 1) * interval
	check(_boss._recover_time(A.SOUND_WAVE) <= cap, "a huge arena never makes the wave recovery wait longer than the cap (%.1f s)" % _boss._recover_time(A.SOUND_WAVE))
	check(_boss._make_columns().size() == 9, "a huge arena still gives a finite column count")


## Distance from Luz's right side to the nearest hazard approaching from the right.
func _incoming_gap() -> float:
	var luz := BoomboxHazard.luz_rect(_player)
	var gap := INF
	for hazard: BoomboxHazard in _boss.get_hazards():
		if hazard.get_rect().position.x > luz.end.x - 1.0:
			gap = minf(gap, hazard.get_rect().position.x - luz.end.x)
	return gap


## True once the wind-up has `left` seconds to go.
func _wind_up_left(left: float) -> Callable:
	return func() -> bool: return _boss.is_telegraphing() and _boss.get_state_time_left() <= left


## Luz dashes (a real ground dash, from rest, facing right) once `trigger` is true.
## Records the hazard overlaps while she was dash-invulnerable and after; stops when
## the dash ends (`to_dash_end`) or when the attack and its hazards are gone.
func _dash_run(step: Dictionary, luz_x: float, trigger: Callable, to_dash_end: bool) -> Dictionary:
	await _awake_boss()
	await _frames(3)
	_player.global_position = Vector2(luz_x, 0.0)
	_player.velocity = Vector2.ZERO
	_player.face_direction(1)
	await _frames(3)
	var before := _player.get_health()
	var result := {"started": false, "overlap_dashing": false, "overlap_after": false, "lost": 0, "dash_frames": 0}
	_boss.plan_step(step)
	_boss.start_attack(int(step["attack"]))
	var guard := 0
	while (_boss.get_state() == BossEnemy.State.ATTACK or _boss.hazard_count() > 0) and guard < MAX_ATTACK_FRAMES:
		await physics_frame
		guard += 1
		if not result["started"] and trigger.call():
			_player.request_dash()
			result["started"] = _player.is_dash_invulnerable()
		var dashing := _player.is_dash_invulnerable()
		result["dash_frames"] += 1 if dashing else 0
		var luz := BoomboxHazard.luz_rect(_player)
		for hazard: BoomboxHazard in _boss.get_hazards():
			if hazard.get_rect().intersects(luz):
				if dashing:
					result["overlap_dashing"] = true
				elif result["started"]:
					result["overlap_after"] = true
		if to_dash_end and result["started"] and not dashing:
			break
	result["lost"] = before - _player.get_health()
	return result


## The dash i-frames cover the whole dash (about 0.51 s from rest: 0.08 s lean-back and
## 0.43 s slide). A hazard that touched her during the dash cannot hurt her afterwards
## while it still overlaps; one that reaches her after the dash ended still hurts.
func case_dash_through_hazards() -> void:
	var A := BoomboxTeacherBoss.Attack
	var near := func() -> bool: return _incoming_gap() < 80.0
	var wave := await _dash_run({"attack": A.SOUND_WAVE, "pattern": [BoomboxTeacherBoss.WAVE_LOW]}, 50.0, near, true)
	check(wave["started"] and wave["overlap_dashing"], "a dash runs into the low wave")
	check(wave["lost"] == 0, "a dash passes through a sound wave")
	var briefcase := await _dash_run({"attack": A.BRIEFCASE}, 100.0, near, true)
	check(briefcase["started"] and briefcase["overlap_dashing"], "a dash runs into the briefcase")
	check(briefcase["lost"] == 0, "a dash passes through the briefcase")
	var bass := await _dash_run({"attack": A.BASS_DROP}, -250.0, _wind_up_left(0.40), false)
	check(bass["started"] and bass["overlap_dashing"], "the dash starts in time and meets the shock")
	check(bass["overlap_after"], "the i-frames end while the same shock still covers her")
	check(bass["lost"] == 0, "a dash that met the shock passes it even after its i-frames end")
	check(float(bass["dash_frames"]) * _dt() >= 0.45, "the dash i-frames last about half a second (%.2f s)" % (float(bass["dash_frames"]) * _dt()))
	var spent := await _dash_run({"attack": A.BASS_DROP}, -250.0, _wind_up_left(0.85), false)
	check(spent["started"] and not spent["overlap_dashing"] and spent["lost"] == 1, "a dash that ended before the shock does not protect her")
	check(spent["overlap_after"], "the shock reached her after the dash ended")


func case_reset_clears_every_hazard() -> void:
	await _awake_boss()
	_boss.start_attack(BoomboxTeacherBoss.Attack.SOUND_WAVE)
	var guard := 0
	while _boss.hazard_count() == 0 and guard < 600:
		await physics_frame
		guard += 1
	check(_boss.hazard_count() > 0 and not _boss.get_wave_pips().is_empty(), "a wave is in flight and the pips are up")
	_hit(13)
	_boss.reset_to_spawn()
	check(_boss.hazard_count() == 0, "a reset removes every hazard at once")
	check(_boss.is_fresh() and _boss.get_phase() == 1, "a reset leaves the boss fresh in phase one")
	check(not _boss.is_beat_running() and _boss.get_wave_pips().is_empty(), "the clock stopped and the pips are gone")
	await _frames(3)
	check(_hazard_nodes() == 0, "no hazard node is left in the world")
	check(_boss.get_attack_log().is_empty() and not _boss.is_overheat_pending(), "the fight memory is wiped")
	_boss.engage()
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	check(_boss.get_board() != null and _boss.get_telegraph().is_floor_marker_visible(0), "the dictation board and its markers are up")
	_boss.reset_to_spawn()
	check(_boss.get_board() == null and not _boss.get_telegraph().is_floor_marker_visible(0), "a reset takes the board and the markers down")
	await _frames(3)
	var boards := 0
	for child: Node in _rig.get_children():
		boards += 1 if child.get_node_or_null("Text") != null else 0
	check(boards == 0, "no blackboard node is left behind")
	_boss.engage()
	_boss.start_attack(BoomboxTeacherBoss.Attack.BASS_DROP)
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	check(_boss.hazard_count() == 1, "the bass drop shock is up")
	_boss.stun(1.0)
	await _frames(3)
	check(_boss.hazard_count() == 0, "a stun cuts the strike and removes the bound shock")
	_boss.reset_to_spawn()
	check(_boss.is_fresh(), "and a reset after the stun is fresh again")


func case_arena_reset_after_luz_dies() -> void:
	_build_arena()
	await _frames(20)
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(15)
	await _frames(40)
	_boss.start_attack(BoomboxTeacherBoss.Attack.SOUND_WAVE)
	var guard := 0
	while _boss.hazard_count() == 0 and guard < 600:
		await physics_frame
		guard += 1
	check(_boss.hazard_count() > 0, "waves are in flight during the fight")
	_player.died.emit()
	check(_boss.hazard_count() == 0, "Luz dying clears the hazards at once")
	_player.global_position = LUZ_START
	_player.respawned.emit()
	await _frames(10)
	check(_arena.get_state() == BossArena.FightState.ARMED, "the arena is armed again")
	check(_boss.is_fresh(), "the boss is fresh again")
	check(_boss.hazard_count() == 0 and _hazard_nodes() == 0, "no hazard is left after the reset")


func case_defeat_through_the_arena() -> void:
	_build_arena()
	await _frames(20)
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(15)
	await _frames(40)
	var events: Array[String] = []
	_boss.defeated.connect(func() -> void: events.append("defeated"))
	_boss.corpse_settled.connect(func() -> void: events.append("settled"))
	_boss.start_attack(BoomboxTeacherBoss.Attack.NOTE_BOUNCE)
	var guard := 0
	while _boss.hazard_count() == 0 and guard < 600:
		await physics_frame
		guard += 1
	check(_boss.hazard_count() > 0, "a hazard is in flight when the killing blow lands")
	_boss.receive_hit(99, HIT_FROM, &"attack_1")
	check(events.has("defeated") and _boss.is_dead(), "the killing blow emits defeated")
	check(_boss.hazard_count() == 0, "no hazard remains on defeat")
	await _frames(90)
	check(events.has("settled"), "the corpse settles")
	check(not _boss.is_beat_running(), "the beat clock stops")
	check(_arena.get_state() == BossArena.FightState.DEFEATED, "the arena registers the defeat")
	check(not _arena.are_doors_closed(), "the arena opens")
	check(_arena.get_reward() == null, "no reward spawns")
	check(not root.get_node("GameCompletion").is_active(), "GameCompletion is not triggered")
	check(_progress().is_defeated(BOSS_ID), "BossProgress records the defeat under the enemy_id")
	check(_hazard_nodes() == 0, "no hazard node is left in the world")
	check(not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "the corpse left the checkpoint contract")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "a corpse takes no hits")
	check(_arena.get_boss_reset_count() == 0, "the arena never had to reset the boss")
	check(is_equal_approx(Engine.time_scale, _scale), "the clock was never slowed or left slowed (scale %.2f)" % Engine.time_scale)
	var fresh := (load(BOSS_SCENE) as PackedScene).instantiate() as BoomboxTeacherBoss
	check(is_equal_approx(fresh.final_freeze_time, 0.25) and is_equal_approx(fresh.final_slowmo_time, 0.5), "the final blow keeps the Artemis defaults")
	fresh.free()


# -- Art (a fixture manifest, never the real sheets) -----------------------------------

## A manifest with every contract clip as two frames of a tiny sheet.
func _write_art_fixture(with_effects := true) -> void:
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	var clips := {}
	var next := 0
	for clip_name: String in BoomboxTeacherBoss.CLIP_SPEEDS:
		clips[clip_name] = [next, next + 1]
		next += 2
	var rows := ceili(float(next) / float(ART_COLUMNS))
	var image := Image.create_empty(ART_COLUMNS * ART_CELL, rows * ART_CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png(ART_DIR + "/fixture_sheet.png")
	var manifest := {
		"cell": 448, "feet_row": 416, "sprite_scale": 0.2896,
		"sheets": {"fixture_sheet.png": {
			"grid": {"columns": ART_COLUMNS, "rows": rows, "cell_width": ART_CELL, "cell_height": ART_CELL},
			"clips": clips, "events": {},
		}},
	}
	if with_effects:
		manifest["props"] = _write_effect_sheet("fixture_props.png", FIXTURE_PROPS)
		manifest["fx"] = _write_effect_sheet("fixture_fx.png", FIXTURE_FX)
		manifest["thrust_fx"] = _write_effect_sheet("fixture_thrust_fx.png", FIXTURE_THRUST)
		var board := Image.create_empty(int(FIXTURE_BOARD.x), int(FIXTURE_BOARD.y), false, Image.FORMAT_RGBA8)
		board.fill(Color.WHITE)
		board.save_png(ART_DIR + "/fixture_board.png")
		manifest["blackboard"] = {"texture": "fixture_board.png", "size": [int(FIXTURE_BOARD.x), int(FIXTURE_BOARD.y)]}
	var file := FileAccess.open(ART_MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))


## A props or fx entry: one white cell per clip, and the declared content box of each clip.
## Every clip but the 4-frame `steam`, `briefcase_spin` and `thrust_streak` has one frame.
func _write_effect_sheet(file_name: String, content: Dictionary) -> Dictionary:
	var clips := {}
	var next := 0
	for clip_name: String in content:
		var count := 4 if clip_name in ["steam", "briefcase_spin", "thrust_streak"] else 1
		clips[clip_name] = range(next, next + count)
		next += count
	var rows := ceili(float(next) / float(ART_COLUMNS))
	var image := Image.create_empty(ART_COLUMNS * ART_CELL, rows * ART_CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png(ART_DIR.path_join(file_name))
	return {
		"sheet": file_name, "sprite_scale": 0.2896, "clips": clips, "content": content,
		"grid": {"columns": ART_COLUMNS, "rows": rows, "cell_width": ART_CELL, "cell_height": ART_CELL},
	}


func _remove_art_fixture() -> void:
	if not DirAccess.dir_exists_absolute(ART_DIR):
		return
	for file_name: String in DirAccess.get_files_at(ART_DIR):
		DirAccess.remove_absolute(ART_DIR.path_join(file_name))
	DirAccess.remove_absolute(ART_DIR)


func _with_manifest(path: String) -> Callable:
	return func(boss: BoomboxTeacherBoss) -> void:
		boss.animation_manifest = path


## The speed the sprite plays `clip` at must make it last `duration` seconds.
func _lasts(clip: StringName, duration: float, tolerance := 0.05) -> bool:
	var sprite := _boss.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames
	var wanted := (float(frames.get_frame_count(clip)) / frames.get_animation_speed(clip)) / duration
	return sprite.animation == clip and absf(sprite.get_playing_speed() - wanted) <= tolerance * wanted


func _sprite() -> AnimatedSprite2D:
	return _boss.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D


## Frames from now until the boss' clip is `clip` (-1 on timeout).
func _frames_until_clip(clip: StringName, limit := 900) -> int:
	var frames := 0
	while _boss.get_clip() != clip and frames < limit:
		await physics_frame
		frames += 1
	return frames if frames < limit else -1


func case_art_absent_keeps_the_placeholders() -> void:
	await _awake_boss(_with_manifest(NO_ART_MANIFEST))
	check(not _boss.has_art(), "a manifest that does not exist means no art")
	check(not _sprite().visible, "the sprite stays hidden without art")
	check(_sprite().material == null, "the sprite has no glow shader without art")
	for path: String in PLACEHOLDER_NODES:
		check((_boss.get_node(path) as CanvasItem).visible, "%s is still drawn without art" % path)
	_boss.start_attack(BoomboxTeacherBoss.Attack.THRUST)
	await _frames(3)
	check(_boss.get_clip() == &"", "no clip is requested without art")
	var shape := _boss.get_node("CollisionShape2D") as CollisionShape2D
	check((shape.shape as RectangleShape2D).size == Vector2(28.0, 84.0), "the body collision covers the drawn height")
	check(shape.position == Vector2(0.0, -42.0), "the body collision is centred on the torso")
	_boss.receive_hit(1, HIT_FROM, &"attack_1")
	check(_boss.is_flash_visible() and _boss._flash.visible, "a hit flashes the white polygon as before")
	await _wait(_boss.flash_time + 0.1)
	_boss.start_attack(BoomboxTeacherBoss.Attack.KICK)
	await _frames(3)
	check(_boss.get_telegraph()._glow.visible, "the telegraph glows on the polygon as before")


func case_art_shows_the_sprite() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(3)
	var sprite := _sprite()
	check(_boss.has_art(), "a manifest with the default clip means art")
	check(sprite.visible, "the sprite shows")
	for path: String in PLACEHOLDER_NODES:
		check(not (_boss.get_node(path) as CanvasItem).visible, "%s is hidden with art" % path)
	check(sprite.offset == Vector2(0.0, -192.0), "the offset puts the feet row on the origin")
	check(is_equal_approx(absf(sprite.scale.x), 0.2896), "the sprite uses the manifest scale")
	check(sprite.get_index() == 0, "the sprite is the first child of Visual, under the flash and the glow")
	check(_boss.get_clip() == &"idle", "he idles")
	check(sprite.material is ShaderMaterial, "the glow and the flash are a shader on the sprite")
	check(not _boss.get_telegraph()._glow.visible and not _boss._flash.visible, "no polygon overlay is drawn over the sprite")
	_remove_art_fixture()


## With art the telegraph glow and the hit flash live on the sprite's material and keep
## their timings: the glow follows the wind-up, the flash lasts `flash_time`.
func case_art_glow_and_flash_on_the_sprite() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(3)
	var material := _sprite().material as ShaderMaterial
	var telegraph := _boss.get_telegraph()
	check(not telegraph.is_glowing() and is_zero_approx(float(material.get_shader_parameter(&"glow_amount"))), "no glow at rest")
	_boss.start_attack(BoomboxTeacherBoss.Attack.THRUST)
	await _frames(4)
	var early := float(material.get_shader_parameter(&"glow_amount"))
	check(telegraph.is_glowing() and early > 0.0, "the wind-up lights the sprite")
	check((material.get_shader_parameter(&"glow_color") as Color).is_equal_approx(BossTelegraph.MELEE_COLOR), "a melee wind-up glows red")
	check(not telegraph._glow.visible, "the polygon glow stays hidden with art")
	await _frames(6)
	check(float(material.get_shader_parameter(&"glow_amount")) > early, "the glow grows through the wind-up")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	check(not telegraph.is_glowing() and is_zero_approx(float(material.get_shader_parameter(&"glow_amount"))), "the glow clears when the strike lands")
	await _wait(2.0)
	check(not _boss.is_flash_visible(), "no flash before a hit")
	_boss.receive_hit(1, HIT_FROM, &"attack_1")
	check(_boss.is_flash_visible() and is_equal_approx(float(material.get_shader_parameter(&"flash_amount")), 1.0), "a hit flashes the sprite white")
	check(not _boss._flash.visible, "the white polygon stays hidden with art")
	await _wait(_boss.flash_time + 0.1)
	check(not _boss.is_flash_visible() and is_zero_approx(float(material.get_shader_parameter(&"flash_amount"))), "the flash ends after flash_time")
	_remove_art_fixture()


## Thrust chain and briefcase in real time: the clip of each part and the strike on a beat.
func case_art_thrust_and_briefcase_clips() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var high := BoomboxTeacherBoss.Height.HIGH
	var low := BoomboxTeacherBoss.Height.LOW
	_boss.plan_step({"attack": BoomboxTeacherBoss.Attack.THRUST, "heights": [high, low]})
	_boss.start_attack(BoomboxTeacherBoss.Attack.THRUST)
	await _frames(2)
	check(_boss.get_clip() == &"thrust_high_windup", "the first thrust winds up at its height")
	check(_lasts(&"thrust_high_windup", _boss._telegraph_total), "the wind-up lasts as long as the telegraph")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await physics_frame
	var strike_frame := Engine.get_physics_frames()
	check(_boss.get_clip() == &"thrust_high_strike", "the strike frame shows when ACTIVE starts")
	check(_gap_to_beat(strike_frame) <= 2, "the strike frame is on a beat (%d frames away)" % _gap_to_beat(strike_frame))
	await _wait(_boss.thrust_strike_time + 0.05)
	check(_boss.get_clip() == &"thrust_low_windup", "between strikes he winds up the next height")
	await _frames_until_clip(&"thrust_low_strike")
	check(_boss.get_clip() == &"thrust_low_strike", "the second strike shows its own height")
	check(_gap_to_beat(Engine.get_physics_frames()) <= 2, "the second strike frame is on a beat")
	await _wait(_boss.thrust_strike_time + 0.05)
	check(_boss.get_clip() == &"thrust_low_recover", "after the last strike he recovers")
	await _frames_until_phase(BossEnemy.AttackPhase.RECOVER)
	await physics_frame
	check(_boss.get_clip() == &"thrust_low_recover", "the recovery keeps the pose")
	await _wait(1.5)
	check(_boss.get_state() != BossEnemy.State.ATTACK and _boss.get_clip() == &"idle", "he is idle again after the attack")
	_boss.start_attack(BoomboxTeacherBoss.Attack.BRIEFCASE)
	await _frames(2)
	check(_boss.get_clip() == &"throw_windup", "the throw winds up")
	check(_lasts(&"throw_windup", _boss._telegraph_total), "the throw wind-up lasts as long as the telegraph")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await physics_frame
	check(_boss.get_clip() == &"throw_release", "the release frame shows when ACTIVE starts")
	check(_gap_to_beat(Engine.get_physics_frames()) <= 2, "the release frame is on a beat")
	await _wait(BoomboxTeacherBoss.THROW_RELEASE_TIME + 0.1)
	check(_boss.get_clip() == &"throw_wait", "he waits empty-handed while the briefcase flies")
	while _boss.get_state_time_left() > BoomboxTeacherBoss.THROW_CATCH_TIME - 0.05 and _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE:
		await physics_frame
	await physics_frame
	check(_boss.get_clip() == &"throw_catch", "he catches it when it comes home")
	await _frames_until_phase(BossEnemy.AttackPhase.RECOVER)
	await physics_frame
	check(_boss.get_clip() == &"idle", "he is idle in the recovery of the throw")
	check(_boss.get_attack_phase() == BossEnemy.AttackPhase.RECOVER, "that was the recovery")
	_remove_art_fixture()


## The clip in the TELEGRAPH, ACTIVE and RECOVER phases of `step`.
func _clips_by_phase(step: Dictionary) -> Array[StringName]:
	var clips: Array[StringName] = []
	_boss.plan_step(step)
	_boss.start_attack(int(step["attack"]))
	await _frames(2)
	clips.append(_boss.get_clip())
	for phase_id: BossEnemy.AttackPhase in [BossEnemy.AttackPhase.ACTIVE, BossEnemy.AttackPhase.RECOVER]:
		await _frames_until_phase(phase_id)
		await physics_frame
		clips.append(_boss.get_clip())
	var guard := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and guard < MAX_ATTACK_FRAMES:
		await physics_frame
		guard += 1
	return clips


func case_art_other_attack_clips() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var attack := BoomboxTeacherBoss.Attack
	var kick: Array[StringName] = [&"kick_windup", &"kick_strike", &"kick_recover"]
	var waves: Array[StringName] = [&"conduct", &"conduct", &"idle"]
	var notes: Array[StringName] = [&"notes", &"notes", &"idle"]
	var lecture: Array[StringName] = [&"lecture", &"lecture", &"idle"]
	var bass: Array[StringName] = [&"bass_lift", &"bass_slam", &"bass_slam"]
	check(await _clips_by_phase({"attack": attack.KICK}) == kick, "the kick plays windup, strike, recover")
	check(await _clips_by_phase(_wave(BoomboxTeacherBoss.WAVE_LOW)) == waves, "the sound waves are conducted until the recovery")
	check(await _clips_by_phase({"attack": attack.NOTE_BOUNCE, "count": 2}) == notes, "the notes are thrown from the notes clip")
	check(await _clips_by_phase({"attack": attack.DICTATION}) == lecture, "the dictation is the lecture clip")
	check(await _clips_by_phase({"attack": attack.BASS_DROP}) == bass, "the bass drop lifts, slams and holds the slam")
	_remove_art_fixture()


func case_art_state_clips() -> void:
	_write_art_fixture()
	# Walking, overheat and the phase change.
	await _awake_boss(func(boss: BoomboxTeacherBoss) -> void:
		boss.animation_manifest = ART_MANIFEST
		boss.walk_speed = 70.0
		boss.auto_phrases = false)
	_player.global_position = Vector2(-100.0, 0.0)
	await _frames_until_clip(&"walk", 200)
	check(_boss.get_clip() == &"walk", "he walks to his mid range with the walk clip")
	_boss.stun(1.0)
	await _frames(2)
	check(_boss.get_clip() == &"overheat", "the overheat stun plays the overheat clip")
	check(_sprite().sprite_frames.get_animation_loop(&"overheat"), "the overheat loops while the stun lasts")
	_boss.walk_speed = 0.0
	await _wait(1.2)
	check(_boss.get_clip() == &"idle", "he idles once the stun ends")
	_hit(13)
	await _frames(3)
	check(_boss.get_state() == BossEnemy.State.TRANSITION and _boss.get_clip() == &"phase_change", "the phase change plays its clip")
	check(_lasts(&"phase_change", _boss.phase_transition_time), "the phase change lasts as long as the transition")
	# Intro: the arena reveal while he waits in IDLE.
	await _build_rig(_with_manifest(ART_MANIFEST))
	await _frames(3)
	_boss.play_intro(1.0)
	await _frames(2)
	check(_boss.get_clip() == &"intro", "the arena reveal plays the intro clip")
	check(_lasts(&"intro", 1.0, 0.1), "the intro lasts as long as the reveal (a few frames in)")
	# Defeat and the corpse.
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(3)
	_boss.receive_hit(99, HIT_FROM, &"attack_1")
	await _frames(2)
	check(_boss.get_clip() == &"defeat", "the killing blow plays the defeat clip")
	check(_lasts(&"defeat", _boss.defeat_time), "the defeat lasts as long as the collapse")
	await _wait(1.0)
	var visual := _boss.get_node("Visual") as Node2D
	check(absf(visual.rotation) > 0.1, "the placeholder pose still tilts Visual")
	check(absf(_sprite().global_transform.y.x) < 0.01, "the sprite undoes the tilt: the clip carries the slump")
	check(absf(_sprite().global_transform.y.length() - 0.2896) < 0.005, "the sprite undoes the squash")
	check(_sprite().frame == _sprite().sprite_frames.get_frame_count(&"defeat") - 1, "the corpse shows the last defeat frame")
	# A corpse restored by a checkpoint shows the last frame at once.
	_build_world()
	var corpse := (load(BOSS_SCENE) as PackedScene).instantiate() as BoomboxTeacherBoss
	corpse.animation_manifest = ART_MANIFEST
	corpse.make_corpse_at(BOSS_AT, 1)
	_rig.add_child(corpse)
	await _frames(3)
	var corpse_sprite := corpse.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	check(corpse_sprite.frame == corpse_sprite.sprite_frames.get_frame_count(&"defeat") - 1 and not corpse_sprite.is_playing(), "a restored corpse lies on the last frame")
	_remove_art_fixture()


# -- Hazard and effect art ----------------------------------------------------------------

func _art_of(hazard: BoomboxHazard, index := 0) -> AnimatedSprite2D:
	return hazard.get_art()[index] as AnimatedSprite2D


func _content(sheet: Dictionary, clip: String) -> Vector2:
	var box: Array = sheet[clip]
	return Vector2(float(box[0]), float(box[1]))


## Starts `step` and returns once its ACTIVE phase is two frames old.
func _into_active(step: Dictionary) -> void:
	_boss.plan_step(step)
	_boss.start_attack(int(step["attack"]))
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)


## Sprites in the world of the boss that play `clip` (puffs and sparks).
## Lets the running attack end and its hazards go.
func _finish_attack() -> void:
	var guard := 0
	while (_boss.get_state() == BossEnemy.State.ATTACK or _boss.hazard_count() > 0) and guard < MAX_CYCLE_FRAMES:
		await physics_frame
		guard += 1


func _puffs(clip: StringName) -> Array[AnimatedSprite2D]:
	var found: Array[AnimatedSprite2D] = []
	for child: Node in _rig.get_children():
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).animation == clip and not child.is_queued_for_deletion():
			found.append(child as AnimatedSprite2D)
	return found


func case_art_scale_relation() -> void:
	var box := Vector2(30.0, 22.0)
	var content := Vector2(100.0, 200.0)
	check(BoomboxHazard.art_scale(content, box, BoomboxHazard.ArtFit.STRETCH).is_equal_approx(Vector2(0.3, 0.11)), "STRETCH fills the box on both axes")
	check(BoomboxHazard.art_scale(content, box, BoomboxHazard.ArtFit.WIDTH).is_equal_approx(Vector2(0.3, 0.3)), "WIDTH matches the box width and keeps the proportions")
	check(BoomboxHazard.art_scale(content, box, BoomboxHazard.ArtFit.CONTAIN).is_equal_approx(Vector2(0.11, 0.11)), "CONTAIN keeps the art inside the box")
	check(BoomboxHazard.art_scale(Vector2.ZERO, box, BoomboxHazard.ArtFit.CONTAIN) == Vector2.ONE, "an unknown content box leaves the art unscaled")
	var hazard := BoomboxHazard.new()
	check(not hazard.has_art() and hazard.get_art().is_empty(), "a hazard has no art until it is given some")
	hazard.attach_art(AnimatedSprite2D.new())
	check(hazard.has_art(), "attached art is kept")
	hazard.free()


## Every hazard shows its drawn sprite scaled to the box that hurts; boxes, speeds and timings are the placeholder's.
func case_art_hazards_wear_the_sprites() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var attack := BoomboxTeacherBoss.Attack
	await _into_active({"attack": attack.BRIEFCASE})
	var briefcase := _boss.get_hazards()[0]
	var expected := BoomboxHazard.art_scale(_content(FIXTURE_PROPS, "briefcase_spin"), _boss.briefcase_size, BoomboxHazard.ArtFit.WIDTH)
	check(briefcase.has_art() and _art_of(briefcase).animation == &"briefcase_spin", "the briefcase tumbles with the spin clip")
	check(_art_of(briefcase).scale.is_equal_approx(expected) and is_equal_approx(_art_of(briefcase).scale.x * 100.0, _boss.briefcase_size.x), "its front view is as wide as the box that hurts")
	check(briefcase.get_rect().size == _boss.briefcase_size, "the briefcase box is unchanged")
	check(_art_of(briefcase).is_playing() and _art_of(briefcase).sprite_frames.get_animation_loop(&"briefcase_spin"), "the spin loops")
	await _finish_attack()
	# Sound waves: stretched to their box, mirrored toward the side they travel.
	await _into_active(_wave(BoomboxTeacherBoss.WAVE_LOW))
	var waves := _boss.get_hazards()
	var left := waves[0] if waves[0].velocity.x < 0.0 else waves[1]
	var right := waves[1] if waves[0].velocity.x < 0.0 else waves[0]
	var wave_box := Vector2(_boss.wave_width, _boss.wave_low_height)
	check(waves.size() == 2 and _art_of(left).animation == &"wave_low", "a low wave is the amber arcs")
	check(_art_of(left).scale.x < 0.0 and _art_of(right).scale.x > 0.0, "the arcs open toward the side they travel")
	check(is_equal_approx(absf(_art_of(right).scale.x) * 100.0, wave_box.x) and is_equal_approx(_art_of(right).scale.y * 130.0, wave_box.y), "the arcs fill the wave box")
	check(left.get_rect().size == wave_box, "the wave box is unchanged")
	await _finish_attack()
	await _into_active(_wave(BoomboxTeacherBoss.WAVE_HIGH))
	check(_art_of(_boss.get_hazards()[0]).animation == &"wave_high", "a high wave is the cyan arcs")
	await _finish_attack()
	# Notes: the single note first, the pair on the second one.
	_boss.plan_step({"attack": attack.NOTE_BOUNCE, "count": 2})
	_boss.start_attack(attack.NOTE_BOUNCE)
	var seen: Array[BoomboxHazard] = []
	var guard := 0
	while seen.size() < 2 and guard < MAX_ATTACK_FRAMES:
		await physics_frame
		for hazard: BoomboxHazard in _boss.get_hazards():
			if not seen.has(hazard):
				seen.append(hazard)
		guard += 1
	check(seen.size() == 2 and _art_of(seen[0]).animation == &"note" and _art_of(seen[1]).animation == &"note_pair", "the notes alternate the single note and the pair")
	var note_box := Vector2.ONE * _boss.note_radius * 2.0
	check(_art_of(seen[0]).scale.is_equal_approx(BoomboxHazard.art_scale(_content(FIXTURE_PROPS, "note"), note_box, BoomboxHazard.ArtFit.CONTAIN)), "a note fits inside its disc")
	check(seen[0].get_rect().size == note_box, "the note box is unchanged")
	await _finish_attack()
	# Bass drop: crests along the floor band, a spark where the slam lands.
	await _into_active({"attack": attack.BASS_DROP})
	var shock := _boss.get_hazards()[0]
	var band := shock.get_rect().size
	var crest_scale := band.y / 70.0
	var crests := shock.get_art()
	var on_floor := true
	for crest: Node2D in crests:
		on_floor = on_floor and is_equal_approx(crest.position.y + 70.0 * crest_scale * 0.5, band.y * 0.5)
	check(crests.size() >= 2 and _art_of(shock).animation == &"bass_shock", "the shock is a row of ground crests")
	check(on_floor and is_equal_approx(_art_of(shock).scale.y * 70.0, band.y), "the crests stand on the floor as tall as the band")
	var first_x := crests[0].position.x - 240.0 * crest_scale * 0.5
	var last_x := crests[crests.size() - 1].position.x + 240.0 * crest_scale * 0.5
	check(first_x <= -band.x * 0.5 + 1.0 and last_x >= band.x * 0.5 - 1.0, "the crests span the whole band that hurts")
	var sparks := _puffs(&"spark")
	check(sparks.size() == 1 and sparks[0].scale.x * 80.0 <= BoomboxTeacherBoss.SPARK_WIDTH + 0.01, "a spark punctuates the slam")
	await _wait(1.0)
	check(_puffs(&"spark").is_empty(), "the spark frees itself")
	_remove_art_fixture()


## The thrust streak wears the pointer box: uniform scale across its length, blunt end at his
## front edge (mirrored with his facing), four frames played once over the strike. Without the
## sheet the red arrow stays; the box and the lifetime are the same either way.
func case_art_thrust_streak() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var box := _content(FIXTURE_THRUST, "thrust_streak")
	var facings: Array[int] = []
	for side: float in [-1.0, 1.0]:
		_player.global_position = Vector2(_boss.global_position.x + side * 120.0, 0.0)
		await _frames(4)
		await _into_active(_thrust(BoomboxTeacherBoss.Height.HIGH))
		var hazard := _boss.get_hazards()[0]
		var streak := _art_of(hazard)
		facings.append(_boss._facing)
		check(hazard.has_art() and streak.animation == &"thrust_streak", "the thrust is the streak clip")
		check(is_equal_approx(absf(streak.scale.x), absf(streak.scale.y)) and is_equal_approx(absf(streak.scale.x) * box.x, _boss.thrust_reach), "uniform scale: as long as the reach, not squashed")
		check(signf(streak.scale.x) == float(_boss._facing), "it points the way he faces")
		check(is_equal_approx(hazard.get_rect().size.x, _boss.thrust_reach) and is_equal_approx(hazard.lifetime, _boss.thrust_strike_time), "the box and the lifetime are unchanged")
		var frames := streak.sprite_frames
		check(not frames.get_animation_loop(&"thrust_streak") and is_equal_approx(float(frames.get_frame_count(&"thrust_streak")) / (frames.get_animation_speed(&"thrust_streak") * streak.speed_scale), _boss.thrust_strike_time), "four frames play once over the strike")
		if side < 0.0:
			check(streak.frame <= 1, "it starts on the first frame")
			await _wait(_boss.thrust_strike_time * 0.7)
			check(is_instance_valid(streak) and streak.frame >= 2, "and is on the late frames near the end")
		await _finish_attack()
	check(facings[0] != facings[1], "both facings were exercised")
	_remove_art_fixture()
	_write_art_fixture()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_MANIFEST))
	manifest.erase("thrust_fx")
	FileAccess.open(ART_MANIFEST, FileAccess.WRITE).store_string(JSON.stringify(manifest))
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	await _into_active(_thrust(BoomboxTeacherBoss.Height.LOW))
	var plain := _boss.get_hazards()[0]
	check(not plain.has_art() and plain.look == BoomboxHazard.Look.POINTER, "without the sheet the red arrow stays")
	check(is_equal_approx(plain.get_rect().size.x, _boss.thrust_reach) and is_equal_approx(plain.lifetime, _boss.thrust_strike_time), "its box and lifetime are the same")
	await _finish_attack()
	check(_boss._effects.has_clip(BoomboxEffectArt.FX, &"wave_low"), "the other effects are still drawn")
	_remove_art_fixture()


## A clip the manifest gives no content box scales from one cell, never from "1 px" or "scale 1",
## so a missing box can no longer blow the art up past the hazard it dresses.
func case_art_effects_without_a_content_box() -> void:
	_write_art_fixture()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART_MANIFEST))
	for key: String in ["props", "fx"]:
		(manifest[key] as Dictionary).erase("content")
	FileAccess.open(ART_MANIFEST, FileAccess.WRITE).store_string(JSON.stringify(manifest))
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var effects := BoomboxEffectArt.new(BossAnimationCatalog.new(ART_MANIFEST))
	var cell := Vector2.ONE * float(ART_CELL)
	check(effects.content(BoomboxEffectArt.PROPS, &"note") == Vector2.ZERO, "the manifest names no content box")
	check(effects.art_size(BoomboxEffectArt.PROPS, &"note") == cell, "the size falls back to one cell")
	check(effects.art_size(BoomboxEffectArt.PROPS, &"missing") == Vector2.ZERO, "a clip that does not exist has no size")
	var node := effects.fit_sprite(BoomboxEffectArt.PROPS, &"note", Vector2(20.0, 20.0), BoomboxHazard.ArtFit.CONTAIN)
	check(node != null and node.scale.is_equal_approx(Vector2.ONE * 5.0), "a sprite fits its box from the cell size")
	node.free()
	var puff := effects.puff(_rig, BoomboxEffectArt.FX, &"chalk_dust", Vector2.ZERO, 30.0)
	check(puff != null and absf(puff.scale.x * float(ART_CELL) - 30.0 * BoomboxEffectArt.PUFF_START_SCALE) < 0.01, "a puff starts at its width, not 30 times it")
	var steam := _boss._steam_sprite
	check(steam != null and absf(steam.scale.x * float(ART_CELL) - BoomboxTeacherBoss.STEAM_ART_WIDTH) < 0.01, "the steam is its width without a box too")
	check(effects.floor_sprites(BoomboxEffectArt.FX, &"bass_shock", Vector2(240.0, 34.0)).is_empty(), "a floor strip with no box keeps its placeholder")
	_remove_art_fixture()


func case_art_steam_over_the_boombox() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	var steam := _boss._steam_sprite
	check(steam != null and not steam.visible, "the steam waits, hidden, until he overheats")
	_boss.stun(1.0)
	await _frames(3)
	check(steam.visible and steam.animation == &"steam" and steam.sprite_frames.get_animation_loop(&"steam"), "the steam loops while he is overheated")
	check(steam.position.y < -92.0 and absf(steam.scale.x * 150.0 - BoomboxTeacherBoss.STEAM_ART_WIDTH) < 0.01, "the steam rises over the boombox at its size")
	check(steam.get_parent() == _boss and steam.sprite_frames.get_frame_count(&"steam") == 4, "the loop has four frames and does not flip with him")
	await _wait(1.2)
	check(not steam.visible, "the steam stops with the stun")
	_remove_art_fixture()
	_write_art_fixture(false)
	await _awake_boss(_with_manifest(ART_MANIFEST))
	check(_boss._steam_sprite == null, "no fx sheet keeps the drawn steam")


## The blackboard, the dictated text and the falling letters.
func case_art_dictation_on_chalk() -> void:
	_write_art_fixture()
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	_boss.plan_step({"attack": BoomboxTeacherBoss.Attack.DICTATION})
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	var board := _boss.get_board()
	var backdrop := board.get_node_or_null("Art") as Sprite2D
	check(backdrop != null and backdrop.texture.get_size() == FIXTURE_BOARD, "the blackboard art is the board")
	check(is_equal_approx(backdrop.scale.x * FIXTURE_BOARD.x, _boss.board_size.x), "it is as wide as the board size")
	check(board.get_children().filter(func(node: Node) -> bool: return node is Polygon2D).is_empty(), "the flat green rectangle is gone")
	var label := board.get_node("Text") as Label
	check(label.get_theme_color(&"font_color") == BoomboxHazard.CHALK_COLOR and label.get_theme_color(&"font_outline_color") == BoomboxHazard.CHALK_OUTLINE_COLOR, "the text is chalk: off-white with a dark outline")
	check(label.get_theme_constant(&"outline_size") > 0, "the chalk text is outlined")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	var letter := _boss.get_hazards()[0]
	check(letter.look == BoomboxHazard.Look.CHALK and letter.glyph == "i", "a letter is drawn as chalk")
	check(not letter.has_art() and letter.get_rect().size == Vector2.ONE * _boss.letter_size, "no box is drawn and the letter box is unchanged")
	var landed: Array[Vector2] = []
	letter.touched_floor.connect(func(at: Vector2) -> void: landed.append(at))
	var guard := 0
	while _puffs(&"chalk_dust").is_empty() and guard < 240:
		await physics_frame
		guard += 1
	var puffs := _puffs(&"chalk_dust")
	check(landed.size() == 1 and puffs.size() >= 1, "a puff of chalk dust rises where the letter lands")
	check(landed.size() == 1 and absf(landed[0].y - _boss.global_position.y) < 1.0, "the letter lands on the floor")
	check(puffs.size() >= 1 and puffs[0].scale.x * 100.0 < BoomboxTeacherBoss.DUST_WIDTH, "the puff grows from a smaller size")
	await _wait(BoomboxEffectArt.PUFF_TIME + 0.2)
	check(_puffs(&"chalk_dust").size() < 2, "the dust fades and frees itself")
	_remove_art_fixture()


func case_art_absent_hazards_stay_placeholders() -> void:
	await _awake_boss(_with_manifest(NO_ART_MANIFEST))
	await _frames(2)
	await _into_active({"attack": BoomboxTeacherBoss.Attack.BRIEFCASE})
	var briefcase := _boss.get_hazards()[0]
	check(not briefcase.has_art() and briefcase.get_art().is_empty(), "the briefcase is the placeholder box without art")
	await _finish_attack()
	_boss.plan_step({"attack": BoomboxTeacherBoss.Attack.DICTATION})
	_boss.start_attack(BoomboxTeacherBoss.Attack.DICTATION)
	await _frames(3)
	var board := _boss.get_board()
	check(board.get_node_or_null("Art") == null and not board.get_children().filter(func(node: Node) -> bool: return node is Polygon2D).is_empty(), "the blackboard is the flat green rectangle")
	var label := board.get_node("Text") as Label
	check(label.get_theme_color(&"font_color") == Color.WHITE and not label.has_theme_color_override(&"font_outline_color"), "the text is plain white")
	await _frames_until_phase(BossEnemy.AttackPhase.ACTIVE)
	await _frames(2)
	check(_boss.get_hazards()[0].look == BoomboxHazard.Look.GLYPH, "the letters keep their white box")
	_boss.stun(1.0)
	await _frames(2)
	check(_boss._steam_sprite == null and _boss._effects == null, "there are no effect sprites")
	_remove_art_fixture()
	_write_art_fixture(false)
	await _awake_boss(_with_manifest(ART_MANIFEST))
	await _frames(2)
	await _into_active({"attack": BoomboxTeacherBoss.Attack.BRIEFCASE})
	check(not _boss.get_hazards()[0].has_art(), "character art without a props sheet keeps the placeholder box")
	check(_boss.has_art(), "and the boss still shows its sprite")

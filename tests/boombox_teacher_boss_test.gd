extends SceneTree
## El Profesor (Boombox Teacher boss): the beat clock and its tempo per phase, strikes
## that start on a beat, the avoidance of every attack (crouch or jump the thrusts, jump
## the low waves, stay grounded for the high ones, be airborne for the bass drop), the
## wave pattern rules, the dictation columns, phrases and finales, the overheat punish
## window, the arena limits, the reset, and the one-drag prefab with its defeat.
## Run: godot --headless --path . --script res://tests/boombox_teacher_boss_test.gd
## Exits 0 when every check passes, 1 otherwise.

const BOSS_SCENE := "res://scenes/enemies/bosses/boombox_teacher.tscn"
const PREFAB_SCENE := "res://scenes/enemies/bosses/boombox_teacher_boss_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 420.0
## Game seconds run per real second (physics frames then last that much longer).
## Timing cases run at 1; the long fights and avoidance runs at the faster default.
const FAST_SCALE := 3.0
const TIMING_CASES := ["case_beat_clock_and_tempo", "case_strikes_start_on_a_beat", "case_minimum_telegraph_at_high_tempo"]
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
	"case_reset_clears_every_hazard": 12,
	"case_arena_reset_after_luz_dies": 5,
	"case_defeat_through_the_arena": 16,
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

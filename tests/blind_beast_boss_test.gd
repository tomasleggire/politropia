extends SceneTree
## BlindBeastBoss ("El Topo"): the noise rules, the burrow loop (untargetable
## underground, exposed after an eruption), every attack with its telegraph and
## its dodge, the phase gating, Hyperfocus as an optional bonus, the reset, the
## light overlay, the defeat and the one-drag arena prefab.
## Run: godot --headless --path . --script res://tests/blind_beast_boss_test.gd
## Exits 0 when every check passes, 1 otherwise.

const ARENA_PREFAB := "res://scenes/enemies/bosses/blind_beast_boss_arena.tscn"
const BOSS_SCENE := "res://scenes/enemies/bosses/blind_beast.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 420.0
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LEFT_LIMIT := -434.0
const RIGHT_LIMIT := 434.0
const LUZ_HEALTH := 99
const FAR_LEFT := -420.0
const BOSS_AT := Vector2(300.0, 0.0)
const ARENA_RECT := Rect2(-434.0, -340.0, 868.0, 400.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const HIT_FROM := Vector2(100.0, 0.0)
const ROOM := &"A"
const BOSS_ID := &"library_blind_beast"
const HUD_LAYER := 40
## LUZ and OJO as the six-dot cells of the table, one flat slot between letters.
const WORD_PATTERNS := ["###...." + "#.#..#" + "." + "#.#.##", "#.#.#." + "." + ".#.##." + "." + "#.#.#."]
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.3, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const CHECKS := {
	"case_prefab_one_drag": 7,
	"case_noise_rules": 13,
	"case_burrowed_and_exposed": 12,
	"case_eruption_targets_newest_noise": 6,
	"case_eruption_hit_and_miss": 11,
	"case_probe": 11,
	"case_claw_counter": 9,
	"case_braille_ridge": 10,
	"case_debris_toss": 8,
	"case_tremor_pulse": 16,
	"case_chain_eruption": 11,
	"case_telegraph_minimums": 13,
	"case_phase_gating": 10,
	"case_stays_inside_arena": 7,
	"case_hyperfocus_is_optional": 13,
	"case_fight_is_winnable_without_hyperfocus": 5,
	"case_reset_clears_everything": 13,
	"case_light_overlay": 8,
	"case_defeat_and_arena": 16,
	"case_unreachable_noise_erupts_in_place": 8,
	"case_empty_draw_falls_back_to_eruption": 6,
	"case_ridge_ignores_invalid_words": 6,
	"case_ridge_fits_narrow_arena": 5,
	"case_corpse_restored_on_reload": 12,
	"case_corpse_made_before_entering_the_tree": 10,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player
var _boss: BlindBeastBoss
var _arena: BossArena


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


func _build_rig(configure := Callable()) -> void:
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
	_player.position = Vector2(FAR_LEFT, 0.0)
	_rig.add_child(_player)
	_player.set_max_health(LUZ_HEALTH)
	_player.heal(LUZ_HEALTH)
	_player.set_checkpoint(Vector2(FAR_LEFT, 0.0))
	current_scene = _rig
	_boss = _make_boss()
	_boss.position = BOSS_AT
	if configure.is_valid():
		configure.call(_boss)
	_rig.add_child(_boss)


func _make_boss() -> BlindBeastBoss:
	var boss := (load(BOSS_SCENE) as PackedScene).instantiate() as BlindBeastBoss
	boss.rng_seed = 7
	boss.hit_stop_time = 0.0
	boss.final_freeze_time = 0.0
	boss.final_slowmo_time = 0.0
	boss.phase_transition_time = 0.3
	boss.defeat_time = 0.2
	boss.patience_time = 999.0
	return boss


## A rig with Luz standing still far to the left and the beast engaged and burrowed.
func _fight_rig(configure := Callable()) -> void:
	await _build_rig(configure)
	await _frames(5)
	_boss.set_arena_limits(LEFT_LIMIT, RIGHT_LIMIT)
	_boss.set_manual_engage(true)
	_boss.engage()
	await _place_luz(FAR_LEFT)


func _cleanup() -> void:
	BossFeel.cancel()
	Engine.time_scale = 1.0
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


## Replaces the rig's boss with the one-drag arena prefab and takes its beast.
func _arena_beast() -> void:
	if is_instance_valid(_boss) and _boss.get_parent() != null:
		_boss.get_parent().remove_child(_boss)
		_boss.free()
	_arena = (load(ARENA_PREFAB) as PackedScene).instantiate() as BossArena
	_arena.arena_rect = ARENA_RECT
	for key: String in ARENA_TIMINGS:
		_arena.set(key, ARENA_TIMINGS[key])
	_rig.add_child(_arena)
	await _frames(20)
	_boss = _arena.get_boss() as BlindBeastBoss
	_boss.hit_stop_time = 0.0
	_boss.final_freeze_time = 0.0
	_boss.final_slowmo_time = 0.0
	_boss.defeat_time = 0.2
	_boss.phase_transition_time = 0.3
	_boss.patience_time = 999.0


func _frames(n: int) -> void:
	for i: int in n:
		await physics_frame


func _secs(t: float) -> void:
	await _frames(ceili(t * 60.0))


func _wait_until(condition: Callable, seconds: float) -> bool:
	for i: int in ceili(seconds * 60.0):
		if condition.call():
			return true
		await physics_frame
	return condition.call()


## Luz stands on the floor at `x`. Frozen, she keeps whatever velocity and state the
## test gives her, so the beast reads exactly that.
func _place_luz(x: float, frozen := true) -> void:
	_player.set_physics_process(true)
	_player.global_position = Vector2(x, 0.0)
	_player.velocity = Vector2.ZERO
	await _frames(3)
	_player.set_physics_process(not frozen)


func _place_luz_airborne(x: float, y: float) -> void:
	_player.set_physics_process(true)
	_player.global_position = Vector2(x, y)
	_player.velocity = Vector2.ZERO
	await _frames(2)
	_player.set_physics_process(false)


func _taken() -> int:
	return LUZ_HEALTH - _player.get_health()


func _hit(damage := 1) -> bool:
	return _boss.receive_hit(damage, HIT_FROM, &"attack_1")


func _luz_swings() -> void:
	_player._state = Player.State.ATTACK
	_player._attack_phase = Player.PHASE_STARTUP


func _luz_idles() -> void:
	_player._state = Player.State.IDLE


## Frames from the call until `condition` holds, or -1 when it never does.
func _frames_until(condition: Callable, max_frames: int) -> int:
	for i: int in max_frames:
		if condition.call():
			return i
		await physics_frame
	return -1


func _in_telegraph(attack: int) -> bool:
	return _boss.get_attack() == attack and _boss.is_telegraphing()


func _in_phase(attack: int, phase: BossEnemy.AttackPhase) -> bool:
	return _boss.get_state() == BossEnemy.State.ATTACK and _boss.get_attack() == attack and _boss.get_attack_phase() == phase


## The centre of the first flat slot that comes after a raised one.
func _flat_slot_x(slots: Array[Dictionary]) -> float:
	var seen_raised := false
	for slot: Dictionary in slots:
		seen_raised = seen_raised or slot["raised"]
		if seen_raised and not slot["raised"]:
			return slot["x"]
	return 0.0


func _spots_apart(xs: PackedFloat32Array) -> Array[float]:
	var sorted := Array(xs)
	sorted.sort()
	var gaps: Array[float] = []
	for i: int in range(1, sorted.size()):
		gaps.append(float(sorted[i]) - float(sorted[i - 1]))
	return gaps


# -- Cases ------------------------------------------------------------------------------

func case_prefab_one_drag() -> void:
	await _build_rig()
	_boss.get_parent().remove_child(_boss)
	_boss.free()
	_arena = (load(ARENA_PREFAB) as PackedScene).instantiate() as BossArena
	_rig.add_child(_arena)
	await _frames(10)
	var beast := _arena.get_boss() as BlindBeastBoss
	check(beast != null and beast.get_parent() == _arena, "the arena finds the beast as a direct child")
	check(_arena.boss_name == "El Topo", "the arena carries the boss name")
	check(beast != null and beast.enemy_id == BOSS_ID, "the enemy id is the unique library_blind_beast")
	check(not _arena.reward_enabled and _arena.get_reward() == null, "no reward is configured or spawned")
	check(_arena.get_state() == BossArena.FightState.ARMED, "the prefab arms itself with no extra setup")
	check(beast != null and not beast.receive_hit(1, HIT_FROM, &"attack_1"), "the beast is untouchable before the fight")
	check(beast != null and beast.max_health == 30 and is_equal_approx(beast.phase_two_threshold, 0.66), "30 health and the first phase threshold at 0.66")


func case_noise_rules() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void:
		boss.noise_memory = 10
		boss.tunnel_speed = 0.0)
	await _place_luz(-300.0)
	await _frames(10)
	check(_boss.get_noise_xs().is_empty(), "standing still makes no noise")
	check(_boss.is_luz_still(), "standing grounded and slow is still")
	_player.velocity.x = 150.0
	await _frames(10)
	check(_boss.get_noise_xs().is_empty(), "walking is quiet")
	check(not _boss.is_luz_still(), "walking is not still")
	_player.velocity.x = 0.0
	_player._state = Player.State.DASH
	await _frames(4)
	check(_boss.get_noise_kinds() == [BlindBeastBoss.KIND_DASH], "a dash starting is loud")
	_luz_idles()
	await _frames(2)
	_luz_swings()
	await _frames(4)
	check(_boss.get_noise_kinds() == [BlindBeastBoss.KIND_DASH, BlindBeastBoss.KIND_SWING], "an attack swing starting is loud")
	_player._attack_phase = Player.PHASE_ACTIVE
	await _frames(4)
	check(_boss.get_noise_xs().size() == 2, "the same swing is only heard once")
	check(not _boss.is_luz_still(), "right after a loud action Luz is not still")
	_luz_idles()
	_player.open_eyes_activated.emit()
	check(_boss.get_noise_kinds().back() == BlindBeastBoss.KIND_HYPERFOCUS, "Hyperfocus counts as a loud noise")
	await _frames(5)
	check(absf(_boss.get_noise_xs()[0] + 300.0) < 1.0, "a noise spot is Luz's x on the floor line")
	var heard := _boss.get_noise_xs().size()
	_player.set_physics_process(true)
	_player.global_position = Vector2(-200.0, -150.0)
	await _wait_until(func() -> bool: return _boss.get_noise_xs().size() > heard, 3.0)
	check(_boss.get_noise_kinds().back() == BlindBeastBoss.KIND_LANDING, "landing after being airborne is loud")
	check(absf(_boss.get_noise_xs()[_boss.get_noise_xs().size() - 1] + 200.0) < 3.0, "the landing spot is where Luz came down")
	check(_boss.hazard_count() > 0, "every noise draws a ripple")


func case_burrowed_and_exposed() -> void:
	await _fight_rig()
	check(_boss.is_burrowed() and not _boss.is_hittable(), "burrowed means untargetable")
	check(_boss.collision_layer == 0, "the root leaves the enemy layer underground")
	check(not _hit(), "a burrowed beast refuses hits")
	check(not _boss._visual.visible, "the body is hidden underground")
	check(_boss._mound_visible(), "only a dirt mound shows by default")
	_boss.show_mound = false
	check(not _boss._mound_visible(), "the mound can be hidden")
	check(_boss.stun(1.0) and _boss.is_exposed(), "a stun brings it up")
	check(_boss.is_hittable() and _boss.collision_layer == Enemy.ENEMY_LAYER and _boss._visual.visible, "exposed means visible and hittable")
	check(_hit() and _boss.get_health() == _boss.max_health - 1, "an exposed beast takes the hit")
	await _secs(1.15)
	check(_boss.is_exposed() == false and not _boss.is_hittable(), "after the window it is untargetable again at once")
	await _secs(0.5)
	check(not _boss._visual.visible and not _hit(), "the dig-in ends hidden and untargetable")
	check(_boss.get_state() == BossEnemy.State.FIGHT, "it went back to the fight")


func case_eruption_targets_newest_noise() -> void:
	await _fight_rig()
	_boss.register_noise(-100.0, &"test")
	_boss.register_noise(120.0, &"test")
	var start_x := _boss.global_position.x
	await _frames(30)
	var travelled := absf(_boss.global_position.x - start_x)
	check(travelled > 90.0 and travelled < 125.0, "it tunnels at about 220 px/s (%.0f px in half a second)" % travelled)
	var seen := await _wait_until(func() -> bool: return _in_telegraph(BlindBeastBoss.Attack.ERUPTION), 4.0)
	check(seen, "it erupts after the tunnel")
	var cracks := _boss.get_crack_xs()
	check(cracks.size() == 1 and absf(cracks[0] - 120.0) < 1.0, "the cracks open at the newest noise spot")
	check(absf(cracks[0] - _player.global_position.x) > 100.0, "not under Luz's current position")
	await _wait_until(func() -> bool: return not _boss.get_column_xs().is_empty(), 1.0)
	check(_boss.get_column_xs().size() == 1 and absf(_boss.get_column_xs()[0] - 120.0) < 1.0, "the column bursts at the noise spot")
	check(_boss.get_noise_xs().size() == 2, "the memory keeps both spots")


func case_eruption_hit_and_miss() -> void:
	await _fight_rig()
	_boss.register_noise(150.0, &"test")
	var missed := await _wait_until(func() -> bool: return _boss.is_stunned(), 5.0)
	check(missed, "a missed eruption leaves it stunned")
	var long_window := _boss.get_state_time_left()
	check(long_window > 1.5 and long_window <= _boss.missed_stun_time, "the miss window is the long one (%.2f s)" % long_window)
	check(_boss.is_exposed() and _boss.is_hittable() and _taken() == 0, "exposed, hittable and Luz untouched")
	check(_hit(), "Luz can punish the disoriented beast")
	await _fight_rig()
	await _place_luz(150.0, false)
	_boss.register_noise(150.0, &"test")
	var landed := await _wait_until(func() -> bool: return _in_phase(BlindBeastBoss.Attack.ERUPTION, BossEnemy.AttackPhase.RECOVER), 5.0)
	check(landed, "an eruption that hits goes into its short window")
	var short_window := _boss.get_state_time_left()
	check(_taken() == 1, "the column hurt Luz once")
	check(not _boss.is_stunned() and _boss.is_exposed() and _boss.is_hittable(), "exposed but not stunned")
	check(short_window <= _boss.exposed_hit_time and short_window < long_window, "the hit window is shorter than the miss window (%.2f vs %.2f s)" % [short_window, long_window])
	await _secs(0.2)
	check(_taken() == 1, "the column hurts once per eruption")
	await _secs(1.0)
	check(_boss.is_burrowed(), "it digs in again after the short window")
	check(_boss.get_state() == BossEnemy.State.FIGHT, "and the fight moves on")


func case_probe() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.patience_time = 0.6)
	await _secs(0.3)
	check(_boss.get_state() != BossEnemy.State.ATTACK, "no probe before the patience runs out")
	var started := await _wait_until(func() -> bool: return _in_telegraph(BlindBeastBoss.Attack.PROBE), 2.0)
	check(started, "after patience_time of silence it probes")
	var cracks := _boss.get_crack_xs()
	check(cracks.size() == 3, "three cracks sweep the arena")
	var gaps := _spots_apart(cracks)
	check(gaps.size() == 2 and absf(gaps[0] - gaps[1]) < 0.5, "evenly spaced")
	check(absf(cracks[0]) <= RIGHT_LIMIT and absf(cracks[2]) <= RIGHT_LIMIT, "all inside the arena")
	var warning := await _frames_until(func() -> bool: return not _boss.get_column_xs().is_empty(), 120)
	check(warning >= 20, "the first crack warns at least 0.35 s (%d frames)" % warning)
	var bursts: Array[float] = []
	var seen := {}
	for i: int in 200:
		var xs := _boss.get_column_xs()
		if not xs.is_empty() and not seen.has(roundi(xs[0])):
			seen[roundi(xs[0])] = true
			bursts.append(xs[0])
		if _in_phase(BlindBeastBoss.Attack.PROBE, BossEnemy.AttackPhase.RECOVER):
			break
		await physics_frame
	check(bursts.size() >= 2, "the columns burst one after another")
	check(_taken() == 0, "Luz standing between the cracks is never touched")
	check(_in_phase(BlindBeastBoss.Attack.PROBE, BossEnemy.AttackPhase.RECOVER) and _boss.is_exposed() and _boss.is_hittable(), "the probe leaves it exposed")
	check(_boss.get_crack_xs().is_empty() and _boss.get_column_xs().is_empty(), "the probe leaves no hazard behind")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.patience_time = 0.6)
	await _place_luz(0.0)
	await _wait_until(func() -> bool: return _taken() > 0, 4.0)
	check(_taken() == 1, "a column that bursts under Luz hurts her once")


func case_claw_counter() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.patience_time = 0.6)
	var exposed := await _wait_until(func() -> bool: return _in_phase(BlindBeastBoss.Attack.PROBE, BossEnemy.AttackPhase.RECOVER), 6.0)
	check(exposed and _boss.is_exposed(), "the probe leaves it exposed and not stunned")
	var side := -1.0 if _boss.global_position.x > 0.0 else 1.0
	await _place_luz(_boss.global_position.x + side * 300.0)
	_luz_swings()
	await _frames(3)
	check(_boss.get_attack() == BlindBeastBoss.Attack.PROBE, "a swing out of reach draws no counter")
	_luz_idles()
	await _frames(2)
	var origin := _boss.global_position.x + side * 60.0
	await _place_luz(origin)
	_luz_swings()
	await _frames(3)
	check(_boss.get_attack() == BlindBeastBoss.Attack.CLAW_COUNTER and _boss.is_telegraphing(), "a swing within reach draws a claw counter")
	check(absf(_boss.get_claw_zone().get_center().x - origin) < 1.0, "the claw aims at the swing's origin")
	check(_boss.get_state_time_left() >= BlindBeastBoss.CLAW_MIN_TELEGRAPH - 0.06, "the red telegraph lasts at least 0.4 s")
	_luz_idles()
	var away := -420.0 if origin > 0.0 else 420.0
	await _place_luz(away)
	check(absf(_boss.get_claw_zone().get_center().x - origin) < 1.0, "it does not follow Luz while she walks away")
	var struck := await _wait_until(func() -> bool: return _in_phase(BlindBeastBoss.Attack.CLAW_COUNTER, BossEnemy.AttackPhase.RECOVER), 2.0)
	check(struck and _taken() == 0, "Luz who left the origin is never touched")
	check(_boss.is_exposed() and _boss.is_hittable(), "the beast stays exposed through its counter")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.patience_time = 0.6)
	await _wait_until(func() -> bool: return _in_phase(BlindBeastBoss.Attack.PROBE, BossEnemy.AttackPhase.RECOVER), 6.0)
	origin = _boss.global_position.x + side * 60.0
	await _place_luz(origin)
	_luz_swings()
	await _frames(3)
	await _wait_until(func() -> bool: return _in_phase(BlindBeastBoss.Attack.CLAW_COUNTER, BossEnemy.AttackPhase.RECOVER), 2.0)
	check(_taken() == 1, "Luz who stays at the origin is clawed once")
	_luz_idles()


func case_braille_ridge() -> void:
	await _fight_rig()
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	var slots := _boss.get_ridge_slots()
	_player.global_position = Vector2(_flat_slot_x(slots), 0.0)
	var pattern := ""
	var flat := 0
	var raised := 0
	for slot: Dictionary in slots:
		pattern += "#" if slot["raised"] else "."
		raised += 1 if slot["raised"] else 0
		flat += 0 if slot["raised"] else 1
	check(WORD_PATTERNS.has(pattern), "the slots spell a braille word from the table (%s)" % pattern)
	check(raised > 0 and flat > raised * 0.5, "some slots are raised and plenty stay flat and safe")
	var first: Dictionary = slots[0]
	var last: Dictionary = slots[slots.size() - 1]
	check(float(first["x"]) - float(first["width"]) * 0.5 >= LEFT_LIMIT and float(last["x"]) + float(last["width"]) * 0.5 <= RIGHT_LIMIT, "the slots stay inside the arena")
	var rise_frame := {}
	var frames := 0
	while _boss.get_state() == BossEnemy.State.ATTACK and frames < 400:
		var heights := _boss.get_ridge_slots()
		for i: int in heights.size():
			if float(heights[i]["height"]) > 0.0 and not rise_frame.has(i):
				rise_frame[i] = frames
		frames += 1
		await physics_frame
	check(not rise_frame.is_empty() and float(rise_frame[rise_frame.keys().min()]) / 60.0 >= BlindBeastBoss.RIDGE_MIN_TELEGRAPH - 0.03, "every bump shows at least 0.7 s before the first spike (%d frames)" % rise_frame[rise_frame.keys().min()])
	var ordered := true
	var previous := -1
	for i: int in slots.size():
		if rise_frame.has(i):
			ordered = ordered and rise_frame[i] >= previous
			previous = rise_frame[i]
	check(rise_frame.size() == raised and ordered, "the raised slots rise in reading order, left to right")
	check(_boss.get_ridge_slots().is_empty(), "the ridge retracts and leaves nothing")
	check(_boss.is_burrowed(), "the beast stays underground for the ridge")
	check(_taken() == 0, "Luz on a flat slot is never touched, whatever rises around her")
	var raised_x := 0.0
	for slot: Dictionary in slots:
		if slot["raised"] and raised_x == 0.0:
			raised_x = slot["x"]
	await _fight_rig()
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	_player.global_position = Vector2(raised_x, 0.0)
	await _wait_until(func() -> bool: return _boss.get_state() != BossEnemy.State.ATTACK, 4.0)
	check(_taken() == 1, "a raised slot hurts Luz when its spike rises")
	check(_boss.get_ridge_slots().is_empty(), "no spike is left after the ridge")


func case_debris_toss() -> void:
	await _fight_rig()
	_boss.start_attack(BlindBeastBoss.Attack.DEBRIS_TOSS)
	var tossed := await _wait_until(func() -> bool: return not _boss.get_rock_landing_xs().is_empty(), 2.0)
	check(tossed and _boss.get_rock_landing_xs().size() == 3, "an eruption flings three rocks")
	var landings := _boss.get_rock_landing_xs()
	var inside := true
	for x: float in landings:
		inside = inside and x >= LEFT_LIMIT and x <= RIGHT_LIMIT
	check(inside and _spots_apart(landings)[0] > 40.0, "distinct landing spots inside the arena")
	var flight := await _frames_until(func() -> bool: return _boss.get_rock_landing_xs().is_empty(), 200)
	check(flight >= 21, "each floor marker shows at least 0.35 s before impact (%d frames)" % flight)
	check(_taken() == 0, "Luz away from the markers is never touched")
	await _fight_rig()
	_boss.start_attack(BlindBeastBoss.Attack.DEBRIS_TOSS)
	await _wait_until(func() -> bool: return not _boss.get_rock_landing_xs().is_empty(), 2.0)
	_player.global_position = Vector2(_boss.get_rock_landing_xs()[0], 0.0)
	await _wait_until(func() -> bool: return _boss.get_rock_landing_xs().is_empty(), 2.0)
	await _frames(2)
	check(_taken() == 1, "a rock that lands on Luz hurts her")
	_boss._clear_hazards()
	check(_boss.get_rock_landing_xs().is_empty(), "clearing the hazards drops the rocks")
	check(_boss.hazard_count() == 0, "nothing is left in the world")
	check(_boss.get_attack() == BlindBeastBoss.Attack.DEBRIS_TOSS, "the attack id is kept")


func case_tremor_pulse() -> void:
	await _fight_rig()
	await _place_luz(-150.0)
	_boss.start_attack(BlindBeastBoss.Attack.TREMOR_PULSE)
	check(_boss.is_exposed(), "it surfaces for the slam")
	var launched := await _wait_until(func() -> bool: return _boss.get_pulse_xs().size() == 2, 3.0)
	check(launched, "the slam sends a pulse in both directions")
	var before := _boss.get_pulse_xs()
	await _frames(6)
	var after := _boss.get_pulse_xs()
	var speed := (absf(after[0] - before[0])) / 0.1
	check(speed > 220.0 and speed < 300.0, "the pulse travels at about 260 px/s (%.0f)" % speed)
	var confused := await _wait_until(func() -> bool: return _boss.is_stunned(), 4.0)
	check(confused and _taken() == 0 and not _boss.is_chasing(), "a still Luz is not felt: nothing happens")
	check(_boss.get_state_time_left() <= _boss.tremor_confused_time and _boss.is_exposed() and _boss.is_hittable(), "it surfaces confused and punishable")
	check(_boss.get_pulse_xs().is_empty(), "the pulses are gone")
	await _fight_rig()
	await _place_luz_airborne(-150.0, -90.0)
	_boss.start_attack(BlindBeastBoss.Attack.TREMOR_PULSE)
	var air_confused := await _wait_until(func() -> bool: return _boss.is_stunned(), 5.0)
	check(air_confused and not _boss.is_chasing() and _taken() == 0, "an airborne Luz is not felt either")
	await _fight_rig()
	await _place_luz(-150.0)
	_player.velocity.x = 120.0
	_boss.start_attack(BlindBeastBoss.Attack.TREMOR_PULSE)
	var chased := await _wait_until(func() -> bool: return _boss.is_chasing(), 5.0)
	check(chased, "a moving grounded Luz is felt: the chase starts")
	check(_boss.is_burrowed() and not _boss.is_stunned(), "it dives to chase her")
	var first := await _wait_until(func() -> bool: return not _boss.get_crack_xs().is_empty(), 1.0)
	check(first and absf(_boss.get_crack_xs()[0] - (-150.0)) < 1.0, "the first fast eruption tracks her real position")
	var warning := await _frames_until(func() -> bool: return not _boss.get_column_xs().is_empty(), 120)
	check(warning >= 20, "a chase crack warns at least 0.35 s (%d frames)" % warning)
	_player.global_position = Vector2(100.0, 0.0)
	var second := await _wait_until(func() -> bool: return not _boss.get_crack_xs().is_empty(), 2.0)
	check(second and absf(_boss.get_crack_xs()[0] - 100.0) < 1.0, "the next one follows where she moved")
	var bursts := 1
	var previous := 0
	for i: int in 400:
		var now := _boss.get_column_xs().size()
		if now > 0 and previous == 0:
			bursts += 1
		previous = now
		if _in_phase(BlindBeastBoss.Attack.TREMOR_PULSE, BossEnemy.AttackPhase.RECOVER):
			break
		await physics_frame
	check(bursts == 3, "three fast eruptions in all (%d)" % bursts)
	check(_taken() >= 1, "a column that finds her hurts")
	check(_boss.get_crack_xs().is_empty() and _boss.get_column_xs().is_empty(), "the chase leaves nothing behind")
	check(_in_phase(BlindBeastBoss.Attack.TREMOR_PULSE, BossEnemy.AttackPhase.RECOVER) and _boss.is_exposed() and _boss.is_hittable(), "it comes up exposed and hittable when the chase ends")


func case_chain_eruption() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.noise_memory = 3)
	for x: float in [-200.0, 0.0, 200.0]:
		_boss.register_noise(x, &"test")
	_boss.start_attack(BlindBeastBoss.Attack.CHAIN_ERUPTION)
	check(_boss.get_crack_xs().size() == 3 and absf(_boss.get_crack_xs()[0] + 200.0) < 1.0 and absf(_boss.get_crack_xs()[2] - 200.0) < 1.0, "cracks open on every remembered spot")
	var order: Array[float] = []
	var stamps: Array[int] = []
	var frame := 0
	var previous := 0
	var warning := -1
	while _boss.get_state() == BossEnemy.State.ATTACK and frame < 400:
		var now := _boss.get_column_xs().size()
		if now > 0 and previous == 0:
			order.append(_boss.get_column_xs()[0])
			stamps.append(frame)
			if warning < 0:
				warning = frame
		previous = now
		frame += 1
		await physics_frame
	check(warning >= 20, "the first crack warns at least 0.35 s (%d frames)" % warning)
	check(order.size() == 3 and order[0] < order[1] and order[1] < order[2], "it erupts oldest to newest")
	check(order.size() == 3 and absf(float(stamps[1] - stamps[0]) / 60.0 - 0.45) < 0.08, "about 0.45 s apart")
	check(_taken() == 0, "Luz away from the spots is never touched")
	check(_boss.is_stunned() and _boss.is_exposed() and _boss.is_hittable(), "it comes up stunned and hittable where it ended")
	check(_boss.get_crack_xs().is_empty(), "no crack is left")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.noise_memory = 3)
	await _place_luz(0.0)
	for x: float in [-200.0, 0.0, 200.0]:
		_boss.register_noise(x, &"test")
	_boss.start_attack(BlindBeastBoss.Attack.CHAIN_ERUPTION)
	await _wait_until(func() -> bool: return _boss.get_state() != BossEnemy.State.ATTACK, 4.0)
	check(_taken() == 1, "standing on a remembered spot gets Luz hit")
	check(_boss.is_exposed() and not _boss.is_stunned(), "a chain that hit gives the short window")
	_boss.register_noise(50.0, &"test")
	check(_boss.get_noise_xs().size() == 3, "the memory holds the last three spots")
	check(absf(_boss.get_noise_xs()[0]) < 1.0, "the oldest one was forgotten")


func case_telegraph_minimums() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void:
		boss.crack_time = 0.05
		boss.chain_crack_time = 0.05
		boss.claw_telegraph_time = 0.05
		boss.ridge_telegraph_time = 0.05
		boss.tremor_telegraph_time = 0.05
		boss.chase_crack_time = 0.05
		boss.debris_flight_time = 0.05)
	for attack: int in BlindBeastBoss.ATTACK_COUNT:
		check(_boss._telegraph_time(attack) >= BossEnemy.MIN_TELEGRAPH, "attack %d never telegraphs under 0.35 s" % attack)
	check(_boss._telegraph_time(BlindBeastBoss.Attack.CLAW_COUNTER) >= 0.4, "the claw telegraph is at least 0.4 s")
	check(_boss._telegraph_time(BlindBeastBoss.Attack.BRAILLE_RIDGE) >= 0.7, "the braille bumps show at least 0.7 s")
	check(_boss.is_burrowed(), "the rig starts underground")
	_boss.start_attack(BlindBeastBoss.Attack.ERUPTION)
	check(_boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH - 0.001, "the telegraph that really runs honours the floor")
	_boss.start_attack(BlindBeastBoss.Attack.TREMOR_PULSE)
	check(_boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH - 0.001, "the slam wind-up honours the floor")
	_boss._phase = 3
	check(_boss._attack_weights().size() == BlindBeastBoss.ATTACK_COUNT, "one weight per attack")


func case_phase_gating() -> void:
	await _fight_rig()
	var weights := _boss._attack_weights()
	check(weights[BlindBeastBoss.Attack.ERUPTION] > 0.0, "phase one erupts")
	check(weights[BlindBeastBoss.Attack.BRAILLE_RIDGE] == 0.0 and weights[BlindBeastBoss.Attack.DEBRIS_TOSS] == 0.0, "no phase two attack in phase one")
	check(weights[BlindBeastBoss.Attack.TREMOR_PULSE] == 0.0 and weights[BlindBeastBoss.Attack.CHAIN_ERUPTION] == 0.0, "no phase three attack in phase one")
	_boss._phase = 2
	weights = _boss._attack_weights()
	check(weights[BlindBeastBoss.Attack.BRAILLE_RIDGE] > 0.0 and weights[BlindBeastBoss.Attack.DEBRIS_TOSS] > 0.0, "phase two adds the ridge and the debris")
	check(weights[BlindBeastBoss.Attack.TREMOR_PULSE] == 0.0 and weights[BlindBeastBoss.Attack.CHAIN_ERUPTION] == 0.0, "no phase three attack in phase two")
	_boss._phase = 3
	_boss.register_noise(-100.0)
	check(_boss._attack_weights()[BlindBeastBoss.Attack.CHAIN_ERUPTION] == 0.0, "a chain needs at least two remembered spots")
	_boss.register_noise(100.0)
	weights = _boss._attack_weights()
	check(weights[BlindBeastBoss.Attack.TREMOR_PULSE] > 0.0 and weights[BlindBeastBoss.Attack.CHAIN_ERUPTION] > 0.0, "phase three adds the tremor and the chain")
	check(weights[BlindBeastBoss.Attack.PROBE] == 0.0 and weights[BlindBeastBoss.Attack.CLAW_COUNTER] == 0.0, "the probe and the claw are answers, never drawn")
	var forbidden := {1: [3, 4, 5, 6], 2: [5, 6]}
	for phase: int in [1, 2]:
		await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.patience_time = 3.0)
		_boss._phase = phase
		var seen := {}
		for i: int in 900:
			if i % 70 == 0:
				_boss.register_noise(-300.0 + float((i / 70) % 5) * 150.0, &"test")
			if _boss.get_state() == BossEnemy.State.ATTACK:
				seen[_boss.get_attack()] = true
			await physics_frame
		var clean := true
		for attack: int in forbidden[phase]:
			clean = clean and not seen.has(attack)
		check(clean and not seen.is_empty(), "phase %d ran %s and drew nothing from a later phase" % [phase, seen.keys()])


func case_stays_inside_arena() -> void:
	await _fight_rig()
	_boss.register_noise(-5000.0, &"test")
	check(_boss.get_noise_xs()[0] >= LEFT_LIMIT and _boss.get_noise_xs()[0] <= RIGHT_LIMIT, "a noise beyond the wall is clamped to the arena")
	var lowest := _boss.global_position.x
	var highest := _boss.global_position.x
	for i: int in 1000:
		lowest = minf(lowest, _boss.global_position.x)
		highest = maxf(highest, _boss.global_position.x)
		if i == 200:
			_boss.register_noise(5000.0, &"test")
		await physics_frame
	check(lowest >= LEFT_LIMIT and highest <= RIGHT_LIMIT, "the beast never leaves the arena (%.0f to %.0f)" % [lowest, highest])
	check(highest > 300.0 and lowest < -300.0, "it really went to both walls (%.0f to %.0f)" % [lowest, highest])
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	var slots := _boss.get_ridge_slots()
	check(float(slots[0]["x"]) >= LEFT_LIMIT and float(slots[slots.size() - 1]["x"]) <= RIGHT_LIMIT, "the ridge fits the limits it was given")
	_boss.set_arena_limits(-200.0, 200.0)
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	slots = _boss.get_ridge_slots()
	check(float(slots[0]["x"]) >= -200.0 and float(slots[slots.size() - 1]["x"]) <= 200.0, "and a narrower arena shrinks it")
	_boss.start_attack(BlindBeastBoss.Attack.PROBE)
	var probe := _boss.get_crack_xs()
	var sweep_inside := true
	for x: float in probe:
		sweep_inside = sweep_inside and x >= -200.0 and x <= 200.0
	check(sweep_inside, "the probe sweeps the new arena")
	_boss.start_attack(BlindBeastBoss.Attack.TREMOR_PULSE)
	await _wait_until(func() -> bool: return _boss.get_pulse_xs().size() > 0, 2.0)
	var gone := await _wait_until(func() -> bool: return _boss.get_pulse_xs().is_empty(), 4.0)
	check(gone, "pulses die at the walls")


func case_hyperfocus_is_optional() -> void:
	await _fight_rig()
	check(_boss.is_burrowed(), "it starts underground")
	_player.open_eyes_activated.emit()
	check(_boss.is_stunned() and _boss.is_exposed() and _boss.is_hittable(), "Hyperfocus drags a burrowed beast up, dazed")
	check(_boss.get_state_time_left() <= _boss.hyperfocus_stun_time and _boss.get_state_time_left() > 1.0, "the daze lasts about 1.2 s")
	check(_boss.get_hyperfocus_cooldown_left() > 7.0, "and the bonus goes on cooldown")
	await _secs(1.8)
	check(_boss.is_burrowed(), "it digs in again afterwards")
	_player.open_eyes_activated.emit()
	check(not _boss.is_stunned(), "on cooldown it is not forced up again")
	check(_boss.get_noise_kinds().back() == BlindBeastBoss.KIND_HYPERFOCUS, "but it still counts as a loud noise")
	_boss._hyperfocus_left = 0.0
	_boss.stun(1.0)
	var stun_left := _boss.get_state_time_left()
	_player.open_eyes_activated.emit()
	check(_boss.get_hyperfocus_cooldown_left() == 0.0 and _boss.get_state_time_left() <= stun_left, "an exposed beast is not affected")
	await _fight_rig()
	_boss.start_attack(BlindBeastBoss.Attack.ERUPTION)
	check(not _boss.get_crack_xs().is_empty(), "an eruption is warning")
	_player.open_eyes_activated.emit()
	check(_boss.is_stunned() and _boss.get_crack_xs().is_empty(), "a burrowed beast mid-eruption is dazed and its cracks vanish")
	await _fight_rig()
	var fake := Node2D.new()
	_rig.add_child(fake)
	_boss._on_player_found(fake)
	check(not fake.has_signal(&"open_eyes_activated") and _boss.get_luz() == null, "a player without the signal is accepted")
	await _frames(5)
	check(_boss.get_state() == BossEnemy.State.FIGHT, "the boss keeps running without it")
	_boss._on_player_found(_player)
	check(_player.is_connected(&"open_eyes_activated", _boss._on_open_eyes), "the signal is connected once the real player is known")


func case_fight_is_winnable_without_hyperfocus() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void:
		boss.patience_time = 1.0
		boss.phase_transition_time = 0.3)
	var windows := 0
	var landed := 0
	var was_exposed := false
	var frames := 0
	while not _boss.is_dead() and frames < 60 * 400:
		if _boss.is_exposed() and not was_exposed:
			windows += 1
		was_exposed = _boss.is_exposed()
		if _boss.is_exposed() and frames % 20 == 0 and _hit():
			landed += 1
		frames += 1
		await physics_frame
	check(_boss.is_dead(), "the beast can be beaten with no Hyperfocus at all (%d s)" % (frames / 60))
	check(windows >= 5, "the fight offers exposed windows by itself (%d)" % windows)
	check(landed == 30, "every health point came from a hit in a window (%d)" % landed)
	check(_boss.get_hyperfocus_cooldown_left() == 0.0, "Hyperfocus was never used")
	check(frames / 60 >= 30, "and the fight is not over in a blink (%d s)" % (frames / 60))


func case_reset_clears_everything() -> void:
	await _fight_rig()
	_boss._phase = 3
	_boss.register_noise(-100.0, &"test")
	_boss.register_noise(120.0, &"test")
	_boss._ensure_overlay()
	_boss.start_attack(BlindBeastBoss.Attack.DEBRIS_TOSS)
	await _wait_until(func() -> bool: return not _boss.get_rock_landing_xs().is_empty(), 2.0)
	check(_boss.hazard_count() > 3 and not _boss.get_noise_xs().is_empty(), "the fight left hazards and a noise memory")
	check(_boss.has_light_overlay(), "the light overlay is up")
	_boss.reset_to_spawn()
	check(_boss.hazard_count() == 0, "after the reset no hazard remains")
	check(_boss.get_noise_xs().is_empty(), "the noise memory is empty too")
	check(_boss.is_fresh(), "the beast is fresh")
	check(_boss.get_phase() == 1 and _boss.get_health() == _boss.max_health, "phase one at full health")
	check(_boss.is_burrowed() and not _boss.is_hittable(), "burrowed and untargetable again")
	check(not _boss.has_light_overlay(), "the overlay is gone")
	check(_boss.global_position.distance_to(BOSS_AT) < 0.5, "back at the spawn")
	check(not _boss.is_chasing() and _boss.get_pulse_xs().is_empty(), "no chase is left")
	await _frames(3)
	check(_boss.get_rock_landing_xs().is_empty(), "no rock lands after the reset")
	_boss.engage()
	_boss.stun(1.0)
	_boss.reset_to_spawn()
	check(_boss.is_fresh() and _boss.is_burrowed(), "a reset also fixes an exposed beast")
	_boss.engage()
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	_boss.reset_to_spawn()
	check(_boss.get_ridge_slots().is_empty() and _boss.hazard_count() == 0, "a reset mid ridge clears the slots")


func case_light_overlay() -> void:
	await _fight_rig()
	check(not _boss.has_light_overlay(), "no overlay before the last phase")
	_boss._surface()
	_hit(21)
	check(_boss.get_phase() == 3, "the beast reached the last phase")
	check(_boss.has_light_overlay(), "the last phase dims the light")
	check(_boss.get_light_layer() < HUD_LAYER, "the overlay sits below the HUD (layer %d)" % _boss.get_light_layer())
	check(_boss._overlay_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it never eats input")
	await _secs(1.0)
	check(_boss._overlay_rect.color.a > 0.2 and _boss._overlay_rect.color.a <= _boss.dim_alpha + 0.001, "it fades in to the configured darkness")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.dim_light_in_final_phase = false)
	_boss._surface()
	_hit(21)
	check(_boss.get_phase() == 3 and not _boss.has_light_overlay(), "the overlay can be switched off")
	check(_boss.get_state() == BossEnemy.State.TRANSITION and _boss.is_exposed(), "and the mechanics do not depend on it")


func case_defeat_and_arena() -> void:
	await _build_rig()
	await _arena_beast()
	var completion := root.get_node("GameCompletion")
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(15)
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "entering the trigger starts the fight")
	check(_arena.get_bar().get_name_text() == "El Topo", "the bar carries the boss name")
	check(_arena.get_bar().get_extra_notch_ratios() == PackedFloat32Array([0.33]), "the bar draws a notch for each phase")
	await _frames(40)
	check(_boss.get_state() != BossEnemy.State.IDLE and _boss.is_burrowed(), "the arena woke the beast and it is underground")
	var signals: Array[String] = []
	_boss.defeated.connect(func() -> void: signals.append("defeated"))
	_boss.corpse_settled.connect(func() -> void: signals.append("settled"))
	_boss._surface()
	_hit(21)
	check(_boss.has_light_overlay(), "phase three put the overlay up before the end")
	await _frames(20)
	_boss._surface()
	_boss.start_attack(BlindBeastBoss.Attack.DEBRIS_TOSS)
	await _wait_until(func() -> bool: return not _boss.get_rock_landing_xs().is_empty(), 2.0)
	_boss._surface()
	check(_boss.receive_hit(99, HIT_FROM, &"attack_1"), "the killing blow lands")
	check(signals.has("defeated"), "defeated is emitted")
	check(_boss.hazard_count() == 0, "no hazard remains on defeat, not even the overlay")
	await _frames(90)
	check(_arena.get_state() == BossArena.FightState.DEFEATED and not _arena.are_doors_closed(), "defeat opens the arena")
	check(signals.has("settled") and not _boss.is_physics_processing(), "the corpse settles")
	check(_boss.is_dead() and _boss._visual.visible and _boss._visual.position.y == 0.0, "the corpse lies above ground, visible")
	check(_boss.global_position.y <= 1.0 and _boss.global_position.y >= -2.0, "on the floor line")
	check(not completion.is_active(), "a non-final boss does not trigger the game completion")
	check(_progress().is_defeated(BOSS_ID), "BossProgress records the defeat under the enemy id")
	check(_arena.get_reward() == null, "no reward spawns")
	check(_boss.get_rock_landing_xs().is_empty(), "the rocks are gone")


## A wall on the floor line: the tunnel can never reach the noise behind it.
func case_unreachable_noise_erupts_in_place() -> void:
	await _fight_rig()
	LevelGeometry.add_solid(_rig, Rect2(150.0, -200.0, 20.0, 200.0), Color.DIM_GRAY)
	_boss.register_noise(0.0, &"test")
	var frames := await _frames_until(func() -> bool: return _boss.is_exposed(), 60 * 8)
	check(frames >= 0 and _boss.is_hittable(), "a beast stuck behind a wall still surfaces and becomes hittable (%d frames)" % frames)
	check(frames >= int(_boss.stuck_tunnel_time * 60.0), "it only gave up after the stuck time (%d frames)" % frames)
	check(_boss.get_attack() == BlindBeastBoss.Attack.ERUPTION, "the answer is a plain eruption")
	check(_boss.global_position.x > 170.0 and absf(_boss.global_position.x - _boss.get_noise_xs()[0]) > 100.0, "it came up where the wall stopped it (x %.0f)" % _boss.global_position.x)
	check(_boss._pending_noise_index() == -1, "the noise counts as answered")
	check(_hit() and _taken() == 0, "Luz can punish it and was never touched")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.tunnel_speed = 0.0)
	_boss.register_noise(100.0, &"test")
	var idle := await _frames_until(func() -> bool: return _boss.is_exposed(), 60 * 8)
	check(idle >= 0 and _boss.is_hittable(), "a beast that cannot tunnel at all surfaces too (%d frames)" % idle)
	check(absf(_boss.global_position.x - BOSS_AT.x) < 1.0, "right where it was")


## A designer zeroed the weights: the beast must still answer the noise.
func case_empty_draw_falls_back_to_eruption() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.weights_phase_one = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	check(_boss._draw_attack(_boss._attack_weights()) == BossEnemy.NO_ATTACK, "all-zero weights draw nothing")
	_boss.register_noise(100.0, &"test")
	var seen := await _wait_until(func() -> bool: return _in_telegraph(BlindBeastBoss.Attack.ERUPTION), 6.0)
	check(seen, "it erupts anyway")
	check(_boss.get_crack_xs().size() == 1 and absf(_boss.get_crack_xs()[0] - 100.0) < 1.0, "at the noise spot")
	check(_boss._pending_noise_index() == -1, "the noise counts as answered")
	var up := await _wait_until(func() -> bool: return _boss.is_exposed(), 3.0)
	check(up and _boss.is_hittable(), "it surfaces and becomes hittable")
	await _secs(1.0)
	check(_boss.get_attack() == BlindBeastBoss.Attack.ERUPTION, "the only attack that ran was the eruption")


func case_ridge_ignores_invalid_words() -> void:
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.ridge_words = PackedStringArray(["", "LUZ", "  "]))
	var always_luz := true
	for i: int in 20:
		always_luz = always_luz and _boss._ridge_pattern(43) == WORD_PATTERNS[0]
	check(always_luz, "empty words are skipped and the valid one is always chosen")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.ridge_words = PackedStringArray(["", " ", "123"]))
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	check(_boss.get_attack() == BlindBeastBoss.Attack.ERUPTION and _boss.get_ridge_slots().is_empty(), "a list with no valid word skips the ridge for an eruption")
	var up := await _wait_until(func() -> bool: return _boss.is_exposed(), 4.0)
	check(up and _boss.is_hittable(), "and he still surfaces, hittable")
	await _fight_rig(func(boss: BlindBeastBoss) -> void: boss.ridge_words = PackedStringArray())
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	check(_boss.get_attack() == BlindBeastBoss.Attack.ERUPTION, "an empty list falls back to the eruption too")
	await _fight_rig(func(boss: BlindBeastBoss) -> void:
		boss.ridge_words = PackedStringArray([""])
		boss.weights_phase_two = PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]))
	_boss._phase = 2
	_boss.register_noise(100.0, &"test")
	var drawn := await _wait_until(func() -> bool: return _boss.get_state() == BossEnemy.State.ATTACK, 6.0)
	check(drawn and _boss.get_attack() == BlindBeastBoss.Attack.ERUPTION, "a drawn ridge with no valid word becomes an eruption")
	var surfaced := await _wait_until(func() -> bool: return _boss.is_exposed(), 3.0)
	check(surfaced and _boss.is_hittable() and _boss._pending_noise_index() == -1, "the noise is answered and he is hittable: no soft-lock")


func case_ridge_fits_narrow_arena() -> void:
	await _fight_rig()
	_boss.set_arena_limits(-100.0, 100.0)
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	var slots := _boss.get_ridge_slots()
	check(slots.size() > 0 and slots.size() <= 10, "a pattern longer than the arena is cut to what fits (%d slots)" % slots.size())
	var inside := true
	for slot: Dictionary in slots:
		inside = inside and float(slot["x"]) - float(slot["width"]) * 0.5 >= -100.0 - 0.01 and float(slot["x"]) + float(slot["width"]) * 0.5 <= 100.0 + 0.01 and float(slot["width"]) >= BlindBeastBoss.MIN_SLOT_WIDTH
	check(inside, "every slot rectangle lies inside the limits")
	_boss.ridge_words = PackedStringArray(["LUZ", "L"])
	check(_boss._ridge_pattern(10) == "###...", "a word that fits is preferred over cutting a longer one")
	_boss.set_arena_limits(-37.0, 41.0)
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	await _frames(2)
	var odd := _boss.get_ridge_slots()
	check(not odd.is_empty() and float(odd[0]["x"]) - float(odd[0]["width"]) * 0.5 >= -37.0 - 0.01 and float(odd[odd.size() - 1]["x"]) + float(odd[odd.size() - 1]["width"]) * 0.5 <= 41.0 + 0.01, "an off-centre narrow arena is respected as well")
	_boss.set_arena_limits(-7.0, 7.0)
	_boss.start_attack(BlindBeastBoss.Attack.BRAILLE_RIDGE)
	check(_boss.get_ridge_slots().is_empty() and _boss.get_attack() == BlindBeastBoss.Attack.ERUPTION, "an arena too narrow for one slot skips the ridge")


## An arena beast beaten and its room reloaded: a second arena and beast with the
## same enemy_id must come up as the same harmless corpse.
func case_corpse_restored_on_reload() -> void:
	await _build_rig()
	await _arena_beast()
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _wait_until(func() -> bool: return _arena.get_state() == BossArena.FightState.ACTIVE, 2.0)
	await _frames(40)
	_boss._surface()
	_hit(21)
	await _frames(20)
	_boss._surface()
	check(_boss.has_light_overlay() and _boss.receive_hit(99, HIT_FROM, &"attack_1"), "the first beast falls in its last phase, dimmed")
	await _frames(90)
	check(_progress().is_defeated(BOSS_ID), "BossProgress holds the defeat")
	_boss = null
	_arena.free()
	await _arena_beast()
	check(_arena.get_boss() == _boss and _arena.get_state() == BossArena.FightState.DEFEATED, "the second arena starts defeated")
	await _check_inert_corpse()


func case_corpse_made_before_entering_the_tree() -> void:
	await _build_rig()
	_boss.get_parent().remove_child(_boss)
	_boss.free()
	_boss = _make_boss()
	_boss.make_corpse_at(Vector2(120.0, 0.0), -1)
	check(_boss.is_dead(), "outside the tree it is already dead")
	_rig.add_child(_boss)
	await _frames(3)
	await _check_inert_corpse()


## Nine checks: the end state of a beast that was beaten earlier.
func _check_inert_corpse() -> void:
	check(_boss.is_dead() and _boss.get_state() == BossEnemy.State.DEFEATED, "it is dead and defeated from the start")
	check(_boss._visual.visible and _boss._visual.position.y == 0.0, "the body lies visible above ground")
	check(not _boss._mound_visible(), "no dirt mound")
	check(_boss.hazard_count() == 0 and not _boss.has_light_overlay(), "no hazard and no dim overlay")
	check(not _boss.is_hittable() and _boss.collision_layer == 0, "it is not hittable")
	var health := _boss.get_health()
	check(not _hit() and _boss.get_health() == health, "it refuses hits")
	_player.set_physics_process(true)
	_player.global_position = Vector2(-200.0, -150.0)
	await _secs(1.0)
	check(_boss.get_noise_xs().is_empty(), "Luz landing records no noise")
	_luz_swings()
	await _frames(4)
	_player.open_eyes_activated.emit()
	check(_boss.get_noise_xs().is_empty(), "a swing and Hyperfocus record no noise either")
	_luz_idles()
	_boss.start_attack(BlindBeastBoss.Attack.ERUPTION)
	await _secs(0.5)
	check(_boss.get_state() == BossEnemy.State.DEFEATED and _boss.get_attack() == BossEnemy.NO_ATTACK and _boss.hazard_count() == 0, "it never starts an attack")

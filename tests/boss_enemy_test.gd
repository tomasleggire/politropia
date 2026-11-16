extends SceneTree
## BossEnemy base: engage gating, the attack lifecycle, weighted draws, phases
## (health and event driven), stun, interrupt, hittable states, the final blow,
## the corpse, reset, and the integration with a real BossArena.
## Run: godot --headless --path . --script res://tests/boss_enemy_test.gd
## Exits 0 when every check passes, 1 otherwise.

const ARENA_SCENE := "res://scenes/enemies/bosses/boss_arena.tscn"
const BOSS_SCENE := "res://tests/support/dummy_boss.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PROJECTILE_SCENE := "res://scenes/enemies/bosses/artemis_arrow.tscn"
const WATCHDOG_SECONDS := 120.0
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LUZ_START := Vector2(-400.0, 0.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const BOSS_AT := Vector2(300.0, 0.0)
const ARENA_RECT := Rect2(-434.0, -340.0, 868.0, 400.0)
const HIT_FROM := Vector2(100.0, 0.0)
const ROOM := &"A"
const BOSS_ID := &"test_dummy_boss"
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.3, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const CHECKS := {
	"case_untouchable_until_engage": 8,
	"case_telegraph_lifecycle": 11,
	"case_weighted_draw": 6,
	"case_health_phases": 12,
	"case_big_hit_crosses_two_thresholds": 3,
	"case_event_driven_phases": 6,
	"case_phase_beat_waits_for_active_strike": 8,
	"case_phase_beat_waits_for_stun": 6,
	"case_phase_beat_during_telegraph": 4,
	"case_stagger": 8,
	"case_stun": 11,
	"case_interrupt_and_super_armor": 6,
	"case_hittable_states_and_root_layer": 9,
	"case_no_recoil": 3,
	"case_projectile_pool": 6,
	"case_final_blow_and_corpse": 11,
	"case_reset_to_fresh": 12,
	"case_arena_integration": 20,
	"case_corpse_restored_on_reload": 17,
	"case_corpse_made_before_entering_the_tree": 8,
	"case_bar_extra_notch_range": 3,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player
var _boss: DummyBoss
var _arena: BossArena
var _phases_seen: Array[int] = []
var _signals: Array[String] = []


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


func _music_stream() -> AudioStream:
	var player := root.get_node("MusicManager").get("_player") as AudioStreamPlayer
	return player.stream


func _build_rig(engage := true, configure := Callable()) -> void:
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
	_boss = _make_boss()
	_boss.position = BOSS_AT
	if configure.is_valid():
		configure.call(_boss)
	_rig.add_child(_boss)
	if engage:
		_boss.set_manual_engage(true)


func _make_boss() -> DummyBoss:
	var boss := (load(BOSS_SCENE) as PackedScene).instantiate() as DummyBoss
	boss.rng_seed = 7
	boss.hit_stop_time = 0.0
	boss.final_freeze_time = 0.0
	boss.final_slowmo_time = 0.0
	boss.phase_transition_time = 0.3
	boss.defeat_time = 0.2
	return boss


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


func _frames(n: int) -> void:
	for i: int in n:
		await physics_frame


## Physics seconds (the boss accumulates its timers in physics time).
func _secs(t: float) -> void:
	await _frames(ceili(t * 60.0))


func _hit(damage := 1) -> bool:
	return _boss.receive_hit(damage, HIT_FROM, &"attack_1")


func _hits(n: int) -> void:
	for i: int in n:
		_hit()


func _awake_boss() -> void:
	await _build_rig()
	await _frames(3)
	_boss.engage()


func _record_phases() -> void:
	_phases_seen.clear()
	_boss.phase_changed.connect(func(phase: int) -> void: _phases_seen.append(phase))


## An engaged 30 HP boss with one threshold at 0.66: a single 11 damage hit crosses it.
func _phased_boss() -> void:
	await _build_rig()
	_boss.phase_thresholds = PackedFloat32Array([0.66])
	await _frames(3)
	_boss.engage()
	_record_phases()
	_signals.clear()
	_boss.sfx_cue.connect(func(cue: StringName) -> void: _signals.append("cue:" + String(cue)))


func _until_attack_phase(attack_phase: BossEnemy.AttackPhase) -> void:
	var frames := 0
	while _boss.get_attack_phase() != attack_phase and frames < 240:
		await physics_frame
		frames += 1


func _until_state_changes_from(state: BossEnemy.State) -> void:
	var frames := 0
	while _boss.get_state() == state and frames < 240:
		await physics_frame
		frames += 1


## Puts `boss` under a fresh test arena (moving it out of its parent) and adds the
## arena to the rig.
func _wrap_boss_in_arena(boss: DummyBoss) -> BossArena:
	if boss.get_parent() != null:
		boss.get_parent().remove_child(boss)
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate() as BossArena
	arena.arena_rect = ARENA_RECT
	for key: String in ARENA_TIMINGS:
		arena.set(key, ARENA_TIMINGS[key])
	arena.boss_name = "Test Boss"
	arena.reward_enabled = false
	arena.add_child(boss)
	boss.position = BOSS_AT
	_rig.add_child(arena)
	return arena


# -- Cases ------------------------------------------------------------------------------

func case_untouchable_until_engage() -> void:
	await _build_rig()
	await _frames(3)
	check(_boss.get_state() == BossEnemy.State.IDLE, "an awaiting boss is idle")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "an awaiting boss refuses hits")
	check(_boss.get_health() == _boss.max_health, "a refused hit costs no health")
	check(_boss.is_fresh(), "an idle full-health boss is fresh")
	await _secs(1.5)
	check(_boss.get_state() == BossEnemy.State.IDLE, "it does not wake by itself under manual engage")
	_boss.engage()
	check(_boss.get_state() == BossEnemy.State.FIGHT, "engage() starts the fight")
	check(_hit(), "an engaged boss takes hits")
	check(not _boss.is_fresh(), "a fighting boss is no longer fresh")


func case_telegraph_lifecycle() -> void:
	await _awake_boss()
	_boss.auto_attack = false
	_boss.start_attack(DummyBoss.Attack.POKE)
	check(_boss.is_telegraphing(), "start_attack begins in the telegraph")
	check(_boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH - 0.001, "a 0.1 s telegraph is raised to the minimum")
	var frames := 0
	while _boss.get_attack_phase() == BossEnemy.AttackPhase.TELEGRAPH and frames < 120:
		await physics_frame
		frames += 1
	check(float(frames) / 60.0 >= BossEnemy.MIN_TELEGRAPH - 0.02, "the telegraph lasted at least 0.35 s (%d frames)" % frames)
	check(_boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE, "the telegraph is followed by the active phase")
	await _secs(0.15)
	check(_boss.get_attack_phase() == BossEnemy.AttackPhase.RECOVER, "the active phase is followed by the recovery")
	await _secs(0.3)
	check(_boss.get_state() == BossEnemy.State.FIGHT, "the recovery returns to the fight")
	var expected: Array[String] = ["begin:0:0", "end:0:0", "begin:0:1", "end:0:1", "begin:0:2", "end:0:2"]
	check(_boss.events == expected, "every phase hook ran once, in order: %s" % [_boss.events])
	check(_boss.get_attack() == DummyBoss.Attack.POKE, "the attack id is kept")
	# A longer telegraph is left alone.
	_boss.start_attack(DummyBoss.Attack.SLAM)
	check(_boss.get_state_time_left() > 0.45, "a telegraph above the minimum keeps its length")
	_boss.start_attack(DummyBoss.Attack.POKE)
	check(_boss.events.has("end:1:0"), "starting an attack closes the one in progress")
	_boss.auto_attack = true
	_boss.fight_delay_min = 0.0
	_boss.fight_delay_max = 0.0
	await _secs(2.0)
	check(_boss.events.size() > 12, "with auto_attack the fight loop starts attacks by itself")


func case_weighted_draw() -> void:
	await _awake_boss()
	var weights := PackedFloat32Array([1.0, 1.0])
	_boss.start_attack(DummyBoss.Attack.POKE)
	var repeats := 0
	for i: int in 30:
		if _boss._draw_attack(weights) == DummyBoss.Attack.POKE:
			repeats += 1
	check(repeats == 0, "the draw never repeats the last attack when another is possible")
	check(_boss._draw_attack(PackedFloat32Array([1.0, 0.0])) == DummyBoss.Attack.POKE, "a lone weighted attack may repeat")
	check(_boss._draw_attack(PackedFloat32Array([0.0, 0.0])) == BossEnemy.NO_ATTACK, "all-zero weights draw nothing")
	_boss.start_attack(DummyBoss.Attack.SLAM)
	var picks := {}
	for i: int in 20:
		picks[_boss._draw_attack(PackedFloat32Array([1.0, 1.0, 1.0]))] = true
	check(not picks.has(DummyBoss.Attack.SLAM) and picks.has(0) and picks.has(2), "an attack with a weight beyond the enum is drawn too")
	_boss.rng.seed = 99
	var first: Array[int] = []
	for i: int in 8:
		first.append(_boss._draw_attack(PackedFloat32Array([1.0, 1.0, 1.0])))
	_boss.rng.seed = 99
	var second: Array[int] = []
	for i: int in 8:
		second.append(_boss._draw_attack(PackedFloat32Array([1.0, 1.0, 1.0])))
	check(first == second, "a seeded rng gives a deterministic sequence")
	check(_boss.rng_seed == 7, "the rng_seed export is honoured")


func case_health_phases() -> void:
	await _build_rig()
	_boss.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	await _frames(3)
	_boss.engage()
	_record_phases()
	check(is_equal_approx(_boss.phase_two_threshold, 0.66), "phase_two_threshold is the first threshold")
	check(is_equal_approx(float(_boss.get("phase_two_threshold")), 0.66), "the arena reads it by property name")
	_hits(10)
	check(_phases_seen.is_empty() and _boss.get_phase() == 1, "above the first threshold nothing changes")
	_hit()
	check(_phases_seen == [2], "the first threshold emits phase_changed(2) once")
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "the transition beat starts at once from the fight")
	_boss.fight_delay_min = 0.0
	_boss.fight_delay_max = 0.0
	_boss.auto_attack = true
	await _secs(0.2)
	check(_boss.get_state() == BossEnemy.State.TRANSITION and _boss.events.is_empty(), "it does not attack during the beat")
	check(_hit(), "it stays hittable during the beat")
	await _secs(0.3)
	check(_boss.get_state() != BossEnemy.State.TRANSITION, "the beat ends")
	_boss.auto_attack = false
	_boss.start_attack(DummyBoss.Attack.POKE)
	_hits(9)
	check(_phases_seen == [2, 3], "the second threshold emits phase_changed(3) once")
	check(_boss.get_phase() == 3 and _boss.entered_phases == [2, 3], "_on_phase_entered ran for each phase")
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "a threshold crossed during a telegraph starts the beat at once")
	_hits(5)
	check(_phases_seen == [2, 3], "no phase beyond the last threshold")


func case_big_hit_crosses_two_thresholds() -> void:
	await _build_rig()
	_boss.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	await _frames(3)
	_boss.engage()
	_record_phases()
	_hit(25)
	check(_phases_seen == [2, 3], "one big hit crosses both thresholds in order")
	check(_boss.get_phase() == 3, "the phase is the last one")
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "a single beat is queued for both")


func case_event_driven_phases() -> void:
	await _build_rig()
	_boss.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	_boss.phases_from_health = false
	await _frames(3)
	_boss.engage()
	_record_phases()
	_hit(28)
	check(_phases_seen.is_empty() and _boss.get_phase() == 1, "health does not move the phase when phases_from_health is off")
	check(is_equal_approx(_boss.phase_two_threshold, 0.66), "the thresholds are still exposed for the bar")
	_boss._advance_phase()
	check(_phases_seen == [2] and _boss.get_phase() == 2, "_advance_phase performs the same change as a crossing")
	await _frames(2)
	check(_boss.get_state() == BossEnemy.State.TRANSITION and _boss.entered_phases == [2], "it queues the beat and calls _on_phase_entered")
	_boss._enter_phase(2)
	check(_phases_seen == [2], "entering the current phase again is ignored")
	_boss._enter_phase(4)
	check(_phases_seen == [2, 4], "a subclass may jump to any later phase")


func case_phase_beat_waits_for_active_strike() -> void:
	await _phased_boss()
	_boss.active_time = 0.5
	_boss.start_attack(DummyBoss.Attack.SLAM)
	await _until_attack_phase(BossEnemy.AttackPhase.ACTIVE)
	_hit(11)
	check(_phases_seen == [2] and _boss.entered_phases == [2], "the crossing announces the phase at once")
	check(_boss.get_state() == BossEnemy.State.ATTACK and _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE, "the beat does not cut a strike in its active phase")
	await _secs(0.2)
	check(_boss.get_state() == BossEnemy.State.ATTACK and _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE, "the strike is still active and the beat still waits")
	await _until_attack_phase(BossEnemy.AttackPhase.RECOVER)
	check(_boss.get_state() == BossEnemy.State.ATTACK and _boss.get_attack_phase() == BossEnemy.AttackPhase.RECOVER, "the beat does not start on the frame the strike ends")
	await _frames(1)
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "the beat starts on the next think once the active phase ended")
	check(_boss.events.count("end:1:1") == 1 and _boss.events.count("end:1:2") == 1, "the active phase ended once, then the recovery was closed once by the beat")
	check(not _boss.stun(0.3), "a stun is refused during the beat")
	await _secs(0.5)
	check(_boss.get_state() == BossEnemy.State.FIGHT and _signals.count("cue:PhaseChange") == 1, "one beat ran and the boss is back in the fight")


func case_phase_beat_waits_for_stun() -> void:
	await _phased_boss()
	_boss.start_attack(DummyBoss.Attack.SLAM)
	check(_boss.stun(0.5), "the boss is stunned")
	_hit(11)
	check(_phases_seen == [2], "the crossing announces the phase at once")
	check(_boss.get_state() == BossEnemy.State.STUN, "the crossing does not end the stun")
	await _secs(0.3)
	check(_boss.get_state() == BossEnemy.State.STUN and not _signals.has("cue:PhaseChange"), "the beat has not started while the stun runs")
	await _until_state_changes_from(BossEnemy.State.STUN)
	check(_boss.get_state() == BossEnemy.State.FIGHT and _boss.stun_ended_count == 1, "the stun ends first and the beat is still pending")
	await _frames(1)
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "the beat starts on the next think after the stun")


func case_phase_beat_during_telegraph() -> void:
	await _phased_boss()
	_boss.start_attack(DummyBoss.Attack.SLAM)
	check(_boss.is_telegraphing(), "the attack is winding up")
	_hit(11)
	check(_boss.get_state() == BossEnemy.State.TRANSITION, "a crossing during a telegraph starts the beat inside the hit")
	check(_boss.events.count("end:1:0") == 1 and _phases_seen == [2], "the wind-up was closed once and the phase announced once")
	await _secs(0.5)
	check(_boss.get_state() == BossEnemy.State.FIGHT and _signals.count("cue:PhaseChange") == 1, "the beat ends back in the fight with a single beat")


func case_stagger() -> void:
	await _awake_boss()
	_boss.stagger_hits = 3
	_boss.stagger_window = 0.5
	_boss.stagger_time = 0.4
	var cues: Array[StringName] = []
	_boss.sfx_cue.connect(func(cue: StringName) -> void: cues.append(cue))
	_boss.start_attack(DummyBoss.Attack.SLAM)
	_hits(2)
	check(_boss.get_state() == BossEnemy.State.ATTACK and _boss.is_telegraphing(), "two hits inside the window do not stagger")
	_hit()
	check(_boss.get_state() == BossEnemy.State.STAGGER, "the third hit inside the window staggers the boss")
	check(_boss.events.count("end:1:0") == 1, "the stagger cut the running attack and its phase hook ran once")
	check(cues.count(&"Stagger") == 1, "the Stagger cue fired once")
	await _secs(0.2)
	check(_boss.get_state() == BossEnemy.State.STAGGER, "the boss stays staggered for stagger_time")
	await _secs(0.3)
	check(_boss.get_state() == BossEnemy.State.FIGHT, "the boss returns to the fight afterwards")
	for i: int in 4:
		_hit()
		await _secs(0.4)
	check(_boss.get_state() == BossEnemy.State.FIGHT and cues.count(&"Stagger") == 1, "hits spread wider than the window never stagger")
	_boss.stagger_hits = 0
	_hits(5)
	check(_boss.get_state() == BossEnemy.State.FIGHT and cues.count(&"Stagger") == 1, "stagger_hits = 0 never staggers")


func case_stun() -> void:
	await _awake_boss()
	check(not _boss.stun(0.0), "a zero stun is refused")
	_boss.start_attack(DummyBoss.Attack.SLAM)
	await _secs(0.1)
	check(_boss.stun(0.4), "stun applies mid-attack")
	check(_boss.get_state() == BossEnemy.State.STUN and _boss.is_stunned(), "the boss is stunned")
	check(_boss.events.has("end:1:0"), "the cut attack phase was closed")
	check(_boss.stun_count == 1, "_on_stunned ran once")
	check(_hit(), "a stunned boss takes hits")
	check(_boss.get_state() == BossEnemy.State.STUN, "a hit does not end the stun")
	await _secs(0.5)
	check(_boss.get_state() == BossEnemy.State.FIGHT and _boss.stun_ended_count == 1, "the stun ends back in the fight")
	check(_boss.stun(0.4) and _boss.get_state() == BossEnemy.State.STUN and _boss.stun_count == 2, "a stun applies again from the fight")
	check(_boss.stun(1.0) and _boss.get_state_time_left() > 0.9 and _boss.stun_count == 2, "a longer stun extends the running one without running _on_stunned again")
	await _build_rig()
	await _frames(3)
	check(not _boss.stun(0.4), "an awaiting boss cannot be stunned")


func case_interrupt_and_super_armor() -> void:
	await _awake_boss()
	var interrupted: Array[int] = []
	_boss.attack_interrupted.connect(func(attack: int) -> void: interrupted.append(attack))
	check(_boss.super_armor, "telegraphs are uninterruptible by default")
	_boss.start_attack(DummyBoss.Attack.SLAM)
	_hit()
	check(_boss.is_telegraphing() and interrupted.is_empty(), "super armor keeps the telegraph")
	_boss.super_armor = false
	_hit()
	check(_boss.get_state() == BossEnemy.State.FLINCH and interrupted == [DummyBoss.Attack.SLAM], "without armor a hit during a telegraph flinches and reports it")
	await _secs(0.4)
	check(_boss.get_state() == BossEnemy.State.FIGHT, "the flinch ends back in the fight")
	_boss.start_attack(DummyBoss.Attack.SLAM)
	_hit()
	check(_boss.is_telegraphing(), "poise holds the next telegraph after an interrupt")
	check(_boss.events.has("end:1:0"), "the interrupted phase was closed")


func case_hittable_states_and_root_layer() -> void:
	await _awake_boss()
	check(_boss.collision_layer == Enemy.ENEMY_LAYER, "the root is on the enemy layer by default")
	_boss._set_hittable(false)
	check(not _boss.is_hittable() and _boss.collision_layer == 0, "not hittable clears the layer")
	check(not _hit(), "an untargetable boss refuses hits (body or part)")
	_boss._set_hittable(true)
	check(_boss.collision_layer == Enemy.ENEMY_LAYER and _hit(), "hittable again restores the layer and the hits")
	_boss.refuse_hits = true
	check(not _hit(), "_accepts_hit can refuse a hit")
	_boss.refuse_hits = false
	# A multi-part boss: the root layer is 0 and parts forward the damage.
	await _build_rig(true, func(boss: DummyBoss) -> void: boss.root_layer_value = 0)
	await _frames(3)
	check(_boss.collision_layer == 0, "a root that is never hit starts with layer 0")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "a forwarded hit before the arena engages is refused")
	_boss.engage()
	var part := Area2D.new()
	_boss.add_child(part)
	check(part.get_parent().receive_hit(1, HIT_FROM, &"attack_1") and _boss.get_health() == _boss.max_health - 1, "a part forwarding damage works through the base")
	_boss.receive_hit(1, HIT_FROM, &"attack_1")
	_boss.reset_to_spawn()
	check(_boss.collision_layer == 0 and _boss.get_health() == _boss.max_health, "reset restores the subclass hittable layer")


func case_no_recoil() -> void:
	await _awake_boss()
	var before := _boss.global_position
	_boss.receive_hit(1, Vector2(200.0, 0.0), &"")
	await _frames(15)
	check(absf(_boss.global_position.x - before.x) < 0.5, "a hit never pushes the boss")
	check(_boss.velocity.x == 0.0, "its velocity stays zero")
	check(_boss._recoil_left == 0.0, "no recoil timer runs")


func case_projectile_pool() -> void:
	await _awake_boss()
	var scene := load(PROJECTILE_SCENE) as PackedScene
	var shot := _boss._launch_projectile(scene, _boss.global_position + Vector2(0.0, -30.0), Vector2.LEFT, 200.0)
	await _frames(2)
	check(shot.is_active() and _boss.active_projectile_count() == 1, "a launched projectile is active")
	check(shot.get_parent() == _boss.get_parent(), "projectiles are re-parented beside the boss")
	check(shot.top_level and not shot.breakable_by_attacks, "projectiles are top level and follow the Artemis defaults")
	_boss.clear_projectiles()
	check(_boss.active_projectile_count() == 0, "clear_projectiles parks them all")
	var again := _boss._launch_projectile(scene, _boss.global_position, Vector2.UP, 100.0)
	check(again == shot, "a parked projectile is reused")
	_boss.free()
	await _frames(2)
	check(not is_instance_valid(shot), "freeing the boss frees its projectiles")
	_boss = null


func case_final_blow_and_corpse() -> void:
	await _build_rig()
	_boss.final_freeze_time = 0.05
	_boss.final_slowmo_time = 0.15
	_boss.defeat_time = 0.2
	await _frames(3)
	_boss.engage()
	_signals.clear()
	_boss.died.connect(func(_enemy: Enemy) -> void: _signals.append("died"))
	_boss.defeated.connect(func() -> void: _signals.append("defeated"))
	_boss.corpse_settled.connect(func() -> void: _signals.append("settled"))
	_boss.sfx_cue.connect(func(cue: StringName) -> void: _signals.append("cue:" + String(cue)))
	_boss.start_attack(DummyBoss.Attack.SLAM)
	_boss.max_health = 30
	check(_boss.receive_hit(99, HIT_FROM, &"attack_1"), "the killing blow lands")
	check(_signals.has("died") and _signals.has("defeated"), "died and defeated are emitted")
	check(_signals.has("cue:Defeat"), "the Defeat cue fires")
	check(BossFeel.is_active() and Engine.time_scale < 1.0, "the slow motion starts")
	check(_boss.is_dead() and _boss.collision_layer == 0, "the boss is a corpse without collision")
	check(_boss.hazard_clears >= 1 and _boss.events.has("end:1:0"), "defeat cleared the hazards and closed the attack")
	var restored := await _wait_real(func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 3.0)
	check(restored, "the slow motion ends and the clock is back to 1.0")
	await _secs(1.0)
	check(_signals.has("settled"), "corpse_settled fires once the corpse rests")
	check(not _boss.is_physics_processing(), "a settled corpse stops processing")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "a corpse takes no hits")
	check(_boss.is_on_floor() and absf(_boss.global_position.y) <= 1.0, "the corpse rests on the floor")


func _wait_real(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func case_reset_to_fresh() -> void:
	await _build_rig()
	_boss.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	_boss.stagger_hits = 0
	await _frames(3)
	_boss.engage()
	_record_phases()
	_boss.start_attack(DummyBoss.Attack.SLAM)
	_hit(25)
	var clears := _boss.hazard_clears
	_boss.reset_to_spawn()
	check(_boss.get_health() == _boss.max_health, "reset restores full health")
	check(_boss.get_phase() == 1, "reset returns to phase one")
	check(_boss.is_fresh(), "reset leaves the boss fresh")
	check(_boss.get_state() == BossEnemy.State.IDLE, "reset leaves it idle")
	check(_boss.hazard_clears > clears, "reset asked the subclass to clear its hazards")
	check(_phases_seen.back() == 1, "reset announces phase one again")
	check(not _hit(), "after a reset the boss waits for the arena again")
	check(_boss.global_position.distance_to(BOSS_AT) < 0.5, "reset returns it to the spawn")
	_boss.engage()
	check(_hit(), "after a new engage the boss takes hits")
	_boss.receive_hit(99, HIT_FROM, &"attack_1")
	check(_boss.is_dead(), "the boss can die")
	_boss.reset_to_spawn()
	check(not _boss.is_dead() and _boss.collision_layer == Enemy.ENEMY_LAYER, "reset revives a corpse on the enemy layer")
	await _frames(3)
	check(_boss.is_physics_processing() and _boss.is_fresh(), "a revived corpse processes and is fresh again")


func case_arena_integration() -> void:
	await _build_rig(false)
	_boss.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	_arena = _wrap_boss_in_arena(_boss)
	await _frames(20)
	var completion := root.get_node("GameCompletion")
	check(_arena.get_boss() == _boss and _arena.get_state() == BossArena.FightState.ARMED, "the arena finds the boss and is armed")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "the boss is untouchable before the fight")
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(15)
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "entering the trigger starts the fight")
	check(_arena.get_bar().get_name_text() == "Test Boss", "the bar carries the custom boss name")
	check(is_equal_approx(_arena.get_bar().get_notch_ratio(), 0.66), "the bar notch is the first threshold")
	check(_arena.get_bar().get_extra_notch_ratios() == PackedFloat32Array([0.33]), "the bar gets a notch for each further threshold")
	check(_music_stream() == root.get_node("MusicManager").BOSS_MUSIC, "the boss music plays during the fight")
	await _frames(40)
	check(_boss.get_state() != BossEnemy.State.IDLE, "the arena engaged the boss")
	check(_arena.are_doors_closed(), "the doors are closed during the fight")
	_boss.receive_hit(99, HIT_FROM, &"attack_1")
	await _frames(60)
	check(_arena.get_state() == BossArena.FightState.DEFEATED, "defeat ends the fight")
	check(not _arena.are_doors_closed(), "defeat opens the arena")
	check(_arena.get_reward() == null, "no reward spawns with reward_enabled off")
	check(not completion.is_active(), "a non-final boss does not trigger the game completion")
	check(_progress().is_defeated(BOSS_ID), "BossProgress marks the boss defeated under its enemy_id")
	check(_music_stream() == root.get_node("MusicManager").GAMEPLAY_MUSIC, "gameplay music is requested when the arena opens")
	check(_arena.get_boss_reset_count() == 0, "the arena never had to reset the boss")
	var corpse: Dictionary = _progress().get_corpse(BOSS_ID)
	check(corpse.has("position"), "the corpse spot was stored")
	check(_boss.is_dead(), "the boss stays a corpse")
	check(not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "it left the checkpoint contract")
	check(root.get_node("BossProgress").to_dict().size() > 0, "the progress is serializable")


## A room reload: the boss was beaten inside an arena, then a second arena and boss
## with the same enemy_id appear (the registry and the arena both restore the corpse).
func case_corpse_restored_on_reload() -> void:
	await _build_rig(false)
	_arena = _wrap_boss_in_arena(_boss)
	await _frames(10)
	_boss.engage()
	check(_boss.receive_hit(99, HIT_FROM, &"attack_1"), "the first boss falls inside its arena")
	await _frames(60)
	check(_progress().is_defeated(BOSS_ID), "BossProgress holds the defeat")
	var corpse: Dictionary = _progress().get_corpse(BOSS_ID)
	_arena.free()
	_boss = _make_boss()
	_arena = _wrap_boss_in_arena(_boss)
	_boss.auto_attack = true
	await _frames(10)
	check(_boss.is_dead() and _boss.get_state() == BossEnemy.State.DEFEATED, "the reloaded boss is dead and defeated from the start")
	check(_boss.collision_layer == 0, "its root collision layer is 0")
	check(not _hit(), "it refuses hits")
	check(_boss.get_health() == _boss.max_health, "a refused hit changes nothing")
	_boss.start_attack(DummyBoss.Attack.POKE)
	await _frames(60)
	check(_boss.get_state() == BossEnemy.State.DEFEATED and _boss.get_attack() == BossEnemy.NO_ATTACK and _boss.events.is_empty(), "it never starts an attack")
	check(_boss.active_projectile_count() == 0 and _rig.find_children("*", "EnemyProjectile", true, false).is_empty(), "no projectile exists")
	check(_boss.global_position.distance_to(corpse["position"]) < 1.5, "it lies where the first one fell")
	check(not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "it is outside the checkpoint contract")
	check(_arena.get_boss() == _boss and _arena.get_state() == BossArena.FightState.DEFEATED, "the arena is in its defeated state")
	check(not _arena.is_trigger_armed(), "the trigger is disabled")
	check(not _arena.are_doors_closed(), "the doors are open")
	check(not _arena.get_bar().is_bar_shown(), "the bar is hidden")
	check(_arena.get_reward() == null, "no reward is spawned with reward_enabled off")
	_player.global_position = IN_TRIGGER
	_player.velocity = Vector2.ZERO
	await _frames(20)
	check(_arena.get_state() == BossArena.FightState.DEFEATED and not _arena.are_doors_closed(), "Luz walking into the old trigger starts nothing")
	await _secs(0.5)
	check(not _boss.is_physics_processing(), "the restored corpse settled and stopped processing")


## The registry restores a corpse while the base `_ready` is still running, but a
## caller may also do it before the boss enters the tree at all.
func case_corpse_made_before_entering_the_tree() -> void:
	await _build_rig(false)
	var boss := _make_boss()
	boss.enemy_id = &"test_dummy_boss_direct"
	boss.make_corpse_at(Vector2(120.0, 0.0), -1)
	check(boss.is_dead() and boss.get_state() == BossEnemy.State.IDLE, "outside the tree it is dead and the state machine has not started")
	_rig.add_child(boss)
	_boss = boss
	await _frames(3)
	check(boss.is_dead() and boss.get_state() == BossEnemy.State.DEFEATED, "once ready it ends in the defeated state")
	check(boss.collision_layer == 0 and boss.get_facing() == -1, "it has no collision and keeps its facing")
	check(boss._contact != null and not boss._contact.monitoring, "its contact damage is off")
	check(not boss.receive_hit(1, HIT_FROM, &"attack_1"), "it refuses hits")
	check(boss.global_position.distance_to(Vector2(120.0, 0.0)) < 1.5, "it rests where it was put")
	await _secs(0.6)
	check(not boss.is_physics_processing(), "it settles and stops processing")
	check(boss.get_active_projectiles().is_empty() and boss.events.is_empty(), "it started nothing")


func case_bar_extra_notch_range() -> void:
	await _build_rig(false)
	var bar := (load("res://scenes/ui/boss_health_bar.tscn") as PackedScene).instantiate() as BossHealthBar
	_rig.add_child(bar)
	var ratios := PackedFloat32Array([0.25, 1.5, -0.1, 0.0, 1.0, 0.75])
	bar.setup("Test", 10, 0.5, ratios)
	var shown: Array[bool] = []
	for notch: ColorRect in bar._extra_notches:
		shown.append(notch.visible)
	check(shown == [true, false, false, false, false, true], "only extra notches strictly between 0 and 1 are shown: %s" % [shown])
	check(bar.get_extra_notch_ratios() == ratios, "get_extra_notch_ratios still returns what setup received")
	bar.setup("Test", 10, 0.5, PackedFloat32Array([0.4, 0.2]))
	shown.clear()
	for notch: ColorRect in bar._extra_notches:
		shown.append(notch.visible)
	check(shown == [true, true, false, false, false, false], "a later setup with in-range ratios shows them and hides the unused ones")
	bar.free()

extends SceneTree
## La Hidra: the one-drag prefab and its platforms, the head parts (hurtboxes,
## shared pool, severing), enrage, the three head attacks and their intended
## avoidance, reachability of every head from the platforms with the player's real
## numbers, the pacing per phase, reset, the final blow, the corpse and the arena
## integration.
## Run: godot --headless --path . --script res://tests/hydra_boss_test.gd
## Exits 0 when every check passes, 1 otherwise. Case names after `--` run alone
## (`-- case_real_attack_hits_heads`); such a partial run is judged on its cases only.

const ARENA_SCENE := "res://scenes/enemies/bosses/hydra_boss_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 420.0
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LUZ_START := Vector2(-400.0, 0.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const HIT_FROM := Vector2(100.0, 0.0)
const BOSS_ID := &"greece_hydra"
const LUZ_HEALTH := 30
const ART_DIR := "user://hydra_art_fixture"
const ART_MANIFEST := ART_DIR + "/animation_manifest.json"
const NO_ART_MANIFEST := ART_DIR + "/missing.json"
const ART_CELL := 4
const ART_COLUMNS := 4
const ART_BODY_OFFSET := Vector2(0.0, -288.0)
const ART_SCALE := 0.2896
const ART_NECK := 18.0
## Frames of every clip of the fixture sheets (a clip of a head sheet is written once per head).
const FIXTURE_BODY_CLIPS := {"idle": 2, "roar": 2, "defeat": 3}
const FIXTURE_HEAD_CLIPS := {"idle": 2, "telegraph": 1, "attack": 2, "roar": 1, "dazed": 1}
## Content boxes (sheet px) the fixture manifest declares for the props.
const FIXTURE_PROPS := {
	"stump": [60, 40], "venom_glob": [40, 40], "venom_pool": [200, 40],
	"venom_splash": [100, 60], "platform": [320, 60], "platform_alt": [320, 70],
}
const FIXTURE_PROP_FRAMES := {"venom_pool": 2}
const ART_ALL: Array[String] = ["body", "heads", "props", "neck"]
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.3, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const CHECKS := {
	"case_prefab_is_one_drag": 11,
	"case_layout_and_gate": 13,
	"case_damage_accounting": 9,
	"case_severing_and_enrage": 16,
	"case_bite_lunge": 13,
	"case_venom_volley": 13,
	"case_neck_sweep": 11,
	"case_reachability": 6,
	"case_pacing_per_phase": 14,
	"case_reset_mid_fight": 14,
	"case_defeat_and_arena": 16,
	"case_corpse_reload": 9,
	"case_stays_in_arena": 4,
	"case_real_attack_hits_heads": 9,
	"case_echo_telegraph_in_duo": 9,
	"case_sever_mid_attack": 25,
	"case_platforms_moved": 5,
	"case_platforms_removed": 5,
	"case_platforms_fallback": 3,
	"case_two_arenas": 4,
	"case_platform_shape_warnings": 4,
	"case_enrage_volley_count": 4,
	"case_enrage_sweep_timing": 6,
	"case_venom_release_in_callback": 5,
	"case_art_absent_keeps_the_placeholders": 8,
	"case_art_body_sprite_and_clips": 12,
	"case_art_defeat_and_corpse": 10,
	"case_art_heads_play_their_clips": 19,
	"case_art_neck_and_stump": 9,
	"case_art_venom_wears_sprites": 11,
	"case_art_platforms_are_dressed": 8,
	"case_art_pieces_are_independent": 9,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player
var _boss: HydraBoss
var _arena: BossArena
var _phases_seen: Array[int] = []
var _defeats := 0
var _settled := 0
var _tap: LogTap
var _only: PackedStringArray = []


## Collects the engine's errors and warnings while a case runs.
class LogTap extends Logger:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		var text := "%s %s" % [code, rationale]
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(text)
		else:
			errors.append(text)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_only = OS.get_cmdline_user_args()
	# A misspelled case name must fail the run instead of passing with zero checks.
	for requested: String in _only:
		if not CHECKS.has(requested):
			_problems.append("unknown case requested: %s" % requested)
	for case_name: String in CHECKS:
		if not _only.is_empty() and not _only.has(case_name):
			continue
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


## The prefab in a room with a floor, walls and Luz. `auto` lets the boss attack
## by itself; `defeated` marks the boss beaten before the arena loads (a reload).
## `manifest` is the art the boss reads: no art unless a case asks for the fixture, so the
## shipped sheets never change what the other cases measure.
func _build(auto := false, defeated := false, manifest := NO_ART_MANIFEST) -> void:
	_cleanup()
	root.get_node("CheckpointService").clear()
	_registry().clear()
	_progress().clear()
	_registry().room_resolver = func(_point: Vector2) -> StringName: return &"A"
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(-516.0, -600.0, 48.0, 600.0), Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(468.0, -600.0, 48.0, 600.0), Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = LUZ_START
	_rig.add_child(_player)
	_player.set_max_health(LUZ_HEALTH)
	_player.heal(LUZ_HEALTH)
	_player.set_checkpoint(LUZ_START)
	current_scene = _rig
	if defeated:
		_progress().mark_defeated(BOSS_ID, Vector2(400.0, 0.0), -1)
	_arena = (load(ARENA_SCENE) as PackedScene).instantiate() as BossArena
	for key: String in ARENA_TIMINGS:
		_arena.set(key, ARENA_TIMINGS[key])
	_boss = _arena.get_node("Hydra") as HydraBoss
	_boss.animation_manifest = manifest
	_boss.rng_seed = 7
	_boss.hit_stop_time = 0.0
	_boss.final_freeze_time = 0.0
	_boss.final_slowmo_time = 0.0
	_boss.phase_transition_time = 0.3
	_boss.defeat_time = 0.2
	_boss.auto_attack = auto
	_rig.add_child(_arena)


func _cleanup() -> void:
	_untap_logs()
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


## A rig with the boss engaged and settled, ready for a scripted attack.
func _awake(auto := false) -> void:
	await _build(auto)
	await _frames(3)
	_boss.engage()
	await _frames(2)


func _put_luz(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	await _frames(4)


func _platform_spot(platform_name: String) -> Vector2:
	var platform := _arena.get_node("Platforms/" + platform_name) as Node2D
	return platform.global_position + Vector2(0.0, -8.0)


func _tap_logs() -> void:
	_untap_logs()
	_tap = LogTap.new()
	OS.add_logger(_tap)


func _untap_logs() -> void:
	if _tap != null:
		OS.remove_logger(_tap)
		_tap = null


func _warnings_naming(text: String) -> int:
	var count := 0
	for warning: String in _tap.warnings:
		count += 1 if warning.contains(text) else 0
	return count


func _platform(platform_name: String) -> StaticBody2D:
	return _arena.get_node("Platforms/" + platform_name) as StaticBody2D


func _remove_platform(platform_name: String) -> void:
	var platform := _platform(platform_name)
	platform.get_parent().remove_child(platform)
	platform.free()


## Luz goes to `spot` facing right and swings once through her own attack path:
## the slash is the AttackHitbox overlap, resolved in the physics frames.
func _real_slash(spot: Vector2) -> void:
	await _put_luz(spot)
	_player.request_attack(0)
	await _secs(0.5)


## The venom spots currently painted on the ground.
func _marked_spots() -> int:
	var count := 0
	for venom: HydraVenom in _boss.get_active_venoms():
		count += 1 if venom.is_marker_visible() else 0
	return count


## Luz at full strength so long runs never end on her death.
func _tough_luz() -> void:
	_player.set_max_health(500)
	_player.heal(500)


func _head(kind: HydraHead.Kind) -> HydraHead:
	return _boss.get_head(kind)


func _slash(head: HydraHead, damage := 1) -> bool:
	return head.receive_hit(damage, HIT_FROM, &"attack_ground_1")


## Waits until `condition` holds or `limit` seconds pass; true when it held.
func _wait_for(condition: Callable, limit: float) -> bool:
	var frames := ceili(limit * 60.0)
	for i: int in frames:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _luz_hurt() -> bool:
	return _player.get_health() < LUZ_HEALTH


func _attack_is_over() -> bool:
	return _boss.get_state() != BossEnemy.State.ATTACK


func _record_signals() -> void:
	_phases_seen.clear()
	_defeats = 0
	_settled = 0
	_boss.phase_changed.connect(func(phase: int) -> void: _phases_seen.append(phase))
	_boss.defeated.connect(func() -> void: _defeats += 1)
	_boss.corpse_settled.connect(func() -> void: _settled += 1)


# -- Cases ------------------------------------------------------------------------------

func case_prefab_is_one_drag() -> void:
	await _build()
	await _frames(20)
	var platforms := get_nodes_in_group(HydraTiers.GROUP)
	var under_platforms := true
	var one_way := true
	for node: Node in platforms:
		under_platforms = under_platforms and node.get_parent().name == &"Platforms" and node.get_parent().get_parent() == _arena
		var platform := node as StaticBody2D
		var shape := platform.get_node("CollisionShape2D") as CollisionShape2D
		one_way = one_way and platform.collision_layer == 2 and shape.one_way_collision
	check(_arena.get_boss() == _boss and _boss.get_parent() == _arena, "the arena finds the Hydra as its direct child")
	check(_arena.boss_name == "La Hidra", "the arena carries the Spanish boss name")
	check(_boss.enemy_id == BOSS_ID, "the boss has the unique enemy id greece_hydra")
	check(not _arena.reward_enabled, "the reward is off")
	check(_arena.get_state() == BossArena.FightState.ARMED, "the arena is armed")
	check(_arena.get_node_or_null("Platforms") != null, "the prefab ships a Platforms node")
	check(platforms.size() >= 5, "the prefab has at least five platforms (%d)" % platforms.size())
	check(under_platforms, "every platform is a child of Platforms under the arena, not under the boss")
	check(one_way, "every platform is a one-way platform on layer 2")
	check(absf(_boss.global_position.x - (_arena.get_world_rect().end.x - _boss.right_wall_margin)) < 0.5, "the body sits near the right wall")
	check(_boss.get_tiers().level_count() == 5, "the tiers are read from the platforms (%d levels)" % _boss.get_tiers().level_count())


func case_layout_and_gate() -> void:
	await _build()
	await _frames(3)
	var low := _head(HydraHead.Kind.BITER)
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	check(not _slash(low) and not _slash(mid) and not _slash(high), "an awaiting boss refuses hits on every head")
	check(low.health == 12 and _boss.get_health() == 36, "a refused hit costs no health")
	_boss.engage()
	await _frames(2)
	check(_boss.collision_layer == 0, "the root body is on no collision layer")
	check(not _boss.receive_hit(1, HIT_FROM, &"attack_ground_1"), "the root body cannot be hit")
	check(low.collision_layer == 8 and mid.collision_layer == 8 and high.collision_layer == 8, "the heads are hurtboxes on the enemy layer")
	check(_boss.max_health == 36 and low.health == 12 and mid.health == 12 and high.health == 12, "three heads of 12 make a pool of 36")
	check(_boss.get_head_health_sum() == _boss.get_health(), "the pool equals the sum of the heads")
	check(low.global_position.y > mid.global_position.y and mid.global_position.y > high.global_position.y, "the heads rest at three heights")
	var tiers := _boss.get_tiers()
	check(is_equal_approx(low.global_position.y, tiers.tier_y(0) - _boss.head_rest_height) and is_equal_approx(high.global_position.y, tiers.tier_y(2) - _boss.head_rest_height), "the low and high heads rest on the lowest and highest tier")
	check(is_equal_approx(low.global_position.x, _boss.global_position.x + low.rest_dx), "the heads reach out to the left of the body")
	var soul := _player.get_soul()
	check(_slash(low), "an engaged boss takes a hit on a head")
	check(_player.get_soul() > soul, "hitting a head gives Luz soul")
	check(not low.is_in_group(Enemy.GROUP_ENEMIES) and not mid.is_in_group(Enemy.GROUP_ENEMIES) and not high.is_in_group(Enemy.GROUP_ENEMIES), "the heads stay out of the enemies group")


func case_damage_accounting() -> void:
	await _awake()
	_record_signals()
	var low := _head(HydraHead.Kind.BITER)
	var amounts: Array[int] = []
	_boss.hit.connect(func(amount: int, _remaining: int) -> void: amounts.append(amount))
	_slash(low, 5)
	check(low.health == 7 and _boss.get_health() == 31, "damage lowers the head and the pool by the same amount")
	check(_boss.get_head_health_sum() == _boss.get_health(), "the pool still equals the sum of the heads")
	_slash(low, 50)
	check(amounts == [5, 7], "a big hit is clamped to what the head has left (%s)" % str(amounts))
	check(low.health == 0 and _boss.get_health() == 24, "the clamped hit costs the pool only the head's health")
	check(_boss.get_head_health_sum() == _boss.get_health(), "the pool equals the sum after a head fell")
	check(not _slash(low), "a severed head refuses hits")
	check(_boss.get_health() == 24, "a refused hit on a stump costs nothing")
	check(_boss.get_phase() == 2, "the first dead head makes phase two")
	_slash(_head(HydraHead.Kind.SWEEPER), 3)
	check(_boss.get_head_health_sum() == _boss.get_health() and _boss.get_health() == 21, "the sum holds through hits on other heads")


func case_severing_and_enrage() -> void:
	await _awake()
	_player.set_max_health(500)
	_player.heal(500)
	_record_signals()
	var low := _head(HydraHead.Kind.BITER)
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	var base_venom := _boss.venom_telegraph
	check(is_equal_approx(_boss.get_enrage_scale(), 1.0), "with three heads nothing is enraged")
	_slash(low, 12)
	await _frames(3)
	check(_phases_seen == [2], "killing a head emits phase_changed with phase two (%s)" % str(_phases_seen))
	check(low.is_severed() and not low.is_hurtbox_enabled() and not low.is_hitbox_armed(), "a severed head loses its hurtbox and hitbox")
	check(not low.monitorable, "the severed hurtbox is switched off in the physics server")
	await _frames(2)
	check(_boss.get_state() == BossEnemy.State.TRANSITION and mid.is_roaring() and high.is_roaring(), "the remaining heads roar through the transition beat")
	check(is_equal_approx(_boss.get_enrage_scale(), 0.85), "one dead head shrinks the telegraphs by 0.85")
	check(is_equal_approx(_boss._telegraph_time(HydraBoss.Attack.VENOM_VOLLEY), base_venom * 0.85), "the venom telegraph shrinks with the enrage")
	check(_boss._venom_count(_boss._make_run(HydraBoss.Attack.VENOM_VOLLEY, high, 0)) == _boss.venom_count + 1, "one more venom glob per dead head")
	_slash(mid, 12)
	await _frames(3)
	check(_phases_seen == [2, 3], "the second dead head makes phase three (%s)" % str(_phases_seen))
	check(is_equal_approx(_boss.get_enrage_scale(), 0.7225), "two dead heads shrink the telegraphs by 0.7225")
	check(_boss._venom_count(_boss._make_run(HydraBoss.Attack.VENOM_VOLLEY, high, 0)) == _boss.venom_count + 2, "two dead heads add two venom globs")
	var floor_time := BossEnemy.MIN_TELEGRAPH
	var all_long_enough := true
	for attack: int in [HydraBoss.Attack.BITE_LUNGE, HydraBoss.Attack.VENOM_VOLLEY, HydraBoss.Attack.NECK_SWEEP]:
		all_long_enough = all_long_enough and _boss._telegraph_time(attack) >= floor_time
	check(all_long_enough, "no telegraph drops under 0.35 s however enraged")
	check(_boss._sweep_speed(_boss._make_run(HydraBoss.Attack.NECK_SWEEP, high, 0)) > _boss.sweep_speed, "a weaker sweep is still faster than the base one once enraged")
	_boss.auto_attack = true
	var dead_attacked := false
	for i: int in 600:
		await physics_frame
		dead_attacked = dead_attacked or _boss.get_attacking_heads().has(low) or _boss.get_attacking_heads().has(mid)
	check(not dead_attacked, "a severed head never attacks")
	_slash(high, 12)
	await _frames(3)
	check(_boss.is_dead() and high.is_severed(), "the last head's death is the boss's death")
	check(_phases_seen == [2, 3], "the killing blow does not announce a fourth phase")


func case_bite_lunge() -> void:
	await _awake()
	await _put_luz(Vector2(60.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	check(_boss.is_telegraphing() and _boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH, "the bite telegraph lasts at least 0.35 s")
	check(_boss.get_attacking_heads() == [low], "the biter carries out the bite")
	await _secs(0.3)
	check(_boss.get_telegraph().is_aim_line_visible(0) and not _boss.get_telegraph().is_aim_line_visible(1), "a red aim line tracks Luz during the wind-up")
	await _wait_for(func() -> bool: return _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE, 2.0)
	var lock := _boss.get_run_lock_point(low)
	check(lock.distance_to(_player.global_position + BossEnemy.PLAYER_CENTER_OFFSET) < 40.0, "the aim locked on the spot where Luz stood")
	await _frames(3)
	check(low.is_hitbox_armed(), "the head hurts on contact while it lunges")
	await _wait_for(func() -> bool: return _boss.get_attack_phase() == BossEnemy.AttackPhase.RECOVER, 2.0)
	check(_luz_hurt(), "standing in the locked spot, Luz is hurt by the lunge")
	check(low.is_stuck() and low.global_position.distance_to(lock) < 14.0, "the head sits stuck at the point it bit")
	check(absf(_boss.get_state_time_left() - _boss.bite_stuck_time) < 0.03, "the stuck window lasts the configured 0.8 s")
	check(not low.is_hitbox_armed(), "the stuck head no longer hurts")
	var health := low.health
	check(_slash(low) and low.health == health - 1, "the stuck head can be hit: the punish window")
	await _wait_for(_attack_is_over, 2.0)
	await _secs(1.0)
	check(not low.is_stuck() and low.global_position.distance_to(low.rest_global) < 2.0, "the head returns to its resting place")
	# Avoiding it: step away from the locked point before the lunge arrives.
	await _awake()
	await _put_luz(Vector2(60.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	await _wait_for(func() -> bool: return _boss.get_run_lock_point(_head(HydraHead.Kind.BITER)) != Vector2.ZERO, 2.0)
	await _put_luz(Vector2(-350.0, 0.0))
	await _wait_for(_attack_is_over, 3.0)
	check(not _luz_hurt(), "away from the locked point the lunge misses")
	check(_player.get_health() == LUZ_HEALTH and not _head(HydraHead.Kind.BITER).is_hitbox_armed(), "the lunge hitbox is off afterwards")


func case_venom_volley() -> void:
	await _awake()
	await _put_luz(Vector2(60.0, 0.0))
	var high := _head(HydraHead.Kind.SPITTER)
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	check(_boss.is_telegraphing() and _boss.get_state_time_left() >= BossEnemy.MIN_TELEGRAPH, "the venom telegraph lasts at least 0.35 s")
	var venoms := _boss.get_active_venoms()
	var spots := _boss.get_run_spots(high)
	check(venoms.size() == 3 and spots.size() == 3, "a volley marks three spots")
	var all_marked := true
	for venom: HydraVenom in venoms:
		all_marked = all_marked and venom.is_marker_visible() and not venom.is_pool()
	check(all_marked, "every spot is marked before anything is thrown")
	check(absf(spots[0].x - 60.0) < 1.0 and is_equal_approx(spots[0].y, 0.0), "the first spot is where Luz stands, on the floor")
	var on_surface := true
	var tops := _boss.get_tiers().platform_tops()
	for spot: Vector2 in spots:
		var on_floor := is_equal_approx(spot.y, 0.0)
		var on_platform := false
		for top: Rect2 in tops:
			on_platform = on_platform or (is_equal_approx(spot.y, top.position.y) and spot.x >= top.position.x and spot.x <= top.end.x)
		on_surface = on_surface and (on_floor or on_platform)
	check(on_surface, "every spot is on the floor or on a platform")
	var marker_frames := 0
	var first := venoms[0]
	while not first.is_pool() and marker_frames < 600:
		marker_frames += 1 if first.is_marker_visible() else 0
		await physics_frame
	check(float(marker_frames) / 60.0 >= BossEnemy.MIN_TELEGRAPH, "a marker shows at least 0.35 s before its glob lands")
	await _frames(6)
	check(first.is_pool() and absf(first.get_pool_time_left() - _boss.venom_pool_time) < 0.2, "the glob leaves a puddle that lasts about 3.5 s")
	check(_luz_hurt(), "standing on the marked spot, Luz is hurt by the puddle")
	var pools := _boss.get_active_venoms()
	await _wait_for(func() -> bool: return _boss.get_active_venoms().is_empty(), 6.0)
	check(pools.size() == 3 and _boss.get_active_venoms().is_empty(), "the puddles dry up and nothing stays behind")
	# Avoiding it: leave the marked spots before the globs land.
	await _awake()
	await _put_luz(Vector2(60.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _wait_for(func() -> bool: return _boss.get_active_venoms().any(func(v: HydraVenom) -> bool: return v.is_flying()), 3.0)
	check(_boss.get_active_venoms().any(func(v: HydraVenom) -> bool: return v.is_marker_visible()), "a marker stays up while its glob flies")
	await _put_luz(Vector2(-350.0, 0.0))
	await _wait_for(func() -> bool: return _boss.get_active_venoms().is_empty() and _attack_is_over(), 8.0)
	check(not _luz_hurt(), "off the marked spots Luz is never touched")
	# A cut-short volley withdraws what was not thrown yet.
	await _awake()
	await _put_luz(Vector2(-350.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _secs(0.2)
	var planned := _boss.get_active_venoms().size()
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(2)
	check(planned == 3 and _boss.get_active_venoms().is_empty(), "a volley cut short withdraws its markers")
	check(_boss.get_run_attack(_head(HydraHead.Kind.SPITTER)) == HydraBoss.NO_ATTACK, "the spitter is free once its volley was cut short")


func case_neck_sweep() -> void:
	await _awake()
	await _put_luz(Vector2(-200.0, 0.0))
	var mid := _head(HydraHead.Kind.SWEEPER)
	var tiers := _boss.get_tiers()
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	check(_boss.is_telegraphing() and _boss.get_state_time_left() >= 0.6, "the sweep line shows for at least 0.6 s")
	await _frames(2)
	var slab := _boss.get_run_slab(mid)
	check(_boss.get_telegraph().is_floor_marker_visible(0), "a band marks the tier Luz stands on")
	check(is_equal_approx(slab.position.y, tiers.tier_y(0) - _boss.sweep_band_height + 4.0), "standing on the floor, the floor tier is marked")
	check(slab.position.x <= _arena.get_world_rect().position.x + 1.0 and slab.end.x > mid.global_position.x, "the band runs from the left wall to the body")
	await _wait_for(func() -> bool: return _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE, 2.0)
	await _frames(2)
	check(mid.is_hitbox_armed() and is_equal_approx(mid.global_position.y, slab.position.y + slab.size.y * 0.5), "the neck lies flat along the marked tier while it sweeps")
	var leftmost := mid.global_position.x
	while _boss.get_attack_phase() == BossEnemy.AttackPhase.ACTIVE:
		leftmost = minf(leftmost, mid.global_position.x)
		await physics_frame
	check(leftmost < _arena.get_world_rect().position.x + 80.0, "the sweep covers the whole tier up to the left wall")
	check(_luz_hurt(), "staying on the marked tier, Luz is hurt by the sweep")
	await _wait_for(_attack_is_over, 3.0)
	await _secs(1.0)
	check(not mid.is_hitbox_armed() and mid.global_position.distance_to(mid.rest_global) < 2.0, "the neck pulls back home and the hitbox is off")
	# Avoiding it: change tier while the line shows.
	await _awake()
	await _put_luz(Vector2(-200.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _secs(0.2)
	await _put_luz(_platform_spot("PlatformMid"))
	await _wait_for(_attack_is_over, 3.0)
	check(not _luz_hurt(), "on another tier the sweep passes below")
	# The marked tier is the one Luz stands on.
	await _awake()
	await _put_luz(_platform_spot("PlatformMid"))
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(2)
	var mid_slab := _boss.get_run_slab(_head(HydraHead.Kind.SWEEPER))
	check(is_equal_approx(mid_slab.position.y, _boss.get_tiers().tier_y(1) - _boss.sweep_band_height + 4.0), "on the middle platform, the middle tier is marked")
	await _put_luz(_platform_spot("PlatformLowRight"))
	await _wait_for(_attack_is_over, 3.0)
	check(not _luz_hurt(), "stepping down to the stair below dodges the middle sweep")


func case_reachability() -> void:
	await _awake()
	var tiers := _boss.get_tiers()
	var jump_height := _player.jump_height
	var levels := tiers.levels()
	var steps_ok := true
	var steps_near_56 := true
	for i: int in range(1, levels.size()):
		var step := levels[i - 1] - levels[i]
		steps_ok = steps_ok and step <= jump_height
		steps_near_56 = steps_near_56 and absf(step - 56.0) <= 1.0
	check(steps_ok, "every vertical step between levels fits in one jump (%.0f px)" % jump_height)
	check(steps_near_56, "the tiers are about 56 px apart")
	var arena_rect := _arena.get_world_rect()
	var surfaces: Array[Rect2] = [Rect2(arena_rect.position.x + 20.0, tiers.floor_y, arena_rect.size.x - 40.0, 1.0)]
	surfaces.append_array(tiers.platform_tops())
	for kind: HydraHead.Kind in [HydraHead.Kind.BITER, HydraHead.Kind.SWEEPER, HydraHead.Kind.SPITTER]:
		var head := _head(kind)
		check(_reachable_from_surfaces(head.get_hurtbox_rect(), surfaces), "the %s head is within reach of a single jump and one attack" % HydraHead.Kind.keys()[kind])
	check(_platforms_reachable(surfaces), "every platform can be climbed to with single jumps")


## True when some standing place, a jump height and one of Luz's attacks (ground
## on the surface, air or up in the jump, facing either way) overlap `target`.
func _reachable_from_surfaces(target: Rect2, surfaces: Array[Rect2]) -> bool:
	var boxes := {&"ground": _player.hitbox_hit1, &"air": _player.hitbox_air, &"up": _player.hitbox_up}
	for surface: Rect2 in surfaces:
		var x := surface.position.x
		while x <= surface.end.x:
			var rise := 0.0
			while rise <= _player.jump_height:
				for attack_name: StringName in boxes:
					if attack_name == &"ground" and rise > 0.0:
						continue
					var box: Rect2 = boxes[attack_name]
					for facing: float in [1.0, -1.0]:
						# Boxes are right-facing; facing left mirrors them around her x.
						var left := x + box.position.x if facing > 0.0 else x - box.end.x
						var world := Rect2(left, surface.position.y - rise + box.position.y, box.size.x, box.size.y)
						if world.intersects(target):
							return true
				rise += 6.0
			x += 8.0
	return false


## Each platform has another surface it can be jumped to: the rise fits the
## jump and the gap fits the horizontal distance covered in the air.
func _platforms_reachable(surfaces: Array[Rect2]) -> bool:
	var rise_gravity := 2.0 * _player.jump_height / (_player.jump_time_to_apex * _player.jump_time_to_apex)
	var fall_gravity := rise_gravity * _player.fall_gravity_multiplier
	for platform: Rect2 in _boss.get_tiers().platform_tops():
		var reachable := false
		for other: Rect2 in surfaces:
			if other == platform:
				continue
			var rise := other.position.y - platform.position.y
			if rise < 0.0 or rise > _player.jump_height:
				continue
			var air_time := _player.jump_time_to_apex + sqrt(2.0 * (_player.jump_height - rise) / fall_gravity)
			var gap := maxf(maxf(other.position.x - platform.end.x, platform.position.x - other.end.x), 0.0)
			if gap <= _player.air_max_speed * air_time * 0.8:
				reachable = true
		if not reachable:
			return false
	return true


func case_pacing_per_phase() -> void:
	await _build(true)
	_player.set_max_health(500)
	_player.heal(500)
	await _frames(3)
	_boss.engage()
	await _put_luz(Vector2(-400.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	# Phase one: one head at a time, no immediate repeat, each with its own attack.
	var stats := await _watch(30.0)
	check(stats["max_simultaneous"] == 1, "with three heads only one attacks at a time (%d)" % stats["max_simultaneous"])
	check(stats["repeats"] == 0 and stats["distinct_heads"] >= 3, "the heads take turns without repeating (%s)" % str(stats))
	check(stats["weak"] == 0, "phase one uses only each head's own attack")
	# Phase two: the two living heads attack as a duo.
	_slash(low, 12)
	await _secs(1.0)
	stats = await _watch(30.0)
	check(stats["max_simultaneous"] == 2, "with two heads the attacks overlap as a duo (%d)" % stats["max_simultaneous"])
	check(stats["weak"] == 0, "weaker versions never appear before the last head")
	check(stats["dead_attacked"] == 0, "the dead head stays out of the duo")
	check(stats["distinct_heads"] == 2, "both living heads join the duo")
	# Phase three: the last head is in a frenzy and throws every attack.
	_slash(mid, 12)
	await _secs(1.0)
	stats = await _watch(40.0)
	check(stats["max_simultaneous"] == 1, "with one head there is only the frenzy of the last head")
	check(stats["weak"] > 0, "the last head also throws weaker versions of the dead heads' attacks")
	check(stats["kinds"] == 3, "the frenzy uses all three attacks (%d)" % stats["kinds"])
	check(stats["distinct_heads"] == 1 and stats["dead_attacked"] == 0, "only the last head attacks")
	check(stats["own_native"] > 0, "the last head still uses its own attack")
	check(_boss.get_enrage_scale() < 0.73 and _boss._fight_delay() <= _boss.fight_delay_max * 0.5, "recoveries and pauses are shorter in the frenzy")
	check(not _boss.is_dead() and high.health == 12, "the last head was never harmed by the pacing run")


## Watches the boss for `seconds` and counts what the heads do.
func _watch(seconds: float) -> Dictionary:
	var stats := {
		"max_simultaneous": 0, "repeats": 0, "weak": 0,
		"dead_attacked": 0, "kinds": 0, "own_native": 0, "distinct_heads": 0,
	}
	var seen_heads: Dictionary = {}
	var seen_kinds: Dictionary = {}
	var previous: Array[HydraHead] = []
	var last_lead: HydraHead
	for i: int in ceili(seconds * 60.0):
		await physics_frame
		var attacking := _boss.get_attacking_heads()
		stats["max_simultaneous"] = maxi(stats["max_simultaneous"], attacking.size())
		for head: HydraHead in attacking:
			var attack := _boss.get_run_attack(head)
			seen_heads[head] = true
			seen_kinds[attack] = true
			if head.is_severed():
				stats["dead_attacked"] += 1
			if _boss.is_run_weak(head):
				stats["weak"] += 1
			elif attack == int(head.kind):
				stats["own_native"] += 1
		if previous.is_empty() and attacking.size() >= 1:
			if attacking[0] == last_lead and attacking.size() == 1 and _boss.get_living_heads().size() > 1:
				stats["repeats"] += 1
			last_lead = attacking[0]
		previous = attacking.duplicate()
	stats["distinct_heads"] = seen_heads.size()
	stats["kinds"] = seen_kinds.size()
	return stats


func case_reset_mid_fight() -> void:
	await _awake(true)
	_player.set_max_health(500)
	_player.heal(500)
	await _put_luz(Vector2(-400.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	_record_signals()
	_slash(low, 5)
	_slash(mid, 12)
	await _secs(1.0)
	_boss.auto_attack = false
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _wait_for(func() -> bool: return not _boss.get_active_venoms().is_empty(), 1.0)
	await _secs(1.2)
	check(not _boss.get_active_venoms().is_empty() and mid.is_severed(), "the fight was under way: venom out, a head down")
	_boss.reset_to_spawn()
	await _frames(3)
	check(low.health == 12 and mid.health == 12 and high.health == 12, "a reset restores all three heads at full health")
	check(not low.is_severed() and not mid.is_severed() and not high.is_severed(), "no head stays severed")
	check(low.is_hurtbox_enabled() and mid.is_hurtbox_enabled() and high.is_hurtbox_enabled(), "every hurtbox is back")
	check(_boss.get_health() == 36 and _boss.get_head_health_sum() == 36, "the pool is full again")
	check(_boss.is_fresh(), "the boss is fresh after the reset")
	check(_boss.get_active_venoms().is_empty(), "no venom remains after the reset")
	check(not low.is_hitbox_armed() and not mid.is_hitbox_armed() and not high.is_hitbox_armed(), "no hitbox stays armed")
	check(_boss.get_telegraph().visible_aim_line_count() == 0 and not _boss.get_telegraph().is_floor_marker_visible(0), "no telegraph remains")
	check(_boss.get_phase() == 1 and _phases_seen.back() == 1, "the reset returns to phase one and announces it")
	check(_boss.collision_layer == 0 and _boss.get_attacking_heads().is_empty(), "the root stays unhittable and no head is mid-attack")
	check(low.global_position.distance_to(low.rest_global) < 1.0 and mid.global_position.distance_to(mid.rest_global) < 1.0, "the heads are back at their resting places")
	check(not _slash(low), "after the reset the boss waits for the arena again")
	_boss.engage()
	check(_slash(mid), "after a new engage the restored head takes hits")


func case_defeat_and_arena() -> void:
	await _build()
	await _frames(3)
	_record_signals()
	var completion := root.get_node("GameCompletion")
	await _put_luz(IN_TRIGGER)
	await _frames(15)
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "entering the trigger starts the fight")
	check(_arena.get_bar().get_name_text() == "La Hidra", "the bar carries the boss name")
	check(is_equal_approx(_arena.get_bar().get_notch_ratio(), 0.667) and _arena.get_bar().get_extra_notch_ratios().size() == 1, "the bar shows a notch per third")
	await _frames(40)
	check(_boss.get_state() != BossEnemy.State.IDLE and _arena.are_doors_closed(), "the arena engaged the boss and closed the doors")
	await _put_luz(Vector2(-350.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _wait_for(func() -> bool: return not _boss.get_active_venoms().is_empty(), 1.0)
	for kind: HydraHead.Kind in [HydraHead.Kind.BITER, HydraHead.Kind.SWEEPER, HydraHead.Kind.SPITTER]:
		_slash(_head(kind), 12)
		await _secs(0.5)
	await _wait_for(func() -> bool: return _settled > 0, 3.0)
	await _frames(60)
	check(_defeats == 1, "the killing blow emits defeated once")
	check(_settled >= 1 and _boss.is_dead(), "the corpse settles")
	check(_boss.get_active_venoms().is_empty(), "no venom remains after the defeat")
	var armed := false
	var severed := true
	for head: HydraHead in _boss.get_heads():
		armed = armed or head.is_hitbox_armed() or head.is_hurtbox_enabled()
		severed = severed and head.is_severed()
	check(severed and not armed, "all three heads are severed and harmless")
	check(_boss.get_telegraph().visible_aim_line_count() == 0, "no telegraph remains")
	check(_arena.get_state() == BossArena.FightState.DEFEATED and not _arena.are_doors_closed(), "the arena opens")
	check(_arena.get_reward() == null, "no reward spawns")
	check(not completion.is_active(), "the Hydra does not trigger the game completion")
	check(_progress().is_defeated(BOSS_ID), "BossProgress records the defeat under greece_hydra")
	check(_phases_seen == [2, 3], "the phases announced were two and three (%s)" % str(_phases_seen))
	check(_boss.collision_layer == 0 and not _slash(_head(HydraHead.Kind.BITER)), "a corpse takes no more hits")
	check(Engine.time_scale == 1.0, "the time scale is back to normal")


func case_corpse_reload() -> void:
	await _build()
	await _frames(3)
	_boss.engage()
	_boss.make_corpse_at(Vector2(400.0, 0.0), -1)
	await _frames(3)
	var all_severed := true
	for head: HydraHead in _boss.get_heads():
		all_severed = all_severed and head.is_severed()
	check(_boss.is_dead() and all_severed, "make_corpse_at on a living instance severs every head")
	check(_boss.get_active_venoms().is_empty(), "the corpse has no hazard")
	# A boss restored as a corpse before it enters the tree (the registry's path).
	var scene := load("res://scenes/enemies/bosses/hydra.tscn") as PackedScene
	var early := scene.instantiate() as HydraBoss
	early.enemy_id = &"greece_hydra_early"
	early.position = Vector2(400.0, 0.0)
	# Like the registry: the corpse is restored once in the tree, before _ready.
	early.tree_entered.connect(func() -> void: early.make_corpse_at(Vector2(400.0, 0.0), -1))
	_rig.add_child(early)
	await _frames(3)
	var early_severed := true
	for head: HydraHead in early.get_heads():
		early_severed = early_severed and head.is_severed()
	check(early.is_dead() and early_severed, "a corpse restored before _ready shows all three heads severed")
	# A reload after the defeat: the arena puts the corpse back.
	await _build(false, true)
	await _frames(10)
	var reloaded_severed := true
	for head: HydraHead in _boss.get_heads():
		reloaded_severed = reloaded_severed and head.is_severed() and not head.is_hurtbox_enabled()
	check(_arena.get_state() == BossArena.FightState.DEFEATED, "the arena reloads as defeated")
	check(_boss.is_dead() and reloaded_severed, "the reloaded body is dead with all three heads severed")
	check(_boss.get_active_venoms().is_empty() and _boss.get_telegraph().visible_aim_line_count() == 0, "the reloaded corpse has no hazard")
	check(not _slash(_head(HydraHead.Kind.SPITTER)), "a reloaded head cannot be hit")
	check(not _arena.are_doors_closed() and _arena.get_node("Platforms").get_child_count() >= 5, "the reloaded arena is open and keeps its platforms")
	check(_boss.collision_layer == 0 and not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "the reloaded corpse is out of every hit and reset")


func case_stays_in_arena() -> void:
	await _build(true)
	_player.set_max_health(500)
	_player.heal(500)
	await _frames(3)
	_boss.engage()
	await _put_luz(Vector2(-300.0, 0.0))
	var world := _arena.get_world_rect()
	var inside := true
	var worst := 0.0
	var spots_inside := true
	var phases: Array[Callable] = [
		func() -> void: pass,
		func() -> void: _slash(_head(HydraHead.Kind.BITER), 12),
		func() -> void: _slash(_head(HydraHead.Kind.SWEEPER), 12),
	]
	for phase_step: Callable in phases:
		phase_step.call()
		await _secs(1.0)
		for i: int in 1500:
			await physics_frame
			for head: HydraHead in _boss.get_heads():
				if head.is_severed():
					continue
				var gap := minf(head.global_position.x - world.position.x, world.end.x - head.global_position.x)
				worst = minf(worst, gap)
				inside = inside and gap >= -0.5 and head.global_position.y <= world.end.y and head.global_position.y >= world.position.y
			for venom: HydraVenom in _boss.get_active_venoms():
				spots_inside = spots_inside and venom.get_spot().x >= world.position.x and venom.get_spot().x <= world.end.x
	check(inside, "the heads stay inside the arena limits (worst gap %.1f)" % worst)
	check(spots_inside, "every venom spot is inside the arena")
	var boss_gap := world.end.x - _boss.global_position.x
	check(boss_gap >= _boss.right_wall_margin - 0.5 and _boss.global_position.x > world.position.x, "the body stays at the right wall")
	check(_boss.get_head_health_sum() == _boss.get_health(), "the pool equalled the heads after a long fight")


# -- Review follow-ups: real attacks, duo telegraph, severing mid-attack, platforms --------

func case_real_attack_hits_heads() -> void:
	await _awake()
	var tiers := _boss.get_tiers()
	for kind: HydraHead.Kind in [HydraHead.Kind.BITER, HydraHead.Kind.SWEEPER, HydraHead.Kind.SPITTER]:
		var head := _head(kind)
		var label := str(HydraHead.Kind.keys()[kind]).to_lower()
		var health := head.health
		var pool := _boss.get_health()
		var soul := _player.get_soul()
		# Luz stands on the head's own tier, a stride to its right, and swings once.
		await _real_slash(Vector2(head.global_position.x - 40.0, tiers.tier_y(int(head.tier)) - 1.0))
		var dealt := _player.attack_damage
		check(head.health == health - dealt, "a real ground slash takes %d from the %s head (%d -> %d)" % [dealt, label, health, head.health])
		check(_boss.get_health() == pool - dealt and _boss.get_head_health_sum() == _boss.get_health(), "the same damage leaves the shared pool by the %s hit" % label)
		check(_player.get_soul() > soul, "a real slash on the %s head gives Luz soul" % label)


## Phase two with `dead` already severed, the boss free to start a duo, and Luz away.
func _duo_ready(dead: HydraHead.Kind) -> void:
	await _awake()
	_boss.duo_offset = 0.3
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	_slash(_head(dead), 12)
	await _secs(1.0)
	_boss.auto_attack = true


func _both_attacking() -> bool:
	return _boss.get_attacking_heads().size() == 2


func case_echo_telegraph_in_duo() -> void:
	var telegraph: BossTelegraph
	# The sweeper leads and the biter echoes: the echo's aim line is slot 1.
	await _duo_ready(HydraHead.Kind.SPITTER)
	telegraph = _boss.get_telegraph()
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _wait_for(_both_attacking, 2.0)
	check(telegraph.is_aim_line_visible(HydraBoss.ECHO_SLOT), "the echo bite paints its own aim line on slot 1")
	check(telegraph.is_floor_marker_visible(HydraBoss.LEAD_SLOT * HydraBoss.MARKERS_PER_RUN), "the lead sweep keeps its band while the echo winds up")
	check(not telegraph.is_aim_line_visible(HydraBoss.LEAD_SLOT), "a sweep lead has no aim line, so the line on slot 0 stays off")
	# The biter leads and the sweeper echoes: the echo's band starts at marker 8.
	await _duo_ready(HydraHead.Kind.SPITTER)
	telegraph = _boss.get_telegraph()
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	await _wait_for(_both_attacking, 2.0)
	var echo_marker := HydraBoss.ECHO_SLOT * HydraBoss.MARKERS_PER_RUN
	check(telegraph.is_floor_marker_visible(echo_marker), "the echo sweep paints its band on marker %d" % echo_marker)
	check(telegraph.is_aim_line_visible(HydraBoss.LEAD_SLOT), "the lead bite keeps its aim line while the echo winds up")
	check(not telegraph.is_floor_marker_visible(HydraBoss.LEAD_SLOT * HydraBoss.MARKERS_PER_RUN), "a bite lead has no band, so marker 0 stays off")
	check(HydraBoss.ECHO_SLOT < BossTelegraph.LINE_POOL_SIZE and HydraBoss.LEAD_SLOT < BossTelegraph.LINE_POOL_SIZE, "both run slots exist in the aim-line pool")
	check((HydraBoss.ECHO_SLOT + 1) * HydraBoss.MARKERS_PER_RUN <= BossTelegraph.MARKER_POOL_SIZE, "both runs' marker ranges fit the marker pool")
	var sweeper := _head(HydraHead.Kind.SWEEPER)
	await _wait_for(func() -> bool: return _boss.get_run_phase(sweeper) == BossEnemy.AttackPhase.ACTIVE, 3.0)
	await _frames(2)
	check(not telegraph.is_floor_marker_visible(echo_marker), "the echo's band goes away once its sweep is active")


## Waits for `head`'s run to reach `phase`, then a frame so its effects are live.
func _await_run_phase(head: HydraHead, phase: int) -> void:
	await _wait_for(func() -> bool: return _boss.get_run_phase(head) == phase, 4.0)
	await _frames(1)


## True once a living head (never one in `dead`) is attacking again.
func _attacks_again(dead: Array[HydraHead]) -> bool:
	return await _wait_for(func() -> bool:
		var heads := _boss.get_attacking_heads()
		return not heads.is_empty() and heads.all(func(h: HydraHead) -> bool: return not dead.has(h) and not h.is_severed()), 10.0)


func _planned_venom_count() -> int:
	return _boss.get_active_venoms().filter(func(v: HydraVenom) -> bool: return v.get_state() == HydraVenom.State.PLANNED).size()


func case_sever_mid_attack() -> void:
	# A lunging biter dies in its ACTIVE phase.
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(60.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	await _await_run_phase(low, BossEnemy.AttackPhase.ACTIVE)
	check(low.is_hitbox_armed(), "the biter's hitbox is armed in the lunge")
	_slash(low, 12)
	await _frames(3)
	check(not low.is_hitbox_armed(), "a biter severed mid-lunge drops its hitbox")
	check(_boss.get_run_attack(low) == BossEnemy.NO_ATTACK, "a biter severed mid-lunge has no run left")
	check(_boss.get_state() != BossEnemy.State.ATTACK, "the boss leaves the attack state when its lead head dies")
	_boss.auto_attack = true
	check(await _attacks_again([low]), "the remaining heads attack again after the biter died")
	# A sweeping neck dies in its ACTIVE phase.
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(-200.0, 0.0))
	var mid := _head(HydraHead.Kind.SWEEPER)
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _await_run_phase(mid, BossEnemy.AttackPhase.ACTIVE)
	check(mid.is_hitbox_armed(), "the sweeper's hitbox is armed in the sweep")
	_slash(mid, 12)
	await _frames(3)
	check(not mid.is_hitbox_armed(), "a sweeper severed mid-sweep drops its hitbox")
	check(_boss.get_run_attack(mid) == BossEnemy.NO_ATTACK, "a sweeper severed mid-sweep has no run left")
	check(_boss.get_state() != BossEnemy.State.ATTACK, "the boss leaves the attack state when the sweeper dies")
	_boss.auto_attack = true
	check(await _attacks_again([mid]), "the remaining heads attack again after the sweeper died")
	# A spitter dies after the first glob left and before the others were thrown.
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	var high := _head(HydraHead.Kind.SPITTER)
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _await_run_phase(high, BossEnemy.AttackPhase.ACTIVE)
	await _wait_for(func() -> bool: return _boss.get_active_venoms().any(func(v: HydraVenom) -> bool: return v.is_flying()), 1.0)
	var planned_before := _planned_venom_count()
	check(planned_before > 0, "a glob is in flight and others are still only planned (%d)" % planned_before)
	_slash(high, 12)
	await _frames(3)
	check(_planned_venom_count() == 0, "the dead spitter's planned venom is withdrawn (%d left)" % _planned_venom_count())
	check(_boss.get_run_attack(high) == BossEnemy.NO_ATTACK, "a spitter severed mid-volley has no run left")
	check(_boss.get_state() != BossEnemy.State.ATTACK, "the boss leaves the attack state when the spitter dies")
	_boss.auto_attack = true
	check(await _attacks_again([high]), "the remaining heads attack again after the spitter died")
	# A duo: the lead sweeper dies while the echo bite is also striking.
	await _duo_ready(HydraHead.Kind.SPITTER)
	low = _head(HydraHead.Kind.BITER)
	mid = _head(HydraHead.Kind.SWEEPER)
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _await_run_phase(low, BossEnemy.AttackPhase.ACTIVE)
	check(mid.is_hitbox_armed() and low.is_hitbox_armed(), "both duo heads are armed at once")
	_slash(mid, 12)
	await _frames(3)
	check(not mid.is_hitbox_armed() and not low.is_hitbox_armed(), "killing the lead disarms the lead and the echo")
	check(_boss.get_attacking_heads().is_empty(), "no run survives the lead's death")
	check(_boss.get_state() != BossEnemy.State.ATTACK, "the boss leaves the attack state when the duo lead dies")
	check(await _attacks_again([mid]), "the last head attacks again after the duo lead died")
	# A duo: the echo biter dies while the lead sweeper is still sweeping.
	await _duo_ready(HydraHead.Kind.SPITTER)
	low = _head(HydraHead.Kind.BITER)
	mid = _head(HydraHead.Kind.SWEEPER)
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _await_run_phase(low, BossEnemy.AttackPhase.ACTIVE)
	check(low.is_hitbox_armed(), "the echo biter is armed in its lunge")
	_slash(low, 12)
	await _frames(3)
	check(not low.is_hitbox_armed(), "a dead echo drops its hitbox")
	check(_boss.get_run_attack(low) == BossEnemy.NO_ATTACK, "a dead echo has no run left")
	check(_boss.get_run_attack(mid) == HydraBoss.Attack.NECK_SWEEP, "the lead sweep goes on after the echo died")
	check(await _attacks_again([low]), "the lead head attacks again after the echo died")


func case_platforms_moved() -> void:
	await _build()
	await _frames(3)
	_tough_luz()
	# The middle platform sinks 8 px and the top one rises 84: both heads follow.
	_platform("PlatformMid").position.y = -100.0
	_platform("PlatformTop").position.y = -300.0
	_boss.engage()
	await _frames(2)
	var tiers := _boss.get_tiers()
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	check(is_equal_approx(tiers.tier_y(1), -108.0) and is_equal_approx(tiers.tier_y(2), -308.0), "the tiers follow the moved platforms (%.0f, %.0f)" % [tiers.tier_y(1), tiers.tier_y(2)])
	check(is_equal_approx(mid.global_position.y, -108.0 - _boss.head_rest_height), "the middle head rests on its moved tier")
	check(is_equal_approx(high.global_position.y, -308.0 - _boss.head_rest_height), "the high head rests on its moved tier")
	await _put_luz(Vector2(100.0, -110.0))
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(2)
	check(is_equal_approx(_boss.get_run_slab(mid).position.y, -108.0 - _boss.sweep_band_height + 4.0), "the sweep band marks the moved platform")
	await _put_luz(Vector2(130.0, -310.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	var spots := _boss.get_run_spots(high)
	check(not spots.is_empty() and is_equal_approx(spots[0].y, -308.0), "the first venom spot lands on the moved platform")


func case_platforms_removed() -> void:
	await _build()
	await _frames(3)
	_tough_luz()
	_remove_platform("PlatformMid")
	_boss.engage()
	await _frames(2)
	var tiers := _boss.get_tiers()
	var mid := _head(HydraHead.Kind.SWEEPER)
	check(tiers.level_count() == 4, "removing a platform removes its level (%d)" % tiers.level_count())
	check(is_equal_approx(tiers.tier_y(1), -168.0), "the middle tier moves to the next level (%.0f)" % tiers.tier_y(1))
	check(is_equal_approx(mid.global_position.y, -168.0 - _boss.head_rest_height), "the middle head rests on the new middle level")
	await _put_luz(_platform_spot("PlatformUpper"))
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(2)
	check(is_equal_approx(_boss.get_run_slab(mid).position.y, -168.0 - _boss.sweep_band_height + 4.0), "the sweep band marks the surviving platform")
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	var dropped := false
	for spot: Vector2 in _boss.get_run_spots(_head(HydraHead.Kind.SPITTER)):
		dropped = dropped or (absf(spot.x - 110.0) < 1.0 and is_equal_approx(spot.y, 0.0))
	check(dropped, "a venom spot where the platform was drops to the floor")


func case_platforms_fallback() -> void:
	await _build()
	await _frames(3)
	_tap_logs()
	for platform_name: String in ["PlatformLowRight", "PlatformMid", "PlatformUpper", "PlatformTop"]:
		_remove_platform(platform_name)
	_boss.engage()
	await _frames(2)
	var tiers := _boss.get_tiers()
	var step := HydraTiers.DEFAULT_TIER_STEP
	check(tiers.level_count() == 2 and is_equal_approx(tiers.tier_y(1), -step) and is_equal_approx(tiers.tier_y(2), -2.0 * step), "with fewer than three levels the heads use the default steps")
	var on_fallback := true
	for kind: HydraHead.Kind in [HydraHead.Kind.BITER, HydraHead.Kind.SWEEPER, HydraHead.Kind.SPITTER]:
		var head := _head(kind)
		on_fallback = on_fallback and is_equal_approx(head.global_position.y, tiers.tier_y(int(head.tier)) - _boss.head_rest_height)
	check(on_fallback, "every head rests on its fallback tier")
	check(_tap.errors.is_empty(), "the fallback layout logs no engine error (%s)" % str(_tap.errors))


func case_two_arenas() -> void:
	await _build()
	await _frames(3)
	var other := (load(ARENA_SCENE) as PackedScene).instantiate() as BossArena
	other.position = Vector2(0.0, -2000.0)
	var other_boss := other.get_node("Hydra") as HydraBoss
	other_boss.enemy_id = &"greece_hydra_other"
	other_boss.auto_attack = false
	# It has no floor under it in this rig, so its rest points are what is compared.
	_rig.add_child(other)
	await _frames(3)
	_boss.engage()
	await _frames(2)
	var tiers := _boss.get_tiers()
	var own := true
	for top: Rect2 in tiers.platform_tops():
		own = own and top.position.y > -300.0
	check(tiers.level_count() == 5 and own, "a second arena's platforms never join this boss's tiers (%d levels)" % tiers.level_count())
	check(is_equal_approx(_head(HydraHead.Kind.SPITTER).global_position.y, -224.0 - _boss.head_rest_height), "this boss's high head stays on its own top platform")
	var other_tiers := other_boss.get_tiers()
	check(other_tiers.level_count() == 5 and is_equal_approx(other_tiers.floor_y, -2000.0), "the second boss reads only its own five levels (%d)" % other_tiers.level_count())
	var other_high := other_boss.get_head(HydraHead.Kind.SPITTER)
	check(is_equal_approx(other_high.rest_global.y, -2224.0 - other_boss.head_rest_height), "the second boss's high head rests on its own arena (y %.1f)" % other_high.rest_global.y)


func case_platform_shape_warnings() -> void:
	await _build()
	_tap_logs()
	await _frames(3)
	var shape_node := _platform("PlatformMid").get_node("CollisionShape2D") as CollisionShape2D
	shape_node.name = &"Shape"
	(_platform("PlatformUpper").get_node("CollisionShape2D") as CollisionShape2D).shape = CircleShape2D.new()
	_boss.engage()
	await _frames(2)
	check(_warnings_naming("PlatformMid") == 1, "a platform whose shape node is misnamed is reported by name (%s)" % str(_tap.warnings))
	check(_warnings_naming("PlatformUpper") == 1, "a platform with a non-rectangle shape is reported by name")
	check(_boss.get_tiers().level_count() == 3, "both platforms are skipped (%d levels)" % _boss.get_tiers().level_count())
	_boss.reset_to_spawn()
	await _frames(3)
	check(_warnings_naming("PlatformMid") == 1, "the same platform is not reported again at every layout")


func case_enrage_volley_count() -> void:
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(_marked_spots() == _boss.venom_count, "three heads: a volley marks %d spots" % _boss.venom_count)
	_slash(_head(HydraHead.Kind.BITER), 12)
	await _secs(1.0)
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(_marked_spots() == _boss.venom_count + 1, "one head down: a volley marks one more spot (%d)" % _marked_spots())
	_slash(_head(HydraHead.Kind.SWEEPER), 12)
	await _secs(1.0)
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(_marked_spots() == _boss.venom_count + 2, "two heads down: a volley marks two more spots (%d)" % _marked_spots())
	# The last head is the sweeper: its volley is the weaker version.
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	_slash(_head(HydraHead.Kind.BITER), 12)
	await _secs(1.0)
	_slash(_head(HydraHead.Kind.SPITTER), 12)
	await _secs(1.0)
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(_marked_spots() == _boss.weak_venom_count, "a weaker volley marks only %d spots (%d)" % [_boss.weak_venom_count, _marked_spots()])


## Seconds from the call to the sweep's ACTIVE phase, and from there to the neck
## reaching the left end, both counted in physics frames.
func _time_sweep() -> Array[float]:
	var sweeper := _head(HydraHead.Kind.SWEEPER)
	var end_x := _arena.get_world_rect().position.x + _boss.sweep_end_margin
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	var telegraph_frames := 0
	while _boss.get_attack_phase() != BossEnemy.AttackPhase.ACTIVE and telegraph_frames < 300:
		telegraph_frames += 1
		await physics_frame
	var travel_frames := 0
	while sweeper.global_position.x > end_x + 2.0 and travel_frames < 300:
		travel_frames += 1
		await physics_frame
	await _wait_for(_attack_is_over, 4.0)
	return [float(telegraph_frames) / 60.0, float(travel_frames) / 60.0]


func case_enrage_sweep_timing() -> void:
	await _awake()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	var sweeper := _head(HydraHead.Kind.SWEEPER)
	var start_x := _boss.global_position.x + sweeper.shoulder.x - _boss.sweep_start_gap
	var distance := start_x - (_arena.get_world_rect().position.x + _boss.sweep_end_margin) - 2.0
	var dead_heads: Array[HydraHead.Kind] = [HydraHead.Kind.SPITTER, HydraHead.Kind.BITER]
	for dead: int in 3:
		if dead > 0:
			_slash(_head(dead_heads[dead - 1]), 12)
			await _secs(1.0)
		var timing := await _time_sweep()
		var wanted_wind_up := _boss.sweep_telegraph * pow(_boss.enrage_telegraph_scale, float(dead))
		var speed := _boss.sweep_speed * (1.0 + _boss.enrage_sweep_speed_gain * float(dead))
		if dead == 2:
			speed *= _boss.frenzy_strength
		check(absf(timing[0] - wanted_wind_up) < 0.07, "%d heads down: the sweep wind-up lasts %.2f s (measured %.2f)" % [dead, wanted_wind_up, timing[0]])
		check(absf(timing[1] - distance / speed) < 0.07, "%d heads down: the neck crosses in %.2f s (measured %.2f)" % [dead, distance / speed, timing[1]])


func case_venom_release_in_callback() -> void:
	await _awake()
	_tap_logs()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	_slash(_head(HydraHead.Kind.SWEEPER), 12)
	await _secs(1.0)
	_slash(_head(HydraHead.Kind.SPITTER), 12)
	await _secs(1.0)
	_slash(low, low.health - 1)
	# The last head throws a (weaker) volley on spots far from Luz, who then walks up
	# to the head and waits there for a puddle before the real killing blow.
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _put_luz(Vector2(low.global_position.x - 40.0, -1.0))
	var live := await _wait_for(func() -> bool: return _boss.get_active_venoms().any(func(v: HydraVenom) -> bool: return v.is_pool()), 5.0)
	var pools := _boss.get_active_venoms()
	var errors_before := _tap.errors.size()
	check(live and low.health == 1, "a puddle is live while the last head has one health left")
	_player.request_attack(0)
	await _secs(0.5)
	check(_boss.is_dead() and low.health == 0, "Luz's real slash lands the killing blow")
	check(_boss.get_active_venoms().is_empty(), "the killing blow withdraws every puddle")
	var still_watching := false
	for venom: HydraVenom in pools:
		still_watching = still_watching or venom.monitoring
	check(not still_watching, "no released puddle keeps monitoring")
	check(_tap.errors.size() == errors_before, "releasing the puddles from the hit logs no engine error (%s)" % str(_tap.errors))


# -- Art (a fixture manifest, never the real sheets) ------------------------------------------

## A manifest with a body sheet, one sheet per head, the props and the neck tile. `parts`
## picks which exist; `without` leaves clips out of the body, the heads and the props.
func _write_art_fixture(parts: Array[String] = ART_ALL, without: Array[String] = []) -> void:
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	var manifest := {"cell": 640, "feet_row": 608, "sprite_scale": ART_SCALE}
	if parts.has("body"):
		var entry := _write_clip_sheet("fixture_body.png", FIXTURE_BODY_CLIPS, without)
		manifest["sheets"] = {"fixture_body.png": {"grid": entry["grid"], "clips": entry["clips"], "events": {}}}
	if parts.has("heads"):
		for key: String in HydraArt.HEAD_ENTRIES:
			var entry := _write_clip_sheet("fixture_%s.png" % key, FIXTURE_HEAD_CLIPS, without)
			entry["sprite_scale"] = ART_SCALE
			manifest[key] = entry
	if parts.has("props"):
		var entry := _write_clip_sheet("fixture_props.png", FIXTURE_PROPS, without, FIXTURE_PROP_FRAMES)
		entry["sprite_scale"] = ART_SCALE
		entry["content"] = FIXTURE_PROPS
		manifest["props"] = entry
	if parts.has("neck"):
		var tile := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
		tile.fill(Color.WHITE)
		tile.save_png(ART_DIR.path_join("fixture_neck.png"))
		manifest["neck"] = {"texture": "fixture_neck.png", "thickness": ART_NECK}
	var file := FileAccess.open(ART_MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))


## One white sheet holding `clips` (clip -> frame count, or a content box: one frame; `frames`
## overrides the count of a clip) and the manifest entry that describes it.
func _write_clip_sheet(file_name: String, clips: Dictionary, without: Array[String], frames := {}) -> Dictionary:
	var drawn := {}
	var next := 0
	for clip_name: String in clips:
		if without.has(clip_name):
			continue
		var count: int = frames.get(clip_name, clips[clip_name] if clips[clip_name] is int else 1)
		drawn[clip_name] = range(next, next + count)
		next += count
	var rows := ceili(float(next) / float(ART_COLUMNS))
	var image := Image.create_empty(ART_COLUMNS * ART_CELL, rows * ART_CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png(ART_DIR.path_join(file_name))
	return {
		"sheet": file_name, "clips": drawn,
		"grid": {"columns": ART_COLUMNS, "rows": rows, "cell_width": ART_CELL, "cell_height": ART_CELL},
	}


func _remove_art_fixture() -> void:
	if not DirAccess.dir_exists_absolute(ART_DIR):
		return
	for file_name: String in DirAccess.get_files_at(ART_DIR):
		DirAccess.remove_absolute(ART_DIR.path_join(file_name))
	DirAccess.remove_absolute(ART_DIR)


## A rig with the fixture art, the boss engaged and settled.
func _awake_art(manifest := ART_MANIFEST) -> void:
	await _build(false, false, manifest)
	await _frames(3)
	_boss.engage()
	await _frames(2)


func _body_sprite() -> AnimatedSprite2D:
	return _boss.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D


## The speed `sprite` plays `clip` at must make it last `duration` seconds.
func _lasts(sprite: AnimatedSprite2D, clip: StringName, duration: float, tolerance := 0.05) -> bool:
	var frames := sprite.sprite_frames
	var wanted := (float(frames.get_frame_count(clip)) / frames.get_animation_speed(clip)) / duration
	return sprite.animation == clip and absf(sprite.get_playing_speed() - wanted) <= tolerance * wanted


## Sprites of `clip` that hang under `node` (puffs and the like), alive.
func _sprites_of(node: Node, clip: StringName) -> Array[AnimatedSprite2D]:
	var found: Array[AnimatedSprite2D] = []
	for child: Node in node.get_children():
		var sprite := child as AnimatedSprite2D
		if sprite != null and sprite.animation == clip and not sprite.is_queued_for_deletion():
			found.append(sprite)
	return found


func _glow_of(sprite: AnimatedSprite2D) -> float:
	return float((sprite.material as ShaderMaterial).get_shader_parameter(&"glow_amount"))


func _flash_of(sprite: AnimatedSprite2D) -> float:
	return float((sprite.material as ShaderMaterial).get_shader_parameter(&"flash_amount"))


func case_art_absent_keeps_the_placeholders() -> void:
	await _awake_art(NO_ART_MANIFEST)
	check(not _boss.has_art() and not _body_sprite().visible, "no manifest means no body art and a hidden sprite")
	check((_boss.get_node("Visual/Body") as CanvasItem).visible, "the body polygon is still drawn")
	var bare := true
	for head: HydraHead in _boss.get_heads():
		bare = bare and head.get_sprite() == null and head.get_neck() == null and head.get_stump_sprite() == null and head.get_clip() == &""
	check(bare, "no head wears a sprite, a textured neck or a stump sprite")
	var slabs := true
	for platform: Node in get_nodes_in_group(&"hydra_platform"):
		slabs = slabs and (platform.get_node("Visual") as CanvasItem).visible and platform.get_node_or_null("HydraArt") == null
	check(slabs, "every platform keeps its slab and gets no sprite")
	await _put_luz(Vector2(60.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(3)
	var venoms := _boss.get_active_venoms()
	check(not venoms.is_empty() and venoms.all(func(v: HydraVenom) -> bool: return v.get_glob_sprite() == null and v.get_pool_sprite() == null), "the venom has no sprite")
	var low := _head(HydraHead.Kind.BITER)
	_slash(low, 3)
	check(low.is_flashing() and low.get_sprite() == null, "a hit flashes the head polygon as before")
	var mid := _head(HydraHead.Kind.SWEEPER)
	_slash(mid, 12)
	await _frames(3)
	check(mid.is_severed() and mid.get_stump_sprite() == null, "a severed head keeps the drawn stump")
	check(_boss.get_telegraph()._sprite_fx == null and _boss.get_clip() == &"", "the phase glow stays on the polygon and no body clip is requested")


func case_art_body_sprite_and_clips() -> void:
	_write_art_fixture()
	await _build(false, false, ART_MANIFEST)
	await _frames(3)
	var sprite := _body_sprite()
	check(_boss.has_art() and sprite.visible, "a manifest with the idle clip means a visible body sprite")
	check(not (_boss.get_node("Visual/Body") as CanvasItem).visible, "the body polygon is hidden")
	check(sprite.offset == ART_BODY_OFFSET and is_equal_approx(absf(sprite.scale.x), ART_SCALE), "the offset puts the feet row on the origin and the scale is the manifest's")
	check(sprite.get_index() == 0 and sprite.material is ShaderMaterial, "the sprite is the first child of Visual with the glow shader")
	check(sprite.get_global_transform().x.x < 0.0, "the art faces the arena: Visual mirrors it")
	check(_boss.get_clip() == &"idle" and sprite.animation == &"idle", "the body idles")
	_boss.play_intro(1.0)
	await _frames(2)
	check(_boss.get_clip() == &"roar" and _lasts(sprite, &"roar", 1.0), "the intro roars as long as the intro lasts")
	_boss.engage()
	_tough_luz()
	await _frames(3)
	check(_boss.get_clip() == &"idle", "engaging ends the intro")
	var telegraph := _boss.get_telegraph()
	_slash(_head(HydraHead.Kind.SPITTER), 12)
	await _frames(3)
	check(_boss.get_state() == BossEnemy.State.TRANSITION and _boss.get_clip() == &"roar" and _lasts(sprite, &"roar", _boss.phase_transition_time), "a head dying roars for the phase beat")
	check(telegraph.is_glowing() and _glow_of(sprite) > 0.0 and not telegraph._glow.visible, "the phase glow lights the sprite, not the polygon")
	await _secs(_boss.phase_transition_time + 0.3)
	check(_boss.get_clip() == &"idle" and not telegraph.is_glowing(), "the beat ends back at idle with no glow")
	var shape := _boss.get_node("CollisionShape2D") as CollisionShape2D
	check((shape.shape as RectangleShape2D).size == Vector2(96.0, 140.0) and shape.position == Vector2(0.0, -70.0), "the body collision is untouched")
	_remove_art_fixture()


func case_art_defeat_and_corpse() -> void:
	_write_art_fixture()
	await _awake_art()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	var sprite := _body_sprite()
	check(_head(HydraHead.Kind.BITER).get_sprite().visible and _boss.get_node("Heads").visible, "the heads show while the fight runs")
	_slash(_head(HydraHead.Kind.BITER), 12)
	await _secs(1.0)
	_slash(_head(HydraHead.Kind.SWEEPER), 12)
	await _secs(1.0)
	check(_boss.get_node("Heads").visible and _boss.get_clip() != &"defeat", "a head dying does not hide the heads")
	_slash(_head(HydraHead.Kind.SPITTER), 12)
	await _frames(3)
	check(_boss.is_dead() and _boss.get_clip() == &"defeat" and _lasts(sprite, &"defeat", _boss.defeat_time, 0.1), "the last head dying plays the defeat clip, as long as the defeat")
	check(not _boss.get_node("Heads").visible, "the drawn defeat shows the severed necks itself: the heads are hidden")
	await _secs(0.6)
	var last: int = sprite.sprite_frames.get_frame_count(&"defeat") - 1
	check(sprite.frame == last and not sprite.is_playing(), "the corpse is the last frame of the defeat")
	check(is_equal_approx(sprite.get_global_transform().y.length(), ART_SCALE) and absf(sprite.get_global_transform().x.y) < 0.001, "the drawn slump replaces the placeholder's tilt and squash")
	# A corpse restored from an earlier run shows the last frame at once.
	await _build(false, true, ART_MANIFEST)
	await _frames(10)
	sprite = _body_sprite()
	check(_boss.is_dead() and _boss.get_clip() == &"defeat" and sprite.frame == last and not sprite.is_playing(), "a restored corpse shows the last defeat frame without playing")
	check(not _boss.get_node("Heads").visible and sprite.is_visible_in_tree(), "its heads are hidden and the body is drawn")
	# Without the defeat clip drawn the heads and their stumps show as before.
	_write_art_fixture(ART_ALL, ["defeat"])
	await _build(false, true, ART_MANIFEST)
	await _frames(10)
	check(_boss.is_dead() and _boss.get_node("Heads").visible, "no defeat clip keeps the heads (and their stumps) visible")
	var stumps := true
	for head: HydraHead in _boss.get_heads():
		stumps = stumps and head.get_stump_sprite().visible and not head.get_sprite().visible
	check(stumps, "every severed head shows its stump sprite and no head")
	_remove_art_fixture()


func case_art_heads_play_their_clips() -> void:
	# Gameplay numbers measured without art, to compare with the art on.
	await _awake_art(NO_ART_MANIFEST)
	var plain: Array[Rect2] = []
	var rests: Array[Vector2] = []
	for head: HydraHead in _boss.get_heads():
		plain.append(head.get_hurtbox_rect())
		rests.append(head.rest_global)
	_write_art_fixture()
	await _awake_art()
	_tough_luz()
	await _put_luz(Vector2(60.0, 0.0))
	var low := _head(HydraHead.Kind.BITER)
	var mid := _head(HydraHead.Kind.SWEEPER)
	var high := _head(HydraHead.Kind.SPITTER)
	var same := true
	for i: int in _boss.get_heads().size():
		var head := _boss.get_heads()[i]
		same = same and head.get_hurtbox_rect() == plain[i] and head.rest_global == rests[i]
	check(same, "the art moves no head and changes no hurtbox")
	var shaped := true
	for head: HydraHead in _boss.get_heads():
		var sprite := head.get_sprite()
		shaped = shaped and sprite != null and sprite.scale.x < 0.0 and is_equal_approx(absf(sprite.scale.x), ART_SCALE) and head.get_clip() == &"idle" and sprite.animation == &"idle"
	check(shaped, "every head wears a left-facing sprite that idles")
	check(low.get_sprite().sprite_frames != high.get_sprite().sprite_frames and low.get_sprite().material != high.get_sprite().material, "each head has its own frames and its own shader")
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	await _frames(2)
	check(low.get_clip() == &"telegraph", "the biter's coil shows the telegraph")
	await _await_run_phase(low, BossEnemy.AttackPhase.ACTIVE)
	check(low.get_clip() == &"attack" and low.get_sprite().animation == &"attack", "the lunge shows the attack")
	await _await_run_phase(low, BossEnemy.AttackPhase.RECOVER)
	check(low.is_stuck() and low.get_clip() == &"dazed" and not low._stuck_mark.visible, "the stuck biter shows the dazed clip and needs no code cross")
	await _wait_for(_attack_is_over, 3.0)
	await _secs(1.0)
	check(low.get_clip() == &"idle", "the biter idles again once it is home")
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(high.get_clip() == &"telegraph", "the spitter's wind-up shows the telegraph")
	await _await_run_phase(high, BossEnemy.AttackPhase.ACTIVE)
	check(high.get_clip() == &"attack" and high.is_roaring(), "the spitter spits with the attack clip, a roar per glob")
	await _wait_for(_attack_is_over, 4.0)
	await _secs(0.5)
	check(high.get_clip() == &"idle", "the spitter recovers at idle")
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(2)
	check(mid.get_clip() == &"telegraph", "the sweeper's pull-back shows the telegraph")
	await _await_run_phase(mid, BossEnemy.AttackPhase.ACTIVE)
	check(mid.get_clip() == &"attack", "the sweep shows the attack")
	await _wait_for(_attack_is_over, 4.0)
	await _secs(1.0)
	check(mid.get_clip() == &"idle", "the sweeper idles again after the sweep")
	_slash(low, 12)
	await _frames(3)
	check(mid.get_clip() == &"roar" and high.get_clip() == &"roar" and mid.get_sprite().animation == &"roar", "the living heads roar for the phase beat")
	check(low.is_severed() and not low.get_sprite().visible, "the severed head shows no head sprite")
	await _secs(_boss.phase_transition_time + 0.3)
	_slash(mid, 1)
	check(_flash_of(mid.get_sprite()) == 1.0 and _flash_of(high.get_sprite()) == 0.0, "a hit flashes the head that took it, on its own sprite")
	await _secs(mid.flash_time + 0.1)
	check(_flash_of(mid.get_sprite()) == 0.0, "the flash ends after flash_time")
	_boss.reset_to_spawn()
	await _frames(3)
	check(low.get_sprite().visible and low.get_clip() == &"idle" and low.get_neck().visible, "a reset puts the severed head back: sprite and neck")
	# A head sheet without `dazed`: the stuck head idles and the code draws the cross.
	_write_art_fixture(ART_ALL, ["dazed"])
	await _awake_art()
	await _put_luz(Vector2(60.0, 0.0))
	low = _head(HydraHead.Kind.BITER)
	_boss.start_attack(HydraBoss.Attack.BITE_LUNGE)
	await _await_run_phase(low, BossEnemy.AttackPhase.RECOVER)
	check(low.get_clip() == &"dazed" and low.get_sprite().animation == &"idle" and low._stuck_mark.visible, "dazed falls back to idle and the stuck cross marks the head")
	_remove_art_fixture()


func case_art_neck_and_stump() -> void:
	_write_art_fixture()
	await _awake_art()
	_tough_luz()
	await _put_luz(Vector2(-350.0, 0.0))
	var mid := _head(HydraHead.Kind.SWEEPER)
	var neck := mid.get_neck()
	check(neck != null and neck.texture != null and neck.texture_mode == Line2D.LINE_TEXTURE_TILE and neck.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "the neck is a tiled, repeating textured line")
	check(is_equal_approx(neck.width, ART_NECK) and neck.show_behind_parent, "its width is the manifest's thickness and it draws behind the head")
	var points := neck.points
	var shoulder := mid.to_local(mid.get_shoulder_global())
	check(points.size() == HydraHead.NECK_SEGMENTS + 1 and points[0].is_equal_approx(shoulder) and points[points.size() - 1] == Vector2.ZERO, "both ends of the neck are exact: the shoulder and the head")
	var sag := 0.0
	for i: int in points.size():
		sag = maxf(sag, absf(points[i].y - shoulder.lerp(Vector2.ZERO, float(i) / float(HydraHead.NECK_SEGMENTS)).y))
	check(sag > 0.0 and sag <= HydraHead.NECK_MAX_SAG + 0.01, "the resting neck sags a little, never past the limit (%.1f px)" % sag)
	_boss.start_attack(HydraBoss.Attack.NECK_SWEEP)
	await _frames(3)
	var flat := true
	for point: Vector2 in mid.get_neck().points:
		flat = flat and point.y == 0.0
	check(flat, "in a sweep the neck is laid flat at the head's height")
	await _wait_for(_attack_is_over, 4.0)
	await _secs(1.0)
	_slash(mid, 12)
	await _frames(3)
	var stump := mid.get_stump_sprite()
	check(not mid.get_neck().visible and not mid.get_sprite().visible, "a severed head loses its neck and its sprite")
	check(stump != null and stump.visible and stump.scale.x < 0.0, "the stump shows, facing left")
	var width := float(FIXTURE_PROPS["stump"][0]) * absf(stump.scale.x)
	check(is_equal_approx(width, HydraHead.STUMP_ART_WIDTH), "the stump is %.0f px wide" % HydraHead.STUMP_ART_WIDTH)
	shoulder = mid.to_local(mid.get_shoulder_global())
	var right_edge := stump.position.x + width * 0.5
	check(is_equal_approx(right_edge, shoulder.x + HydraHead.STUMP_ROOT_INSET) and is_equal_approx(stump.position.y, shoulder.y + HydraHead.STUMP_DROOP * 0.5), "its root sits on the shoulder, drooping like the placeholder")
	_remove_art_fixture()


func case_art_venom_wears_sprites() -> void:
	_write_art_fixture()
	await _awake_art()
	_tough_luz()
	await _put_luz(Vector2(60.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	var venom := _boss.get_active_venoms()[0]
	check(venom.is_marker_visible() and not venom.get_glob_sprite().visible and not venom.get_pool_sprite().visible, "while planned only the amber marker shows")
	await _wait_for(func() -> bool: return venom.is_flying(), 3.0)
	await _frames(1)
	var glob := venom.get_glob_sprite()
	check(glob.visible and venom.is_marker_visible() and not venom.get_pool_sprite().visible, "a flying glob wears its sprite and keeps the marker")
	check(is_equal_approx(float(FIXTURE_PROPS["venom_glob"][0]) * glob.scale.x, HydraVenom.GLOB_ART_SIZE), "the glob is %.0f px" % HydraVenom.GLOB_ART_SIZE)
	await _wait_for(func() -> bool: return venom.is_pool(), 3.0)
	var pool := venom.get_pool_sprite()
	check(pool.visible and not glob.visible and not venom.is_marker_visible(), "a landed puddle wears its sprite")
	var width := float(FIXTURE_PROPS["venom_pool"][0]) * pool.scale.x
	var height := float(FIXTURE_PROPS["venom_pool"][1]) * pool.scale.y
	check(is_equal_approx(width, _boss.venom_pool_width) and is_equal_approx(pool.position.y, -height * 0.5), "it is as wide as the puddle and stands on its surface")
	check(pool.sprite_frames.get_animation_loop(&"venom_pool") and pool.sprite_frames.get_frame_count(&"venom_pool") == 2, "the puddle is a two-frame loop")
	check(_sprites_of(venom, &"venom_splash").size() == 1, "the landing throws one splash")
	await _secs(0.5)
	check(_sprites_of(venom, &"venom_splash").is_empty(), "the splash frees itself")
	await _secs(_boss.venom_pool_time - 1.0)
	var blinked := false
	for i: int in 60:
		await physics_frame
		blinked = blinked or pool.modulate.a < 0.99
	check(blinked, "the puddle blinks before it dries")
	await _wait_for(func() -> bool: return not venom.is_pool(), 3.0)
	check(not pool.visible and not glob.visible, "a dried puddle shows no sprite")
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _wait_for(func() -> bool: return venom.is_active(), 1.0)
	_boss.reset_to_spawn()
	await _frames(3)
	check(not pool.visible and not glob.visible and not venom.is_active(), "releasing the venom hides its sprites")
	_remove_art_fixture()


func case_art_platforms_are_dressed() -> void:
	_write_art_fixture()
	await _build(false, false, ART_MANIFEST)
	await _frames(3)
	var names := ["PlatformLowLeft", "PlatformLowRight", "PlatformMid", "PlatformUpper", "PlatformTop"]
	var dressed := true
	var hidden := true
	var intact := true
	for platform_name: String in names:
		var platform := _platform(platform_name)
		dressed = dressed and platform.get_node_or_null("HydraArt") is AnimatedSprite2D
		hidden = hidden and not (platform.get_node("Visual") as CanvasItem).visible
		var collision := platform.get_node_or_null("CollisionShape2D") as CollisionShape2D
		intact = intact and collision != null and (collision.shape as RectangleShape2D).size == Vector2(160.0, 16.0) and collision.one_way_collision
	check(dressed and hidden, "every scanned platform wears a sprite and hides its slab")
	check(intact, "the collision child keeps its name, size and one-way rule")
	var first := _platform("PlatformLowLeft").get_node("HydraArt") as AnimatedSprite2D
	var second := _platform("PlatformLowRight").get_node("HydraArt") as AnimatedSprite2D
	var third := _platform("PlatformMid").get_node("HydraArt") as AnimatedSprite2D
	check(first.animation == &"platform" and second.animation == &"platform_alt" and third.animation == &"platform", "the two slabs alternate in scan order")
	check(is_equal_approx(float(FIXTURE_PROPS["platform"][0]) * first.scale.x, 160.0), "the slab is 160 px wide")
	var top := first.position.y - float(FIXTURE_PROPS["platform"][1]) * first.scale.y * 0.5
	var top_alt := second.position.y - float(FIXTURE_PROPS["platform_alt"][1]) * second.scale.y * 0.5
	check(is_equal_approx(top, -8.0) and is_equal_approx(top_alt, -8.0), "the art's top edge sits on the collision top and the rest hangs below")
	# A platform added later and one that moved are dressed on the next rescan, nothing is doubled.
	var added := StaticBody2D.new()
	added.name = "PlatformAdded"
	added.position = Vector2(300.0, -100.0)
	added.add_to_group(&"hydra_platform")
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(160.0, 16.0)
	shape.shape = rect
	added.add_child(shape)
	var slab := Polygon2D.new()
	slab.name = "Visual"
	added.add_child(slab)
	_arena.get_node("Platforms").add_child(added)
	_platform("PlatformMid").position.y = -90.0
	_boss.set_arena_limits(-468.0, 468.0)
	await _frames(2)
	check(added.get_node_or_null("HydraArt") != null and not slab.visible, "a platform added later is dressed on the rescan")
	var sprites := 0
	for platform_name: String in names:
		for child: Node in _platform(platform_name).get_children():
			sprites += 1 if child is AnimatedSprite2D else 0
	check(sprites == names.size(), "a rescan never doubles a sprite")
	check(third.get_parent() == _platform("PlatformMid") and third.position.is_equal_approx(first.position), "a moved platform keeps its sprite fitted to its collision")
	_remove_art_fixture()


func case_art_pieces_are_independent() -> void:
	# Only the heads: the body, the platforms and the venom keep their placeholders.
	_write_art_fixture(["heads"])
	await _awake_art()
	var head := _head(HydraHead.Kind.BITER)
	check(not _boss.has_art() and (_boss.get_node("Visual/Body") as CanvasItem).visible, "heads with art and a body without: the body polygon stays")
	check(head.get_sprite() != null and head.get_neck() == null and head.get_stump_sprite() == null, "the head wears its sprite while its neck and stump keep the placeholder")
	check(_platform("PlatformMid").get_node_or_null("HydraArt") == null and (_platform("PlatformMid").get_node("Visual") as CanvasItem).visible, "the platforms keep their slabs")
	await _put_luz(Vector2(60.0, 0.0))
	_boss.start_attack(HydraBoss.Attack.VENOM_VOLLEY)
	await _frames(2)
	check(_boss.get_active_venoms()[0].get_glob_sprite() == null, "the venom keeps its drawing")
	# Only the body.
	_write_art_fixture(["body"])
	await _awake_art()
	check(_boss.has_art() and _head(HydraHead.Kind.BITER).get_sprite() == null, "a body with art and heads without: the head polygons stay")
	# Only the props: platforms, stump and venom are dressed, the body and heads are not.
	_write_art_fixture(["props"])
	await _awake_art()
	head = _head(HydraHead.Kind.BITER)
	check(not _boss.has_art() and head.get_sprite() == null and head.get_stump_sprite() != null, "props alone dress the stump and nothing else of the head")
	check(_platform("PlatformMid").get_node_or_null("HydraArt") != null, "props alone dress the platforms")
	# Only the neck.
	_write_art_fixture(["neck"])
	await _awake_art()
	head = _head(HydraHead.Kind.BITER)
	check(head.get_neck() != null and head.get_sprite() == null and not _boss.has_art(), "a neck alone is a textured line under the head polygon")
	# A props sheet with no platform clips leaves the slabs.
	_write_art_fixture(["props"], ["platform", "platform_alt"])
	await _awake_art()
	check(_platform("PlatformMid").get_node_or_null("HydraArt") == null and (_platform("PlatformMid").get_node("Visual") as CanvasItem).visible, "a props sheet without platform clips keeps the slabs")
	_remove_art_fixture()

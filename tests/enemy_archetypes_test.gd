extends SceneTree
## Regression test for the airborne and charging archetypes on top of the enemy
## base: the Flyer (hover, line-of-sight aggro, steered chase, walls, give-up,
## light knockback, falling corpse) and the Charger (patrol, detection,
## telegraph -> charge -> recovery, ledges and walls, commitment), plus the
## persistence rules and the pogo for each of them.
## Run: godot --headless --path . --script res://tests/enemy_archetypes_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Timing-sensitive cases count physics steps instead of reading the clock.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FLYER_SCENE := "res://scenes/enemies/flyer.tscn"
const CHARGER_SCENE := "res://scenes/enemies/charger.tscn"
const WATCHDOG_SECONDS := 180.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const LEDGE_FLOOR := Rect2(-100.0, 0.0, 200.0, 200.0)
const ROOM_A := &"A"
const ROOM_B := &"B"
const BOUNCE_SPEED := -300.0
const BOUNCE_STEPS := 32

const CHECKS := {
	"case_flyer_hovers_near_its_spawn": 3,
	"case_flyer_needs_line_of_sight": 4,
	"case_flyer_chases_and_hurts": 4,
	"case_flyer_stops_at_walls_and_gives_up": 6,
	"case_flyer_leash": 1,
	"case_flyer_light_knockback_and_corpse": 6,
	"case_flyer_persistence": 7,
	"case_flyer_is_pogoable": 3,
	"case_charger_patrols": 3,
	"case_charger_detection": 4,
	"case_charger_sequence": 8,
	"case_charger_stops_at_a_ledge": 3,
	"case_charger_stops_at_a_wall": 3,
	"case_charger_commits": 5,
	"case_charger_persistence": 7,
	"case_charger_is_pogoable": 3,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _enemy: Enemy


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _tick() -> void:
	_clock += root.get_process_delta_time()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	_release_all()
	_free_rig()
	_registry().clear()
	_checkpoints().clear()
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


# -- Rig and helpers -----------------------------------------------------------------

## The autoloads are not compile-time globals in a --script run.
func _registry() -> Node:
	return root.get_node("EnemyRegistry")


func _checkpoints() -> Node:
	return root.get_node("CheckpointService")


## A floor (top at y=0), optionally with Luz on it at the origin, and the
## registry told that every spawn belongs to room A.
func _build_rig(with_player := true, floor_rect: Rect2 = FLOOR_RECT) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM_A
	if with_player:
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
		_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


func _add_enemy(scene_path: String, id: StringName, at: Vector2, facing := 1) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	enemy.enemy_id = id
	enemy.start_facing = facing
	enemy.position = at
	_rig.add_child(enemy)
	return enemy


func _spawn(scene_path: String, at: Vector2, facing := 1) -> void:
	_enemy = _add_enemy(scene_path, &"e1", at, facing)
	await _frames(SETTLE_FRAMES)


func _place_player(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO


func _add_wall(rect: Rect2) -> StaticBody2D:
	return LevelGeometry.add_solid(_rig, rect, Color.DIM_GRAY)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_enemy = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _steps(n: int) -> void:
	for i: int in n:
		await physics_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


## Follows the enemy for `seconds` of physics time and reports its extremes.
func _watch(seconds: float) -> Dictionary:
	var seen := {"min_x": 1e9, "max_x": -1e9, "min_y": 1e9, "max_y": -1e9, "max_speed": 0.0, "turns": 0}
	var last_sign := signf(_enemy.velocity.x)
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		var at := _enemy.global_position
		seen["min_x"] = minf(seen["min_x"], at.x)
		seen["max_x"] = maxf(seen["max_x"], at.x)
		seen["min_y"] = minf(seen["min_y"], at.y)
		seen["max_y"] = maxf(seen["max_y"], at.y)
		seen["max_speed"] = maxf(seen["max_speed"], _enemy.velocity.length())
		var sign_now := signf(_enemy.velocity.x)
		if sign_now != 0.0 and last_sign != 0.0 and sign_now != last_sign:
			seen["turns"] += 1
		if sign_now != 0.0:
			last_sign = sign_now
	return seen


## Places her in the air and lets a few physics steps pass.
func _drop_player_at(at: Vector2) -> void:
	_place_player(at)
	await _steps(3)


## Down slash from above a frozen enemy; reports whether Luz bounced.
func _pogo_off_enemy(scene_path: String, enemy_at: Vector2, luz_y: float) -> void:
	await _build_rig()
	_place_player(Vector2(-300.0, 0.0))
	await _steps(3)
	await _spawn(scene_path, enemy_at)
	_enemy.set_ai_active(false)
	var health_before := _enemy.get_health()
	await _drop_player_at(Vector2(enemy_at.x, luz_y))
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var bounced := false
	for i: int in BOUNCE_STEPS:
		await physics_frame
		bounced = bounced or _player.velocity.y < BOUNCE_SPEED
	check(bounced, "the down slash bounces Luz off it")
	check(_enemy.get_health() == health_before - 1, "and it took the hit (%d)" % _enemy.get_health())
	check(_player.get_health() == 3, "she took no damage (%d)" % _player.get_health())
	Input.action_release(&"move_down")


## Rules 1 to 3 for whichever archetype is in `_enemy`, spawned at `spawn`.
func _check_persistence(scene_path: String, spawn: Vector2) -> void:
	await _build_rig(false)
	await _spawn(scene_path, spawn)
	_enemy.receive_hit(1, spawn + Vector2(-60.0, 0.0))
	_enemy.global_position += Vector2(300.0, 0.0)
	_registry().enter_room(ROOM_B)
	_registry().enter_room(ROOM_A)
	check(_enemy.get_health() == _enemy.max_health, "rule 2: re-entry restores full health (%d)" % _enemy.get_health())
	check(_enemy.global_position.distance_to(spawn) < 1.0, "rule 2: and puts it back at its spawn")
	_enemy.receive_hit(_enemy.max_health, spawn + Vector2(-60.0, 0.0))
	await _secs(1.5)
	var corpse_at := _enemy.global_position
	_registry().enter_room(ROOM_B)
	_registry().enter_room(ROOM_A)
	await _frames(3)
	check(_enemy.is_dead() and _registry().has_kill(&"e1"), "rule 1: the killed enemy stays dead across rooms")
	check(_enemy.global_position.distance_to(corpse_at) < 1.0, "rule 1: its corpse did not move")
	_checkpoints().reset_resettable_enemies()
	check(not _enemy.is_dead() and _enemy.get_health() == _enemy.max_health, "rule 3: a desk rest revives it at full health")
	check(_enemy.global_position.distance_to(spawn) < 1.0, "rule 3: at its spawn")
	check(not _registry().has_kill(&"e1") and _enemy.collision_layer == Enemy.ENEMY_LAYER, "rule 3: the record is gone and it is solid again")


# -- Flyer ---------------------------------------------------------------------------

func case_flyer_hovers_near_its_spawn() -> void:
	await _build_rig(false)
	await _spawn(FLYER_SCENE, Vector2(0.0, -150.0))
	var home := _enemy.get_spawn_position()
	var seen := await _watch(4.0)
	var reach := maxf(absf(seen["max_x"] - home.x), maxf(absf(seen["max_y"] - home.y), absf(seen["min_y"] - home.y)))
	check(reach < 14.0, "idle, it stays within a few pixels of its spawn (%.1f)" % reach)
	check(seen["max_y"] - seen["min_y"] > 2.0, "and bobs gently (%.1f px)" % [seen["max_y"] - seen["min_y"]])
	check(not (_enemy as Flyer).is_engaged(), "with nobody around it does not aggro")


func case_flyer_needs_line_of_sight() -> void:
	await _build_rig()
	var wall := _add_wall(Rect2(60.0, -400.0, 20.0, 400.0))
	await _spawn(FLYER_SCENE, Vector2(180.0, -60.0), -1)
	var flyer := _enemy as Flyer
	var far := _add_enemy(FLYER_SCENE, &"far", Vector2(400.0, -60.0), -1) as Flyer
	await _secs(0.8)
	check(not flyer.is_engaged(), "a wall between them blocks the aggro")
	check(flyer.global_position.distance_to(flyer.get_spawn_position()) < 14.0, "so it keeps hovering")
	check(not far.is_engaged(), "out of aggro range it ignores her even in sight")
	wall.free()
	await _secs(0.4)
	check(flyer.is_engaged(), "once the wall is gone it sees her and engages")


func case_flyer_chases_and_hurts() -> void:
	await _build_rig()
	await _spawn(FLYER_SCENE, Vector2(160.0, -60.0), -1)
	var flyer := _enemy as Flyer
	var closest := 1e9
	var top_speed := 0.0
	for i: int in 180:
		await physics_frame
		closest = minf(closest, flyer.get_body_center().distance_to(_player.global_position + Vector2(0.0, -29.0)))
		top_speed = maxf(top_speed, flyer.velocity.length())
	check(top_speed > 100.0, "it speeds up to cruising speed (%.0f)" % top_speed)
	check(top_speed <= flyer.chase_max_speed + 1.0, "but never beyond its max speed (%.0f)" % top_speed)
	check(closest < 30.0, "it reaches her (closest %.0f)" % closest)
	check(_player.get_health() < 3, "touching it costs a pip (%d)" % _player.get_health())


func case_flyer_stops_at_walls_and_gives_up() -> void:
	await _build_rig()
	await _spawn(FLYER_SCENE, Vector2(180.0, -60.0), -1)
	var flyer := _enemy as Flyer
	await _secs(0.3)
	check(flyer.is_engaged(), "it engages in plain sight")
	_add_wall(Rect2(60.0, -400.0, 20.0, 400.0))
	var min_x := 1e9
	var returned := false
	for i: int in 360:
		await physics_frame
		min_x = minf(min_x, flyer.global_position.x)
		returned = returned or flyer.is_returning()
	check(min_x > 93.0, "it slides along the wall and never passes through (min x %.1f)" % min_x)
	check(_player.get_health() == 3, "so it never reaches her")
	check(returned, "after losing sight for a while it gives up and heads home")
	check(not flyer.is_engaged() and not flyer.is_returning(), "and then hovers again")
	check(flyer.global_position.distance_to(flyer.get_spawn_position()) < 14.0, "at its spawn")


func case_flyer_leash() -> void:
	await _build_rig()
	_enemy = _add_enemy(FLYER_SCENE, &"e1", Vector2(150.0, -60.0), -1)
	(_enemy as Flyer).leash_distance = 40.0
	var returned := false
	for i: int in 180:
		await physics_frame
		returned = returned or (_enemy as Flyer).is_returning()
	check(returned, "straying past the leash sends it home even with Luz in sight")


func case_flyer_light_knockback_and_corpse() -> void:
	await _build_rig(false)
	await _spawn(FLYER_SCENE, Vector2(200.0, -100.0), -1)
	_enemy.receive_hit(1, Vector2(150.0, -100.0))
	await _secs(0.45)
	check(_enemy.global_position.x > 200.0 + 40.0, "a hit knocks it back strongly (x %.0f)" % _enemy.global_position.x)
	check(_enemy.get_health() == 1, "2 HP: one hit leaves 1")
	_enemy.receive_hit(1, Vector2(150.0, -100.0))
	check(_enemy.is_dead(), "and the second kills it")
	var died_in_air := _enemy.global_position.y < -60.0
	check(died_in_air, "it dies in the air (y %.0f)" % _enemy.global_position.y)
	await _secs(1.5)
	check(absf(_enemy.global_position.y) < 2.0, "the corpse falls to the floor (y %.1f)" % _enemy.global_position.y)
	check(not _enemy.is_physics_processing(), "and stays there")


func case_flyer_persistence() -> void:
	await _check_persistence(FLYER_SCENE, Vector2(40.0, -120.0))


func case_flyer_is_pogoable() -> void:
	await _pogo_off_enemy(FLYER_SCENE, Vector2(0.0, -100.0), -175.0)


# -- Charger -------------------------------------------------------------------------

func case_charger_patrols() -> void:
	await _build_rig(false, LEDGE_FLOOR)
	await _spawn(CHARGER_SCENE, Vector2.ZERO)
	var seen := await _watch(8.0)
	check(seen["max_y"] < 2.0, "it never falls off the platform (max y %.1f)" % seen["max_y"])
	check(seen["max_x"] > 50.0 and seen["min_x"] < -50.0, "it patrols both ways (x %.0f..%.0f)" % [seen["min_x"], seen["max_x"]])
	check(seen["max_speed"] < 55.0, "at about 50 px/s (%.0f)" % seen["max_speed"])


func case_charger_detection() -> void:
	await _build_rig()
	_add_wall(Rect2(180.0, -90.0, 80.0, 20.0))
	await _spawn(CHARGER_SCENE, Vector2.ZERO)
	var charger := _enemy as Charger
	charger.walk_speed = 0.0
	_place_player(Vector2(200.0, 0.0))
	await _secs(0.3)
	check(charger.get_phase() == Charger.Phase.TELEGRAPH, "Luz ahead, in range and in sight starts the telegraph")
	charger.reset_to_spawn()
	_place_player(Vector2(-200.0, 0.0))
	await _secs(0.5)
	check(charger.get_phase() == Charger.Phase.PATROL, "behind it she is ignored")
	_place_player(Vector2(200.0, -90.0))
	await _secs(0.5)
	var on_ledge := absf(_player.global_position.y + 90.0) < 2.0
	check(on_ledge and charger.get_phase() == Charger.Phase.PATROL, "too far above (outside the vertical band) she is ignored")
	_place_player(Vector2(320.0, 0.0))
	await _secs(0.5)
	check(charger.get_phase() == Charger.Phase.PATROL, "beyond the horizontal range she is ignored")


func case_charger_sequence() -> void:
	await _build_rig()
	await _spawn(CHARGER_SCENE, Vector2.ZERO)
	var charger := _enemy as Charger
	_place_player(Vector2(200.0, 0.0))
	var dt := 1.0 / Engine.physics_ticks_per_second
	var marks := {"telegraph": -1.0, "charge": -1.0, "recover": -1.0, "patrol": -1.0}
	var x_at := {"telegraph": 0.0, "charge": 0.0, "recover": 0.0, "patrol": 0.0}
	var phase_names := {Charger.Phase.TELEGRAPH: "telegraph", Charger.Phase.CHARGE: "charge", Charger.Phase.RECOVER: "recover"}
	var last_phase := charger.get_phase()
	var top_speed := 0.0
	var t := 0.0
	for i: int in int(4.0 / dt):
		await physics_frame
		t += dt
		var phase := charger.get_phase()
		if phase == Charger.Phase.CHARGE:
			top_speed = maxf(top_speed, absf(charger.velocity.x))
		if phase != last_phase:
			var key: String = phase_names.get(phase, "patrol")
			if marks[key] < 0.0:
				marks[key] = t
				x_at[key] = charger.global_position.x
			last_phase = phase
	check(absf(marks["charge"] - marks["telegraph"] - charger.telegraph_time) < 0.1, "the telegraph lasts about %.2f s (%.2f)" % [charger.telegraph_time, marks["charge"] - marks["telegraph"]])
	check(absf(x_at["charge"] - x_at["telegraph"]) < 1.0, "it stands still while telegraphing")
	check(top_speed >= charger.charge_speed - 10.0, "the charge is fast (%.0f px/s)" % top_speed)
	check(absf(marks["recover"] - marks["charge"] - charger.charge_time) < 0.1, "a clear run lasts about %.1f s (%.2f)" % [charger.charge_time, marks["recover"] - marks["charge"]])
	check(absf(marks["patrol"] - marks["recover"] - charger.recover_time) < 0.1, "the recovery window lasts about %.1f s (%.2f)" % [charger.recover_time, marks["patrol"] - marks["recover"]])
	check(absf(x_at["patrol"] - x_at["recover"]) < 1.0, "and it stands still through it")
	check(charger.get_phase() == Charger.Phase.PATROL and absf(charger.velocity.x) > 40.0, "then it patrols again")
	check(_player.get_health() < 3, "the charge hurts on contact (%d)" % _player.get_health())


func case_charger_stops_at_a_ledge() -> void:
	await _build_rig(false, LEDGE_FLOOR)
	await _spawn(CHARGER_SCENE, Vector2(-60.0, 0.0))
	var charger := _enemy as Charger
	charger.walk_speed = 0.0
	charger._set_phase(Charger.Phase.TELEGRAPH)
	var seen := await _watch(2.5)
	check(seen["max_y"] < 2.0, "it never falls off the platform (max y %.1f)" % seen["max_y"])
	check(seen["max_x"] > 40.0 and seen["max_x"] < 100.0, "it ran toward the edge and stopped over the floor (max x %.0f)" % seen["max_x"])
	check(charger.get_phase() != Charger.Phase.CHARGE, "the charge ended early at the ledge")


func case_charger_stops_at_a_wall() -> void:
	await _build_rig(false)
	_add_wall(Rect2(150.0, -200.0, 40.0, 200.0))
	await _spawn(CHARGER_SCENE, Vector2.ZERO)
	var charger := _enemy as Charger
	charger.walk_speed = 0.0
	charger._set_phase(Charger.Phase.TELEGRAPH)
	var seen := await _watch(1.2)
	check(seen["max_x"] <= 150.0 - 15.0 + 2.0, "it stops at the wall (max x %.1f)" % seen["max_x"])
	check(seen["max_x"] > 100.0, "after running at it (max x %.1f)" % seen["max_x"])
	check(charger.get_phase() == Charger.Phase.RECOVER, "and goes into recovery instead of pushing on")


func case_charger_commits() -> void:
	await _build_rig(false)
	await _spawn(CHARGER_SCENE, Vector2.ZERO)
	var charger := _enemy as Charger
	charger.walk_speed = 0.0
	charger._set_phase(Charger.Phase.TELEGRAPH)
	await _steps(5)
	var held_x := charger.global_position.x
	charger.receive_hit(1, Vector2(held_x + 40.0, 0.0))
	await _steps(5)
	check(absf(charger.global_position.x - held_x) < 1.0, "a hit during the telegraph does not push it (x %.2f, phase %d)" % [charger.global_position.x, charger.get_phase()])
	check(charger.get_health() == 2, "but it does hurt")
	await _secs(0.5)
	check(charger.get_phase() == Charger.Phase.CHARGE, "and the charge still comes")
	charger.receive_hit(1, Vector2(charger.global_position.x + 200.0, 0.0))
	check(absf(charger._recoil_velocity) < charger.recoil_speed * 0.5, "a hit during the charge only shoves a little (%.0f)" % charger._recoil_velocity)
	await _secs(0.3)
	check(charger.get_phase() == Charger.Phase.CHARGE and charger.global_position.x > held_x + 30.0, "and it keeps charging")


func case_charger_persistence() -> void:
	await _check_persistence(CHARGER_SCENE, Vector2(40.0, 0.0))


func case_charger_is_pogoable() -> void:
	await _pogo_off_enemy(CHARGER_SCENE, Vector2.ZERO, -110.0)

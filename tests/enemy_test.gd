extends SceneTree
## Regression test for the enemy base, the walker, room persistence and the
## player's hit recoil: patrol, contact damage, death into a corpse, the three
## persistence rules and the pause of off-room enemies.
## Run: godot --headless --path . --script res://tests/enemy_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WALKER_SCENE := "res://scenes/enemies/walker.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const LEDGE_FLOOR := Rect2(-100.0, 0.0, 200.0, 200.0)
const WALL_RECT := Rect2(150.0, -100.0, 40.0, 100.0)
## Longer than the i-frames plus the hit-stop that precedes them.
const IFRAMES_OVER := 1.2
const DEATH_BEAT := 1.0
## Where a stationary walker stands in front of Luz, inside her slash reach.
const WALKER_AHEAD := Vector2(60.0, 0.0)
const ROOM_A := &"A"
const ROOM_B := &"B"

const CHECKS := {
	"case_patrols_and_turns_at_ledges": 4,
	"case_turns_at_a_wall": 3,
	"case_contact_damages_once": 3,
	"case_two_hits_kill": 10,
	"case_hit_reaction": 5,
	"case_corpse_falls_and_rests": 3,
	"case_rule_1_corpse_persists_across_rooms": 5,
	"case_rule_1_corpse_survives_a_reload": 3,
	"case_rule_2_room_reentry_resets_the_living": 5,
	"case_off_room_enemies_pause": 3,
	"case_rule_3_desk_rest_revives": 6,
	"case_rule_3_death_revives": 4,
	"case_player_recoil_on_hit": 4,
	"case_no_recoil_without_a_hit": 1,
	"case_recoil_keeps_the_air_jump": 2,
	"case_time_scale_untouched": 1,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _walker: Walker
var _died_events := 0
var _hit_events: Array[Vector2i] = []
var _health_events := 0


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


## A flat floor (top at y=0), optionally with Luz on it, and the registry
## told that every spawn belongs to room A.
func _build_rig(with_player := true, floor_rect: Rect2 = FLOOR_RECT) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM_A
	if with_player:
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
		_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


func _add_walker(id: StringName, at: Vector2, facing := 1, speed := 0.0) -> Walker:
	var walker := (load(WALKER_SCENE) as PackedScene).instantiate() as Walker
	walker.enemy_id = id
	walker.start_facing = facing
	walker.walk_speed = speed
	walker.position = at
	walker.died.connect(func(_enemy: Enemy) -> void: _died_events += 1)
	walker.hit.connect(func(amount: int, remaining: int) -> void: _hit_events.append(Vector2i(amount, remaining)))
	_rig.add_child(walker)
	return walker


func _spawn_walker(id: StringName = &"w1", at := WALKER_AHEAD, facing := 1, speed := 0.0) -> void:
	_died_events = 0
	_hit_events.clear()
	_walker = _add_walker(id, at, facing, speed)
	await _frames(SETTLE_FRAMES)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_walker = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


## One slash at the walker, then waits for it to resolve and for Luz to settle.
func _slash_walker() -> void:
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	await _frames(2)
	_player.request_attack(0)
	await _secs(0.5)


## Walks the patrol for `seconds`, tracking how far it ever got.
func _watch_patrol(seconds: float) -> Dictionary:
	var seen := {"min_x": 1e9, "max_x": -1e9, "max_y": -1e9, "turns": 0}
	var last_sign := signf(_walker.velocity.x)
	var end := _clock + seconds
	while _clock < end:
		await process_frame
		var x := _walker.global_position.x
		seen["min_x"] = minf(seen["min_x"], x)
		seen["max_x"] = maxf(seen["max_x"], x)
		seen["max_y"] = maxf(seen["max_y"], _walker.global_position.y)
		var sign_now := signf(_walker.velocity.x)
		if sign_now != 0.0 and last_sign != 0.0 and sign_now != last_sign:
			seen["turns"] += 1
		if sign_now != 0.0:
			last_sign = sign_now
	return seen


# -- Cases -----------------------------------------------------------------------

func case_patrols_and_turns_at_ledges() -> void:
	await _build_rig(false, LEDGE_FLOOR)
	await _spawn_walker(&"w1", Vector2.ZERO, 1, 60.0)
	var seen := await _watch_patrol(6.0)
	check(seen["max_y"] < 2.0, "the walker never falls off the platform (max y %.1f)" % seen["max_y"])
	check(seen["max_x"] > 50.0 and seen["min_x"] < -50.0, "it patrols both ways (x %.0f..%.0f)" % [seen["min_x"], seen["max_x"]])
	check(seen["max_x"] <= LEDGE_FLOOR.end.x and seen["min_x"] >= LEDGE_FLOOR.position.x, "its centre stays over the platform")
	check(seen["turns"] >= 2, "it turned around at both ledges (%d turns)" % seen["turns"])


func case_turns_at_a_wall() -> void:
	await _build_rig(false)
	LevelGeometry.add_solid(_rig, WALL_RECT, Color.DIM_GRAY)
	await _spawn_walker(&"w1", Vector2(60.0, 0.0), 1, 60.0)
	var seen := await _watch_patrol(3.0)
	var front := WALL_RECT.position.x - 20.0
	check(seen["max_x"] <= front + 2.0, "it stops at the wall (max x %.1f, wall front %.1f)" % [seen["max_x"], front])
	check(seen["turns"] >= 1, "it turns back at the wall (%d turns)" % seen["turns"])
	check(_walker.global_position.x < seen["max_x"] - 20.0, "and walks away from it (x %.0f)" % _walker.global_position.x)


func case_contact_damages_once() -> void:
	await _build_rig()
	_health_events = 0
	_player.health_changed.connect(func(_current: int, _maximum: int) -> void: _health_events += 1)
	await _spawn_walker(&"w1", Vector2.ZERO, 1, 0.0)
	await _secs(0.8)
	check(_player.get_health() == 2, "touching the walker costs one pip (%d)" % _player.get_health())
	check(_health_events == 1, "and fires health_changed once (%d)" % _health_events)
	_player.global_position = Vector2.ZERO
	_player.velocity = Vector2.ZERO
	await _secs(IFRAMES_OVER)
	check(_player.get_health() <= 1, "contact hurts again after the i-frames (%d)" % _player.get_health())


func case_two_hits_kill() -> void:
	await _build_rig()
	await _spawn_walker()
	var contact := _walker.get_node("ContactDamage") as ContactDamage
	await _slash_walker()
	check(_walker.get_health() == 1 and not _walker.is_dead(), "one slash leaves it at 1 health (%d)" % _walker.get_health())
	await _slash_walker()
	check(_walker.is_dead(), "the second slash kills it")
	var died_at := _walker.global_position
	check(_died_events == 1, "died fires exactly once (%d)" % _died_events)
	check(_hit_events == [Vector2i(1, 1), Vector2i(1, 0)], "hit reports the damage and what is left: %s" % [_hit_events])
	check(_walker.collision_layer == 0, "the corpse is off every layer")
	check(not contact.monitoring, "the corpse no longer deals contact damage")
	check(is_instance_valid(_walker) and _walker.is_inside_tree(), "the corpse stays in the world")
	_player.global_position = _walker.global_position
	await _secs(0.4)
	check(_player.get_health() == 3, "Luz walks through the corpse unharmed (%d)" % _player.get_health())
	check(_walker.global_position.distance_to(died_at) < 3.0, "it lies where it died (%s)" % _walker.global_position)
	check(not _walker.receive_hit(1, Vector2.ZERO), "a corpse cannot be hit again")


func case_hit_reaction() -> void:
	await _build_rig()
	await _spawn_walker()
	var flash := _walker.get_node("Visual").get_child(-1) as Polygon2D
	check(flash != null and not flash.visible, "the hurt flash starts hidden")
	_walker.receive_hit(1, Vector2.ZERO)
	check(flash.visible and flash.color == Color.WHITE, "a hit flashes the body white")
	var before := _walker.global_position.x
	await _secs(0.3)
	check(_walker.global_position.x > before + 4.0, "the hit shoves it away from the source (x %.1f)" % _walker.global_position.x)
	await _secs(0.15)
	check(not flash.visible, "the flash ends quickly")
	check(_walker.get_health() == 1, "the hit cost one health")


func case_corpse_falls_and_rests() -> void:
	await _build_rig(false)
	await _spawn_walker(&"w1", Vector2(0.0, -200.0))
	_walker.receive_hit(2, Vector2(-50.0, -200.0))
	check(_walker.is_dead() and _walker.global_position.y < -150.0, "it dies in the air")
	await _secs(1.0)
	check(absf(_walker.global_position.y) < 2.0, "the corpse falls to the floor (y %.1f)" % _walker.global_position.y)
	check(not _walker.is_physics_processing(), "and then freezes")


func case_rule_1_corpse_persists_across_rooms() -> void:
	await _build_rig()
	await _spawn_walker()
	_walker.receive_hit(2, Vector2.ZERO)
	var at := _walker.global_position
	await _secs(0.3)
	_registry().enter_room(ROOM_B)
	_registry().enter_room(ROOM_A)
	await _frames(3)
	check(_walker.is_dead(), "the killed walker is still dead after leaving and re-entering")
	check(_walker.global_position.distance_to(at) < 1.0, "its corpse did not move")
	check(_walker.visible and _walker.get_node("Visual").visible, "and it is still visible")
	check(_registry().has_kill(&"w1"), "the registry holds the kill")
	check(_walker.get_health() == 0, "with no health back")


func case_rule_1_corpse_survives_a_reload() -> void:
	await _build_rig()
	await _spawn_walker()
	_walker.receive_hit(2, Vector2.ZERO)
	var at := _walker.global_position
	await _secs(0.3)
	_walker.free()
	_walker = _add_walker(&"w1", Vector2(-200.0, 0.0))
	await _frames(SETTLE_FRAMES)
	check(_walker.is_dead(), "the same id comes back as a corpse after the scene reloads")
	check(_walker.global_position.distance_to(at) < 3.0, "lying where it died, not at its spawn (%s)" % _walker.global_position)
	check(_walker.collision_layer == 0, "still non-colliding")


func case_rule_2_room_reentry_resets_the_living() -> void:
	await _build_rig(false)
	await _spawn_walker(&"w1", Vector2(40.0, 0.0), -1, 60.0)
	_walker.receive_hit(1, Vector2(100.0, 0.0))
	_walker.global_position = Vector2(500.0, 0.0)
	_walker._facing = 1
	_registry().enter_room(ROOM_B)
	check(_walker.get_health() == 1 and _walker.global_position.x == 500.0, "other rooms do not reset it")
	_registry().enter_room(ROOM_A)
	check(_walker.get_health() == _walker.max_health, "re-entering its room restores full health (%d)" % _walker.get_health())
	check(_walker.global_position.distance_to(Vector2(40.0, 0.0)) < 1.0, "and puts it back at its spawn (%s)" % _walker.global_position)
	check(_walker.get_facing() == -1, "facing its spawn direction")
	check(not _walker.is_dead() and _walker.velocity == Vector2.ZERO, "alive and idle")


func case_off_room_enemies_pause() -> void:
	await _build_rig(false)
	await _spawn_walker(&"w1", Vector2.ZERO, 1, 60.0)
	await _secs(0.3)
	check(_walker.global_position.x > 5.0, "an enemy in the active room walks")
	_registry().set_active_room(ROOM_B)
	var parked := _walker.global_position
	await _secs(0.3)
	check(not _walker.is_ai_active() and _walker.global_position == parked, "an off-room enemy is paused")
	_registry().enter_room(ROOM_A)
	await _secs(0.3)
	check(_walker.is_ai_active() and _walker.global_position.x != parked.x, "it wakes when Luz comes back")


func case_rule_3_desk_rest_revives() -> void:
	await _build_rig(false)
	await _spawn_walker(&"w1", Vector2(40.0, 0.0))
	_walker.receive_hit(2, Vector2.ZERO)
	await _secs(0.3)
	_registry().enter_room(ROOM_B)
	check(_walker.is_dead(), "dead before the rest")
	_checkpoints().reset_resettable_enemies()
	check(not _walker.is_dead() and _walker.get_health() == _walker.max_health, "a desk rest revives it at full health")
	check(_walker.global_position.distance_to(Vector2(40.0, 0.0)) < 1.0, "at its spawn")
	check(_walker.collision_layer == Enemy.ENEMY_LAYER and (_walker.get_node("ContactDamage") as ContactDamage).monitoring, "solid and dangerous again")
	check(not _registry().has_kill(&"w1"), "the corpse record is gone")
	check(_walker.get_node("Visual").modulate == Color.WHITE, "and the corpse tint is gone")


func case_rule_3_death_revives() -> void:
	await _build_rig()
	await _spawn_walker(&"w1", Vector2(300.0, 0.0))
	_walker.receive_hit(2, Vector2.ZERO)
	for i: int in 3:
		_player.take_damage(1, Vector2(-100.0, -30.0))
		if i < 2:
			await _secs(IFRAMES_OVER)
	await _frames(3)
	check(_walker.is_dead(), "the corpse stays during the death fade, so nothing visibly resets early")
	await _secs(DEATH_BEAT)
	check(not _walker.is_dead() and _walker.get_health() == _walker.max_health, "Luz's death revives it at full health")
	check(_walker.global_position.distance_to(Vector2(300.0, 0.0)) < 1.0, "at its spawn")
	check(not _registry().has_kill(&"w1"), "and the kill record is cleared")


func case_player_recoil_on_hit() -> void:
	await _build_rig()
	await _spawn_walker()
	_player.global_position = Vector2.ZERO
	_player.request_attack(0)
	await _secs(0.3)
	check(_walker.get_health() == 1, "the slash landed")
	check(_player.global_position.x < -4.0, "Luz is pushed away from the target (x %.1f)" % _player.global_position.x)
	check(_player.global_position.x > -30.0, "only slightly (x %.1f)" % _player.global_position.x)
	check(_player._state != Player.State.HURT, "the recoil is not a hurt state")


func case_no_recoil_without_a_hit() -> void:
	await _build_rig()
	_player.request_attack(0)
	await _secs(0.4)
	check(absf(_player.global_position.x) < 1.0, "a slash that hits nothing does not move her (x %.1f)" % _player.global_position.x)


func case_recoil_keeps_the_air_jump() -> void:
	await _build_rig()
	_player.can_double_jump = true
	await _spawn_walker(&"w1", Vector2(60.0, 0.0))
	_player.global_position = Vector2(0.0, -14.0)
	_player.velocity = Vector2.ZERO
	_player.request_attack(0)
	await _secs(0.3)
	check(_walker.get_health() == 1, "the air slash landed")
	check(_player._air_jumps_left == _player.air_jumps, "the recoil leaves her air jump alone")


func case_time_scale_untouched() -> void:
	await _build_rig()
	await _spawn_walker()
	_walker.receive_hit(1, Vector2.ZERO)
	await _frames(2)
	check(Engine.time_scale == 1.0, "enemy hit-stop never touches Engine.time_scale")

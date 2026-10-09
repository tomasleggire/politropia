extends SceneTree
## Regression test for the Greece population: enemy placements, spikes, the
## fairness rules around them, and the real level booting with them.
## Run: godot --headless --path . --script res://tests/greece_population_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.

const Reach := preload("res://tests/support/greece_reach.gd")
const Probe := preload("res://tests/support/greece_probe.gd")
const WATCHDOG_SECONDS := 120.0
const BODY_CENTER := GreeceLayout.BODY_CENTER_OFFSET
const SAFE_MARGIN := 60.0
const FULL_JUMP := 130.0
const WALKER_ID := &"greece_b2_walker_a"
const HIGH_DAMAGE := 99
## Rooms that must stay free of regular enemies.
const SAFE_ROOMS: Array[String] = ["Entrada", "Altar", "T3"]
## enemy_id -> [archetype, camera room].
const EXPECTED := {
	&"greece_b2_walker_a": [&"walker", "B2"],
	&"greece_shaft_flyer_a": [&"flyer", "Shaft"],
	&"greece_shaft_flyer_b": [&"flyer", "Shaft"],
	&"greece_t1_flyer_a": [&"flyer", "T1"],
	&"greece_t2_charger_a": [&"charger", "T2"],
	&"greece_t2_shooter_a": [&"shooter", "T2"],
	&"greece_exit_shooter_a": [&"shooter", "Exit"],
	&"greece_b3_walker_a": [&"walker", "B3"],
	&"greece_b3_charger_a": [&"charger", "B3"],
}
## Classes of the nodes each archetype must spawn as.
const ARCHETYPE_CLASSES := {
	&"walker": "Walker",
	&"flyer": "Flyer",
	&"charger": "Charger",
	&"shooter": "Shooter",
}
## Spawn offset from the origin (feet) to the body centre; flyers hover.
const HOVER_CENTER := {&"flyer": -11.0, &"shooter": -14.0}

const CHECKS := {
	"case_enemy_data": 6,
	"case_enemy_placement": 3,
	"case_arrival_clearance": 2,
	"case_spikes_geometry": 5,
	"case_spikes_critical_path": 4,
	"case_probe_boot": 6,
	"case_probe_spikes_jumpable": 2,
	"case_probe_persistence": 5,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _probe: Probe


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_probe = Probe.new(self)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
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


# -- Helpers ---------------------------------------------------------------------

func _registry() -> Node:
	return root.get_node("EnemyRegistry")


func _checkpoints() -> Node:
	return root.get_node("CheckpointService")


func _home_room(entry: Dictionary) -> String:
	var spawn: Vector2 = entry["position"]
	return GreeceLayout.camera_room(GreeceLayout.room_for(spawn + BODY_CENTER, ""))


func _body_center(entry: Dictionary) -> Vector2:
	var spawn: Vector2 = entry["position"]
	return spawn + Vector2(0.0, HOVER_CENTER.get(entry["archetype"], -20.0))


## Every place where Luz appears: both ends of every doorway, the level spawn
## and the desk.
func _arrival_points() -> Array[Vector2]:
	var points: Array[Vector2] = [GreeceLayout.SPAWN, GreeceLayout.DESK_POSITION]
	for door: Dictionary in GreeceLayout.doorways():
		points.append(door["from_arrival"])
		points.append(door["to_arrival"])
	return points


func _solid_covering(point: Vector2) -> bool:
	for rect: Rect2 in GreeceLayout.solids() + GreeceLayout.one_ways():
		if rect.has_point(point):
			return true
	return false


func _rests_on_a_solid(rect: Rect2) -> bool:
	for solid: Rect2 in GreeceLayout.solids():
		var below := is_equal_approx(solid.position.y, rect.end.y)
		if below and solid.position.x <= rect.position.x and solid.end.x >= rect.end.x:
			return true
	return false


# -- Data ------------------------------------------------------------------------

func case_enemy_data() -> void:
	var entries := GreeceLayout.enemies()
	var ids := {}
	var wrong_rooms: Array[String] = []
	var wrong_kinds: Array[String] = []
	for entry: Dictionary in entries:
		var key: StringName = entry["enemy_id"]
		ids[key] = true
		var expected: Array = EXPECTED.get(key, [])
		if expected.is_empty() or expected[0] != entry["archetype"]:
			wrong_kinds.append(str(key))
		elif expected[1] != _home_room(entry):
			wrong_rooms.append("%s in %s" % [key, _home_room(entry)])
	check(entries.size() == EXPECTED.size(), "%d placements, expected %d" % [entries.size(), EXPECTED.size()])
	check(ids.size() == entries.size(), "enemy ids are unique")
	check(wrong_kinds.is_empty(), "every placement is a known id with its archetype: %s" % str(wrong_kinds))
	check(wrong_rooms.is_empty(), "every enemy is homed in its room: %s" % str(wrong_rooms))
	var in_safe_room := entries.any(func(entry: Dictionary) -> bool: return _home_room(entry) in SAFE_ROOMS)
	check(not in_safe_room, "Entrada, the altar room and the boss arena have no regular enemies")
	var known := entries.all(func(entry: Dictionary) -> bool: return ARCHETYPE_CLASSES.has(entry["archetype"]))
	check(known and entries.all(func(entry: Dictionary) -> bool: return absi(entry["facing"]) == 1), "archetypes are known and facings are -1 or 1")


func case_enemy_placement() -> void:
	var buried: Array[String] = []
	var floating: Array[String] = []
	var outside: Array[String] = []
	for entry: Dictionary in GreeceLayout.enemies():
		var key := str(entry["enemy_id"])
		var spawn: Vector2 = entry["position"]
		var center := _body_center(entry)
		var room: Rect2 = GreeceLayout.rooms()[_home_room(entry)]
		if _solid_covering(center) or _solid_covering(spawn + Vector2(0.0, -3.0)):
			buried.append(key)
		if not room.has_point(center):
			outside.append(key)
		if not HOVER_CENTER.has(entry["archetype"]) and not _rests_on_floor(spawn):
			floating.append(key)
	check(buried.is_empty(), "no enemy spawns inside a solid: %s" % str(buried))
	check(outside.is_empty(), "every body centre sits inside its room: %s" % str(outside))
	check(floating.is_empty(), "walkers and chargers spawn on a floor: %s" % str(floating))


func _rests_on_floor(spawn: Vector2) -> bool:
	for rect: Rect2 in GreeceLayout.solids():
		if is_equal_approx(rect.position.y, spawn.y) and rect.position.x + 20.0 <= spawn.x and rect.end.x - 20.0 >= spawn.x:
			return true
	return false


func case_arrival_clearance() -> void:
	var too_close: Array[String] = []
	for entry: Dictionary in GreeceLayout.enemies():
		for point: Vector2 in _arrival_points():
			var distance := (entry["position"] as Vector2).distance_to(point)
			if distance < GreeceLayout.ARRIVAL_CLEARANCE:
				too_close.append("%s %.0f px from %s" % [entry["enemy_id"], distance, point])
	check(too_close.is_empty(), "nothing spawns within %.0f px of an arrival: %s" % [GreeceLayout.ARRIVAL_CLEARANCE, str(too_close)])
	var nearest := INF
	for entry: Dictionary in GreeceLayout.enemies():
		for point: Vector2 in [GreeceLayout.SPAWN, GreeceLayout.DESK_POSITION]:
			nearest = minf(nearest, (entry["position"] as Vector2).distance_to(point))
	check(nearest >= GreeceLayout.ARRIVAL_CLEARANCE, "the level spawn and the desk are far from every enemy (%.0f px)" % nearest)


# -- Spikes ------------------------------------------------------------------------

func case_spikes_geometry() -> void:
	var loose: Array[String] = []
	var buried: Array[String] = []
	var on_steps: Array[String] = []
	var tall: Array[String] = []
	var out_of_view: Array[String] = []
	for rect: Rect2 in GreeceLayout.hazards():
		var label := str(rect.position)
		if not _rests_on_a_solid(rect):
			loose.append(label)
		for solid: Rect2 in GreeceLayout.solids():
			if solid.intersects(rect):
				buried.append(label)
		for step: Rect2 in GreeceLayout.one_ways():
			if step.grow(4.0).intersects(rect):
				on_steps.append(label)
		if rect.size.y >= FULL_JUMP * 0.25:
			tall.append(label)
		var room := GreeceLayout.camera_room(GreeceLayout.room_for(rect.get_center(), ""))
		if not GreeceLayout.camera_bounds(room).encloses(rect):
			out_of_view.append(label)
	check(loose.is_empty(), "every spike row rests on a floor: %s" % str(loose))
	check(buried.is_empty(), "no spike row overlaps a solid: %s" % str(buried))
	check(on_steps.is_empty(), "no spike row touches a one-way step: %s" % str(on_steps))
	check(tall.is_empty(), "spike rows are low enough to jump over: %s" % str(tall))
	check(out_of_view.is_empty(), "the camera of each spike's room shows it: %s" % str(out_of_view))


func case_spikes_critical_path() -> void:
	var reach := Reach.new(GreeceLayout.solids(), GreeceLayout.one_ways(), GreeceLayout.hazards())
	var standable_under_spike := 0
	for surface: Dictionary in reach.surfaces:
		for rect: Rect2 in GreeceLayout.hazards():
			var overlaps := rect.position.x < float(surface.x1) and rect.end.x > float(surface.x0)
			if overlaps and absf(rect.end.y - float(surface.y)) < 1.5:
				standable_under_spike += 1
	check(standable_under_spike == 0, "no standable surface sits under a spike row (%d do)" % standable_under_spike)
	var safe_points: Array[Vector2] = [GreeceLayout.SPAWN, GreeceLayout.DESK_POSITION, Vector2(210.0, 444.0), Vector2(2470.0, 270.0), Vector2(1950.0, GreeceLayout.ALCOVE_FLOOR_Y), Vector2(3000.0, 544.0), Vector2(2500.0, 1880.0)]
	var near_spike := 0
	for point: Vector2 in safe_points:
		for rect: Rect2 in GreeceLayout.hazards():
			if rect.grow(SAFE_MARGIN).has_point(point):
				near_spike += 1
	check(near_spike == 0, "spawn, desk and the surfaces the tests rely on keep %.0f px from every spike (%d do not)" % [SAFE_MARGIN, near_spike])
	var start := reach.surface_at(GreeceLayout.SPAWN)
	var seen := reach.reachable(start, 110.0, 220.0)
	var goals: Array[Vector2] = [GreeceLayout.DESK_POSITION, Vector2(210.0, 444.0), Vector2(2470.0, 270.0), Vector2(3000.0, 544.0), Vector2(2500.0, 1880.0)]
	var missed := goals.filter(func(goal: Vector2) -> bool: return not seen.has(reach.surface_at(goal)))
	check(missed.is_empty(), "with spikes as non-standable, jump and dash still reach the desk, both medal ledges, T3 and the exit: %s" % str(missed))
	var far_side := reach.surface_at(Vector2(3300.0, 2720.0))
	var double_jump := reach.reachable(start, 230.0, 220.0)
	check(far_side >= 0 and not seen.has(far_side) and double_jump.has(far_side), "the B3 medal side still needs the double jump and no more")


# -- Physics probes ----------------------------------------------------------------

func case_probe_boot() -> void:
	_registry().clear()
	await _probe.load_level(true)
	await _probe.frames(5)
	var enemies := get_nodes_in_group(&"enemies")
	check(enemies.size() == EXPECTED.size(), "the level boots %d enemies (%d)" % [EXPECTED.size(), enemies.size()])
	var mismatches: Array[String] = []
	var awake: Array[String] = []
	for node: Node in enemies:
		var enemy := node as Enemy
		var expected: Array = EXPECTED.get(enemy.enemy_id, [])
		if expected.is_empty() or str(enemy.home_room) != expected[1]:
			mismatches.append(str(enemy.enemy_id))
		else:
			var expected_class: String = ARCHETYPE_CLASSES[expected[0]]
			if enemy.enemy_id == &"greece_t1_flyer_a":
				expected_class = "BookFlyer"
			if (node.get_script() as Script).get_global_name() != expected_class:
				mismatches.append("%s is not a %s" % [enemy.enemy_id, expected_class])
		if enemy.is_ai_active():
			awake.append(str(enemy.enemy_id))
	check(mismatches.is_empty(), "EnemyRegistry homes every enemy and each is its archetype: %s" % str(mismatches))
	check(awake.is_empty(), "with Luz in Entrada every enemy is paused: %s" % str(awake))
	check(get_nodes_in_group(&"greece_spikes").size() == GreeceLayout.hazards().size(), "the level builds one spike node per spike row")
	check(_probe.level.get_node_or_null("Enemies") != null and _probe.level.get_node("Enemies").get_child_count() == EXPECTED.size(), "enemies live under one Enemies node")
	_registry().enter_room(&"B2")
	var b2_awake: Array[String] = []
	for node: Node in enemies:
		if (node as Enemy).is_ai_active():
			b2_awake.append(str((node as Enemy).enemy_id))
	check(b2_awake == [str(WALKER_ID)], "entering B2 wakes only the B2 walker: %s" % str(b2_awake))


## A plain running jump clears the B2 spike row without a scratch.
func case_probe_spikes_jumpable() -> void:
	_registry().clear()
	await _probe.load_level(true)
	var player: Player = _probe.player
	var health := player.get_health()
	var row := GreeceLayout.B2_SPIKES
	await _probe.place(Vector2(row.position.x - 70.0, 2720.0))
	Input.action_press(&"move_right")
	var armed := false
	var end := _probe.clock + 1.6
	while _probe.clock < end and player.global_position.x < row.end.x + 30.0:
		await process_frame
		if not armed and player.global_position.x >= row.position.x - 40.0:
			armed = true
			Input.action_press(&"jump")
	_probe.release_all()
	check(player.global_position.x >= row.end.x + 30.0, "a running jump crosses the B2 spikes (x %.0f)" % player.global_position.x)
	check(player.get_health() == health, "crossing the B2 spikes by jumping costs no health")


## Kill the B2 walker, leave B2 and come back: the corpse stays. Rest: it lives.
func case_probe_persistence() -> void:
	_registry().clear()
	await _probe.load_level(true)
	var walker := _probe.level.get_node("Enemies/" + str(WALKER_ID)) as Enemy
	await _probe.place(Vector2(1300.0, 2720.0))
	check(walker.is_ai_active() and not walker.is_dead(), "in B2 the walker is awake and alive")
	walker.receive_hit(HIGH_DAMAGE, walker.global_position + Vector2(40.0, 0.0), &"")
	check(walker.is_dead() and _registry().has_kill(WALKER_ID), "a lethal hit kills it and the registry records the kill")
	var corpse_at := walker.global_position
	await _probe.place(Vector2(800.0, 2720.0))
	check(_probe.level.get_room() == &"Entrada" and not walker.is_ai_active(), "leaving B2 for Entrada pauses the walker")
	await _probe.place(Vector2(1300.0, 2720.0))
	check(_probe.level.get_room() == &"B2" and walker.is_dead() and walker.global_position.distance_to(corpse_at) < 2.0, "back in B2 the corpse is still where it fell")
	_checkpoints().reset_resettable_enemies()
	check(not walker.is_dead() and not _registry().has_kill(WALKER_ID), "a desk rest revives it and clears the kill")

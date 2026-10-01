extends SceneTree
## Regression test for the Greece level layout: data constraints, data-level
## reachability and physics probes in the real scene.
## Run: godot --headless --path . --script res://tests/greece_layout_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.

const Reach := preload("res://tests/support/greece_reach.gd")
const Probe := preload("res://tests/support/greece_probe.gd")
const WATCHDOG_SECONDS := 300.0
const MAX_SHAPES := 300
const DOOR_MARGIN := 60.0
const PLAYER_SIZE := Vector2(38.0, 58.0)
const JUMP_RISE := 110.0
const DOUBLE_JUMP_RISE := 230.0
const MAX_GAP := 220.0
const SHAFT_STEP_MAX := 100.0

const CHECKS := {
	"case_room_graph": 3,
	"case_doorway_clearances": 9,
	"case_collision_budget": 2,
	"case_gate_geometry": 5,
	"case_reachability_jump_only": 8,
	"case_reachability_double_jump": 2,
	"case_shaft_steps": 2,
	"case_probe_spawn": 3,
	"case_probe_gate_blocks": 3,
	"case_probe_drop_through": 2,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _probe: Probe
var _reach: Reach


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_probe = Probe.new(self)
	_reach = Reach.new(GreeceLayout.solids(), GreeceLayout.one_ways())
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


# -- Data ------------------------------------------------------------------------

func case_room_graph() -> void:
	var rooms := GreeceLayout.rooms()
	var linked := _rooms_linked_from("Entrada")
	check(linked.size() == rooms.size(), "all %d rooms connect through doorways (%d linked)" % [rooms.size(), linked.size()])
	for door: Dictionary in GreeceLayout.doorways():
		if not rooms.has(door.from) or not rooms.has(door.to):
			check(false, "doorway names unknown room: %s" % str(door))
			return
	check(true, "doorways name known rooms")
	check(rooms.has("Altar") and rooms.has("Exit") and rooms.has("T3"), "altar, exit and boss rooms exist")


func _rooms_linked_from(start: String) -> Dictionary:
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var room: String = queue.pop_back()
		for door: Dictionary in GreeceLayout.doorways():
			var other := _other_side(door, room)
			if other != "" and not seen.has(other):
				seen[other] = true
				queue.append(other)
	return seen


func _other_side(door: Dictionary, room: String) -> String:
	if door.from == room:
		return door.to
	if door.to == room:
		return door.from
	return ""


func case_doorway_clearances() -> void:
	for door: Dictionary in GreeceLayout.doorways():
		var opening: Rect2 = door.rect
		var is_hole := opening.size.x > opening.size.y
		var clear := opening.size.x if is_hole else opening.size.y
		var need := (PLAYER_SIZE.x if is_hole else PLAYER_SIZE.y) + DOOR_MARGIN
		check(clear >= need, "%s-%s opening %.0f >= %.0f" % [door.from, door.to, clear, need])


func case_collision_budget() -> void:
	var shapes := GreeceLayout.solids().size() + GreeceLayout.one_ways().size()
	check(shapes < MAX_SHAPES, "collision shapes %d < %d" % [shapes, MAX_SHAPES])
	check(shapes > 0, "layout has collision")


func case_gate_geometry() -> void:
	var gate := GreeceLayout.GATE
	check(gate.size.x > gate.size.y, "gate is wider than tall (not clingable)")
	check(gate.size.y > 130.0 * 1.2, "gate blocks a single jump")
	check(gate.size.y <= 130.0 * 2.0 - 50.0, "double jump clears the gate with a 50 px margin")
	check(_distance_to_clingable_walls(gate) >= 600.0, "gate is >= 600 px from every clingable wall on its near side")
	check(_gate_is_not_flanked_by_walls(gate), "no clingable rect touches the gate sides")


## Smallest horizontal distance from the gate to a clingable rect on its near
## (left) side that the player could kick off. The far-side wall is only
## reachable after crossing the gate, so it is not an exploit route.
func _distance_to_clingable_walls(gate: Rect2) -> float:
	var best := INF
	for rect: Rect2 in GreeceLayout.solids():
		if _is_clingable(rect) and rect.end.x <= gate.position.x and rect.end.y > gate.position.y - 400.0:
			best = minf(best, gate.position.x - rect.end.x)
	return best


func _gate_is_not_flanked_by_walls(gate: Rect2) -> bool:
	for rect: Rect2 in GreeceLayout.solids():
		var touches := rect.grow(2.0).intersects(gate) and rect != gate
		if touches and _is_clingable(rect):
			return false
	return true


func _is_clingable(rect: Rect2) -> bool:
	return rect.size.y >= 80.0 and rect.size.y >= rect.size.x


# -- Reachability (data level) -----------------------------------------------------

func case_reachability_jump_only() -> void:
	var start := _reach.surface_at(GreeceLayout.SPAWN)
	check(start >= 0, "spawn stands on a surface")
	var seen := _reach.reachable(start, JUMP_RISE, MAX_GAP)
	_check_reaches(seen, Vector2(1050.0, 1200.0), "altar floor")
	_check_reaches(seen, Vector2(210.0, 444.0), "T1 medal ledge")
	_check_reaches(seen, Vector2(2470.0, 270.0), "T2 medal platform")
	_check_reaches(seen, Vector2(1600.0, 1380.0), "shaft medal dash platform")
	_check_reaches(seen, Vector2(1950.0, 1380.0), "shaft medal alcove floor")
	_check_reaches(seen, Vector2(3000.0, 544.0), "T3 floor")
	_check_reaches(seen, Vector2(2500.0, 1880.0), "exit room floor")


func case_reachability_double_jump() -> void:
	var start := _reach.surface_at(GreeceLayout.SPAWN)
	var jump_only := _reach.reachable(start, JUMP_RISE, MAX_GAP)
	var far_side := _reach.surface_at(Vector2(3300.0, 2720.0))
	check(far_side >= 0 and not jump_only.has(far_side), "B3 medal side is NOT reachable with jump and dash")
	var with_double := _reach.reachable(start, DOUBLE_JUMP_RISE, MAX_GAP)
	check(with_double.has(far_side), "B3 medal side IS reachable with a double jump")


func _check_reaches(seen: Dictionary, point: Vector2, label: String) -> void:
	var index := _reach.surface_at(point)
	check(index >= 0 and seen.has(index), "%s reachable from spawn" % label)


func case_shaft_steps() -> void:
	var tops: Array[float] = []
	for rect: Rect2 in GreeceLayout.one_ways():
		if rect.position.x >= GreeceLayout.SHAFT_X0 - 1.0 and rect.end.x <= GreeceLayout.SHAFT_X1 + 1.0:
			tops.append(rect.position.y)
	tops.sort()
	tops.reverse()
	var worst := 2720.0 - tops[0]
	for i: int in range(1, tops.size()):
		worst = maxf(worst, tops[i - 1] - tops[i])
	check(worst <= SHAFT_STEP_MAX, "largest vertical shaft step %.0f <= %.0f" % [worst, SHAFT_STEP_MAX])
	check(tops[tops.size() - 1] <= 640.0 and 544.0 - tops[tops.size() - 1] >= -SHAFT_STEP_MAX, "top shaft platform reaches the T2 floor")


# -- Physics probes ----------------------------------------------------------------

func case_probe_spawn() -> void:
	await _probe.load_level()
	await _probe.frames(60)
	var player := _probe.player
	check(player.is_on_floor(), "spawn: player stands on the floor")
	check(absf(player.global_position.y - GreeceLayout.SPAWN.y) < 2.0, "spawn: feet rest on the Entrada floor (y=%.1f)" % player.global_position.y)
	check(absf(player.global_position.x - GreeceLayout.SPAWN.x) < 2.0, "spawn: player did not drift")


func case_probe_gate_blocks() -> void:
	await _probe.load_level()
	var gate := GreeceLayout.GATE
	await _probe.place(Vector2(gate.position.x - 380.0, 2720.0))
	var best := await _probe.hop_dash_toward(1.0, 3.0)
	_probe.release_all()
	check(best > gate.position.x - 80.0, "gate: probe reached the gate (furthest x %.0f)" % best)
	check(best < gate.position.x, "gate: furthest x %.0f stays left of the gate edge %.0f" % [best, gate.position.x])
	check(_probe.player.global_position.y > 2000.0, "gate: player did not escape upward")


func case_probe_drop_through() -> void:
	await _probe.load_level()
	await _probe.place(Vector2(1560.0, 2360.0 - 1.0))
	var start_y := _probe.player.global_position.y
	check(_probe.player.is_on_floor(), "drop: player stands on the shaft one-way")
	Input.action_press(&"move_down")
	await _probe.tap(&"jump")
	await _probe.secs(0.5)
	_probe.release_all()
	check(_probe.player.global_position.y > start_y + 20.0, "drop: down + jump falls through the one-way")

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
const Trials := preload("res://tests/support/greece_alcove_trials.gd")
const WATCHDOG_SECONDS := 300.0
const MAX_SHAPES := 300
const DOOR_MARGIN := 60.0
const PLAYER_SIZE := Vector2(38.0, 58.0)
const JUMP_RISE := 110.0
const DOUBLE_JUMP_RISE := 230.0
const MAX_GAP := 220.0
const SHAFT_STEP_MAX := 100.0
const FULL_JUMP := 130.0
## Widest pit a running jump clears without the dash under the alcove lintel;
## measured at about 176, rounded up. The sweep below keeps the real margin.
const NO_DASH_GAP := 190.0
const SAFE_MARGIN := 25.0
const ALCOVE_RANGE := 300.0
const SILL_RUN_START := Vector2(1900.0, 1329.0)
const MEDAL_FLOOR_START := Vector2(2320.0, 1329.0)
const EDGE_JUMP_OFFSETS: Array[float] = [-40.0, -20.0, -10.0, 0.0, 10.0, 20.0, 28.0, 34.0]
## The shaft approaches only need to fail, so they run faster than real time.
const APPROACH_TIME_SCALE := 3.0
## Scripted double jump over the gate: take-off distance, delay of the second
## press, and the least headroom above the gate top the jump must leave.
const GATE_TAKEOFF_DISTANCE := 110.0
const GATE_DOUBLE_JUMP_DELAY := 0.30
const GATE_MIN_MARGIN := 40.0
const DASH_DELAYS: Array[float] = [0.15, 0.3, 0.4]

const CHECKS := {
	"case_room_graph": 3,
	"case_doorway_clearances": 9,
	"case_collision_budget": 2,
	"case_hazard_placement": 4,
	"case_gate_geometry": 5,
	"case_reachability_jump_only": 7,
	"case_reachability_double_jump": 2,
	"case_alcove_geometry": 6,
	"case_reachability_alcove": 4,
	"case_shaft_steps": 2,
	"case_probe_spawn": 3,
	"case_probe_gate_blocks": 3,
	"case_probe_gate_double_jump": 4,
	"case_probe_placeholder_unlocks": 4,
	"case_probe_drop_through": 2,
	"case_probe_alcove_no_dash": 2,
	"case_probe_alcove_edge_sweep": 2,
	"case_probe_alcove_dash": 3,
	"case_probe_alcove_return": 3,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _probe: Probe
var _reach: Reach
var _trials: Trials


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_probe = Probe.new(self)
	_trials = Trials.new(_probe)
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


func case_hazard_placement() -> void:
	var b2: Rect2 = GreeceLayout.rooms()["B2"]
	for hazard: Rect2 in GreeceLayout.hazards():
		check(b2.encloses(hazard), "hazard sits inside the B2 room")
		check(is_equal_approx(hazard.end.y, b2.end.y), "hazard rests on the B2 floor")
		check(hazard.end.x < GreeceLayout.SHAFT_X0 and hazard.position.x > 1164.0 + DOOR_MARGIN, "hazard is clear of the shaft foot and the Entrada doorway")
		check(hazard.size.y < FULL_JUMP * 0.25, "hazard is low enough to jump over")


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
	_check_reaches(seen, GreeceLayout.DESK_POSITION, "altar floor")
	_check_reaches(seen, Vector2(210.0, 444.0), "T1 medal ledge")
	_check_reaches(seen, Vector2(2470.0, 270.0), "T2 medal platform")
	_check_reaches(seen, Vector2(1950.0, GreeceLayout.ALCOVE_FLOOR_Y), "alcove take-off sill")
	_check_reaches(seen, Vector2(3000.0, 544.0), "T3 floor")
	_check_reaches(seen, Vector2(2500.0, 1880.0), "exit room floor")


func case_reachability_double_jump() -> void:
	var start := _reach.surface_at(GreeceLayout.SPAWN)
	var jump_only := _reach.reachable(start, JUMP_RISE, MAX_GAP)
	var far_side := _reach.surface_at(Vector2(3300.0, 2720.0))
	check(far_side >= 0 and not jump_only.has(far_side), "B3 medal side is NOT reachable with jump and dash")
	var with_double := _reach.reachable(start, DOUBLE_JUMP_RISE, MAX_GAP)
	check(with_double.has(far_side), "B3 medal side IS reachable with a double jump")


func case_alcove_geometry() -> void:
	var gap := GreeceLayout.ALCOVE_FAR_START - GreeceLayout.ALCOVE_SILL_END
	check(gap >= 205.0 and gap <= 230.0, "alcove pit is %.0f px wide (205 to 230)" % gap)
	check(_alcove_window_height() >= 90.0, "alcove entry window is %.0f px tall (>= 90)" % _alcove_window_height())
	check(GreeceLayout.ALCOVE_SILL_END - Trials.SILL_START >= 120.0, "sill gives a 120 px run-up")
	check(GreeceLayout.ALCOVE_PIT_FLOOR_Y - GreeceLayout.ALCOVE_FLOOR_Y >= FULL_JUMP + 30.0, "pit is deeper than a jump plus 30 px")
	_check_not_clingable(Vector2(2150.0, 1140.0), "alcove lintel")
	_check_not_clingable(Vector2(2400.0, 1400.0), "medal floor block")


func _alcove_window_height() -> float:
	for door: Dictionary in GreeceLayout.doorways():
		if door.to == "ShaftAlcove":
			var opening: Rect2 = door.rect
			return opening.size.y
	return 0.0


func _check_not_clingable(point: Vector2, label: String) -> void:
	var rect := _solid_at(point)
	check(rect.size != Vector2.ZERO and not _is_clingable(rect), "%s exists and cannot be gripped" % label)


func _solid_at(point: Vector2) -> Rect2:
	for rect: Rect2 in GreeceLayout.solids():
		if rect.has_point(point):
			return rect
	return Rect2()


func case_reachability_alcove() -> void:
	var start := _reach.surface_at(GreeceLayout.SPAWN)
	var sill := _reach.surface_at(Vector2(1950.0, GreeceLayout.ALCOVE_FLOOR_Y))
	var far := _reach.surface_at(Vector2(2370.0, GreeceLayout.ALCOVE_FLOOR_Y))
	check(sill >= 0 and far >= 0, "alcove sill and medal floor are standing surfaces")
	var no_dash := _reach.reachable(start, FULL_JUMP, NO_DASH_GAP, true)
	check(no_dash.has(sill), "without the dash the sill is reachable from spawn")
	check(not no_dash.has(far), "without the dash the medal floor is NOT reachable, falls from higher included")
	var with_dash := _reach.reachable(sill, JUMP_RISE, MAX_GAP, true)
	check(with_dash.has(far), "a jump with the air dash from the sill reaches the medal floor")


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


# -- Physics probes: the medal alcove ------------------------------------------------

func case_probe_alcove_no_dash() -> void:
	await _probe.load_level()
	var starts := _approach_starts()
	var escapes: Array[String] = []
	Engine.time_scale = APPROACH_TIME_SCALE
	for start: Vector2 in starts:
		escapes.append_array(await _approach_escapes(start))
	Engine.time_scale = 1.0
	check(starts.size() >= 7, "approaches start from %d shaft surfaces near the alcove" % starts.size())
	check(escapes.is_empty(), "no-dash approaches reached the medal floor: %s" % str(escapes))


## Shaft one-ways within ALCOVE_RANGE of the alcove floor, at their alcove-side
## end, plus the altar sill across the shaft.
func _approach_starts() -> Array[Vector2]:
	var starts: Array[Vector2] = [Vector2(1470.0, GreeceLayout.DESK_POSITION.y - 1.0)]
	for rect: Rect2 in GreeceLayout.one_ways():
		var in_shaft := rect.position.x >= GreeceLayout.SHAFT_X0 and rect.end.x <= GreeceLayout.SHAFT_X1
		if in_shaft and absf(rect.position.y - GreeceLayout.ALCOVE_FLOOR_Y) <= ALCOVE_RANGE:
			starts.append(Vector2(rect.end.x - 20.0, rect.position.y - 1.0))
	return starts


## Edge jumps with two release timings, a plain run-off and wall kick spam
## toward the alcove side. Returns the attempts that got in.
func _approach_escapes(start: Vector2) -> Array[String]:
	var found: Array[String] = []
	for hold: float in [0.8, 0.3]:
		await _trials.run_jump(start, 1.0, start.x + 10.0 + hold * 20.0, hold, -1.0)
		_note_escape(found, "jump hold %.1f from %s" % [hold, start])
	await _trials.run_off(start, 1.0)
	_note_escape(found, "run off from %s" % start)
	await _trials.wall_kicks(start, 1.0, 2.0)
	_note_escape(found, "wall kicks from %s" % start)
	return found


func _note_escape(found: Array[String], label: String) -> void:
	if _trials.reached_medal_floor:
		found.append(label)


func case_probe_alcove_edge_sweep() -> void:
	await _probe.load_level()
	var edge := GreeceLayout.ALCOVE_SILL_END
	var worst := INF
	var reached := false
	for offset: float in EDGE_JUMP_OFFSETS:
		await _trials.run_jump(SILL_RUN_START, 1.0, edge + offset, 0.8, -1.0)
		worst = minf(worst, _trials.medal_floor_edge() - _trials.closest_x)
		reached = reached or _trials.reached_medal_floor
	check(not reached, "no sill jump without the dash lands on the medal floor")
	check(worst >= SAFE_MARGIN, "closest no-dash jump stops %.0f px short of the medal floor (>= %.0f)" % [worst, SAFE_MARGIN])


func case_probe_alcove_dash() -> void:
	await _probe.load_level()
	for delay: float in DASH_DELAYS:
		var trigger := GreeceLayout.ALCOVE_SILL_END - 15.0
		await _trials.run_jump(SILL_RUN_START, 1.0, trigger, 0.8, delay)
		check(_trials.reached_medal_floor, "jump then air dash %.2fs after take-off lands on the medal floor" % delay)


func case_probe_alcove_return() -> void:
	await _probe.load_level()
	var trigger := GreeceLayout.ALCOVE_FAR_START + 8.0
	await _trials.run_jump(MEDAL_FLOOR_START, -1.0, trigger, 0.8, 0.3)
	check(_trials.reached_sill, "from the medal floor a jump and air dash lands back on the sill")
	await _probe.place(SILL_RUN_START)
	Input.action_press(&"move_left")
	await _probe.secs(1.5)
	_probe.release_all()
	var player := _probe.player
	check(player.is_on_floor() and player.global_position.x < Trials.SILL_START + 19.0, "walking off the sill drops onto a shaft platform")
	await _trials.wall_kicks(Vector2(2150.0, GreeceLayout.ALCOVE_PIT_FLOOR_Y - 1.0), -1.0, 6.0)
	check(_trials.reached_sill, "from the pit floor, wall kicks on the sill climb back out")


func case_probe_gate_double_jump() -> void:
	await _probe.load_level()
	_probe.player.unlock_double_jump()
	var gate := GreeceLayout.GATE
	var peak: float = await _probe.run_double_jump(Vector2(gate.position.x - GATE_TAKEOFF_DISTANCE, 2720.0), 1.0, GATE_DOUBLE_JUMP_DELAY, 0.7)
	var margin := (2720.0 - peak) - gate.size.y
	check(margin >= GATE_MIN_MARGIN, "gate: the double jump tops the gate with %.0f px to spare" % margin)
	var landed: bool = await _probe.wait_for_floor(2700.0, 4.0)
	var player := _probe.player
	check(landed and player.global_position.x > gate.end.x, "gate: walks off the gate and lands past its edge (x %.0f)" % player.global_position.x)
	await _probe.secs(1.5)
	_probe.release_all()
	check(player.global_position.x > GreeceLayout.markers()["Medal4"].x - 20.0, "gate: Luz runs on to the Medal4 side (x %.0f)" % player.global_position.x)
	check(player.is_on_floor() and player.global_position.y > 2700.0, "gate: Luz ends on the B3 floor, not on top of the gate")


func case_probe_placeholder_unlocks() -> void:
	await _probe.load_level()
	var pickup := _probe.level.get_node("Markers/DoubleJumpPlaceholder") as Area2D
	check(pickup.is_in_group(&"greece_placeholder"), "placeholder: pickup is in the greece_placeholder group")
	check(not _probe.player.has_double_jump(), "placeholder: Luz starts without the double jump")
	await _probe.place(GreeceLayout.markers()["BossArena"])
	check(_probe.player.has_double_jump(), "placeholder: touching it unlocks the double jump")
	check(not pickup.visible, "placeholder: the pickup hides itself after the touch")

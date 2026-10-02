extends SceneTree
## Regression test for the Hollow Knight style room transitions in the Greece
## level: the doorway data, every doorway in both directions on the real
## geometry (fade, instant camera bounds, placement, input lock), the shaft
## climbs, the alcove that must not transition, the input lock, and death.
## Run: godot --headless --path . --script res://tests/room_transition_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.

const Probe := preload("res://tests/support/greece_probe.gd")
const WATCHDOG_SECONDS := 240.0
const EPSILON := 0.01
const CROSS_TIMEOUT := 4.0
const SETTLE_SECONDS := 0.6
const BODY_CENTER := Vector2(0.0, -29.0)
const FAR_FROM_PASSAGE := 80.0
const DROP_SPEED := 300.0
const CLIMB_SPEED := 520.0
## How far past the 32 px walk-out her feet may be when control returns, and
## the least she must walk (the Entrada step stops her after 13 px).
const WALK_TOLERANCE := 14.0
const MIN_WALK := 10.0
const BLACK := 0.99

const CHECKS := {
	"case_doorway_data": 9,
	"case_every_doorway_both_ways": 9,
	"case_climb_and_drop_real_geometry": 8,
	"case_alcove_has_no_transition": 4,
	"case_input_lock_and_release": 6,
	"case_fades_do_not_stack": 5,
	"case_death_around_transitions": 8,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _probe: Probe
var _player: Player
var _camera: RoomCamera
var _level: Node
var _changes: Array[Array] = []


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
	_probe.release_all()
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


# -- Helpers ---------------------------------------------------------------------------

func _load_level() -> void:
	await _probe.load_level()
	_level = _probe.level
	_player = _probe.player as Player
	_camera = _level.get_node("RoomCamera")
	_changes.clear()
	_level.room_changed.connect(func(from_room: StringName, to_room: StringName) -> void: _changes.append([from_room, to_room]))


func _transition() -> RoomTransition:
	return _level.get_node("RoomTransition")


func _alpha() -> float:
	return _player.get_screen_fade().get_alpha()


func _room() -> String:
	return String(_level.get_room())


func _bounds_are(rect: Rect2) -> bool:
	var now := _camera.get_room_bounds()
	return now.position.distance_to(rect.position) < EPSILON and now.size.distance_to(rect.size) < EPSILON


func _center() -> Vector2:
	return _player.global_position + BODY_CENTER


func _inside(room_name: String) -> bool:
	return (GreeceLayout.rooms()[room_name] as Rect2).has_point(_center())


func _wait_until_free(timeout: float) -> bool:
	var end := _probe.clock + timeout
	while _probe.clock < end:
		await process_frame
		if not _player.is_in_room_transition() and not _transition().is_active():
			return true
	return false


# -- Doorway data ------------------------------------------------------------------------

func case_doorway_data() -> void:
	var doors := GreeceLayout.doorways()
	var moving := 0
	var sides_ok := true
	var arrivals_ok := true
	for door: Dictionary in doors:
		moving += 1 if door["transitions"] else 0
		sides_ok = sides_ok and door["from_side"] == -int(door["to_side"])
		if door["orientation"] == GreeceLayout.HORIZONTAL and door["transitions"]:
			for room_name: String in [door["from"], door["to"]]:
				var feet := GreeceLayout.arrival_point(door, room_name)
				arrivals_ok = arrivals_ok and (GreeceLayout.rooms()[room_name] as Rect2).has_point(feet + BODY_CENTER)
	check(doors.size() == 9 and moving == 8, "nine passages, eight of them change room (%d/%d)" % [moving, doors.size()])
	check(sides_ok, "the two rooms of every passage lie on opposite sides")
	check(arrivals_ok, "every side door's arrival point is inside the room it leads into")
	var by_pair := {}
	for door: Dictionary in doors:
		by_pair["%s|%s" % [door["from"], door["to"]]] = door
	check(not by_pair["Shaft|ShaftAlcove"]["transitions"], "the alcove shares the shaft's camera room")
	check(by_pair["T2|Shaft"]["orientation"] == GreeceLayout.VERTICAL and by_pair["T1|T2"]["orientation"] == GreeceLayout.HORIZONTAL, "holes are vertical, side doors horizontal")
	check(GreeceLayout.entry_lip_y(by_pair["T2|Shaft"], "T2") == 544.0 and is_nan(GreeceLayout.entry_lip_y(by_pair["Shaft|B2"], "Shaft")), "only the T2 floor hole has a lip to clear")
	var t1_t2: Dictionary = by_pair["T1|T2"]
	check(GreeceLayout.transition_for(Vector2(1050.0, 500.0), "T1", doors).get("to", "") == "T2", "past the middle of the T1|T2 door the camera room is T2")
	check(GreeceLayout.transition_for(Vector2(1010.0, 500.0), "T1", doors).is_empty() and GreeceLayout.transition_for(Vector2(1010.0, 500.0), "T2", doors).get("to", "") == "T1", "the near half of a door changes nothing, the far half goes back")
	check(GreeceLayout.transition_for(Vector2(1890.0, 1300.0), "Shaft", doors).is_empty() and GreeceLayout.travel_direction(t1_t2, "T2") == Vector2.RIGHT, "the alcove door never starts a transition and travel follows the target room")


# -- Every doorway, both ways -------------------------------------------------------------

## Body-centre point in the half of `door` that belongs to `room_name`.
func _half_center(door: Dictionary, room_name: String) -> Vector2:
	var rect: Rect2 = door["rect"]
	var side: int = door["from_side"] if room_name == door["from"] else door["to_side"]
	return rect.get_center() + Vector2(0.0, float(side) * rect.size.y * 0.25)


## Puts Luz in `from_room` next to `door`, ready to cross. Side doors: standing
## inside the door, ready to walk. Holes: moving through the passage.
func _stage(door: Dictionary, from_room: String, to_room: String) -> void:
	if door["orientation"] == GreeceLayout.HORIZONTAL:
		await _probe.place(GreeceLayout.arrival_point(door, from_room))
		return
	var rect: Rect2 = door["rect"]
	var from_side: int = door["from_side"] if from_room == door["from"] else door["to_side"]
	var far := Vector2(rect.get_center().x, rect.get_center().y + float(from_side) * (rect.size.y * 0.5 + FAR_FROM_PASSAGE))
	_player.global_position = far - BODY_CENTER
	_player.velocity = Vector2.ZERO
	await _probe.frames(3)
	var travel := GreeceLayout.travel_direction(door, to_room)
	var speed := CLIMB_SPEED if travel.y < 0.0 else DROP_SPEED
	_player.global_position = _half_center(door, from_room) - BODY_CENTER
	_player.velocity = travel * speed


func _hold_for(door: Dictionary, to_room: String) -> StringName:
	if door["orientation"] != GreeceLayout.HORIZONTAL:
		return &""
	return &"move_right" if GreeceLayout.travel_direction(door, to_room).x > 0.0 else &"move_left"


## Crosses `door` from `from_room` into `to_room` and measures everything the
## spec asks about. The key (side doors) is released as soon as input locks.
func _cross(door: Dictionary, from_room: String, to_room: String) -> Dictionary:
	var old_bounds := GreeceLayout.camera_bounds(from_room)
	var new_bounds := GreeceLayout.camera_bounds(to_room)
	var travel := GreeceLayout.travel_direction(door, to_room)
	await _stage(door, from_room, to_room)
	var result := {
		"staged": _room() == from_room, "max_alpha": 0.0, "blended": false, "cut_alpha": -1.0,
		"locked": false, "released": false, "feet": Vector2.ZERO, "facing": 0, "center_inside": false,
	}
	_changes.clear()
	var key := _hold_for(door, to_room)
	if key != &"":
		Input.action_press(key)
	var end := _probe.clock + CROSS_TIMEOUT
	while _probe.clock < end:
		await process_frame
		_sample_crossing(result, old_bounds, new_bounds)
		if result["locked"] and not _player.is_in_room_transition() and not _transition().is_active():
			result["released"] = true
			result["feet"] = _player.global_position
			result["facing"] = _player.get_facing()
			result["center_inside"] = _inside(to_room)
			result["changes"] = _changes.duplicate()
			result["bounds_new"] = _bounds_are(new_bounds)
			result["alpha_end"] = _alpha()
			break
	_probe.release_all()
	await _probe.secs(SETTLE_SECONDS)
	result["travel"] = travel
	return result


func _sample_crossing(result: Dictionary, old_bounds: Rect2, new_bounds: Rect2) -> void:
	var alpha := _alpha()
	result["max_alpha"] = maxf(result["max_alpha"], alpha)
	if _player.is_in_room_transition():
		result["locked"] = true
		for action: StringName in [&"move_left", &"move_right"]:
			Input.action_release(action)
	if _bounds_are(new_bounds):
		if result["cut_alpha"] < 0.0:
			result["cut_alpha"] = alpha
	elif not _bounds_are(old_bounds):
		result["blended"] = true


func case_every_doorway_both_ways() -> void:
	await _load_level()
	var problems := {"staged": [], "black": [], "blend": [], "cut": [], "lock": [], "placed": [], "faded": [], "emitted": []}
	var crossings := 0
	for door: Dictionary in GreeceLayout.doorways():
		if not door["transitions"]:
			continue
		for direction: int in 2:
			var from_room: String = door["from"] if direction == 0 else door["to"]
			var to_room: String = door["to"] if direction == 0 else door["from"]
			var label := "%s>%s" % [from_room, to_room]
			var r := await _cross(door, from_room, to_room)
			crossings += 1
			_collect_problems(problems, label, door, to_room, r)
	check(crossings == 16, "all eight passages were crossed in both directions (%d)" % crossings)
	check(problems["staged"].is_empty(), "every crossing started in the right room: %s" % [problems["staged"]])
	check(problems["black"].is_empty(), "the fade reaches black every time: %s" % [problems["black"]])
	check(problems["blend"].is_empty(), "the camera never shows a blended rect: %s" % [problems["blend"]])
	check(problems["cut"].is_empty(), "the bounds switch only while the screen is black: %s" % [problems["cut"]])
	check(problems["lock"].is_empty(), "input is locked during and released after: %s" % [problems["lock"]])
	check(problems["placed"].is_empty(), "Luz ends inside the new room at that door, on the floor, facing travel: %s" % [problems["placed"]])
	check(problems["faded"].is_empty(), "the fade ends fully transparent: %s" % [problems["faded"]])
	check(problems["emitted"].is_empty(), "room_changed fires exactly once with the right rooms: %s" % [problems["emitted"]])


func _collect_problems(problems: Dictionary, label: String, door: Dictionary, to_room: String, r: Dictionary) -> void:
	var new_bounds := GreeceLayout.camera_bounds(to_room)
	if not r["staged"]:
		problems["staged"].append(label)
	if r["max_alpha"] < BLACK:
		problems["black"].append("%s (%.2f)" % [label, r["max_alpha"]])
	if r["blended"] or not r.get("bounds_new", false):
		problems["blend"].append(label)
	if r["cut_alpha"] < 0.95:
		problems["cut"].append("%s (%.2f)" % [label, r["cut_alpha"]])
	if not r["locked"] or not r["released"]:
		problems["lock"].append(label)
	if not _placement_ok(door, to_room, r):
		problems["placed"].append("%s %s" % [label, r["feet"]])
	if r.get("alpha_end", 1.0) != 0.0:
		problems["faded"].append(label)
	var expected: Array = [StringName(_staged_from(label)), StringName(to_room)]
	var seen: Array = r.get("changes", [])
	if seen.size() != 1 or seen[0] != expected:
		problems["emitted"].append("%s %s" % [label, seen])


func _staged_from(label: String) -> String:
	return label.split(">")[0]


func _placement_ok(door: Dictionary, to_room: String, r: Dictionary) -> bool:
	if not r["center_inside"]:
		return false
	if door["orientation"] == GreeceLayout.VERTICAL:
		return true
	var travel: Vector2 = r["travel"]
	var arrival := GreeceLayout.arrival_point(door, to_room)
	var feet: Vector2 = r["feet"]
	var walked := (feet.x - arrival.x) * travel.x
	var on_floor := absf(_player.global_position.y - arrival.y) < 2.0 and _player.is_on_floor()
	return walked >= MIN_WALK and walked <= 32.0 + WALK_TOLERANCE and r["facing"] == int(travel.x) and on_floor


# -- Real geometry: shaft climbs and the T2 drop -------------------------------------------

func case_climb_and_drop_real_geometry() -> void:
	await _load_level()
	await _probe.place(Vector2(1760.0, 2265.0))
	await _wait_until_free(2.0)
	check(_room() == "B2", "staged on the shaft's bottom step, in B2's half of the opening")
	_changes.clear()
	Input.action_press(&"jump")
	var end_wait := _probe.clock + 1.5
	while _changes.is_empty() and _probe.clock < end_wait:
		await process_frame
	_probe.release_all()
	check(_room() == "Shaft" and _bounds_are(GreeceLayout.camera_bounds("Shaft")), "jumping up from B2 into the shaft switches to the shaft room (%s, y %.0f)" % [_room(), _player.global_position.y])
	check(_changes == [[&"B2", &"Shaft"]], "that climb emitted B2 to Shaft once: %s" % [_changes])
	await _probe.place(Vector2(1790.0, 640.0))
	_changes.clear()
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	var peak_alpha := 0.0
	var end := _probe.clock + 3.0
	while _probe.clock < end:
		await process_frame
		peak_alpha = maxf(peak_alpha, _alpha())
		if _room() == "T2" and _player.is_on_floor() and not _player.is_in_room_transition():
			break
	_probe.release_all()
	check(peak_alpha >= BLACK, "the climb out of the shaft fades to black")
	check(_room() == "T2" and _bounds_are(GreeceLayout.camera_bounds("T2")), "the shaft top opens into T2 with T2's bounds")
	check(_player.is_on_floor() and absf(_player.global_position.y - 544.0) < 1.0 and _inside("T2"), "she ends standing on the T2 floor (y %.0f)" % _player.global_position.y)
	await _probe.place(Vector2(1300.0, 544.0))
	_changes.clear()
	_player.global_position = Vector2(1790.0, 500.0)
	_player.velocity = Vector2.ZERO
	await _probe.secs(2.0)
	check(_room() == "Shaft" and _player.is_on_floor() and _inside("Shaft"), "dropping down the T2 hole lands in the shaft room (%s, y %.0f)" % [_room(), _player.global_position.y])
	check(_changes == [[&"T2", &"Shaft"]], "the drop emitted T2 to Shaft once: %s" % [_changes])


# -- The alcove is part of the shaft ---------------------------------------------------------

func case_alcove_has_no_transition() -> void:
	await _load_level()
	await _probe.place(Vector2(1990.0, GreeceLayout.ALCOVE_FLOOR_Y))
	var sill_room := _room()
	_changes.clear()
	Input.action_press(&"move_left")
	var worst_alpha := 0.0
	var locked_frames := 0
	var end := _probe.clock + 1.2
	while _probe.clock < end:
		await process_frame
		worst_alpha = maxf(worst_alpha, _alpha())
		locked_frames += 1 if _player.is_input_locked() else 0
	_probe.release_all()
	check(sill_room == "Shaft" and _room() == "Shaft", "the alcove sill and the shaft are one camera room")
	check(worst_alpha == 0.0 and locked_frames == 0, "walking out of the alcove never fades or locks (alpha %.2f, %d locked frames)" % [worst_alpha, locked_frames])
	check(_changes.is_empty(), "no room_changed between shaft and alcove: %s" % [_changes])
	check(_player.global_position.x < 1860.0 - 19.0, "she did walk through the door (x %.0f)" % _player.global_position.x)


# -- Input lock ----------------------------------------------------------------------------

func case_input_lock_and_release() -> void:
	await _load_level()
	var door := _door("Entrada", "B2")
	await _probe.place(GreeceLayout.arrival_point(door, "Entrada"))
	Input.action_press(&"move_right")
	var start_x := _player.global_position.x
	while not _player.is_in_room_transition() and _player.global_position.x < start_x + 200.0:
		await process_frame
	Input.action_release(&"move_right")
	check(_player.is_in_room_transition() and _player.is_input_locked(), "walking into the door locks input")
	check(absf(_player.velocity.x - _player.run_max_speed) < 10.0, "she auto-walks at run speed (%.0f)" % _player.velocity.x)
	Input.action_press(&"jump")
	Input.action_press(&"dash")
	_player.request_jump()
	_player.request_dash()
	_player.request_attack(0)
	var highest_rise := 0.0
	var dashed := false
	while _player.is_in_room_transition():
		await process_frame
		highest_rise = maxf(highest_rise, -_player.velocity.y)
		dashed = dashed or _player._state == Player.State.DASH
	_probe.release_all()
	check(highest_rise < 1.0 and not dashed, "touch and key presses during the lock do nothing (rise %.0f)" % highest_rise)
	check(not _player.is_input_locked() and not _player.is_in_room_transition(), "control returns afterwards")
	await _probe.frames(2)
	var released_x := _player.global_position.x
	await _probe.secs(0.5)
	check(absf(_player.global_position.x - released_x) < 4.0 and absf(_player.velocity.x) < 1.0, "no direction is left held after the release (moved %.1f px)" % (_player.global_position.x - released_x))
	check(_player.is_on_floor() and _room() == "B2", "she stands in B2 afterwards")


func _door(from_room: String, to_room: String) -> Dictionary:
	for door: Dictionary in GreeceLayout.doorways():
		if door["from"] == from_room and door["to"] == to_room:
			return door
	return {}


# -- Fades never stack -----------------------------------------------------------------------

func case_fades_do_not_stack() -> void:
	await _load_level()
	var door := _door("Entrada", "B2")
	await _probe.place(Vector2(1000.0, 2720.0))
	_player.take_hazard_damage(1, Vector2(1000.0, 2720.0))
	check(not _transition().begin(door, "Entrada", "B2"), "a room fade cannot start during the hazard return")
	await _probe.secs(1.2)
	check(_alpha() == 0.0 and not _player.is_input_locked() and _player.get_health() == 2, "the hazard return still ends cleanly with its pip lost")
	await _probe.place(GreeceLayout.arrival_point(door, "Entrada"))
	check(_transition().begin(door, "Entrada", "B2"), "with her free the same fade starts")
	var damaged := _player.take_damage(1, Vector2(0.0, 2720.0))
	check(not damaged and _player.get_health() == 2, "no damage is taken during a transition")
	_player.fall_out_of_bounds()
	await _probe.secs(1.5)
	check(not _transition().is_active() and not _player.is_input_locked() and _alpha() == 0.0, "a fall cuts the transition short and the hazard return takes the veil")


# -- Death -----------------------------------------------------------------------------------

func case_death_around_transitions() -> void:
	await _load_level()
	var door := _door("Entrada", "B2")
	await _probe.place(GreeceLayout.arrival_point(door, "Entrada"))
	Input.action_press(&"move_right")
	while not _player.is_in_room_transition():
		await process_frame
	Input.action_release(&"move_right")
	_player._health = 1
	_player.fall_out_of_bounds()
	await _probe.secs(1.5)
	var spawn := GreeceLayout.SPAWN
	check(not _transition().is_active() and not _player.is_input_locked() and _alpha() == 0.0, "death in the middle of a transition leaves no lock or veil")
	check(_player.get_health() == 3 and _player.global_position.distance_to(spawn) < 6.0, "she wakes at the level start with full health")
	check(_room() == "Entrada" and _bounds_are(GreeceLayout.camera_bounds("Entrada")), "the room and bounds match where she woke")
	var finished_door := await _cross(door, "Entrada", "B2")
	check(finished_door["released"] and _room() == "B2", "a normal crossing works after that death")
	_changes.clear()
	_player._health = 1
	_player.fall_out_of_bounds()
	await _probe.secs(1.5)
	check(_room() == "Entrada" and _changes == [[&"B2", &"Entrada"]], "dying right after a transition respawns in Entrada and reports the move: %s" % [_changes])
	check(_bounds_are(GreeceLayout.camera_bounds("Entrada")) and _player.global_position.distance_to(spawn) < 6.0, "the camera snapped to the destination room")
	check(not _player.is_input_locked() and _alpha() == 0.0 and absf(_player.velocity.x) < 1.0, "no doorway walk-out after a respawn")
	check(_player.get_health() == 3, "full health after the second death")

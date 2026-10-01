extends SceneTree
## Regression test for the per-room camera bounds: RoomCamera clamping and
## blending on a synthetic rig, level_01 staying unchanged, room selection in
## GreeceLayout, and the real RoomCamera inside the Greece level.
## Run: godot --headless --path . --script res://tests/room_camera_bounds_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.

const Probe := preload("res://tests/support/greece_probe.gd")
const WATCHDOG_SECONDS := 180.0
const LEVEL_01 := "res://scenes/levels/level_01.tscn"
const WORLD := Vector2(4000.0, 3000.0)
const TRANSITION := 0.35
const SETTLE_SECONDS := 1.5
const EPSILON := 1.0
## Largest camera move in one frame that still reads as a glide, not a snap.
const MAX_GLIDE_STEP := 45.0

const CHECKS := {
	"case_bounds_clamp": 4,
	"case_small_room_centered": 2,
	"case_snap_uses_bounds": 2,
	"case_blend_is_gradual": 4,
	"case_clear_restores_world": 3,
	"case_level_01_unchanged": 3,
	"case_room_selection": 8,
	"case_probe_camera_in_room": 2,
	"case_probe_camera_crossing": 4,
	"case_probe_camera_alcove": 2,
	"case_probe_camera_small_room": 2,
	"case_probe_camera_respawn": 2,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _probe: Probe
var _cam: RoomCamera
var _target: Node2D


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


# -- Synthetic rig -----------------------------------------------------------------

func _make_rig() -> void:
	_target = Node2D.new()
	root.add_child(_target)
	_cam = RoomCamera.new()
	_cam.world_size = WORLD
	_cam.target = _target
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(_cam)


func _free_rig() -> void:
	_cam.queue_free()
	_target.queue_free()
	await process_frame


func _half_view(cam: RoomCamera) -> Vector2:
	return cam.get_viewport_rect().size * 0.5 / cam.zoom


## True when the view sits inside `rect`, or is centred on it when the room is
## smaller than the view on that axis.
func _view_respects(cam: RoomCamera, rect: Rect2) -> bool:
	var half := _half_view(cam)
	var centre := cam.global_position
	return _axis_respects(centre.x, rect.position.x, rect.end.x, half.x) \
		and _axis_respects(centre.y, rect.position.y, rect.end.y, half.y)


func _axis_respects(centre: float, low: float, high: float, half: float) -> bool:
	if high - low <= half * 2.0:
		return absf(centre - (low + high) * 0.5) < EPSILON
	return centre - half >= low - EPSILON and centre + half <= high + EPSILON


func _rects_match(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < EPSILON and a.size.distance_to(b.size) < EPSILON


func case_bounds_clamp() -> void:
	_make_rig()
	var room := Rect2(1000.0, 1000.0, 1200.0, 800.0)
	_cam.set_room_bounds(room, 0.0)
	for point: Vector2 in [Vector2.ZERO, Vector2(5000.0, 5000.0)]:
		_target.global_position = point
		_cam.snap_to_target()
		check(_view_respects(_cam, room), "view stays inside the room with the target at %s" % point)
	_target.global_position = room.get_center()
	_cam.snap_to_target()
	check(_view_respects(_cam, room), "view stays inside the room with the target in the middle")
	check(absf(_cam.global_position.x - room.get_center().x) < EPSILON, "camera follows the target inside the room")
	await _free_rig()


func case_small_room_centered() -> void:
	_make_rig()
	var room := Rect2(2000.0, 2000.0, 500.0, 300.0)
	_cam.set_room_bounds(room, 0.0)
	for point: Vector2 in [Vector2.ZERO, Vector2(2300.0, 2100.0)]:
		_target.global_position = point
		_cam.snap_to_target()
		check(_cam.global_position.distance_to(room.get_center()) < EPSILON, "a room smaller than the view is centred (target %s)" % point)
	await _free_rig()


func case_snap_uses_bounds() -> void:
	_make_rig()
	var room := Rect2(1000.0, 1000.0, 1200.0, 800.0)
	_cam.set_room_bounds(Rect2(0.0, 0.0, 900.0, 900.0), 0.0)
	_cam.set_room_bounds(room, TRANSITION)
	_target.global_position = Vector2(1500.0, 1400.0)
	_cam.snap_to_target()
	check(_rects_match(_cam.get_room_bounds(), room), "snap_to_target finishes a running bounds blend")
	check(_view_respects(_cam, room), "snap_to_target lands inside the new bounds")
	await _free_rig()


func case_blend_is_gradual() -> void:
	_make_rig()
	var from_room := Rect2(0.0, 0.0, 1500.0, 900.0)
	var to_room := Rect2(1500.0, 0.0, 1500.0, 900.0)
	_target.global_position = Vector2(1450.0, 500.0)
	_cam.set_room_bounds(from_room, 0.0)
	_cam.snap_to_target()
	_cam.set_room_bounds(to_room, TRANSITION)
	_target.global_position = Vector2(1600.0, 500.0)
	var steps := await _record_blend_steps(to_room)
	var biggest: float = 0.0 if steps.is_empty() else steps.max()
	check(steps.size() >= 8, "bounds glide over %d frames, not one" % steps.size())
	check(biggest < 150.0, "largest blend step %.0f px per frame" % biggest)
	check(_rects_match(_cam.get_room_bounds(), to_room), "bounds end on the new room")
	await _wait(SETTLE_SECONDS)
	check(_view_respects(_cam, to_room), "view ends inside the new room")
	await _free_rig()


## Per-frame movement of the clamp rect's left edge until it reaches `to_room`.
func _record_blend_steps(to_room: Rect2) -> Array[float]:
	var steps: Array[float] = []
	var last := _cam.get_room_bounds().position.x
	var end := _probe.clock + TRANSITION + 0.3
	while _probe.clock < end:
		await process_frame
		var now := _cam.get_room_bounds().position.x
		if absf(now - last) > 0.01:
			steps.append(absf(now - last))
		last = now
	return steps


func case_clear_restores_world() -> void:
	_make_rig()
	_cam.set_room_bounds(Rect2(1000.0, 1000.0, 1200.0, 800.0), 0.0)
	_cam.clear_room_bounds(0.0)
	_target.global_position = Vector2.ZERO
	_cam.snap_to_target()
	var half := _half_view(_cam)
	check(_rects_match(_cam.get_room_bounds(), Rect2(Vector2.ZERO, WORLD)), "clearing the bounds falls back to the world rect")
	check(_cam.global_position.distance_to(half) < EPSILON, "clamps to the world corner again")
	_cam.set_room_bounds(Rect2(1000.0, 1000.0, 1200.0, 800.0), 0.0)
	_cam.clear_room_bounds(TRANSITION)
	await _wait(TRANSITION + 0.2)
	check(_rects_match(_cam.get_room_bounds(), Rect2(Vector2.ZERO, WORLD)), "a blended clear ends on the world rect")
	await _free_rig()


func _wait(seconds: float) -> void:
	var end := _probe.clock + seconds
	while _probe.clock < end:
		await process_frame


func case_level_01_unchanged() -> void:
	change_scene_to_file(LEVEL_01)
	await _probe.frames(10)
	var cam: RoomCamera = current_scene.get_node("RoomCamera")
	var player: Node2D = current_scene.get_node("Player")
	check(_rects_match(cam.get_room_bounds(), Rect2(Vector2.ZERO, cam.world_size)), "level_01 camera clamps to its world with no bounds")
	await _wait(SETTLE_SECONDS)
	var half := _half_view(cam)
	var expected := Vector2(
		clampf(player.global_position.x, half.x, cam.world_size.x - half.x),
		clampf(player.global_position.y - cam.vertical_offset, half.y, cam.world_size.y - half.y)
	)
	check(cam.global_position.distance_to(expected) < 2.0, "level_01 camera still follows the old world clamp")
	cam.set_room_bounds(Rect2(0.0, 0.0, 800.0, 600.0), 0.0)
	cam.clear_room_bounds(0.0)
	check(_rects_match(cam.get_room_bounds(), Rect2(Vector2.ZERO, cam.world_size)), "clear_room_bounds restores the level_01 world clamp")


# -- Room selection (data) -----------------------------------------------------------

func case_room_selection() -> void:
	var door := Vector2(1132.0, 2640.0)
	check(GreeceLayout.room_for(door, "Entrada") == "Entrada", "standing in the Entrada|B2 doorway keeps Entrada")
	check(GreeceLayout.room_for(door, "B2") == "B2", "standing in the Entrada|B2 doorway keeps B2")
	check(GreeceLayout.room_for(Vector2(1200.0, 2640.0), "Entrada") == "B2", "stepping inside B2 switches to B2")
	check(GreeceLayout.room_for(Vector2(1680.0, 560.0), "T2") == "T2", "16 px into the shaft opening still counts as T2")
	check(GreeceLayout.room_for(Vector2(1680.0, 600.0), "T2") == "Shaft", "well inside the shaft switches to the shaft")
	check(GreeceLayout.room_for(Vector2(1050.0, 1100.0), "") == "Altar", "with no previous room the containing room is picked")
	var shaft := GreeceLayout.camera_bounds("Shaft")
	check(shaft.encloses(GreeceLayout.rooms()["ShaftAlcove"]), "shaft camera bounds include the medal alcove")
	check(_all_bounds_inside_world(), "every room's camera bounds lie inside the world")


func _all_bounds_inside_world() -> bool:
	var world := Rect2(Vector2.ZERO, GreeceLayout.WORLD_SIZE)
	for room_name: String in GreeceLayout.rooms():
		if not world.encloses(GreeceLayout.camera_bounds(room_name)):
			return false
	return true


# -- Real camera in the Greece level ---------------------------------------------------

func _greece_camera() -> RoomCamera:
	return _probe.level.get_node("RoomCamera")


func case_probe_camera_in_room() -> void:
	await _probe.load_level()
	var cam := _greece_camera()
	Input.action_press(&"move_right")
	var outside := 0
	var end := _probe.clock + 0.8
	while _probe.clock < end:
		await process_frame
		if not _view_respects(cam, cam.get_room_bounds()):
			outside += 1
	_probe.release_all()
	check(outside == 0, "camera left the Entrada bounds on %d frames while walking" % outside)
	check(_rects_match(cam.get_room_bounds(), GreeceLayout.camera_bounds("Entrada")), "Entrada camera bounds are the room plus its walls")


func case_probe_camera_crossing() -> void:
	await _probe.load_level()
	var cam := _greece_camera()
	var entrada := GreeceLayout.camera_bounds("Entrada")
	var next_room := GreeceLayout.camera_bounds("B2")
	await _probe.place(Vector2(1040.0, 2719.0))
	Input.action_press(&"move_right")
	var timing := await _watch_crossing(cam, entrada, next_room)
	_probe.release_all()
	check(timing.arrived, "crossing the doorway ends on the B2 bounds")
	check(timing.duration >= TRANSITION * 0.6 and timing.duration <= TRANSITION + 0.15, "bounds blend took %.2fs (about %.2fs)" % [timing.duration, TRANSITION])
	check(timing.max_step < MAX_GLIDE_STEP, "camera moved at most %.0f px in a frame while crossing" % timing.max_step)
	await _wait(SETTLE_SECONDS)
	check(_view_respects(cam, next_room), "camera settles inside the B2 bounds")


## Watches the camera until its bounds are `next_room`. Returns whether they
## got there, how long the blend lasted and the largest camera step per frame.
func _watch_crossing(cam: RoomCamera, entrada: Rect2, next_room: Rect2) -> Dictionary:
	var result := {"arrived": false, "duration": 0.0, "max_step": 0.0}
	var started := -1.0
	var last_position := cam.global_position
	var give_up := _probe.clock + 4.0
	while _probe.clock < give_up and not result.arrived:
		await process_frame
		result.max_step = maxf(result.max_step, cam.global_position.distance_to(last_position))
		last_position = cam.global_position
		if started < 0.0 and not _rects_match(cam.get_room_bounds(), entrada):
			started = _probe.clock
		result.arrived = _rects_match(cam.get_room_bounds(), next_room)
		if result.arrived and started >= 0.0:
			result.duration = _probe.clock - started
	return result


func case_probe_camera_alcove() -> void:
	await _probe.load_level()
	var cam := _greece_camera()
	await _probe.place(Vector2(2370.0, GreeceLayout.ALCOVE_FLOOR_Y - 1.0))
	await _wait(SETTLE_SECONDS)
	var shaft := GreeceLayout.camera_bounds("Shaft")
	check(_rects_match(cam.get_room_bounds(), shaft), "on the medal floor the camera keeps the shaft bounds")
	check(_view_respects(cam, shaft), "the medal floor view stays inside the shaft bounds")


func case_probe_camera_small_room() -> void:
	await _probe.load_level()
	var cam := _greece_camera()
	await _wait(SETTLE_SECONDS)
	var bounds := cam.get_room_bounds()
	check(bounds.size.x < _half_view(cam).x * 2.0, "Entrada is narrower than the view (%.0f px)" % bounds.size.x)
	check(absf(cam.global_position.x - bounds.get_center().x) < EPSILON, "the camera is centred on Entrada")


func case_probe_camera_respawn() -> void:
	await _probe.load_level()
	var cam := _greece_camera()
	await _probe.place(Vector2(3300.0, 2719.0))
	await _wait(SETTLE_SECONDS)
	_probe.player.respawn()
	await _probe.frames(2)
	var entrada := GreeceLayout.camera_bounds("Entrada")
	check(_rects_match(cam.get_room_bounds(), entrada), "respawn jumps the bounds back to Entrada without a blend")
	var landed := cam.global_position
	cam.snap_to_target()
	check(cam.global_position.distance_to(landed) < 2.0, "respawn already snapped the camera onto Luz in Entrada")

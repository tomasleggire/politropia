extends RefCounted
## Shared state, waits and event recording for the Stillness Desk ritual test
## suites. Waits run on the game clock (accumulated process deltas), the time
## base the desk's tweens and the FX use, so a frame hitch stretches a wait
## instead of skewing it.

const LEVEL := "res://scenes/levels/level_01.tscn"
const DESK_ID := &"level_01_desk_a"
const PHASE_DORMANT := 0
const PHASE_AWAKENED := 1
const PHASE_MOUNT := 2
const PHASE_CELEBRATE := 3
const PHASE_RESTING := 4
const PHASE_DISMOUNT := 5
const RITUAL_PHASES: Array[int] = [PHASE_MOUNT, PHASE_CELEBRATE, PHASE_RESTING, PHASE_DISMOUNT]
## A measured duration may overshoot by this many of the worst frames seen.
const HITCH_FRAMES := 3.0

class Dummy extends Node:
	var n := 0

	func reset_to_checkpoint_state() -> void:
		n += 1

var tree: SceneTree
var checks := 0
var failed: Array[String] = []
var clock := 0.0
var dt_max := 0.0
# StillnessDesk, Player, StillnessDeskFx and the autoloads reference autoload
# singletons, which are not resolvable in a --script run, so they are typed by
# their native base class.
var cps: Node
var tc: Node
var lvl: Node
var desk: Node2D
var player: CharacterBody2D
var fx: Node2D
var cam: RoomCamera
var dummy: Dummy
var phases: Array[int] = []
var acts := 0
var trace: Array[Array] = []   # [anim, frame, backpack visible]
var ev: Array[Dictionary] = []
var paper_z: Array[int] = []


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	cps = tree.root.get_node("CheckpointService")
	tc = tree.root.get_node("TouchControls")
	tree.process_frame.connect(_tick)
	tree.process_frame.connect(_sample_trace)
	cps.checkpoint_activated.connect(_count_activation)


# -- Assertions and waits -------------------------------------------------------

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func frames(n: int) -> void:
	for i: int in n:
		await tree.process_frame


func secs(t: float) -> void:
	var end := clock + t
	while clock < end:
		await tree.process_frame


func wait_phase(ph: int, timeout: float = 8.0) -> bool:
	var end := clock + timeout
	while desk.get_phase() != ph and clock < end:
		await tree.process_frame
	return desk.get_phase() == ph


## Restarts the worst-frame measurement for the timing about to be observed.
func open_window() -> void:
	dt_max = 0.0


## A tolerance widened by the worst frames of the current window.
func slack(base: float) -> float:
	return base + HITCH_FRAMES * dt_max


func _tick() -> void:
	var dt := tree.root.get_process_delta_time()
	clock += dt
	dt_max = maxf(dt_max, dt)


# -- Level setup ---------------------------------------------------------------

func fresh_level() -> void:
	cps.clear()
	await setup_level()
	await place()


## Marks the desk as activated without running the ritual (a repeat rest follows).
func awaken() -> void:
	cps.activate(DESK_ID, LEVEL, desk.get_spawn_position())
	await frames(3)
	clear_records()


func place() -> void:
	player.global_position = desk.get_spawn_position()
	player.velocity = Vector2.ZERO
	await frames(30)


func setup_level() -> void:
	tree.change_scene_to_file(LEVEL)
	await frames(10)
	lvl = tree.current_scene
	desk = lvl.get_node("StillnessDesk")
	player = lvl.get_node("Player")
	fx = desk.get_node("Fx")
	cam = lvl.get_node("RoomCamera")
	dummy = Dummy.new()
	dummy.add_to_group("checkpoint_resettable")
	lvl.add_child(dummy)
	clear_records()
	_record_paper_z()
	_bind_desk_signals()


func clear_records() -> void:
	phases.clear()
	ev.clear()
	trace.clear()
	acts = 0
	dummy.n = 0


func _record_paper_z() -> void:
	paper_z.clear()
	for sheet: Node2D in desk.get_node("Visuals/Papers").get_children():
		paper_z.append(sheet.z_index)


func _bind_desk_signals() -> void:
	desk.phase_changed.connect(_on_phase_changed)
	desk.celebration_started.connect(_on_celebration_started)
	desk.celebration_peak.connect(_on_celebration_peak)
	desk.celebration_finished.connect(_on_celebration_finished)
	desk.dismount_started.connect(_on_dismount_started)
	desk.rest_completed.connect(_on_rest_completed)


# -- Event recording -----------------------------------------------------------

func _record(kind: String) -> Dictionary:
	var entry := {"kind": kind, "t": clock, "n": dummy.n, "acts": acts}
	ev.append(entry)
	return entry


func _on_phase_changed(p: int) -> void:
	phases.append(p)


func _on_celebration_started(first: bool) -> void:
	_record("start")["first"] = first


func _on_celebration_peak() -> void:
	_record("peak")["health"] = player._health


func _on_celebration_finished() -> void:
	_record("finish")


func _on_dismount_started() -> void:
	_record("dismount")


func _on_rest_completed(_id: StringName) -> void:
	_record("completed")


func _count_activation(_id: StringName, _path: String, _position: Vector2) -> void:
	acts += 1


func _sample_trace() -> void:
	if not is_instance_valid(desk) or not is_instance_valid(player):
		return
	if desk.get_phase() in RITUAL_PHASES:
		trace.append([player._sprite.animation, player._sprite.frame, desk._backpack.visible])


func events_of(kind: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in ev:
		if entry["kind"] == kind:
			found.append(entry)
	return found


func count_events(kind: String) -> int:
	return events_of(kind).size()


func last_event(kind: String) -> Dictionary:
	var found := events_of(kind)
	return found[-1] if not found.is_empty() else {}


# -- Scene queries -------------------------------------------------------------

func cam_home() -> bool:
	return absf(cam.get_zoom_ratio() - 1.0) < 0.02 and cam.get_focus_weight() < 0.01


func swing_range(t: float) -> float:
	var mx := 0.0
	var end := clock + t
	while clock < end:
		await tree.process_frame
		mx = maxf(mx, absf(fx.get_swing_angle()))
	return mx


func _sheets() -> Array[Node]:
	return desk.get_node("Visuals/Papers").get_children()


func papers_home() -> bool:
	var orbit := fx.get_node("PaperOrbit")
	var sheets := _sheets()
	for i: int in sheets.size():
		if sheets[i].position.distance_to(orbit.get_rest_position(i)) > 1.0:
			return false
	return true


func papers_z_home() -> bool:
	var sheets := _sheets()
	for i: int in sheets.size():
		if sheets[i].z_index != paper_z[i]:
			return false
	return true


func papers_lifted() -> float:
	var orbit := fx.get_node("PaperOrbit")
	var sheets := _sheets()
	var m := 0.0
	for i: int in sheets.size():
		m = maxf(m, sheets[i].position.distance_to(orbit.get_rest_position(i)))
	return m


# -- Input helpers -------------------------------------------------------------

func press_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func key_event(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func touch_event(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)

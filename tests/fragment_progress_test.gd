extends SceneTree
## Book fragments: the run-scoped FragmentProgress autoload (collect, count, no
## double count, signal, reset, save data), the collectable fragment prefab
## (touch collects, stays collected after a room reload, display copies are not
## collectable), the lectern's `require_all_fragments` option and the HUD
## counter.
## Run: godot --headless --path . --script res://tests/fragment_progress_test.gd

const FRAGMENT_SCENE := preload("res://scenes/world/fragmento_libro_2.tscn")
const PEDESTAL_SCENE := "res://scenes/world/atril_libro.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)
const WATCHDOG_SECONDS := 60.0

var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player
var _events: Array[Vector3i] = []


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		print("FAIL: watchdog")
		quit(1))
	await _run()
	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)


func _progress() -> Node:
	return root.get_node("FragmentProgress")


func _run() -> void:
	_case_service()
	await _case_fragment_prefab()
	await _case_pedestal()
	await _case_hud()
	_progress().clear()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _build_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = Node2D.new()
	root.add_child(_rig)
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FLOOR_RECT.size
	shape.shape = rect
	body.position = FLOOR_RECT.get_center()
	body.add_child(shape)
	_rig.add_child(body)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(-400.0, 0.0)
	_rig.add_child(_player)
	await _frames(20)


func _case_service() -> void:
	var progress := _progress()
	progress.clear()
	_events.clear()
	progress.fragment_collected.connect(func(id: int, count: int, total: int) -> void: _events.append(Vector3i(id, count, total)))
	check(progress.count() == 0, "starts empty")
	check(progress.collect(2), "collect returns true the first time")
	check(not progress.collect(2), "no double count")
	check(progress.count() == 1 and progress.has_fragment(2), "count and has_fragment")
	check(not progress.collect(0) and not progress.collect(5), "out of range ids are refused")
	check(_events.size() == 1 and _events[0] == Vector3i(2, 1, 4), "signal carries id, count, total once")
	var saved: Dictionary = progress.to_dict()
	progress.clear()
	check(progress.count() == 0 and not progress.has_fragment(2), "clear forgets")
	progress.from_dict(saved)
	check(progress.has_fragment(2) and progress.count() == 1, "from_dict restores")
	progress.from_dict({"fragments": "bad"})
	check(progress.count() == 0, "bad data leaves a clean slate")
	for id in [1, 2, 3, 4]:
		progress.collect(id)
	check(progress.is_complete(), "complete after four")
	progress.clear()


func _case_fragment_prefab() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	var fragment := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	check(fragment.fragment_id == 2, "scene 2 carries fragment_id 2")
	fragment.position = Vector2(0.0, 0.0)
	_rig.add_child(fragment)
	await _frames(3)
	check(is_instance_valid(fragment) and not progress.has_fragment(2), "not collected before Luz arrives")
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(6)
	check(progress.has_fragment(2) and progress.count() == 1, "touching collects once")
	await create_timer(0.6).timeout
	check(not is_instance_valid(fragment), "collected fragment frees itself")
	# Re-entering the room: a fresh instance of an already collected fragment is gone.
	var again := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	_rig.add_child(again)
	await _frames(3)
	check(not is_instance_valid(again) or again.is_queued_for_deletion(), "collected fragment stays collected after a reload")
	# A display copy never collects.
	progress.clear()
	var display := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	display.collectible = false
	display.position = Vector2(0.0, 0.0)
	_rig.add_child(display)
	_player.global_position = Vector2(300.0, -10.0)
	await _frames(4)
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(6)
	check(progress.count() == 0 and is_instance_valid(display) and not display.is_queued_for_deletion(), "display copies are not collectable")
	progress.clear()


func _case_pedestal() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	# Loaded at run time: the pedestal script names the TouchControls autoload.
	var pedestal := (load(PEDESTAL_SCENE) as PackedScene).instantiate()
	pedestal.position = Vector2(300.0, 0.0)
	_rig.add_child(pedestal)
	await _frames(3)
	check(pedestal.require_all_fragments == false, "require_all_fragments defaults to false")
	pedestal.set("_player", _player)
	check(pedestal.request_interact(), "default pedestal accepts a fragment without collecting any")
	pedestal.set("_fragments_placed", 0)
	pedestal.require_all_fragments = true
	check(not pedestal.request_interact(), "require_all refuses while fragments are missing")
	for id in [1, 2, 3, 4]:
		progress.collect(id)
	check(pedestal.request_interact(), "require_all accepts once all four are collected")
	progress.clear()


func _case_hud() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	progress.collect(1)
	var hud := HUD_SCENE.instantiate()
	_rig.add_child(hud)
	await _frames(2)
	var label := hud.get_node("PlayerUI/FragmentCounter/Count") as Label
	check(label.text == "1/4", "HUD shows the count when created (%s)" % label.text)
	progress.collect(3)
	check(label.text == "2/4", "HUD updates on the signal (%s)" % label.text)
	progress.clear()

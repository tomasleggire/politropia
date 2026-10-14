extends SceneTree
## PauseMenu autoload: inert without Luz, pauses and resumes the tree, keeps the
## touch layer from leaking input, the Mapa hook and the main menu button.
## Run: godot --headless --path . --script res://tests/pause_menu_test.gd

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WATCHDOG_SECONDS := 60.0
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var checks := 0
var failed: Array[String] = []
var _rig: Node2D


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	await process_frame
	var pause := root.get_node_or_null("PauseMenu")
	check(pause != null, "PauseMenu autoload exists")
	if pause == null:
		return
	var touch := root.get_node("TouchControls")
	pause.fade_time = 0.0
	pause.open()
	check(not pause.is_open() and not paused, "cannot pause without Luz")

	_rig = Node2D.new()
	root.add_child(_rig)
	var player := PLAYER_SCENE.instantiate() as Player
	_rig.add_child(player)
	await _frames(3)
	check(pause.can_pause(), "can pause with Luz in the scene")

	touch.call(&"_set_action_held", &"move_left", true)
	check(Input.is_action_pressed(&"move_left"), "setup: move_left held")
	pause.open()
	check(pause.is_open() and paused, "open pauses the tree")
	check(pause.get_node("Menu").visible, "menu visible")
	check(not Input.is_action_pressed(&"move_left"), "touch layer released what it held")
	check(touch.get("_input_blocked") == true, "touch layer blocked while paused")
	check(pause.get_node("Menu/Center/Panel/Margin/Box/Map").disabled, "Mapa disabled by default")
	check(not pause.get_node("PauseButton").visible, "pause button hidden while open")

	var map_requests := [0]
	pause.map_requested.connect(func() -> void: map_requests[0] += 1)
	pause.set_map_enabled(true)
	var map_button := pause.get_node("Menu/Center/Panel/Margin/Box/Map") as Button
	check(not map_button.disabled, "Mapa enabled through the hook")
	map_button.pressed.emit()
	check(map_requests[0] == 1, "Mapa emits map_requested")
	pause.set_map_enabled(false)

	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	pause._unhandled_input(esc)
	check(not pause.is_open() and not paused, "Escape resumes")
	check(touch.get("_input_blocked") == false, "touch layer works again after resume")
	await _frames(2)
	pause._unhandled_input(esc)
	check(pause.is_open() and paused, "Escape opens")
	(pause.get_node("Menu/Center/Panel/Margin/Box/Resume") as Button).pressed.emit()
	check(not pause.is_open() and not paused, "Reanudar resumes")

	pause.show_button_without_touch = true
	await process_frame
	await process_frame
	check(pause.get_node("PauseButton").visible, "pause button shows in game")
	(pause.get_node("PauseButton") as Button).pressed.emit()
	check(pause.is_open(), "pause button opens the menu")
	pause.main_menu_scene = MENU_SCENE
	(pause.get_node("Menu/Center/Panel/Margin/Box/Quit") as Button).pressed.emit()
	await _frames(6)
	check(not paused and not pause.is_open(), "Menú principal unpauses")
	check(current_scene != null and current_scene.scene_file_path == MENU_SCENE, "Menú principal loads the main menu")

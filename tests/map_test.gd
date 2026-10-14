extends SceneTree
## Map: visit tracking, layout resources, MapScreen opening from the pause menu.
## Run: godot --headless --path . --script res://tests/map_test.gd

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WATCHDOG_SECONDS := 60.0
const LIBRARY_Z1 := "res://scenes/levels/library/zone_1.tscn"
const LIBRARY_Z2 := "res://scenes/levels/library/zone_2.tscn"

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
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


func _run() -> void:
	await process_frame
	var progress := root.get_node_or_null("MapProgress")
	var screen := root.get_node_or_null("MapScreen")
	var pause := root.get_node_or_null("PauseMenu")
	check(progress != null and screen != null and pause != null, "autoloads exist")
	if progress == null or screen == null or pause == null:
		return
	_check_progress(progress)
	_check_layouts(progress)
	await _check_screen(progress, screen, pause)


func _check_progress(progress: Node) -> void:
	progress.clear()
	check(progress.visited_count() == 0 and progress.current_scene_path() == "", "starts empty")
	progress.visit(LIBRARY_Z1)
	progress.visit(LIBRARY_Z2)
	progress.visit(LIBRARY_Z1)
	check(progress.visited_count() == 2, "visits are counted once")
	check(progress.has_visited(LIBRARY_Z2) and not progress.has_visited("res://scenes/levels/library/zone_5.tscn"), "only visited rooms are known")
	check(progress.current_scene_path() == LIBRARY_Z1, "current room is the last one entered")
	var data: Dictionary = progress.to_dict()
	progress.clear()
	check(progress.visited_count() == 0, "clear forgets the rooms")
	progress.from_dict(data)
	check(progress.visited_count() == 2 and progress.current_scene_path() == LIBRARY_Z1, "from_dict restores")
	progress.from_dict({"visited": "nonsense"})
	check(progress.visited_count() == 0, "invalid data leaves a clean slate")
	progress.clear()


func _check_layouts(_progress: Node) -> void:
	var layouts := MapLayout.load_all()
	check(layouts.size() >= 2, "layout resources load (%d)" % layouts.size())
	var names := layouts.map(func(layout: MapLayout) -> String: return layout.level_name)
	check("Biblioteca" in names and "Grecia" in names, "library and greece layouts exist")
	for layout in layouts:
		check(not layout.rooms.is_empty() and layout.bounds().size.x > 0.0, "%s has rooms" % layout.level_name)
		for room in layout.rooms:
			check(ResourceLoader.exists(room.scene_path), "%s scene exists: %s" % [layout.level_name, room.scene_path])
			check(not room.display_name.is_empty() and room.map_rect.size.x > 0.0, "%s room is named and sized" % room.scene_path)
			for other in room.connects_to:
				var back := layout.find_room(other)
				check(back != null and room.scene_path in back.connects_to, "connection is mutual: %s" % room.scene_path.get_file())
	check(MapLayout.find_for_scene(LIBRARY_Z1).level_name == "Biblioteca", "find_for_scene")
	check(MapLayout.find_for_scene("res://nope.tscn") == null, "unknown scene has no layout")
	for level in ["library", "greece"]:
		for zone in ["zone_1", "zone_2", "zone_3", "zone_4", "zone_5", "zone_6", "zone_healing"]:
			var path := "res://scenes/levels/%s/%s.tscn" % [level, zone]
			check(MapLayout.find_for_scene(path) != null, "%s/%s is on the map" % [level, zone])
	var artemis := MapLayout.find_for_scene("res://scenes/levels/greece/zone_artemis.tscn")
	check(artemis != null and artemis.level_name == "Grecia", "greece/zone_artemis is on the map")


func _check_screen(progress: Node, screen: Node, pause: Node) -> void:
	var rig := Node2D.new()
	root.add_child(rig)
	var player := PLAYER_SCENE.instantiate() as Player
	rig.add_child(player)
	await physics_frame
	pause.fade_time = 0.0
	check(not screen.is_open(), "map starts closed")
	progress.clear()
	progress.visit(LIBRARY_Z1)
	progress.visit(LIBRARY_Z2)
	pause.open()
	check(pause.is_open() and paused, "pause opens")
	var map_button := pause.get_node("Menu/Center/Panel/Margin/Box/Map") as Button
	check(not map_button.disabled, "Mapa button is enabled")
	map_button.pressed.emit()
	check(screen.is_open() and paused, "Mapa opens the map while paused")
	check((screen.get_node("Root/Frame/Box/Header/Title") as Label).text == "Biblioteca", "shows the level name")
	var fragments := (screen.get_node("Root/Frame/Box/Header/Fragments") as Label).text
	check(fragments == "Fragmentos %d/4" % root.get_node("FragmentProgress").count(), "shows the fragments (%s)" % fragments)
	check((screen.get_node("Root/Frame/Box/Footer/Hint") as Label).text == "Pasillo de lectura", "names the current room")
	await process_frame
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	check(not screen.is_open(), "Escape closes the map")
	check(pause.is_open() and paused, "back to the pause menu, still paused")
	pause.close()
	check(not paused, "resume unpauses")
	screen.open()
	check(screen.is_open() and paused, "open works outside the pause menu")
	screen.close()
	check(not screen.is_open() and not paused, "close restores the game")
	rig.queue_free()
	progress.clear()

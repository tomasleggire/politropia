extends SceneTree
## Collectibles: session manager (catalog validation, duplicates, signals,
## reset), world pickup (real player layers, non-player bodies, immediate
## deactivation, reload), scene changes, gallery logic and the main-menu
## integration (Collectables opens the gallery, Volver returns, New Game clears).
## Run: godot --headless --path . --script res://tests/collectibles_test.gd

const PICKUP_SCENE := preload("res://scenes/world/collectible_pickup.tscn")
const GALLERY_SCENE := preload("res://scenes/ui/collectibles_gallery.tscn")
const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const GALLERY_PATH := "res://scenes/ui/collectibles_gallery.tscn"
const MENU_PATH := "res://scenes/ui/main_menu.tscn"
const ZONE_1 := "res://scenes/levels/library/zone_1.tscn"
const ZONE_2 := "res://scenes/levels/library/zone_2.tscn"
const FIRST_ID := "library_first_page"
const SECOND_ID := "library_marginal_note"
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)
const WATCHDOG_SECONDS := 120.0

var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player


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


func _manager() -> Node:
	return root.get_node("Collectibles")


func _definitions() -> Array:
	return _manager().call("get_all_definitions")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	# Let the autoloads finish their _ready() (the manager loads the catalog there).
	await process_frame
	_case_service()
	await _case_pickup()
	await _case_scene_reload()
	await _case_gallery_logic()
	await _case_menu_integration()
	_manager().call("clear")


func _case_service() -> void:
	var manager := _manager()
	manager.call("clear")
	print("CASE manager")

	check(int(manager.call("get_total_count")) == 4, "catalog has four provisional collectibles")
	check(_definitions().size() == 4, "get_all_definitions returns the whole catalog")
	var ids: Array = []
	for definition: CollectibleDefinition in _definitions():
		ids.append(definition.id)
	check(ids.size() == 4 and ids.count(FIRST_ID) == 1 and ids.count(SECOND_ID) == 1, "catalog ids are unique and stable")
	check(not bool(manager.call("has_collected", FIRST_ID)), "has_collected is false before collecting")

	var events: Array = []
	var on_collected := func(id: String, count: int, total: int) -> void:
		events.append(Vector3i(ids.find(id), count, total))
	manager.connect("collectible_collected", on_collected)

	check(bool(manager.call("try_collect", FIRST_ID)), "try_collect accepts a catalog id")
	check(bool(manager.call("has_collected", FIRST_ID)), "collected id is reported by has_collected")
	check(int(manager.call("get_collected_count")) == 1, "collected count increases once")
	check(not bool(manager.call("try_collect", FIRST_ID)), "the same id cannot be collected twice")
	check(int(manager.call("get_collected_count")) == 1, "duplicate collection does not increase the count")
	check(events.size() == 1 and events[0] == Vector3i(ids.find(FIRST_ID), 1, 4), "signal fires once with id, count and total")

	check(bool(manager.call("try_collect", SECOND_ID)), "a second, different id can be collected")
	check(int(manager.call("get_collected_count")) == 2, "two different ids count independently")
	check(bool(manager.call("has_collected", FIRST_ID)) and bool(manager.call("has_collected", SECOND_ID)), "both ids stay collected")
	var collected: Array = manager.call("get_collected_ids")
	check(collected == [FIRST_ID, SECOND_ID], "get_collected_ids is sorted and complete")

	check(not bool(manager.call("try_collect", "unknown_collectible")), "an id outside the catalog is rejected")
	check(not bool(manager.call("has_collected", "unknown_collectible")), "a rejected id is not registered")
	check(int(manager.call("get_collected_count")) == 2, "a rejected id does not change the count")
	check(events.size() == 2, "only accepted collections emit the signal")
	manager.disconnect("collectible_collected", on_collected)

	# clear() must forget collected ids without touching the catalog or other progress.
	var fragments := root.get_node("FragmentProgress")
	fragments.clear()
	fragments.collect(1)
	manager.call("clear")
	check(int(manager.call("get_collected_count")) == 0, "clear forgets the collectibles of the session")
	check(not bool(manager.call("has_collected", FIRST_ID)), "clear removes has_collected")
	check(int(manager.call("get_total_count")) == 4 and _definitions().size() == 4, "clear keeps the catalog intact")
	check(bool(fragments.has_fragment(1)), "clear does not touch FragmentProgress")
	fragments.clear()


func _build_rig() -> void:
	_free_rig()
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


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null


func _make_pickup(definition: CollectibleDefinition, at: Vector2) -> CollectiblePickup:
	var pickup := PICKUP_SCENE.instantiate() as CollectiblePickup
	pickup.definition = definition
	pickup.position = at
	# Keep the node alive long enough to inspect its state without depending on
	# the animation: the collection must be registered before it ends.
	pickup.collect_animation_time = 1.0
	return pickup


func _case_pickup() -> void:
	print("CASE pickup")
	var manager := _manager()
	manager.call("clear")
	var definition := _definitions()[0] as CollectibleDefinition
	await _build_rig()

	var pickup := _make_pickup(definition, Vector2(0.0, -30.0))
	_rig.add_child(pickup)
	await _frames(3)
	check(is_instance_valid(pickup) and not pickup.is_collected(), "pickup waits until the player touches it")

	# A body on the player's physics layer but outside the player group must not count.
	var stranger := CharacterBody2D.new()
	stranger.collision_layer = 1
	stranger.collision_mask = 0
	var stranger_shape := CollisionShape2D.new()
	var stranger_rect := RectangleShape2D.new()
	stranger_rect.size = Vector2(24.0, 44.0)
	stranger_shape.shape = stranger_rect
	stranger_shape.position = Vector2(0.0, -22.0)
	stranger.add_child(stranger_shape)
	stranger.position = Vector2(0.0, -30.0)
	_rig.add_child(stranger)
	await _frames(4)
	check(int(manager.call("get_collected_count")) == 0, "a non-player body does not collect")
	check(is_instance_valid(pickup) and not pickup.is_collected(), "the pickup stays available after a non-player body touches it")
	stranger.queue_free()
	await _frames(2)

	var events: Array = []
	var on_collected := func(id: String, _count: int, _total: int) -> void:
		events.append(id)
	manager.connect("collectible_collected", on_collected)

	_player.global_position = Vector2(0.0, -10.0)
	await _frames(2)
	await process_frame
	check(bool(manager.call("has_collected", FIRST_ID)), "the real player body collects on contact")
	check(is_instance_valid(pickup) and pickup.is_collected(), "pickup marks itself collected before the animation ends")
	check(not pickup.monitoring and pickup.get_node("CollisionShape2D").disabled, "collision is disabled immediately after collecting")
	check(is_instance_valid(pickup) and pickup.visible, "the node is still fading when the checks run")
	check(events.size() == 1, "collection emits the manager signal exactly once")

	_player.global_position = Vector2(-400.0, -10.0)
	await _frames(3)
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(4)
	check(int(manager.call("get_collected_count")) == 1, "touching again does not duplicate progress")
	check(events.size() == 1, "no second collection signal")
	manager.disconnect("collectible_collected", on_collected)

	# Death and respawn must not touch the collectible progress.
	check(_player.take_damage(999, _player.global_position), "lethal damage starts the death flow")
	await _frames(90)
	check(bool(manager.call("has_collected", FIRST_ID)), "collectibles stay collected after death and respawn")
	check(int(manager.call("get_collected_count")) == 1, "death does not duplicate or clear progress")

	# Re-instantiating the level object simulates a reload: it must vanish at once.
	var reloaded := _make_pickup(definition, Vector2(220.0, -30.0))
	_rig.add_child(reloaded)
	await _frames(3)
	check(not is_instance_valid(reloaded) or reloaded.is_queued_for_deletion(), "an already collected object removes itself on build")

	_free_rig()
	manager.call("clear")


func _wait_scene() -> void:
	for i in 5:
		await process_frame


func _case_scene_reload() -> void:
	print("CASE scene reload")
	var manager := _manager()
	manager.call("clear")
	check(bool(manager.call("try_collect", FIRST_ID)), "first id collected before changing level")
	check(bool(manager.call("try_collect", SECOND_ID)), "second id collected before changing level")

	change_scene_to_file(ZONE_1)
	await _wait_scene()
	check(current_scene != null and current_scene.scene_file_path == ZONE_1, "zone 1 loaded")
	check(bool(manager.call("has_collected", FIRST_ID)), "progress survives a change_scene_to_file")
	var pickup := current_scene.get_node_or_null("CollectibleFirstPage")
	check(pickup == null or pickup.is_queued_for_deletion(), "zone 1 pickup is gone after being collected earlier")

	change_scene_to_file(ZONE_2)
	await _wait_scene()
	check(current_scene != null and current_scene.scene_file_path == ZONE_2, "zone 2 loaded through the connected door target")
	check(bool(manager.call("has_collected", FIRST_ID)) and bool(manager.call("has_collected", SECOND_ID)), "both ids stay collected across two level loads")
	var connected_pickup := current_scene.get_node_or_null("CollectibleMarginalNote")
	check(connected_pickup == null or connected_pickup.is_queued_for_deletion(), "zone 2 pickup is gone after being collected earlier")

	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	await process_frame
	manager.call("clear")


func _case_gallery_logic() -> void:
	print("CASE gallery")
	var manager := _manager()
	manager.call("clear")
	var holder := Control.new()
	holder.size = Vector2(640.0, 360.0)
	root.add_child(holder)
	var gallery := GALLERY_SCENE.instantiate()
	holder.add_child(gallery)
	await process_frame
	await process_frame

	check(gallery.call("get_slot_count") == 4, "gallery lists the whole catalog")
	check(gallery.call("get_progress_text") == "0 / 4", "gallery starts with zero progress")
	check(bool(gallery.call("is_selected_locked")), "the default selection is locked while nothing is collected")
	check(gallery.call("get_selected_title") == "???", "a locked item hides its title")
	check(gallery.call("get_selected_category") == "Bloqueado", "a locked item hides its category")
	var first := _definitions()[0] as CollectibleDefinition
	var locked_body: String = gallery.call("get_selected_body")
	check(not locked_body.contains(first.title) and not locked_body.contains("Texto provisional"), "a locked item hides its content")
	check(first.image == null, "the provisional catalog includes an item without a texture")
	check(gallery.call("get_slot_count") == 4, "an empty texture does not remove or break a slot")

	check(bool(manager.call("try_collect", FIRST_ID)), "gallery test collects the first item")
	gallery.call("refresh")
	await process_frame
	check(gallery.call("get_progress_text") == "1 / 4", "gallery updates the progress counter")
	check(gallery.call("get_selected_index") == 0 and not bool(gallery.call("is_selected_locked")), "the first unlocked item is selected by default")
	check(gallery.call("get_selected_title") == first.title, "an unlocked item shows its title")
	check(gallery.call("get_selected_category") == first.category, "an unlocked item shows its category")
	check(gallery.call("get_selected_body") == first.content, "an unlocked item shows its full text")

	gallery.call("select_item", 1)
	check(bool(gallery.call("is_selected_locked")) and gallery.call("get_selected_title") == "???", "selecting a locked slot keeps it hidden")
	check(not String(gallery.call("get_selected_body")).contains("Texto provisional"), "selecting a locked slot does not leak its text")
	check(gallery.call("get_slot_count") == 4, "the full catalog remains visible with one unlocked item")

	var detail_text := gallery.get_node("%DetailText") as RichTextLabel
	var detail_scroll := gallery.get_node("%DetailScroll") as ScrollContainer
	detail_text.text = "Una entrada larga de prueba para comprobar el desplazamiento.\n".repeat(30)
	await process_frame
	var scroll_bar := detail_scroll.get_v_scroll_bar()
	check(scroll_bar.max_value > scroll_bar.page, "a long detail text becomes scrollable")

	holder.queue_free()
	await process_frame
	manager.call("clear")


func _case_menu_integration() -> void:
	print("CASE menu")
	var manager := _manager()
	manager.call("clear")
	var menu := MENU_SCENE.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame

	check((menu.get_node("%Continue") as Button).disabled, "Continue stays disabled")
	check((menu.get_node("%Achievements") as Button).text.strip_edges() == "LOGROS", "Achievements keeps its label")
	manager.call("try_collect", FIRST_ID)
	menu.call("_reset_new_game_progress")
	check(not bool(manager.call("has_collected", FIRST_ID)), "New Game reset clears collectibles")
	check(int(manager.call("get_collected_count")) == 0, "New Game leaves collectible progress empty")

	;(menu.get_node("%Collectables") as Button).pressed.emit()
	await _wait_scene()
	check(current_scene != null and current_scene.scene_file_path == GALLERY_PATH, "Collectables opens the gallery")
	if current_scene != null and current_scene.scene_file_path == GALLERY_PATH:
		check(current_scene.call("get_slot_count") == 4, "the gallery opens without a saved game")
		check(current_scene.call("get_progress_text") == "0 / 4", "a new session shows every gallery item locked")
		;(current_scene.get_node("%Back") as Button).pressed.emit()
		await _wait_scene()
		check(current_scene != null and current_scene.scene_file_path == MENU_PATH, "Volver returns to the main menu")
		# The main menu starts a background load of zone 1 in _ready(). Finish it
		# before quitting so the headless log does not report a load cut short.
		var load_status := ResourceLoader.load_threaded_get_status(ZONE_1)
		if load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(ZONE_1)

	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	manager.call("clear")

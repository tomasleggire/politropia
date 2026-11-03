extends SceneTree
## Collectibles: session manager (catalog validation, duplicates, signals,
## reset), world pickup (real player layers, non-player bodies, immediate
## deactivation, reload), scene changes, gallery logic and the main-menu
## integration (Collectables opens the gallery, Volver returns, New Game clears).
## Run: godot --headless --path . --script res://tests/collectibles_test.gd

const PICKUP_SCENE := preload("res://scenes/world/collectible_pickup.tscn")
const GALLERY_SCENE := preload("res://scenes/ui/collectibles_gallery.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const GALLERY_PATH := "res://scenes/ui/collectibles_gallery.tscn"
const MENU_PATH := "res://scenes/ui/main_menu.tscn"
const ZONE_1 := "res://scenes/levels/library/zone_1.tscn"
const ZONE_2 := "res://scenes/levels/library/zone_2.tscn"
const FIRST_ID := "ruby_owl_read_aloud"
const SECOND_ID := "emerald_bull_clear_text"
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)
const WATCHDOG_SECONDS := 120.0
const EXPECTED_REGIONS := {
	"ruby_owl_read_aloud": Vector2i(0, 0),
	"emerald_bull_clear_text": Vector2i(512, 0),
	"sapphire_horse_extra_time": Vector2i(1024, 0),
	"turquoise_dolphin_learn_by_listening": Vector2i(0, 512),
	"jade_hound_quiet_space": Vector2i(512, 512),
	"garnet_goat_other_ways": Vector2i(1024, 512),
}

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
	_case_coin_textures()
	await _case_pickup()
	await _case_scene_reload()
	await _case_gallery_logic()
	await _case_menu_integration()
	_manager().call("clear")


func _case_service() -> void:
	var manager := _manager()
	manager.call("clear")
	print("CASE manager")

	check(int(manager.call("get_total_count")) == 6, "catalog has the six collectibles")
	check(_definitions().size() == 6, "get_all_definitions returns the whole catalog")
	var ids: Array = []
	for definition: CollectibleDefinition in _definitions():
		ids.append(definition.id)
	check(ids.size() == 6 and ids.count(FIRST_ID) == 1 and ids.count(SECOND_ID) == 1, "catalog ids are unique and stable")
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
	check(events.size() == 1 and events[0] == Vector3i(ids.find(FIRST_ID), 1, 6), "signal fires once with id, count and total")

	check(bool(manager.call("try_collect", SECOND_ID)), "a second, different id can be collected")
	check(int(manager.call("get_collected_count")) == 2, "two different ids count independently")
	check(bool(manager.call("has_collected", FIRST_ID)) and bool(manager.call("has_collected", SECOND_ID)), "both ids stay collected")
	var collected: Array = manager.call("get_collected_ids")
	check(collected == [SECOND_ID, FIRST_ID], "get_collected_ids is sorted and complete")

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
	check(int(manager.call("get_total_count")) == 6 and _definitions().size() == 6, "clear keeps the catalog intact")
	check(bool(fragments.has_fragment(1)), "clear does not touch FragmentProgress")
	fragments.clear()


func _case_coin_textures() -> void:
	print("CASE coin textures")
	var definitions := _definitions()
	var all_assigned := definitions.size() == 6
	var all_512 := true
	var all_transparent := true
	var same_atlas := true
	var shared_atlas: Texture2D = null
	var unique_regions := true
	var unique_images := true
	var regions: Array[Vector2i] = []
	var image_blobs: Array[PackedByteArray] = []
	for definition: CollectibleDefinition in definitions:
		var image := definition.image
		if image == null or not (image is AtlasTexture):
			all_assigned = false
			continue
		var atlas_texture := image as AtlasTexture
		var region := atlas_texture.region
		all_512 = all_512 and image.get_size() == Vector2(512.0, 512.0) and region.size == Vector2(512.0, 512.0)
		var expected: Vector2i = EXPECTED_REGIONS.get(definition.id, Vector2i(-1, -1))
		all_assigned = all_assigned and Vector2i(region.position) == expected
		if atlas_texture.atlas == null:
			all_assigned = false
		elif shared_atlas == null:
			shared_atlas = atlas_texture.atlas
		elif shared_atlas != atlas_texture.atlas:
			same_atlas = false
		for existing: Vector2i in regions:
			if existing == Vector2i(region.position):
				unique_regions = false
		regions.append(Vector2i(region.position))

		var region_image := atlas_texture.get_image()
		if region_image == null:
			all_transparent = false
			continue
		var pixels := region_image.get_data()
		var transparent_pixels := 0
		for i in range(3, pixels.size(), 4):
			if pixels[i] <= 2:
				transparent_pixels += 1
		var visible_pixels := pixels.size() / 4 - transparent_pixels
		all_transparent = all_transparent and transparent_pixels > 0 and visible_pixels > 0
		var blob := region_image.get_data()
		for existing: PackedByteArray in image_blobs:
			if existing == blob:
				unique_images = false
		image_blobs.append(blob)

	check(definitions.size() == 6, "six collectible definitions are present")
	check(all_assigned, "all six definitions have an AtlasTexture from coins.png")
	check(all_512, "all six coin regions are exactly 512x512")
	check(regions.size() == 6 and unique_regions, "the six coin regions cover different spritesheet areas")
	check(same_atlas and shared_atlas != null and shared_atlas.get_size() == Vector2(1536.0, 1024.0), "all coins reference the same full-resolution 1536x1024 spritesheet")
	check(shared_atlas != null and shared_atlas.resource_path == "res://coins.png", "the shared atlas is the original coins.png import")
	check(all_transparent, "the coin regions keep a transparent background")
	check(unique_images, "the six regions contain different coin art")


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
	var pickup_icon := pickup.get_node("Icon") as Sprite2D
	var pickup_placeholder := pickup.get_node("Placeholder") as Polygon2D
	check(pickup_icon.texture == definition.image, "pickup uses the image of its own definition")
	check(pickup_icon.visible and not pickup_placeholder.visible, "pickup hides the placeholder when the coin exists")
	check(pickup_icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pickup keeps nearest filtering for the coin")
	check(pickup_icon.modulate == Color.WHITE, "pickup does not tint the original coin colors")
	check(is_equal_approx(pickup_icon.scale.x, 26.0 / 512.0), "pickup scales the 512x512 coin cell without distortion")

	var second_definition := _definitions()[1] as CollectibleDefinition
	var second_pickup := _make_pickup(second_definition, Vector2(300.0, -30.0))
	_rig.add_child(second_pickup)
	await _frames(3)
	var second_icon := second_pickup.get_node("Icon") as Sprite2D
	check(second_icon.texture == second_definition.image, "a second pickup uses its own definition image")
	check(second_icon.texture != pickup_icon.texture, "different definitions use different coin regions")
	second_pickup.queue_free()
	await _frames(2)

	# A real definition without art must keep the neutral placeholder and not crash.
	var fallback_definition := CollectibleDefinition.new()
	fallback_definition.id = "missing_image_test"
	fallback_definition.title = "Sin imagen"
	fallback_definition.image = null
	var fallback_pickup := _make_pickup(fallback_definition, Vector2(400.0, -30.0))
	_rig.add_child(fallback_pickup)
	await _frames(3)
	check(not (fallback_pickup.get_node("Icon") as Sprite2D).visible, "a definition without image hides the coin sprite")
	check((fallback_pickup.get_node("Placeholder") as Polygon2D).visible, "a definition without image keeps the neutral placeholder")
	fallback_pickup.queue_free()
	await _frames(2)

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
	var pickup := current_scene.get_node_or_null("CollectibleRubyOwl")
	check(pickup == null or pickup.is_queued_for_deletion(), "zone 1 pickup is gone after being collected earlier")

	change_scene_to_file(ZONE_2)
	await _wait_scene()
	check(current_scene != null and current_scene.scene_file_path == ZONE_2, "zone 2 loaded through the connected door target")
	check(bool(manager.call("has_collected", FIRST_ID)) and bool(manager.call("has_collected", SECOND_ID)), "both ids stay collected across two level loads")
	var connected_pickup := current_scene.get_node_or_null("CollectibleEmeraldBull")
	check(connected_pickup == null or connected_pickup.is_queued_for_deletion(), "zone 2 pickup is gone after being collected earlier")

	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	await process_frame
	manager.call("clear")


func _slot_icon(gallery: Node, index: int) -> CollectibleIcon:
	var grid := gallery.get_node_or_null("%Grid")
	if grid == null:
		return null
	var slot := grid.get_node_or_null("Slot%d" % index)
	if slot == null:
		return null
	return slot.get_node_or_null("Content/Icon") as CollectibleIcon


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

	check(gallery.call("get_slot_count") == 6, "gallery lists the whole catalog")
	check(gallery.call("get_progress_text") == "0 / 6", "gallery starts with zero progress")
	check(bool(gallery.call("is_selected_locked")), "the default selection is locked while nothing is collected")
	check(gallery.call("get_selected_title") == "???", "a locked item hides its title")
	check(gallery.call("get_selected_category") == "Bloqueado", "a locked item hides its category")
	var first := _definitions()[0] as CollectibleDefinition
	var locked_body: String = gallery.call("get_selected_body")
	check(not locked_body.contains(first.title) and not locked_body.contains("texto a voz"), "a locked item hides its content")
	check(first.image != null, "the first catalog item has a coin texture")
	check(gallery.call("get_slot_count") == 6, "the assigned texture does not remove or break a slot")
	var gallery_icons: Array[CollectibleIcon] = []
	for i in 6:
		var icon := _slot_icon(gallery, i)
		check(icon != null and icon.definition == _definitions()[i], "gallery slot %d uses its own definition" % i)
		if icon != null:
			gallery_icons.append(icon)
			check(icon.locked, "locked gallery slot %d keeps its silhouette state" % i)
			check(icon.definition.image != null, "locked gallery slot %d still has its assigned coin" % i)
			check(icon.uses_coin_silhouette(), "locked gallery slot %d silhouettes its own coin" % i)
			check(icon.material is ShaderMaterial, "locked gallery slot %d uses the silhouette shader" % i)
			check(icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "gallery slot %d uses nearest filtering" % i)
	check(gallery_icons.size() == 6, "all six gallery slots have their coin icon")
	if gallery_icons.size() == 6:
		var silhouette_material := gallery_icons[0].material as ShaderMaterial
		var silhouette_shader := silhouette_material.shader if silhouette_material != null else null
		check(silhouette_shader != null, "the locked silhouette shader loads")
		if silhouette_shader != null:
			check(silhouette_shader.code.contains("source.a") and silhouette_shader.code.contains("silhouette_color.rgb"), "the silhouette shader darkens RGB while keeping the coin alpha")
	var detail_icon := gallery.get_node("%DetailIcon") as CollectibleIcon
	check(detail_icon != null and detail_icon.locked, "the locked detail draws a silhouette")
	check(detail_icon != null and detail_icon.definition.image == first.image, "the detail and the first slot use the same coin texture")
	check(detail_icon != null and detail_icon.uses_coin_silhouette(), "the locked detail silhouettes the selected coin")

	check(bool(manager.call("try_collect", FIRST_ID)), "gallery test collects the first item")
	gallery.call("refresh")
	await process_frame
	check(gallery.call("get_progress_text") == "1 / 6", "gallery updates the progress counter")
	check(gallery.call("get_selected_index") == 0 and not bool(gallery.call("is_selected_locked")), "the first unlocked item is selected by default")
	check(gallery.call("get_selected_title") == first.title, "an unlocked item shows its title")
	check(gallery.call("get_selected_category") == first.category, "an unlocked item shows its category")
	check(gallery.call("get_selected_body") == first.content, "an unlocked item shows its full text")
	var unlocked_slot := _slot_icon(gallery, 0)
	check(unlocked_slot != null and not unlocked_slot.locked, "the first unlocked slot stops using the silhouette")
	check(unlocked_slot != null and unlocked_slot.definition.image == first.image, "the unlocked slot shows the first coin")
	check(unlocked_slot != null and not unlocked_slot.uses_coin_silhouette() and unlocked_slot.material == null, "the unlocked slot draws the coin with its original colors")
	check(detail_icon != null and not detail_icon.locked, "the unlocked detail stops using the silhouette")
	check(detail_icon != null and detail_icon.definition.image == first.image, "the unlocked detail shows the same first coin")
	check(detail_icon != null and not detail_icon.uses_coin_silhouette() and detail_icon.material == null, "the unlocked detail draws the coin with its original colors")

	gallery.call("select_item", 1)
	check(bool(gallery.call("is_selected_locked")) and gallery.call("get_selected_title") == "???", "selecting a locked slot keeps it hidden")
	check(not String(gallery.call("get_selected_body")).contains("texto a voz"), "selecting a locked slot does not leak its text")
	check(detail_icon != null and detail_icon.locked, "selecting a locked slot restores the silhouette")
	check(detail_icon != null and detail_icon.definition.image == _definitions()[1].image, "the locked detail still references its own coin")
	check(detail_icon != null and detail_icon.uses_coin_silhouette(), "the restored silhouette still uses the selected coin")
	check(gallery.call("get_slot_count") == 6, "the full catalog remains visible with one unlocked item")

	var detail_text := gallery.get_node("%DetailText") as RichTextLabel
	var detail_scroll := gallery.get_node("%DetailScroll") as ScrollContainer
	detail_text.text = "Una entrada larga de prueba para comprobar el desplazamiento.\n".repeat(30)
	await process_frame
	var scroll_bar := detail_scroll.get_v_scroll_bar()
	check(scroll_bar.max_value > scroll_bar.page, "a long detail text becomes scrollable")

	var fallback_definition := CollectibleDefinition.new()
	fallback_definition.id = "missing_image_test"
	fallback_definition.title = "Sin imagen"
	fallback_definition.image = null
	var fallback_icon := CollectibleIcon.new()
	fallback_icon.size = Vector2(62.0, 62.0)
	fallback_icon.set_definition(fallback_definition, false)
	holder.add_child(fallback_icon)
	var locked_fallback_icon := CollectibleIcon.new()
	locked_fallback_icon.size = Vector2(62.0, 62.0)
	locked_fallback_icon.set_definition(fallback_definition, true)
	holder.add_child(locked_fallback_icon)
	await process_frame
	check(fallback_icon.definition == fallback_definition and fallback_icon.definition.image == null, "a missing image keeps the gallery fallback path")
	check(not fallback_icon.uses_coin_silhouette() and fallback_icon.material == null, "an unlocked missing image keeps the procedural fallback")
	check(not locked_fallback_icon.uses_coin_silhouette() and locked_fallback_icon.material == null, "a locked missing image keeps the generic silhouette fallback")
	check(gallery.call("get_slot_count") == 6, "a missing image does not change the catalog or slot count")
	fallback_icon.queue_free()
	locked_fallback_icon.queue_free()
	await process_frame

	holder.queue_free()
	await process_frame
	manager.call("clear")


func _case_menu_integration() -> void:
	print("CASE menu")
	var manager := _manager()
	manager.call("clear")
	var menu_scene := load(MENU_PATH) as PackedScene
	check(menu_scene != null, "the main menu scene loads")
	if menu_scene == null:
		return
	var menu := menu_scene.instantiate()
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
		check(current_scene.call("get_slot_count") == 6, "the gallery opens without a saved game")
		check(current_scene.call("get_progress_text") == "0 / 6", "a new session shows every gallery item locked")
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

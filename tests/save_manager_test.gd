extends SceneTree

## Unit test for SaveManager: local serialization, restoration, and merge.
## Run: godot --headless --path . --script res://tests/save_manager_test.gd

const WATCHDOG_SECONDS := 10.0

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		print("FAIL: watchdog")
		quit(1)
	)
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

	var save_mgr := root.get_node_or_null("/root/SaveManager")
	check(save_mgr != null, "SaveManager exists in tree")
	if save_mgr == null:
		return

	var collectibles := root.get_node_or_null("/root/Collectibles")
	var abilities := root.get_node_or_null("/root/AbilityProgress")
	var checkpoints := root.get_node_or_null("/root/CheckpointService")

	# Clean slate
	save_mgr.clear_save()
	check(not save_mgr.has_save(), "clean save file removed")

	# Populate test data
	if abilities:
		abilities.record(&"double_jump")
		check(abilities.is_unlocked(&"double_jump"), "double_jump recorded")

	if checkpoints:
		checkpoints.activate(&"test_cp", "res://scenes/levels/library/zone_1.tscn", Vector2(120, 240))
		check(checkpoints.has_active_checkpoint(), "checkpoint active")

	if collectibles:
		var all_defs: Array = collectibles.get_all_definitions()
		if not all_defs.is_empty():
			var item_id: String = all_defs[0].id
			collectibles.try_collect(item_id)
			check(collectibles.has_collected(item_id), "collectible recorded")

	# Save to disk
	var saved: bool = save_mgr.save_game()
	check(saved, "save_game returned true")
	check(save_mgr.has_save(), "save file created on disk")

	# Clear in-memory
	if abilities:
		abilities.clear()
		check(not abilities.is_unlocked(&"double_jump"), "abilities cleared in memory")
	if checkpoints:
		checkpoints.clear()
		check(not checkpoints.has_active_checkpoint(), "checkpoints cleared in memory")
	if collectibles:
		collectibles.clear()
		check(collectibles.get_collected_count() == 0, "collectibles cleared in memory")

	# Load back
	var loaded: bool = save_mgr.load_game()
	check(loaded, "load_game returned true")

	if abilities:
		check(abilities.is_unlocked(&"double_jump"), "double_jump restored from disk")
	if checkpoints:
		check(checkpoints.has_active_checkpoint(), "checkpoint active restored")
		check(checkpoints.get_active_checkpoint_id() == &"test_cp", "checkpoint ID matches")
		check(checkpoints.get_active_scene_path() == "res://scenes/levels/library/zone_1.tscn", "checkpoint scene matches")
	if collectibles:
		var all_defs: Array = collectibles.get_all_definitions()
		if not all_defs.is_empty():
			var item_id: String = all_defs[0].id
			check(collectibles.has_collected(item_id), "collectible restored from disk")

		# Test merging remote collectibles
		if all_defs.size() > 1:
			var second_id: String = all_defs[1].id
			save_mgr.merge_collectibles([second_id])
			check(collectibles.has_collected(second_id), "remote collectible merged")
			check(collectibles.has_collected(all_defs[0].id), "original collectible retained")

	# Clean up after test
	save_mgr.clear_save()
	check(not save_mgr.has_save(), "save file cleaned up")

extends SceneTree

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
	var save_svc := root.get_node_or_null("/root/SaveService")
	var checkpoint_svc := root.get_node_or_null("/root/CheckpointService")
	check(save_mgr != null, "SaveManager available")
	check(save_svc != null, "SaveService available")
	check(checkpoint_svc != null, "CheckpointService available")

	# ========================================================
	# CASE 1: Cloud save with NO active checkpoint
	# ========================================================
	var simulated_cloud_data_no_cp: Dictionary = {
		"version": 1,
		"timestamp": 12345678,
		"scene_path": "res://scenes/levels/library/zone_1.tscn",
		"checkpoint": {
			"version": 1,
			"active_id": "",
			"scene_path": "",
			"spawn_x": 0.0,
			"spawn_y": 0.0,
			"activated_ids": []
		},
		"collectibles": {
			"collected": ["item_test"],
			"version": 1
		},
		"abilities": {
			"abilities": ["double_jump"],
			"version": 1
		}
	}

	save_mgr.clear_save()
	check(not FileAccess.file_exists("user://savegame.json"), "savegame.json cleaned")
	check(not checkpoint_svc.has_active_checkpoint(), "No active checkpoint on clean state")

	save_mgr.apply_save_data(simulated_cloud_data_no_cp, true)
	check(save_mgr.has_save(), "SaveManager has_save is true after cloud sync")
	check(FileAccess.file_exists("user://savegame.json"), "savegame.json written")
	check(FileAccess.file_exists("user://politropia_save.dat"), "politropia_save.dat synchronized by SaveManager")
	check(save_mgr.get_saved_scene_path() == "res://scenes/levels/library/zone_1.tscn", "Fallback scene path matches zone_1 when no checkpoint")

	# ========================================================
	# CASE 2: Cloud save WITH healing room checkpoint (library_desk_a)
	# Even if scene_path was stored as zone_1.tscn in JSON!
	# ========================================================
	var simulated_cloud_data_healing: Dictionary = {
		"version": 1,
		"timestamp": 12345689,
		"scene_path": "res://scenes/levels/library/zone_1.tscn", # Mismatched scene_path
		"checkpoint": {
			"version": 1,
			"active_id": "library_desk_a",
			"scene_path": "res://scenes/levels/library/zone_healing.tscn",
			"spawn_x": 449.0,
			"spawn_y": 739.0,
			"activated_ids": ["library_desk_a"]
		},
		"collectibles": {
			"collected": ["item_test", "item_test_2"],
			"version": 1
		},
		"abilities": {
			"abilities": ["double_jump"],
			"version": 1
		}
	}

	save_mgr.apply_save_data(simulated_cloud_data_healing, true)
	check(checkpoint_svc.has_active_checkpoint(), "CheckpointService has active checkpoint")
	check(String(checkpoint_svc.get_active_checkpoint_id()) == "library_desk_a", "Active checkpoint is library_desk_a")
	check(checkpoint_svc.get_active_scene_path() == "res://scenes/levels/library/zone_healing.tscn", "Active checkpoint scene is zone_healing.tscn")
	check(save_mgr.get_saved_scene_path() == "res://scenes/levels/library/zone_healing.tscn", "SaveManager resolves scene path to zone_healing.tscn")

	# Verify save data produced prioritizes the healing room
	var exported_save: Dictionary = save_mgr.get_save_data()
	check(exported_save["scene_path"] == "res://scenes/levels/library/zone_healing.tscn", "get_save_data stores zone_healing.tscn as scene_path")
	check(exported_save["checkpoint"]["active_id"] == "library_desk_a", "get_save_data stores library_desk_a in checkpoint")

	# ========================================================
	# CASE 3: In-game Checkpoint activation updates SaveManager
	# ========================================================
	checkpoint_svc.activate(&"library_desk_a", "res://scenes/levels/library/zone_healing.tscn", Vector2(449.0, 739.0))
	check(save_mgr.get_saved_scene_path() == "res://scenes/levels/library/zone_healing.tscn", "Activating checkpoint sets saved scene path to zone_healing")

	# ========================================================
	# CASE 4: SaveManager.load_game() keeps SaveService in sync
	# ========================================================
	save_mgr.load_game()
	check(checkpoint_svc.has_active_checkpoint(), "load_game preserves active checkpoint")
	check(save_mgr.get_saved_scene_path() == "res://scenes/levels/library/zone_healing.tscn", "load_game maintains zone_healing as saved scene")

	# ========================================================
	# CASE 5: Empty cloud save progress detection
	# ========================================================
	var firebase_svc := root.get_node_or_null("/root/FirebaseService")
	check(firebase_svc != null, "FirebaseService available")
	var user_firestore_empty: Dictionary = {
		"abilities": {"abilities": [], "version": 1},
		"blind_quest": {"accepted": false, "completed": false, "reward_granted": false, "version": 1},
		"bosses": {"bosses": {}, "version": 1},
		"checkpoint": {"activated_ids": [], "active_id": "", "scene_path": "", "spawn_x": 0.0, "spawn_y": 0.0, "version": 1},
		"collectibles": {"collected": [], "version": 1},
		"fragments": {"levels": {}, "version": 2},
		"map": {"current": "", "version": 1, "visited": []},
		"scene_path": "res://scenes/levels/library/zone_1.tscn",
		"secrets": {"rewards": [], "version": 1, "walls": []},
		"timestamp": 1795389926,
		"version": 1
	}
	check(not firebase_svc.has_save_progress(user_firestore_empty), "has_save_progress returns false for default empty save")
	check(firebase_svc.has_save_progress(simulated_cloud_data_healing), "has_save_progress returns true for healing save")

	# Clean up
	save_mgr.clear_save()

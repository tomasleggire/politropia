extends Node

## Central persistence manager (autoload `SaveManager`).
##
## Coordinates all run and world state across session boundaries:
## - Collectibles
## - Player Abilities
## - Bosses
## - Level Fragments
## - Map Discovery
## - Secrets
## - Blind NPC Quest
## - Active Checkpoint & Scene
##
## Emits signals for UI feedback and integrates with CloudSave (Firebase).

signal save_completed
signal load_completed
signal save_cleared

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const DEFAULT_SCENE := "res://scenes/levels/library/zone_1.tscn"

var _is_saving := false
var _auto_save_enabled := true
var _saved_scene_path := ""
var _last_save_timestamp := 0


func _ready() -> void:
	# Connect to key progression signals to auto-save locally
	_connect_subsystems.call_deferred()
	if has_save():
		load_game()


func _connect_subsystems() -> void:
	if Collectibles != null and not Collectibles.collectible_collected.is_connected(_on_auto_save_trigger):
		Collectibles.collectible_collected.connect(func(_id: String, _c: int, _t: int) -> void: _on_auto_save_trigger())

	if CheckpointService != null and not CheckpointService.checkpoint_activated.is_connected(_on_checkpoint_activated):
		CheckpointService.checkpoint_activated.connect(_on_checkpoint_activated)

	if AbilityProgress != null and not AbilityProgress.ability_recorded.is_connected(_on_ability_recorded):
		AbilityProgress.ability_recorded.connect(_on_ability_recorded)


func _on_auto_save_trigger() -> void:
	if _auto_save_enabled:
		save_game()


func _on_checkpoint_activated(_checkpoint_id: StringName, scene_path: String, _spawn_position: Vector2) -> void:
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		_saved_scene_path = scene_path
	if _auto_save_enabled:
		save_game()


func _on_ability_recorded(_ability: StringName) -> void:
	if _auto_save_enabled:
		save_game()


func get_saved_scene_path() -> String:
	if CheckpointService != null and CheckpointService.has_active_checkpoint():
		var cp_scene := CheckpointService.get_active_scene_path()
		if not cp_scene.is_empty() and ResourceLoader.exists(cp_scene):
			return cp_scene
	if not _saved_scene_path.is_empty() and ResourceLoader.exists(_saved_scene_path):
		return _saved_scene_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var cur := tree.current_scene.scene_file_path
		if not cur.is_empty() and not cur.contains("main_menu") and not cur.contains("new_game_intro") and ResourceLoader.exists(cur):
			return cur
	return DEFAULT_SCENE


func set_saved_scene_path(path: String) -> void:
	if not path.is_empty() and ResourceLoader.exists(path):
		_saved_scene_path = path


## Checks if a valid local save file exists.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or (SaveService != null and SaveService.has_save())


## Reads raw save data from disk without modifying in-memory state.
func get_disk_save_data() -> Dictionary:
	var local_data := _read_save_file()
	if not local_data.is_empty():
		return local_data

	if SaveService != null and SaveService.has_save():
		var payload := SaveService._read_payload()
		if not payload.is_empty():
			var cp: Variant = payload.get("checkpoint", {})
			var prog: Variant = payload.get("progress", {})
			var prog_dict: Dictionary = prog if prog is Dictionary else {}
			return {
				"version": SAVE_VERSION,
				"timestamp": 0,
				"scene_path": payload.get("scene_path", ""),
				"checkpoint": cp if cp is Dictionary else {},
				"collectibles": prog_dict.get("collectibles", {}),
				"abilities": prog_dict.get("abilities", {}),
				"bosses": prog_dict.get("bosses", {}),
				"fragments": prog_dict.get("fragments", {}),
				"map": prog_dict.get("map", {}),
				"secrets": prog_dict.get("secrets", {}),
				"blind_quest": prog_dict.get("blind_quest", {}),
			}
	return {}


## Builds a unified, JSON-friendly dictionary of all game progress.
func get_save_data() -> Dictionary:
	var ts := _last_save_timestamp if _last_save_timestamp > 0 else int(Time.get_unix_time_from_system())
	return {
		"version": SAVE_VERSION,
		"timestamp": ts,
		"scene_path": get_saved_scene_path(),
		"collectibles": Collectibles.to_dict() if Collectibles else {},
		"abilities": AbilityProgress.to_dict() if AbilityProgress else {},
		"bosses": BossProgress.to_dict() if BossProgress else {},
		"fragments": FragmentProgress.to_dict() if FragmentProgress else {},
		"map": MapProgress.to_dict() if MapProgress else {},
		"secrets": SecretProgress.to_dict() if SecretProgress else {},
		"blind_quest": BlindQuestProgress.to_dict() if BlindQuestProgress else {},
		"checkpoint": CheckpointService.to_dict() if CheckpointService else {},
	}


## Writes progress to local disk safely and uploads to Firebase if authenticated.
func save_game() -> bool:
	if _is_saving:
		return false
	_is_saving = true

	_last_save_timestamp = int(Time.get_unix_time_from_system())
	var data := get_save_data()
	var json_string := JSON.stringify(data, "\t")

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open %s for writing: %s" % [SAVE_PATH, FileAccess.get_open_error()])
		_is_saving = false
		return false

	file.store_string(json_string)
	file.close()
	_is_saving = false

	# Keep SaveService in sync with current checkpoint and scene state
	_sync_save_service()

	save_completed.emit()

	# Synchronize with cloud in background if user is authenticated
	if FirebaseService != null and FirebaseService.is_logged_in:
		FirebaseService.save_to_cloud(data)

	return true


## Loads game progress from local disk.
func load_game() -> bool:
	if not has_save():
		return false

	var data := _read_save_file()
	if data.is_empty() and SaveService != null and SaveService.has_save():
		data = get_disk_save_data()

	if data.is_empty():
		return false

	apply_save_data(data, false)
	load_completed.emit()
	return true


## Restores all subsystems from dictionary data.
## When `persist_locally` is true, writes the applied data to disk.
func apply_save_data(data: Dictionary, persist_locally := true) -> void:
	_auto_save_enabled = false

	if Collectibles and data.has("collectibles") and data["collectibles"] is Dictionary:
		var c_dict: Dictionary = data["collectibles"]
		if c_dict.has("collected") and c_dict["collected"] is Array:
			Collectibles.merge_collected_ids(c_dict["collected"])
		else:
			Collectibles.from_dict(c_dict)

	if AbilityProgress and data.has("abilities") and data["abilities"] is Dictionary:
		AbilityProgress.from_dict(data["abilities"])

	if BossProgress and data.has("bosses") and data["bosses"] is Dictionary:
		BossProgress.from_dict(data["bosses"])

	if FragmentProgress and data.has("fragments") and data["fragments"] is Dictionary:
		FragmentProgress.from_dict(data["fragments"])

	if MapProgress and data.has("map") and data["map"] is Dictionary:
		MapProgress.from_dict(data["map"])

	if SecretProgress and data.has("secrets") and data["secrets"] is Dictionary:
		SecretProgress.from_dict(data["secrets"])

	if BlindQuestProgress and data.has("blind_quest") and data["blind_quest"] is Dictionary:
		BlindQuestProgress.from_dict(data["blind_quest"])

	if CheckpointService and data.has("checkpoint") and data["checkpoint"] is Dictionary:
		CheckpointService.from_dict(data["checkpoint"])

	_saved_scene_path = _extract_scene_path(data)
	_auto_save_enabled = true
	_last_save_timestamp = int(data.get("timestamp", 0))

	# Keep SaveService in sync with current state even when not persisting to JSON immediately
	_sync_save_service()

	if persist_locally:
		save_game()


## Merges remote collectibles into the local state and saves.
## Guarantees that collectibles found in any session are never lost.
func merge_collectibles(remote_ids: Array) -> void:
	if Collectibles:
		Collectibles.merge_collected_ids(remote_ids)
		save_game()


## Clears local file and resets all subsystems for New Game.
func clear_save() -> void:
	_saved_scene_path = ""
	_last_save_timestamp = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	if SaveService != null:
		SaveService.delete_save()

	if Collectibles:
		Collectibles.clear()
	if AbilityProgress:
		AbilityProgress.clear()
	if BossProgress:
		BossProgress.clear()
	if FragmentProgress:
		FragmentProgress.clear()
	if MapProgress:
		MapProgress.clear()
	if SecretProgress:
		SecretProgress.clear()
	if BlindQuestProgress:
		BlindQuestProgress.clear()
	if CheckpointService:
		CheckpointService.clear()

	save_cleared.emit()


# ---------------------------------------------------------
# PRIVATE HELPERS
# ---------------------------------------------------------

func _sync_save_service() -> void:
	if SaveService != null:
		SaveService.sync_from_state(get_saved_scene_path())


func _extract_scene_path(data: Dictionary) -> String:
	if CheckpointService != null and CheckpointService.has_active_checkpoint():
		var active_scene := CheckpointService.get_active_scene_path()
		if not active_scene.is_empty() and ResourceLoader.exists(active_scene):
			return active_scene

	var cp: Variant = data.get("checkpoint", {})
	if cp is Dictionary:
		var cp_scene: String = str(cp.get("scene_path", cp.get("active_scene_path", "")))
		if not cp_scene.is_empty() and ResourceLoader.exists(cp_scene):
			return cp_scene

	var scene: String = str(data.get("scene_path", ""))
	if not scene.is_empty() and ResourceLoader.exists(scene):
		return scene

	return DEFAULT_SCENE


func _read_save_file() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: could not open %s for reading: %s" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(content) != OK or not json.data is Dictionary:
		push_error("SaveManager: invalid or corrupt save file.")
		return {}

	return json.data as Dictionary

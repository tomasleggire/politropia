extends Node

## In-memory fragment state, separated by playable level (for example,
## `library` and `greece`). Carried fragments are temporary; deposited ones are
## secured for the current run until a new game starts. This is memory-only;
## progress is not written to disk.

signal progress_changed(level_key: String)
signal fragment_state_changed(level_key: String, id: int, state: int)
signal fragment_collected(id: int, count: int, total: int)

const TOTAL := 4

enum FragmentState { AVAILABLE, CARRIED, DEPOSITED }

var _levels: Dictionary = {}


func current_level_key() -> String:
	var current := get_tree().current_scene
	return level_key_for_scene(current.scene_file_path if current != null else "")


func level_key_for_scene(scene_path: String) -> String:
	var parts := scene_path.split("/")
	var level_index := parts.find("levels")
	if level_index >= 0 and level_index + 1 < parts.size():
		return parts[level_index + 1]
	return "default" if scene_path.is_empty() else scene_path


func fragment_state(id: int, level_key := "") -> int:
	if not _valid_id(id):
		return FragmentState.AVAILABLE
	var data := _level_data(_resolve_level_key(level_key))
	if data["deposited"].has(id):
		return FragmentState.DEPOSITED
	if data["carried"].has(id):
		return FragmentState.CARRIED
	return FragmentState.AVAILABLE


func collect(id: int, level_key := "") -> bool:
	if not _valid_id(id):
		return false
	var key := _resolve_level_key(level_key)
	if fragment_state(id, key) != FragmentState.AVAILABLE:
		return false
	var data := _level_data(key)
	data["carried"][id] = true
	_emit_state_changed(key, id)
	fragment_collected.emit(id, data["carried"].size(), TOTAL)
	return true


func deposit(id: int, level_key := "") -> bool:
	if not _valid_id(id):
		return false
	var key := _resolve_level_key(level_key)
	var data := _level_data(key)
	if not data["carried"].has(id) or data["deposited"].has(id):
		return false
	data["carried"].erase(id)
	data["deposited"][id] = true
	_emit_state_changed(key, id)
	return true


func has_fragment(id: int, level_key := "") -> bool:
	return fragment_state(id, level_key) != FragmentState.AVAILABLE


func is_carried(id: int, level_key := "") -> bool:
	return fragment_state(id, level_key) == FragmentState.CARRIED


func is_deposited(id: int, level_key := "") -> bool:
	return fragment_state(id, level_key) == FragmentState.DEPOSITED


func carried_ids(level_key := "") -> Array[int]:
	return _ids(_level_data(_resolve_level_key(level_key))["carried"])


func deposited_ids(level_key := "") -> Array[int]:
	return _ids(_level_data(_resolve_level_key(level_key))["deposited"])


## On death, only the unsecured fragments are dropped. The placed fragments and
## the reconstruction guard are left untouched.
func lose_carried(level_key := "") -> void:
	var key := _resolve_level_key(level_key)
	var data := _level_data(key)
	if data["carried"].is_empty():
		return
	var lost_ids := _ids(data["carried"])
	data["carried"].clear()
	progress_changed.emit(key)
	for id: int in lost_ids:
		fragment_state_changed.emit(key, id, FragmentState.AVAILABLE)


func count(level_key := "") -> int:
	var data := _level_data(_resolve_level_key(level_key))
	return data["carried"].size() + data["deposited"].size()


func total() -> int:
	return TOTAL


func is_complete(level_key := "") -> bool:
	return count(level_key) == TOTAL


func is_fully_deposited(level_key := "") -> bool:
	return deposited_ids(level_key).size() == TOTAL


## Claims the one-time reconstruction sequence only after every distinct piece
## has been deposited. This survives room changes and death in this run.
func begin_reconstruction(level_key := "") -> bool:
	var key := _resolve_level_key(level_key)
	var data := _level_data(key)
	if data["deposited"].size() != TOTAL or data["reconstruction_started"]:
		return false
	data["reconstruction_started"] = true
	progress_changed.emit(key)
	return true


func reconstruction_started(level_key := "") -> bool:
	return bool(_level_data(_resolve_level_key(level_key))["reconstruction_started"])


func _emit_state_changed(level_key: String, id: int) -> void:
	progress_changed.emit(level_key)
	fragment_state_changed.emit(level_key, id, fragment_state(id, level_key))


## New Game clears in-memory fragment progress for every level.
func clear() -> void:
	var previous := _levels.duplicate(true)
	_levels.clear()
	for key: Variant in previous:
		var data: Dictionary = previous[key]
		progress_changed.emit(String(key))
		for id: int in data["carried"].keys():
			fragment_state_changed.emit(String(key), id, FragmentState.AVAILABLE)
		for id: int in data["deposited"].keys():
			fragment_state_changed.emit(String(key), id, FragmentState.AVAILABLE)


func to_dict() -> Dictionary:
	return {"version": 2, "levels": _levels.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	_levels.clear()
	var saved_levels: Variant = data.get("levels")
	if saved_levels is Dictionary:
		for key: Variant in saved_levels:
			var saved: Variant = saved_levels[key]
			if saved is Dictionary:
				var state := _empty_level_state()
				_copy_valid_ids(saved.get("carried", []), state["carried"])
				_copy_valid_ids(saved.get("deposited", []), state["deposited"])
				for id: int in state["deposited"].keys():
					state["carried"].erase(id)
				state["reconstruction_started"] = bool(saved.get("reconstruction_started", false))
				_levels[String(key)] = state
		return

	# Accept the older run-scoped format as carried progress in this level.
	var old_ids: Variant = data.get("fragments")
	if old_ids is Array:
		var state := _level_data(current_level_key())
		_copy_valid_ids(old_ids, state["carried"])


func _resolve_level_key(level_key: String) -> String:
	return current_level_key() if level_key.is_empty() else level_key


func _level_data(level_key: String) -> Dictionary:
	if not _levels.has(level_key):
		_levels[level_key] = _empty_level_state()
	return _levels[level_key]


func _empty_level_state() -> Dictionary:
	return {"carried": {}, "deposited": {}, "reconstruction_started": false}


func _valid_id(id: int) -> bool:
	return id >= 1 and id <= TOTAL


func _ids(source: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for id: Variant in source.keys():
		result.append(int(id))
	result.sort()
	return result


func _copy_valid_ids(source: Variant, destination: Dictionary) -> void:
	if not source is Array:
		return
	for id: Variant in source:
		if id is int and _valid_id(id):
			destination[id] = true

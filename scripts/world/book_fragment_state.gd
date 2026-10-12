extends Node

## Runtime-only book fragment progress, isolated by the current level folder.
signal state_changed(level_id: String)

const FRAGMENT_IDS := ["fragmento_1", "fragmento_2", "fragmento_3", "fragmento_4"]

var _levels: Dictionary = {}


func current_level_id() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	var path := scene.scene_file_path
	var marker := "/levels/"
	var start := path.find(marker)
	if start < 0:
		return path
	var remainder := path.substr(start + marker.length())
	var category := remainder.get_slice("/", 0)
	return path.substr(0, start + marker.length()) + category


func _level(level_id: String) -> Dictionary:
	if not _levels.has(level_id):
		_levels[level_id] = {"carried": {}, "deposited": {}, "pickups": {}}
	return _levels[level_id]


func get_carried(level_id: String) -> Array[String]:
	return _ids(_level(level_id)["carried"])


func get_deposited(level_id: String) -> Array[String]:
	return _ids(_level(level_id)["deposited"])


func has_reconstruction_started(level_id: String) -> bool:
	return bool(_level(level_id).get("reconstruction_started", false))


func try_start_reconstruction(level_id: String) -> bool:
	var data := _level(level_id)
	if data["deposited"].size() != FRAGMENT_IDS.size() or data.get("reconstruction_started", false):
		return false
	data["reconstruction_started"] = true
	return true


func has_fragment(level_id: String, fragment_id: String) -> bool:
	var data := _level(level_id)
	return data["carried"].has(fragment_id) or data["deposited"].has(fragment_id)


func register_pickup(level_id: String, fragment_id: String, pickup: Node) -> void:
	var data := _level(level_id)
	data["pickups"][fragment_id] = weakref(pickup)
	if has_fragment(level_id, fragment_id):
		pickup.call("set_collected", true)
	else:
		pickup.call("set_collected", false)


func collect(level_id: String, fragment_id: String, pickup: Node) -> bool:
	if not FRAGMENT_IDS.has(fragment_id) or has_fragment(level_id, fragment_id):
		return false
	var data := _level(level_id)
	data["carried"][fragment_id] = true
	data["pickups"][fragment_id] = weakref(pickup)
	pickup.call("set_collected", true)
	state_changed.emit(level_id)
	return true


func deposit_carried(level_id: String) -> Array[String]:
	var data := _level(level_id)
	var moved: Array[String] = []
	for fragment_id in FRAGMENT_IDS:
		if data["carried"].has(fragment_id) and not data["deposited"].has(fragment_id):
			data["deposited"][fragment_id] = true
			moved.append(fragment_id)
	data["carried"].clear()
	if not moved.is_empty():
		state_changed.emit(level_id)
	return moved


func lose_carried(level_id: String) -> void:
	if level_id.is_empty() or not _levels.has(level_id):
		return
	var data: Dictionary = _levels[level_id]
	if data["carried"].is_empty():
		return
	var lost: Array[String] = _ids(data["carried"])
	data["carried"].clear()
	for fragment_id in lost:
		var pickup_ref: WeakRef = data["pickups"].get(fragment_id)
		var pickup: Object = pickup_ref.get_ref() if pickup_ref != null else null
		if is_instance_valid(pickup):
			pickup.call("set_collected", false)
	state_changed.emit(level_id)


func _ids(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for fragment_id in FRAGMENT_IDS:
		if source.has(fragment_id):
			result.append(fragment_id)
	return result

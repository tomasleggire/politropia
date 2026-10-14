extends Node

## Zones Luz has visited during this run (autoload `MapProgress`).
##
## USAGE: nothing to place. It notices on its own every time a new scene with Luz
## in it is loaded and records it, so the map only shows rooms she has been in.
## `MapScreen` reads `has_visited()` and `current_scene_path()`.
##
## Why an autoload: like FragmentProgress it has to outlive the zone scenes.
## `main_menu.gd` calls `clear()` on New Game.
##
## SAVE SYSTEM NOTE: no disk save yet. Use `to_dict()` / `from_dict()` when one
## exists.

signal room_visited(scene_path: String)

var _visited: Dictionary = {}
var _current := ""
var _last_seen := ""


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == _last_seen:
		return
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	_last_seen = scene.scene_file_path
	visit(_last_seen)


## Marks `scene_path` as visited and as the room Luz is in now.
func visit(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	_current = scene_path
	if _visited.has(scene_path):
		return
	_visited[scene_path] = true
	room_visited.emit(scene_path)


func has_visited(scene_path: String) -> bool:
	return _visited.has(scene_path)


## Scene Luz is in now ("" before the first zone).
func current_scene_path() -> String:
	return _current


func visited_count() -> int:
	return _visited.size()


## Forgets everything (tests, new game).
func clear() -> void:
	_visited.clear()
	_current = ""
	_last_seen = ""


func to_dict() -> Dictionary:
	var paths: Array = _visited.keys()
	paths.sort()
	return {"version": 1, "visited": paths, "current": _current}


## Replaces everything with `data`; invalid data leaves a clean slate.
func from_dict(data: Dictionary) -> void:
	clear()
	var paths: Variant = data.get("visited")
	if paths is Array:
		for path: Variant in paths:
			if path is String and not (path as String).is_empty():
				_visited[path] = true
	var current: Variant = data.get("current")
	if current is String:
		_current = current

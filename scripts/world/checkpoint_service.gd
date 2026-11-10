extends Node

## Global owner of the active checkpoint. Holds identity and spawn data only;
## presentation and interaction belong to the placed checkpoint component.
## Registered as the `CheckpointService` autoload so state survives scene changes.

## Emitted after a checkpoint becomes the active one.
signal checkpoint_activated(checkpoint_id: StringName, scene_path: String, spawn_position: Vector2)

## Enemies opt in to checkpoint regeneration by joining this group and
## implementing `reset_to_checkpoint_state()` (no arguments, no return value).
const RESETTABLE_GROUP := &"checkpoint_resettable"
const RESET_METHOD := &"reset_to_checkpoint_state"

var _active_id := &""
var _active_scene_path := ""
var _active_spawn_position := Vector2.ZERO
var _activated_ids := {}
var _pending_restore := false
var _pending_scene_path := ""


func activate(checkpoint_id: StringName, scene_path: String, spawn_position: Vector2) -> void:
	_active_id = checkpoint_id
	_active_scene_path = scene_path
	_active_spawn_position = spawn_position
	_activated_ids[checkpoint_id] = true
	checkpoint_activated.emit(checkpoint_id, scene_path, spawn_position)


## True once `checkpoint_id` was activated during this run, even if another
## checkpoint is active now. Lets a checkpoint tell a first ceremony from a repeat.
func was_ever_activated(checkpoint_id: StringName) -> bool:
	return _activated_ids.has(checkpoint_id)


func has_active_checkpoint() -> bool:
	return _active_id != &""


func get_active_checkpoint_id() -> StringName:
	return _active_id


func get_active_scene_path() -> String:
	return _active_scene_path


func is_active(checkpoint_id: StringName, scene_path: String) -> bool:
	return has_active_checkpoint() and _active_id == checkpoint_id and _active_scene_path == scene_path


func has_checkpoint_for_scene(scene_path: String) -> bool:
	return has_active_checkpoint() and _active_scene_path == scene_path


## Returns the active spawn position for `scene_path`, or `fallback` when the
## active checkpoint belongs to another scene (or none is active).
func get_spawn_position_for_scene(scene_path: String, fallback := Vector2.ZERO) -> Vector2:
	if has_checkpoint_for_scene(scene_path):
		return _active_spawn_position
	return fallback


## Points the player's respawn at the active checkpoint of `scene_path`.
## Returns false, leaving the player untouched, when there is none.
func apply_to_player(player: Player, scene_path: String) -> bool:
	if player == null or not has_checkpoint_for_scene(scene_path):
		return false
	player.apply_checkpoint(_active_spawn_position)
	return true


## One-line level start: when a checkpoint is active for `scene_path`, points
## the player's respawn at it and places the player there. Returns false,
## leaving the player at its scene start position, when there is none.
func restore_player_for_scene(player: Player, scene_path: String) -> bool:
	if _pending_restore:
		return restore_pending_player_for_scene(player, scene_path)
	if not apply_to_player(player, scene_path):
		return false
	player.respawn()
	return true


func queue_pending_restore() -> void:
	if has_active_checkpoint():
		_pending_restore = true
		_pending_scene_path = _active_scene_path


func clear_pending_restore() -> void:
	_pending_restore = false
	_pending_scene_path = ""


func restore_pending_player(player: Player) -> bool:
	var scene := get_tree().current_scene
	return false if scene == null else restore_pending_player_for_scene(player, scene.scene_file_path)


func restore_pending_player_for_scene(player: Player, scene_path: String) -> bool:
	if not _pending_restore or player == null or scene_path != _pending_scene_path:
		return false
	_pending_restore = false
	_pending_scene_path = ""
	player.apply_checkpoint(_active_spawn_position)
	player.respawn()
	player.grant_respawn_invulnerability()
	reset_resettable_enemies()
	return true


## Changes rooms on death when the latest checkpoint is in another scene.
func return_to_active_checkpoint_scene() -> bool:
	if not has_active_checkpoint() or _active_scene_path.is_empty():
		return false
	if not ResourceLoader.exists(_active_scene_path):
		push_error("CheckpointService: checkpoint scene does not exist: %s" % _active_scene_path)
		return false
	reset_resettable_enemies()
	queue_pending_restore()
	var error := get_tree().change_scene_to_file(_active_scene_path)
	if error != OK:
		clear_pending_restore()
		push_error("CheckpointService: could not return to checkpoint scene (%d)." % error)
		return false
	return true


## Asks every resettable enemy to return to its checkpoint state. Safe when
## the group is empty.
func reset_resettable_enemies() -> void:
	get_tree().call_group(RESETTABLE_GROUP, RESET_METHOD)


func to_dict() -> Dictionary:
	var activated: Array[String] = []
	for checkpoint_id: Variant in _activated_ids:
		activated.append(String(checkpoint_id))
	activated.sort()
	return {
		"version": 1,
		"active_id": String(_active_id),
		"scene_path": _active_scene_path,
		"spawn_x": _active_spawn_position.x,
		"spawn_y": _active_spawn_position.y,
		"activated_ids": activated,
	}


func from_dict(data: Dictionary) -> void:
	clear()
	if int(data.get("version", 0)) != 1:
		return
	var activated: Variant = data.get("activated_ids", [])
	if activated is Array:
		for checkpoint_id: Variant in activated:
			if checkpoint_id is String and not (checkpoint_id as String).is_empty():
				_activated_ids[StringName(checkpoint_id)] = true
	var active_id: Variant = data.get("active_id", "")
	var scene_path: Variant = data.get("scene_path", "")
	var spawn_x: Variant = data.get("spawn_x", 0.0)
	var spawn_y: Variant = data.get("spawn_y", 0.0)
	if active_id is String and not active_id.is_empty() and scene_path is String and not scene_path.is_empty() and _is_number(spawn_x) and _is_number(spawn_y):
		_active_id = StringName(active_id)
		_active_scene_path = scene_path
		_active_spawn_position = Vector2(float(spawn_x), float(spawn_y))
		_activated_ids[_active_id] = true


func clear() -> void:
	_active_id = &""
	_active_scene_path = ""
	_active_spawn_position = Vector2.ZERO
	_activated_ids.clear()
	_pending_restore = false
	_pending_scene_path = ""


func _is_number(value: Variant) -> bool:
	return value is int or value is float

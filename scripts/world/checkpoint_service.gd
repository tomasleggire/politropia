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
	if not apply_to_player(player, scene_path):
		return false
	player.respawn()
	return true


## Asks every resettable enemy to return to its checkpoint state. Safe when
## the group is empty.
func reset_resettable_enemies() -> void:
	get_tree().call_group(RESETTABLE_GROUP, RESET_METHOD)


func clear() -> void:
	_active_id = &""
	_active_scene_path = ""
	_active_spawn_position = Vector2.ZERO
	_activated_ids.clear()

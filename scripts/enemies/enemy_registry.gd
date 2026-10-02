extends Node

## Room persistence for enemies (autoload `EnemyRegistry`).
##
## Why an autoload and not a level-owned node: like CheckpointService, the
## killed set must outlive the level scene (a scene reload keeps corpses where
## they died until a rest or a death), and enemies find it without any level
## wiring. Only the room mapping is level specific, and it is injected through
## `room_resolver` (Greece by default).
##
## Rules, as decided by the user:
## 1. A killed enemy stays dead, its corpse visible where it died, until Luz
##    rests at a Stillness Desk or dies.
## 2. Leaving a room and re-entering it resets that room's LIVING enemies to
##    their spawn at full health (`enter_room`, driven by the level's
##    `room_changed`).
## 3. A desk rest or Luz's death resets everything: this node joins the
##    `checkpoint_resettable` group, as every enemy does, and
##    CheckpointService.reset_resettable_enemies() (called by the desk and by
##    the player's respawn, after she has been moved) reaches all of them.
##
## Performance: enemies outside the current room are paused (no AI, no
## gravity). An empty active room means the level does no room tracking and
## nothing is paused.

const BODY_CENTER_OFFSET := Vector2(0.0, -29.0)

## Maps a world point (an enemy's spawn) to its room name. Replace it for a
## level that is not Greece; an invalid callable falls back to Greece.
var room_resolver := Callable()

var _enemies: Dictionary = {}
var _kills: Dictionary = {}
var _active_room: StringName = &""


func _ready() -> void:
	add_to_group(&"checkpoint_resettable")


## Rule 3 for enemies that are not in the scene right now.
func reset_to_checkpoint_state() -> void:
	_kills.clear()


func register(enemy: Enemy) -> void:
	var key := enemy.get_enemy_key()
	if _enemies.has(key) and _enemies[key] != enemy:
		push_warning("Duplicate enemy_id '%s': persistence will mix them up." % key)
	_enemies[key] = enemy
	enemy.home_room = room_of(enemy.get_spawn_position())
	enemy.set_ai_active(_is_room_active(enemy.home_room))
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if _kills.has(key):
		var record: Dictionary = _kills[key]
		enemy.make_corpse_at(record["position"], record["facing"])


func unregister(enemy: Enemy) -> void:
	var key := enemy.get_enemy_key()
	if _enemies.get(key) == enemy:
		_enemies.erase(key)


func has_kill(key: StringName) -> bool:
	return _kills.has(key)


func get_kill(key: StringName) -> Dictionary:
	return _kills.get(key, {})


func forget(key: StringName) -> void:
	_kills.erase(key)


func get_active_room() -> StringName:
	return _active_room


## Pauses every enemy outside `room` without resetting anyone. Used when a
## level starts or ends; "" lifts the pause.
func set_active_room(room: StringName) -> void:
	_active_room = room
	for enemy: Enemy in _enemies.values():
		enemy.set_ai_active(_is_room_active(enemy.home_room))


## Rule 2: Luz entered `room`. Its living enemies return to their spawn at
## full health; corpses stay. Every other room is paused.
func enter_room(room: StringName) -> void:
	set_active_room(room)
	for enemy: Enemy in _enemies.values():
		if enemy.home_room == room and not enemy.is_dead():
			enemy.reset_to_spawn()


func room_of(point: Vector2) -> StringName:
	if room_resolver.is_valid():
		return room_resolver.call(point)
	return StringName(GreeceLayout.camera_room(GreeceLayout.room_for(point + BODY_CENTER_OFFSET, "")))


## Forgets everything (tests, new game).
func clear() -> void:
	_kills.clear()
	_active_room = &""
	room_resolver = Callable()


func _is_room_active(room: StringName) -> bool:
	return _active_room.is_empty() or room == _active_room


func _on_enemy_died(enemy: Enemy) -> void:
	_kills[enemy.get_enemy_key()] = {
		"position": enemy.global_position,
		"facing": enemy.get_facing(),
	}

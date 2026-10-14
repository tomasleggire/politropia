extends Node

## Secrets Luz has opened during this run (autoload `SecretProgress`).
##
## USAGE: nothing to place. A `BreakableWall` records its `wall_id` here when it
## crumbles and a `SoulCache` records its `reward_id` when it is opened, so a
## broken wall stays open and a reward is never given twice when Luz leaves a
## room and comes back.
##
## Why an autoload: like FragmentProgress it has to outlive the zone scenes.
## `main_menu.gd` calls `clear()` on New Game.
##
## SAVE SYSTEM NOTE: no disk save yet. Use `to_dict()` / `from_dict()` when one
## exists.

signal wall_broken(wall_id: StringName)
signal reward_claimed(reward_id: StringName)

var _walls: Dictionary = {}
var _rewards: Dictionary = {}


## Marks a wall as broken. Returns false when it already was (or the id is empty).
func break_wall(wall_id: StringName) -> bool:
	if wall_id.is_empty() or _walls.has(wall_id):
		return false
	_walls[wall_id] = true
	wall_broken.emit(wall_id)
	return true


func is_wall_broken(wall_id: StringName) -> bool:
	return _walls.has(wall_id)


## Marks a reward as given. Returns false when it already was (or the id is empty).
func claim_reward(reward_id: StringName) -> bool:
	if reward_id.is_empty() or _rewards.has(reward_id):
		return false
	_rewards[reward_id] = true
	reward_claimed.emit(reward_id)
	return true


func is_reward_claimed(reward_id: StringName) -> bool:
	return _rewards.has(reward_id)


## Secrets found so far: broken walls plus opened rewards.
func count() -> int:
	return _walls.size() + _rewards.size()


## Forgets everything (tests, new game).
func clear() -> void:
	_walls.clear()
	_rewards.clear()


func to_dict() -> Dictionary:
	var walls: Array = _walls.keys()
	var rewards: Array = _rewards.keys()
	walls.sort()
	rewards.sort()
	return {"version": 1, "walls": walls, "rewards": rewards}


## Replaces everything with `data`; invalid data leaves a clean slate.
func from_dict(data: Dictionary) -> void:
	clear()
	for key: String in ["walls", "rewards"]:
		var ids: Variant = data.get(key)
		if not ids is Array:
			continue
		for id: Variant in ids:
			if id is String or id is StringName:
				(_walls if key == "walls" else _rewards)[StringName(id)] = true

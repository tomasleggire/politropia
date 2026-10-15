extends Node

## Abilities Luz has earned during this run (autoload `AbilityProgress`).
##
## USAGE: nothing to place. `DoubleJumpReward` records the double jump here when
## Luz picks it up, and every new `Player` restores it in `_ready`, so the ability
## survives the change of zone (each zone scene holds its own Player node).
##
## Why an autoload: like BossProgress it has to outlive the zone scenes.
## `main_menu.gd` calls `clear()` on New Game.
##
## SAVE SYSTEM NOTE: no disk save yet. Store `to_dict()` in the same save as
## `BossProgress.to_dict()` and restore both together with `from_dict()`.

signal ability_recorded(ability: StringName)

const SAVE_VERSION := 1

var _abilities: Dictionary = {}


## Remembers an ability. Returns false when it already was (or the id is empty).
func record(ability: StringName) -> bool:
	if ability.is_empty() or _abilities.has(ability):
		return false
	_abilities[ability] = true
	ability_recorded.emit(ability)
	return true


func is_unlocked(ability: StringName) -> bool:
	return _abilities.has(ability)


## Forgets everything (tests, new game).
func clear() -> void:
	_abilities.clear()


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "abilities": _abilities.keys().map(func(a: Variant) -> String: return String(a))}


## Restores `to_dict()`; anything unexpected leaves a clean slate.
func from_dict(data: Dictionary) -> void:
	clear()
	if int(data.get("version", 0)) != SAVE_VERSION or not data.get("abilities") is Array:
		return
	for ability: Variant in data["abilities"]:
		if ability is String and not (ability as String).is_empty():
			_abilities[StringName(ability)] = true

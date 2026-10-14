extends Node

## Book fragments collected during this run (autoload `FragmentProgress`).
##
## USAGE: a `FloatingBookFragment` calls `collect(fragment_id)` when Luz touches
## it. Anything that wants to react (HUD counter, pickup toast, pedestal)
## listens to `fragment_collected(id, count, total)` or reads `count()`.
##
## Why an autoload: like CheckpointService and BossProgress it has to outlive
## the zone scenes, so a fragment stays collected when Luz leaves a room and
## comes back. `main_menu.gd` calls `clear()` on New Game.
##
## SAVE SYSTEM NOTE: no disk save yet. Use `to_dict()` / `from_dict()` when one
## exists.

signal fragment_collected(id: int, count: int, total: int)

## How many fragments the book has. Ids run from 1 to `TOTAL`.
const TOTAL := 4

var _collected: Dictionary = {}


## Marks `id` as collected. Returns false (and emits nothing) when the id is
## out of range or was already collected, so a fragment never counts twice.
func collect(id: int) -> bool:
	if id < 1 or id > TOTAL or _collected.has(id):
		return false
	_collected[id] = true
	fragment_collected.emit(id, count(), TOTAL)
	return true


func has_fragment(id: int) -> bool:
	return _collected.has(id)


func count() -> int:
	return _collected.size()


func total() -> int:
	return TOTAL


func is_complete() -> bool:
	return count() >= TOTAL


## Forgets every fragment (tests, new game).
func clear() -> void:
	_collected.clear()


func to_dict() -> Dictionary:
	var ids: Array = _collected.keys()
	ids.sort()
	return {"version": 1, "fragments": ids}


## Replaces everything with `data`; invalid data leaves a clean slate.
func from_dict(data: Dictionary) -> void:
	_collected.clear()
	var ids: Variant = data.get("fragments")
	if not ids is Array:
		return
	for id: Variant in ids:
		if id is int and id >= 1 and id <= TOTAL:
			_collected[id] = true

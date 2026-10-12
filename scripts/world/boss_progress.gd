extends Node

## Bosses beaten during this run (autoload `BossProgress`).
##
## Why its own autoload: EnemyRegistry forgets every kill on a desk rest or a
## death (that is its rule for ordinary enemies), and a boss must not return
## from either. Like the registry and CheckpointService it has to outlive the
## level scene, so a re-entered or reloaded arena still knows its boss is gone.
## It holds identity only; BossArena owns what to do with it.

var _defeated: Dictionary = {}


func mark_defeated(boss_id: StringName) -> void:
	_defeated[boss_id] = true


func is_defeated(boss_id: StringName) -> bool:
	return _defeated.has(boss_id)


## Forgets every boss (tests, new game).
func clear() -> void:
	_defeated.clear()

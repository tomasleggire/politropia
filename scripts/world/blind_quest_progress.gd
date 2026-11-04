extends Node

## Session-scoped progress for the BlindNPC quest (autoload `BlindQuestProgress`).
##
## The NPC lives inside a zone scene, so its own flags would reset every time Luz
## leaves the room and comes back. This small service keeps the mission state and
## the pending reward alive across zone loads. It is memory-only, on purpose.
##
## `main_menu.gd` calls `clear()` on New Game, like the other run-scoped services.

signal changed

var _accepted := false
var _completed := false
var _reward_granted := false


## Marks the first dialogue as finished. Returns false when it already was.
func accept() -> bool:
	if _accepted:
		return false
	_accepted = true
	changed.emit()
	return true


func is_accepted() -> bool:
	return _accepted


## Marks the final dialogue as finished. Returns false without an accepted quest
## or when it was already completed.
func complete() -> bool:
	if not _accepted or _completed:
		return false
	_completed = true
	changed.emit()
	return true


func is_completed() -> bool:
	return _completed


## Marks the physical reward as handed over. Returns false when the quest is not
## complete or the reward was already handed over.
func grant_reward() -> bool:
	if not _completed or _reward_granted:
		return false
	_reward_granted = true
	changed.emit()
	return true


func is_reward_granted() -> bool:
	return _reward_granted


## Forgets everything (tests, new game).
func clear() -> void:
	if not _accepted and not _completed and not _reward_granted:
		return
	_accepted = false
	_completed = false
	_reward_granted = false
	changed.emit()

class_name DemoEndToast
extends Node

## Closing message of the demo: once Artemis is beaten and Luz takes the double
## jump, a toast says "Fin de la demo / Gracias por jugar" (via `PickupToast`).
##
## HOW TO USE (drag and drop):
## 1. Instance `scenes/world/demo_end_toast.tscn` in the room that holds the
##    BossArena (it finds the arena among its siblings by itself).
## 2. Turn `Enabled` off to switch the message off, or edit the texts here.
##
## It waits for the pickup because that one announces the ability first; the
## message is queued behind it. With the arena's reward switched off it shows
## when the arena opens. A room reloaded with the boss already beaten shows
## nothing: the message belongs to the moment of the victory.

## Emitted when the message is queued (tests listen to it).
signal toast_shown

@export_group("Message")
@export var enabled := true
@export var title := "Fin de la demo"
@export var subtitle := "Gracias por jugar"
## Seconds between the trigger and the message.
@export_range(0.0, 10.0, 0.1) var delay := 0.6

@export_group("Arena")
## The arena to watch. Empty: the first BossArena among the siblings.
@export var arena: BossArena

var _shown := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if arena == null:
		arena = _find_sibling_arena()
	if arena == null:
		push_warning("DemoEndToast %s has no BossArena: set `Arena` or place it next to one." % get_path())
		return
	arena.reward_spawned.connect(_on_reward_spawned)
	arena.arena_cleared.connect(_on_arena_cleared)


func _find_sibling_arena() -> BossArena:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is BossArena:
			return sibling as BossArena
	return null


func _on_reward_spawned(reward: DoubleJumpReward) -> void:
	if not reward.collected.is_connected(_on_reward_collected):
		reward.collected.connect(_on_reward_collected)


func _on_reward_collected(_player: Node) -> void:
	_announce()


func _on_arena_cleared() -> void:
	if not arena.reward_enabled:
		_announce()


func _announce() -> void:
	if not enabled or _shown:
		return
	_shown = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null:
		toast.call(&"show_toast", title, subtitle)
	toast_shown.emit()

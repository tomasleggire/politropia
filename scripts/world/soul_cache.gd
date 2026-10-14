class_name SoulCache
extends Area2D

## A hidden chest that refills Luz's soul once and announces the secret.
## Drag `scenes/world/soul_cache.tscn` into the secret room (the node's position
## is the chest's base) and give it a unique `reward_id`. Touching it fills the
## soul bar and shows a toast; it is recorded in `SecretProgress`, so the reward
## is never given twice in a run. The empty chest stays in place, dimmed.
## It draws behind the tile layers (z_index -1) so a `SecretChamber` cover can
## hide it until the wall breaks.
## New Game forgets it.

signal opened(reward_id: StringName)

@export_group("Reward")
## Unique name of this reward; empty = scene path plus node name.
@export var reward_id: StringName = &""
## Soul given on opening; 0 or less fills the bar.
@export var soul_amount := 0
@export_group("Toast")
@export var toast_title := "Secreto encontrado"
@export var toast_subtitle := "Un cofre de almas guardaba tu aliento"
@export_group("Look")
## Glow colour while the chest is still closed.
@export var glow_color := Color(1.0, 0.78, 0.42, 0.34)

var _claimed := false

@onready var _chest: Sprite2D = $Chest
@onready var _glow: Sprite2D = $Glow
@onready var _light: PointLight2D = $Light


func _ready() -> void:
	glow_color.a = glow_color.a
	_glow.modulate = glow_color
	if _already_claimed():
		_claimed = true
		_show_empty()
		return
	body_entered.connect(_on_body_entered)
	_wait_for_reveal.call_deferred()


## Inside a covered `SecretChamber` the glow and light stay off, so nothing
## hints at the room until its wall breaks.
func _wait_for_reveal() -> void:
	for node in get_tree().get_nodes_in_group(SecretChamber.GROUP):
		var chamber := node as SecretChamber
		if chamber.is_covered() and chamber.contains(global_position + Vector2(0.0, -8.0)):
			var light_energy := _light.energy
			_glow.modulate.a = 0.0
			_light.energy = 0.0
			chamber.revealed.connect(func() -> void:
				_light.energy = light_energy
				_pulse(), CONNECT_ONE_SHOT)
			return
	_pulse()


func get_effective_id() -> StringName:
	if not reward_id.is_empty():
		return reward_id
	var scene_path := owner.scene_file_path if owner != null else ""
	return StringName("%s#%s" % [scene_path, name])


func is_claimed() -> bool:
	return _claimed


func _already_claimed() -> bool:
	var progress := get_node_or_null("/root/SecretProgress")
	return progress != null and progress.is_reward_claimed(get_effective_id())


func _on_body_entered(body: Node2D) -> void:
	if _claimed or not body.is_in_group(&"player"):
		return
	_claimed = true
	var progress := get_node_or_null("/root/SecretProgress")
	if progress != null:
		progress.claim_reward(get_effective_id())
	if body.has_method(&"add_soul") and body.has_method(&"get_max_soul"):
		body.add_soul(soul_amount if soul_amount > 0 else int(body.get_max_soul()))
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null:
		toast.show_toast(toast_title, toast_subtitle)
	opened.emit(get_effective_id())
	_show_empty(true)


func _pulse() -> void:
	_glow.modulate.a = glow_color.a
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_glow, "modulate:a", glow_color.a * 0.45, 1.4)
	tween.tween_property(_glow, "modulate:a", glow_color.a, 1.4)


func _show_empty(animated := false) -> void:
	var tween := create_tween().set_parallel(true) if animated else null
	if tween == null:
		_glow.modulate.a = 0.0
		_light.energy = 0.0
		_chest.modulate = Color(0.55, 0.55, 0.6)
		return
	tween.tween_property(_glow, "modulate:a", 0.0, 0.6)
	tween.tween_property(_light, "energy", 0.0, 0.6)
	tween.tween_property(_chest, "modulate", Color(0.55, 0.55, 0.6), 0.6)

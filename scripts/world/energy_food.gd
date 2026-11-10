class_name EnergyFood
extends Node2D

## Interactive one-use food that restores half of Luz's concentration meter.

const PLAYER_GROUP := &"player"
const INTERACTABLE_GROUP := &"interactable"
const RESTORE_RATIO := 0.5

@export_range(0.0, 1.0, 0.05) var restore_ratio := RESTORE_RATIO
@export_range(0.05, 1.0, 0.05) var consume_animation_time := 0.28

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _glow: Sprite2D = $Glow
@onready var _area: Area2D = $InteractionArea
@onready var _prompt: InteractionPrompt = $InteractionPrompt

var _player: Player
var _player_nearby := false
var _consumed := false
var _base_y := 0.0
var _bob_tween: Tween
var _glow_tween: Tween


func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_prompt.prompt_text = "Comer"
	_base_y = position.y
	_start_idle_animation()
	_refresh_interaction()


func _exit_tree() -> void:
	_set_touch_interact_available(false)
	if is_instance_valid(_player) and _player.soul_changed.is_connected(_on_player_soul_changed):
		_player.soul_changed.disconnect(_on_player_soul_changed)


func _process(_delta: float) -> void:
	if can_interact() and Input.is_action_just_pressed(&"interact"):
		request_interact()


func can_interact() -> bool:
	return (
		not _consumed
		and _player_nearby
		and is_instance_valid(_player)
	)


## Entry point used by the mobile interact button.
func request_interact() -> bool:
	if not can_interact():
		return false
	if _player.get_soul() >= _player.get_max_soul():
		var toast := get_node_or_null("/root/PickupToast")
		if toast != null:
			toast.call(&"show_toast", "La concentración está completa")
		return false
	_consumed = true
	_set_touch_interact_available(false)
	_prompt.hide_prompt()
	_player.add_soul(roundi(float(_player.get_max_soul()) * restore_ratio))
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null and toast.has_method(&"show_energy_food_first_use"):
		toast.call(&"show_energy_food_first_use")
	_play_consume_animation()
	return true


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(PLAYER_GROUP):
		return
	var player := body as Player
	if player == null:
		return
	_player_nearby = true
	_player = player
	if not _player.soul_changed.is_connected(_on_player_soul_changed):
		_player.soul_changed.connect(_on_player_soul_changed)
	_refresh_interaction()


func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	_player_nearby = false
	if is_instance_valid(_player) and _player.soul_changed.is_connected(_on_player_soul_changed):
		_player.soul_changed.disconnect(_on_player_soul_changed)
	_player = null
	_refresh_interaction()


func _on_player_soul_changed(_current: int, _maximum: int) -> void:
	_refresh_interaction()


func _refresh_interaction() -> void:
	var available := can_interact()
	if is_instance_valid(_prompt):
		if available:
			_prompt.show_prompt()
		else:
			_prompt.hide_prompt()
	_set_touch_interact_available(available)


func _set_touch_interact_available(available: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_interact_available"):
		touch.set_interact_available(self, available)


func _start_idle_animation() -> void:
	_bob_tween = create_tween().set_loops()
	_bob_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(self, "position:y", _base_y - 3.0, 1.0)
	_bob_tween.tween_property(self, "position:y", _base_y + 3.0, 1.0)
	_glow_tween = create_tween().set_loops()
	_glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(_glow, "modulate:a", 0.64, 0.8)
	_glow_tween.tween_property(_glow, "modulate:a", 0.3, 0.8)


func _play_consume_animation() -> void:
	if _bob_tween != null:
		_bob_tween.kill()
	if _glow_tween != null:
		_glow_tween.kill()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", scale * 1.18, consume_animation_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, consume_animation_time).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(queue_free)

class_name InteractionPrompt
extends Node2D

## Small world-space key hint ("E  Rest") that fades in while an interactable
## is in range. Purely presentational: the owner decides when to show it.

@export var action: StringName = &"interact"
@export var prompt_text := "Rest":
	set(value):
		prompt_text = value
		_refresh_labels()
@export_range(0.05, 1.0, 0.01) var fade_time := 0.18

var _fade_tween: Tween

@onready var _key_label: Label = %KeyLabel
@onready var _action_label: Label = %ActionLabel


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	_refresh_labels()


func show_prompt() -> void:
	_fade_to(1.0)


func hide_prompt() -> void:
	_fade_to(0.0)


func is_prompt_visible() -> bool:
	return visible and modulate.a > 0.0


func _fade_to(alpha: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if alpha > 0.0:
		visible = true
		_refresh_labels()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(self, "modulate:a", alpha, fade_time)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func() -> void: visible = false)


func _refresh_labels() -> void:
	if _key_label == null or _action_label == null:
		return
	_key_label.text = _key_hint()
	_action_label.text = prompt_text


func _key_hint() -> String:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return OS.get_keycode_string(event.physical_keycode)
	return "E"

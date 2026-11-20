class_name NpcSpeechBubble
extends Node2D

signal finished

@onready var panel: PanelContainer = $PanelContainer
@onready var label: RichTextLabel = $PanelContainer/MarginContainer/RichTextLabel

@export var text_speed := 0.03

var _dialogue: Array[String] = []
var _current_index := 0
var _is_typing := false
var _tween: Tween


func _ready() -> void:
	hide()

	if label:
		label.bbcode_enabled = true
		label.add_theme_font_size_override("normal_font_size", 32)
		label.add_theme_constant_override("line_separation", 6)
		label.add_theme_constant_override("text_highlight_h_padding", 4)
		label.add_theme_constant_override("text_highlight_v_padding", 4)
		label.add_theme_color_override("default_color", Color("#FFF8E7"))
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.custom_minimum_size = Vector2(380, 0)

	if panel:
		panel.custom_minimum_size = Vector2(0, 0)


func start_dialogue(lines: Array[String]) -> void:
	if lines.is_empty():
		return

	_dialogue = lines
	_current_index = 0

	show()
	_show_current_line()


func _show_current_line() -> void:
	if _current_index >= _dialogue.size():
		_end_dialogue()
		return

	if _tween and _tween.is_running():
		_tween.kill()

	label.text = _dialogue[_current_index]
	label.visible_ratio = 0.0

	if panel:
		panel.reset_size()

	_is_typing = true

	var text_length := label.get_parsed_text().length()
	var duration := text_length * text_speed

	_tween = create_tween()
	_tween.tween_property(label, "visible_ratio", 1.0, duration)
	_tween.finished.connect(func():
		_is_typing = false
	)


func advance_dialogue() -> void:
	if not visible:
		return

	# If text is still typing, finish it first.
	if _is_typing:
		if _tween and _tween.is_running():
			_tween.kill()

		label.visible_ratio = 1.0
		_is_typing = false
		return

	# If this was the last line, close the dialogue.
	if _current_index >= _dialogue.size() - 1:
		_end_dialogue()
		return

	# Otherwise, advance to the next line.
	_current_index += 1
	_show_current_line()


func _end_dialogue() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_is_typing = false
	hide()
	finished.emit()

func is_dialogue_active() -> bool:
	return visible

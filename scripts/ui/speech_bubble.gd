class_name SpeechBubble
extends Node2D

signal finished

@onready var panel: PanelContainer = $PanelContainer
@onready var label: RichTextLabel = $PanelContainer/MarginContainer/RichTextLabel

@export var text_speed := 0.03

var _lines: Array[String] = []
var _current_line := 0
var _is_typing := false
var _tween: Tween

func _ready() -> void:
	hide()

func start_dialogue(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_current_line = 0
	show()
	_show_line()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
		
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _is_typing:
			if _tween:
				_tween.kill()
			label.visible_ratio = 1.0
			_is_typing = false
		else:
			_current_line += 1
			if _current_line < _lines.size():
				_show_line()
			else:
				_finish()

func _show_line() -> void:
	_is_typing = true
	label.text = _lines[_current_line]
	label.visible_ratio = 0.0
	
	var text_length := label.get_parsed_text().length()
	var duration := text_length * text_speed
	
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(label, "visible_ratio", 1.0, duration)
	_tween.finished.connect(func(): _is_typing = false)

func _finish() -> void:
	hide()
	finished.emit()

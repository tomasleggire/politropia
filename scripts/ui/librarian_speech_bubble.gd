class_name LibrarianSpeechBubble
extends Node2D

signal finished

@onready var panel: PanelContainer = $PanelContainer
@onready var label: RichTextLabel = $PanelContainer/MarginContainer/RichTextLabel

@export var text_speed := 0.03

var _is_typing := false
var _tween: Tween

func _ready() -> void:
	hide()
	if label:
		label.bbcode_enabled = true
		label.add_theme_font_size_override("normal_font_size", 32)
		label.add_theme_constant_override("line_separation", 6)
		# 🔹 1. Padding para separar las pastillas de colores horizontal y verticalmente
		label.add_theme_constant_override("text_highlight_h_padding", 4)
		label.add_theme_constant_override("text_highlight_v_padding", 4)
		label.add_theme_color_override("default_color", Color("#FFF8E7"))
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		# 🔹 2. Cambiamos de Vector2(650, 0) a Vector2(380, 0)
		label.custom_minimum_size = Vector2(380, 0)
		
	if panel:
		panel.custom_minimum_size = Vector2(0, 0)

func show_text(text: String) -> void:
	show()
	_is_typing = true
	label.text = text
	label.visible_ratio = 0.0
	
	# Obligamos al panel a encoger su altura al contenido real
	if panel:
		panel.reset_size()
	
	var text_length := label.get_parsed_text().length()
	var duration := text_length * text_speed
	
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(label, "visible_ratio", 1.0, duration)
	_tween.finished.connect(func(): _is_typing = false)

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
			_finish()

func _finish() -> void:
	hide()
	finished.emit()

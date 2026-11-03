class_name SpeechBubble
extends Node2D

signal finished

@onready var panel: PanelContainer = $VBoxContainer/PanelContainer
@onready var label: RichTextLabel = $VBoxContainer/PanelContainer/MarginContainer/RichTextLabel
@onready var next_button: Button = $VBoxContainer/NextButton

@export var text_speed := 0.03

var _lines: Array[String] = []
var _current_line := 0
var _is_typing := false
var _tween: Tween

func _ready() -> void:
	hide()
	if label:
		label.bbcode_enabled = true
		label.add_theme_font_size_override("normal_font_size", 32)
		label.add_theme_constant_override("line_separation", 12)
		label.add_theme_color_override("default_color", Color("#FFF8E7"))
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.custom_minimum_size = Vector2(520, 0) # Ancho fijo, altura adaptativa
		
	if panel:
		panel.custom_minimum_size = Vector2(0, 0) # Fuerza al panel a encogerse al texto

	if next_button:
		next_button.pressed.connect(_advance_dialogue)

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
		_advance_dialogue()

func _advance_dialogue() -> void:
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
	
	if next_button:
		if _current_line < _lines.size() - 1:
			next_button.text = "Siguiente >"
		else:
			next_button.text = "Entendido"
	
	var text_length := label.get_parsed_text().length()
	var duration := text_length * text_speed
	
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(label, "visible_ratio", 1.0, duration)
	_tween.finished.connect(func(): _is_typing = false)
	
	# Fuerza el reajuste automático de tamaño del cuadro violeta al terminar de cargar el frame
	await get_tree().process_frame
	if panel:
		panel.reset_size()

func _finish() -> void:
	hide()
	finished.emit()

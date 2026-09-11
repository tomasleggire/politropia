class_name StoryLine
extends CanvasLayer

## Una sola línea narrativa: tipografía grande, alto contraste, auto-hide.

signal line_shown(text: String)

@export var display_seconds: float = 2.6

var _label: Label
var _panel: PanelContainer
var _hide_left: float = 0.0
var _shown: Dictionary = {}


func _ready() -> void:
	layer = 80
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	if _hide_left <= 0.0:
		return
	_hide_left -= delta
	if _hide_left <= 0.0:
		visible = false


func show_line(text: String, once_id: StringName = &"") -> void:
	if once_id != &"" and _shown.has(once_id):
		return
	if once_id != &"":
		_shown[once_id] = true
	_label.text = text
	visible = true
	_hide_left = display_seconds
	line_shown.emit(text)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -300.0
	_panel.offset_right = 300.0
	_panel.offset_top = -150.0
	_panel.offset_bottom = -70.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	_panel.add_child(_label)

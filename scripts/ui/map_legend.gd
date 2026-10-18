class_name MapLegend
extends Control

## Small legend of the map screen: one gold icon and a word per landmark kind
## the current level uses. `MapScreen` calls `show_kinds()`.
##
## USAGE: it lives in the footer of `scenes/ui/map_screen.tscn`. Texts and
## colours are exports.

@export_group("Texts")
@export var boss_text := "Jefe"
@export var rest_text := "Descanso"
@export var lectern_text := "Atril"

@export_group("Look")
@export var icon_radius := 6.0
@export var gap := 14.0
@export var text_color := Color(0.91, 0.851, 0.659, 0.9)
@export var icon_color := Color(0.96, 0.82, 0.38, 1.0)
@export var font_size := 12

var _kinds: Array[int] = []


## Draws the legend for `kinds` (MapRoom.Landmark values). SECRET never shows.
func show_kinds(kinds: Array[int]) -> void:
	_kinds = []
	for kind in kinds:
		if _text_for(kind) != "":
			_kinds.append(kind)
	visible = not _kinds.is_empty()
	custom_minimum_size = Vector2(_total_width(), icon_radius * 2.0 + 6.0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var x := 0.0
	for kind in _kinds:
		var text := _text_for(kind)
		MapView.draw_landmark(self, kind, Vector2(x + icon_radius, size.y * 0.5), icon_radius, icon_color)
		x += icon_radius * 2.0 + 4.0
		draw_string(font, Vector2(x, size.y * 0.5 + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + gap


func _total_width() -> float:
	var font := get_theme_default_font()
	var width := 0.0
	for kind in _kinds:
		var text_width := font.get_string_size(_text_for(kind), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 40.0
		width += icon_radius * 2.0 + 4.0 + text_width + gap
	return width


func _text_for(kind: int) -> String:
	match kind:
		MapRoom.Landmark.BOSS:
			return boss_text
		MapRoom.Landmark.REST:
			return rest_text
		MapRoom.Landmark.LECTERN:
			return lectern_text
	return ""

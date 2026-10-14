class_name MapView
extends Control

## Draws one `MapLayout`: the rooms Luz has visited, the doors between them and
## a marker on the room she is in. Rooms she has not seen stay hidden.
##
## USAGE: it lives inside `scenes/ui/map_screen.tscn`; call `show_map()`. The
## colours are exports so the map can be restyled from the Inspector.

@export_group("Rooms")
@export var room_fill := Color(0.075, 0.14, 0.27, 1.0)
@export var room_border := Color(0.541, 0.447, 0.251, 1.0)
@export var room_border_width := 1.5
@export var connector_color := Color(0.541, 0.447, 0.251, 1.0)
@export var connector_width := 2.0

@export_group("Current room")
@export var current_fill := Color(0.878, 0.725, 0.31, 0.32)
@export var current_border := Color(0.96, 0.84, 0.45, 1.0)
## Seconds for one pulse of the Luz marker.
@export_range(0.2, 4.0, 0.1) var pulse_seconds := 1.4

@export_group("Layout")
## Free space kept around the map, in pixels.
@export var padding := 14.0
## The map never scales a unit above this, so a small level is not blown up.
@export var max_units_scale := 14.0
@export var label_color := Color(0.91, 0.851, 0.659, 0.9)
@export var label_size := 9

var _layout: MapLayout
var _visited: Dictionary = {}
var _current := ""
var _time := 0.0


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


## Sets what to draw. `visited` maps scene path -> true.
func show_map(layout: MapLayout, visited: Dictionary, current_scene: String) -> void:
	_layout = layout
	_visited = visited
	_current = current_scene
	queue_redraw()


func _draw() -> void:
	if _layout == null:
		return
	var transform := _fit_transform()
	for room in _layout.rooms:
		if room == null or not _visited.has(room.scene_path):
			continue
		for other_path in room.connects_to:
			var other := _layout.find_room(other_path)
			if other != null and _visited.has(other_path) and room.scene_path < other_path:
				draw_line(transform * room.map_rect.get_center(), transform * other.map_rect.get_center(), connector_color, connector_width, true)
	for room in _layout.rooms:
		if room != null and _visited.has(room.scene_path):
			_draw_room(room, transform)


func _draw_room(room: MapRoom, transform: Transform2D) -> void:
	var rect := Rect2(transform * room.map_rect.position, room.map_rect.size * transform.get_scale())
	var is_current := room.scene_path == _current
	draw_rect(rect, room_fill)
	if is_current:
		draw_rect(rect, current_fill)
	draw_rect(rect, current_border if is_current else room_border, false, room_border_width * (1.6 if is_current else 1.0))
	var font := get_theme_default_font()
	if font != null and not room.display_name.is_empty():
		var text_size := font.get_string_size(room.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size)
		if text_size.x + 6.0 <= rect.size.x and text_size.y + 4.0 <= rect.size.y:
			var at := rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.25 + (10.0 if is_current else 0.0))
			draw_string(font, at, room.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, label_color)
	if is_current:
		_draw_marker(rect.get_center() - Vector2(0.0, 8.0 if rect.size.y > 30.0 else 0.0))


## Luz marker: a gold diamond with a soft halo that pulses.
func _draw_marker(center: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * TAU / pulse_seconds)
	draw_circle(center, 7.0 + 3.0 * pulse, Color(current_border, 0.18 + 0.12 * pulse))
	var points := PackedVector2Array([
		center + Vector2(0.0, -5.0), center + Vector2(4.0, 0.0),
		center + Vector2(0.0, 5.0), center + Vector2(-4.0, 0.0),
	])
	draw_colored_polygon(points, Color(1.0, 0.95, 0.7, 1.0))
	points.append(points[0])
	draw_polyline(points, Color(0.2, 0.14, 0.04, 1.0), 1.0, true)


## Map units -> pixels: the whole layout fits the control and stays centred.
func _fit_transform() -> Transform2D:
	var bounds := _layout.bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Transform2D.IDENTITY
	var available := size - Vector2.ONE * padding * 2.0
	var unit := minf(minf(available.x / bounds.size.x, available.y / bounds.size.y), max_units_scale)
	unit = maxf(unit, 0.01)
	var origin := (size - bounds.size * unit) * 0.5 - bounds.position * unit
	return Transform2D(Vector2(unit, 0.0), Vector2(0.0, unit), origin)

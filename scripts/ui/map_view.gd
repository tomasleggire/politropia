class_name MapView
extends Control

## Draws one `MapLayout`: the rooms Luz has visited (filled), the rooms she has
## not (a dim outline, while the layout's `reveal_unvisited` is on), the doors
## between them, landmark icons and a marker on the room she is in.
##
## USAGE: it lives inside `scenes/ui/map_screen.tscn`; call `show_map()`. The
## colours are exports so the map can be restyled from the Inspector.

@export_group("Rooms")
@export var room_fill := Color(0.075, 0.14, 0.27, 1.0)
@export var room_border := Color(0.541, 0.447, 0.251, 1.0)
@export var room_border_width := 1.5
@export var connector_color := Color(0.541, 0.447, 0.251, 1.0)
@export var connector_width := 2.0

@export_group("Unvisited rooms")
## Drawing alpha of the fill and the outline of rooms Luz has not entered yet.
## Opaque colour under the translucent fill, so door lines do not show through.
@export var unvisited_base := Color(0.027, 0.051, 0.114, 1.0)
@export_range(0.0, 1.0, 0.05) var unvisited_fill_alpha := 0.12
@export_range(0.0, 1.0, 0.05) var unvisited_border_alpha := 0.5
@export_range(0.0, 1.0, 0.05) var unvisited_label_alpha := 0.55

@export_group("Landmarks")
@export var landmark_color := Color(0.96, 0.82, 0.38, 1.0)
## Icon radius in pixels, scaled down in small rooms.
@export_range(4.0, 20.0, 0.5) var landmark_radius := 8.0

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
		if room == null or not _is_shown(room):
			continue
		for other_path in room.connects_to:
			var other := _layout.find_room(other_path)
			if other != null and _is_shown(other) and room.scene_path < other_path:
				var both := _visited.has(room.scene_path) and _visited.has(other_path)
				var color := connector_color if both else Color(connector_color, unvisited_border_alpha)
				draw_line(transform * room.map_rect.get_center(), transform * other.map_rect.get_center(), color, connector_width, true)
	for room in _layout.rooms:
		if room != null and _is_shown(room):
			_draw_room(room, transform)


## How many rooms the current map draws (visited, or all when revealing).
func shown_room_count() -> int:
	if _layout == null:
		return 0
	var count := 0
	for room in _layout.rooms:
		if room != null and _is_shown(room):
			count += 1
	return count


## A room is drawn when visited, or when the layout reveals unvisited rooms.
func _is_shown(room: MapRoom) -> bool:
	return _visited.has(room.scene_path) or _layout.reveal_unvisited


func _draw_room(room: MapRoom, transform: Transform2D) -> void:
	var rect := Rect2(transform * room.map_rect.position, room.map_rect.size * transform.get_scale())
	var is_current := room.scene_path == _current
	var seen := _visited.has(room.scene_path)
	var has_icon := room.landmark != MapRoom.Landmark.NONE and (seen or room.landmark != MapRoom.Landmark.SECRET)
	if seen:
		draw_rect(rect, room_fill)
	else:
		draw_rect(rect, unvisited_base)
		draw_rect(rect, Color(room_fill, unvisited_fill_alpha))
	if is_current:
		draw_rect(rect, current_fill)
	var border := current_border if is_current else (room_border if seen else Color(room_border, unvisited_border_alpha))
	draw_rect(rect, border, false, room_border_width * (1.6 if is_current else 1.0))
	var radius := minf(landmark_radius, minf(rect.size.x, rect.size.y) * 0.3)
	var label_shift := 0.0
	if has_icon:
		var dim := 1.0 if seen else 0.8
		draw_landmark(self, room.landmark, rect.get_center() - Vector2(0.0, 4.0), radius, Color(landmark_color, dim))
		label_shift = radius + 6.0
	var font := get_theme_default_font()
	if font != null and not room.display_name.is_empty():
		var text_size := font.get_string_size(room.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size)
		if text_size.x + 6.0 <= rect.size.x and text_size.y + 4.0 + label_shift <= rect.size.y:
			var at := rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.25 + label_shift - (4.0 if has_icon else 0.0) + (10.0 if is_current and not has_icon else 0.0))
			draw_string(font, at, room.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, label_color if seen else Color(label_color, unvisited_label_alpha))
	if is_current:
		var marker_at := rect.get_center() - Vector2(0.0, 8.0 if rect.size.y > 30.0 else 0.0)
		if has_icon:
			marker_at = rect.position + Vector2(minf(rect.size.x * 0.2, 12.0), minf(rect.size.y * 0.25, 12.0))
		_draw_marker(marker_at)


## Gold landmark icon centred on `center`, `radius` pixels wide. Static so the
## legend draws the very same shapes.
static func draw_landmark(canvas: CanvasItem, kind: int, center: Vector2, radius: float, color: Color) -> void:
	var dark := Color(0.2, 0.14, 0.04, 0.9)
	match kind:
		MapRoom.Landmark.BOSS:
			# Eight-point star: the arena.
			var star := PackedVector2Array()
			for i in 16:
				var angle := TAU * float(i) / 16.0 - PI * 0.5
				star.append(center + Vector2.from_angle(angle) * radius * (1.0 if i % 2 == 0 else 0.42))
			canvas.draw_colored_polygon(star, color)
			star.append(star[0])
			canvas.draw_polyline(star, dark, 1.0, true)
		MapRoom.Landmark.REST:
			# Stillness desk: seat, legs and a back.
			var w := radius * 0.95
			canvas.draw_rect(Rect2(center + Vector2(-w, -radius * 0.1), Vector2(w * 2.0, radius * 0.4)), color)
			canvas.draw_rect(Rect2(center + Vector2(-w * 0.8, radius * 0.3), Vector2(radius * 0.3, radius * 0.6)), color)
			canvas.draw_rect(Rect2(center + Vector2(w * 0.8 - radius * 0.3, radius * 0.3), Vector2(radius * 0.3, radius * 0.6)), color)
			canvas.draw_rect(Rect2(center + Vector2(-w, -radius * 0.9), Vector2(radius * 0.3, radius * 0.9)), color)
		MapRoom.Landmark.LECTERN:
			# Open book on a stand.
			var left := PackedVector2Array([
				center + Vector2(0.0, -radius * 0.3), center + Vector2(-radius, -radius * 0.65),
				center + Vector2(-radius, radius * 0.35), center + Vector2(0.0, radius * 0.7),
			])
			var right := PackedVector2Array([
				center + Vector2(0.0, -radius * 0.3), center + Vector2(radius, -radius * 0.65),
				center + Vector2(radius, radius * 0.35), center + Vector2(0.0, radius * 0.7),
			])
			canvas.draw_colored_polygon(left, color)
			canvas.draw_colored_polygon(right, color)
			canvas.draw_line(center + Vector2(0.0, -radius * 0.3), center + Vector2(0.0, radius * 0.7), dark, 1.0, true)
		MapRoom.Landmark.SECRET:
			canvas.draw_arc(center, radius * 0.7, 0.0, TAU, 20, color, 1.6, true)
			canvas.draw_circle(center, radius * 0.22, color)


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

@tool
class_name BossTelegraph
extends Node2D

## Placeholder telegraph FX shared by boss attacks. It can show a coloured
## glow over the boss body, an aim line and a pool of floor markers. Every node
## is built once in `_ready` and only reused afterwards, so showing, moving and
## hiding a telegraph allocates nothing. Final art replaces the visuals, not the
## calls: the boss logic only talks to this API.
##
## Colour language: amber warns of a ranged attack, red of melee, pale
## moon-silver marks phase two.

const RANGED_COLOR := Color(1.0, 0.72, 0.25)
const MELEE_COLOR := Color(0.95, 0.25, 0.2)
const MOON_COLOR := Color(0.8, 0.9, 1.0)

const MARKER_POOL_SIZE := 8
const GLOW_MAX_ALPHA := 0.65
const MARKER_ALPHA := 0.38
const LINE_WIDTH := 3.0
## An aim line that still follows Luz is dimmer than a locked one.
const LINE_TRACKING_ALPHA := 0.45

var _glow: Polygon2D
var _line: Line2D
var _markers: Array[Polygon2D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_line()
	_build_markers()


## Hands the telegraph the boss body so the glow can mirror its silhouette.
func bind_body(body: Polygon2D) -> void:
	_glow = Polygon2D.new()
	_glow.polygon = body.polygon
	_glow.visible = false
	var parent := body.get_parent()
	parent.add_child(_glow)
	parent.move_child(_glow, body.get_index() + 1)


## Tints the body with `color`; `amount` 0 hides it and 1 is the full glow.
func set_glow(color: Color, amount: float) -> void:
	if _glow == null:
		return
	_glow.visible = amount > 0.0
	_glow.color = Color(color, clampf(amount, 0.0, 1.0) * GLOW_MAX_ALPHA)


## A line of `length` px from `from` along `direction` (normalized), both in
## world space. A `locked` line is solid: the aim will not move any more.
func show_aim_line(from: Vector2, direction: Vector2, length: float, color: Color, locked: bool) -> void:
	_line.set_point_position(0, to_local(from))
	_line.set_point_position(1, to_local(from + direction * length))
	_line.default_color = Color(color, 1.0 if locked else LINE_TRACKING_ALPHA)
	_line.visible = true


func hide_aim_line() -> void:
	if _line != null:
		_line.visible = false


## A rectangle on the floor (world space) in marker slot `slot`.
func show_floor_marker(slot: int, rect: Rect2, color: Color) -> void:
	var marker := _markers[slot]
	marker.global_position = rect.position
	marker.scale = rect.size
	marker.color = Color(color, MARKER_ALPHA)
	marker.visible = true


func hide_floor_marker(slot: int) -> void:
	_markers[slot].visible = false


func hide_floor_markers() -> void:
	for marker: Polygon2D in _markers:
		marker.visible = false


func clear() -> void:
	set_glow(Color.WHITE, 0.0)
	hide_aim_line()
	hide_floor_markers()


func is_aim_line_visible() -> bool:
	return _line != null and _line.visible


func is_glowing() -> bool:
	return _glow != null and _glow.visible


func is_floor_marker_visible(slot: int) -> bool:
	return _markers[slot].visible


func _build_line() -> void:
	_line = Line2D.new()
	_line.width = LINE_WIDTH
	_line.z_index = 2
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.add_point(Vector2.ZERO)
	_line.add_point(Vector2.ZERO)
	_line.visible = false
	add_child(_line)


## Unit squares positioned and scaled per use, so a marker never rebuilds its
## polygon.
func _build_markers() -> void:
	var unit := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for i: int in MARKER_POOL_SIZE:
		var marker := Polygon2D.new()
		marker.polygon = unit
		marker.top_level = true
		marker.z_index = -1
		marker.visible = false
		add_child(marker)
		_markers.append(marker)

class_name SoulMeter
extends Control

## Placeholder soul vessel for the HUD: a dim ring that fills from the bottom
## as soul grows. While there is enough soul for a focus heal it glows. Final
## art replaces the drawing by setting `full_texture` / `empty_texture`; the
## full texture is cropped to the fill level.

const VESSEL := Color("9fc7e6")
const VESSEL_EMPTY := Color(0.62, 0.78, 0.9, 0.3)
const CUE := Color("fff3c2")
const RING_WIDTH := 2.0
const EDGE_INSET := 3.0

@export_group("Art")
@export var full_texture: Texture2D
@export var empty_texture: Texture2D

@export_group("Feedback")
@export var cue_pulse_time := 0.7

## 0 is empty, 1 is full.
var fill := 0.0:
	set(value):
		fill = clampf(value, 0.0, 1.0)
		queue_redraw()
## 0..1 strength of the "can heal" glow; driven by a looping tween.
var glow := 0.0:
	set(value):
		glow = value
		queue_redraw()

var _can_heal := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_soul(current: int, maximum: int, can_heal: bool) -> void:
	fill = float(current) / float(maxi(maximum, 1))
	_set_can_heal(can_heal)


func is_cue_visible() -> bool:
	return _can_heal


func _set_can_heal(value: bool) -> void:
	if _can_heal == value:
		return
	_can_heal = value
	if _tween != null:
		_tween.kill()
		_tween = null
	glow = 0.0
	if _can_heal:
		_tween = create_tween().set_loops()
		_tween.tween_property(self, "glow", 1.0, cue_pulse_time)
		_tween.tween_property(self, "glow", 0.35, cue_pulse_time)


func _draw() -> void:
	_draw_empty()
	if fill > 0.0:
		_draw_fill()
	if _can_heal:
		draw_arc(size * 0.5, _radius() + 2.0, 0.0, TAU, 48, Color(CUE, 0.25 + 0.6 * glow), 3.0, true)


func _draw_empty() -> void:
	if empty_texture != null:
		draw_texture_rect(empty_texture, Rect2(Vector2.ZERO, size), false)
		return
	draw_circle(size * 0.5, _radius(), Color(0.02, 0.05, 0.1, 0.35))
	draw_arc(size * 0.5, _radius(), 0.0, TAU, 48, VESSEL_EMPTY, RING_WIDTH, true)


func _draw_fill() -> void:
	if full_texture != null:
		var crop := size.y * fill
		var source_scale := Vector2(full_texture.get_size()) / size
		var dest := Rect2(0.0, size.y - crop, size.x, crop)
		draw_texture_rect_region(full_texture, dest, Rect2(dest.position * source_scale, dest.size * source_scale))
		return
	var center := size * 0.5
	var radius := _radius()
	var top := center.y + radius - 2.0 * radius * fill
	var row := maxf(top, center.y - radius)
	while row <= center.y + radius:
		var half := sqrt(maxf(radius * radius - (row - center.y) * (row - center.y), 0.0))
		draw_line(Vector2(center.x - half, row), Vector2(center.x + half, row), Color(VESSEL, 0.9), 1.5)
		row += 1.0


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - EDGE_INSET

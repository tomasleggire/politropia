class_name MenuSelector
extends Control
## Ornaments of the main menu: a thin vertical gold line with diamond caps, a
## glowing four-point star that slides to the selected row and a gold underline
## that re-sweeps under it. Purely decorative; draws in additive blend.

@export_group("Gold line")
@export var line_color := Color(0.93, 0.74, 0.36, 0.9)
@export var line_overhang := 22.0
@export var cap_radius := 3.0

@export_group("Star")
@export var star_radius := 9.0
@export var star_slide_time := 0.22
@export var star_breath_period := 2.4

@export_group("Underline")
@export var underline_gap := 3.0
@export var underline_extra := 18.0
@export var underline_sweep_time := 0.32

var _star_y := 0.0
var _sweep := 0.0
var _line_top := 0.0
var _line_bottom := 0.0
var _underline_x0 := 0.0
var _underline_x1 := 0.0
var _underline_y := 0.0
var _has_target := false
var _time := 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = MainMenuStage.additive_material()
	visible = false


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Sets the vertical span of the gold line from the first and last rows.
func set_span(first: Button, last: Button) -> void:
	_line_top = _row_center(first) - first.size.y * 0.5 - line_overhang
	_line_bottom = _row_center(last) + last.size.y * 0.5 + line_overhang


func select(button: Button, animate: bool = true) -> void:
	var target_y := _row_center(button)
	var font := button.get_theme_font(&"font")
	var font_size := button.get_theme_font_size(&"font_size")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_underline_x0 = button.global_position.x - global_position.x
	_underline_x1 = _underline_x0 + text_width + underline_extra
	_underline_y = button.global_position.y - global_position.y + button.size.y - underline_gap
	visible = true
	if _tween != null:
		_tween.kill()
	if not animate or not _has_target:
		_has_target = true
		_star_y = target_y
		_sweep = 1.0
		return
	_sweep = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "_star_y", target_y, star_slide_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_sweep", 1.0, underline_sweep_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _row_center(button: Button) -> float:
	return button.global_position.y - global_position.y + button.size.y * 0.5


func _draw() -> void:
	_draw_gold_line()
	if not _has_target:
		return
	_draw_underline()
	_draw_star()


func _draw_gold_line() -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		points.append(Vector2(0.0, lerpf(_line_top, _line_bottom, t)))
		var color := line_color
		color.a *= pow(sin(PI * t), 0.6)
		colors.append(color)
	draw_polyline_colors(points, colors, 1.0)
	_draw_diamond(Vector2(0.0, _line_top), cap_radius, line_color)
	_draw_diamond(Vector2(0.0, _line_bottom), cap_radius, line_color)


func _draw_underline() -> void:
	var end_x := lerpf(_underline_x0, _underline_x1, _sweep)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in 13:
		var t := float(i) / 12.0
		points.append(Vector2(lerpf(_underline_x0, end_x, t), _underline_y))
		var color := line_color
		color.a *= lerpf(1.0, 0.25, t)
		colors.append(color)
	draw_polyline_colors(points, colors, 1.0)
	var cap := line_color
	cap.a *= _sweep
	_draw_diamond(Vector2(end_x, _underline_y), cap_radius, cap)


func _draw_star() -> void:
	var breath := 1.0 + 0.12 * sin(TAU * _time / star_breath_period)
	var center := Vector2(0.0, _star_y)
	for i in 4:
		var glow := Color(1.0, 0.72, 0.3, 0.07)
		draw_circle(center, star_radius * (1.9 - 0.35 * i) * breath, glow)
	var outer := star_radius * breath
	var inner := outer * 0.2
	var points := PackedVector2Array()
	for i in 8:
		var angle := PI * 0.25 * i - PI * 0.5
		var radius := outer if i % 2 == 0 else inner
		if i % 2 == 0 and i % 4 == 2:
			radius = outer * 1.45  # Longer horizontal flare, like the concept.
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(1.0, 0.93, 0.7, 1.0))
	draw_circle(center, outer * 0.22, Color(1, 1, 1, 0.9))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
	]), color)

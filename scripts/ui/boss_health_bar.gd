class_name BossHealthBar
extends CanvasLayer

## Boss health at the top centre of the screen, inside the safe area: name,
## bar, a notch where phase two starts, and a title card for the intro. It is
## driven by calls (a BossArena forwards the boss's `hit` signal), never by
## polling. A hit drains the bar at once and a lighter "damage chunk" trails
## behind it. The row of health pips sits top-left and the touch controls at
## the bottom, so the bar is kept clear of both: its width shrinks on narrow
## screens before it would reach the pips.

const BAR_LAYER := 41
const NO_NOTCH := -1.0

@export_group("Layout")
@export var bar_size := Vector2(300.0, 12.0)
@export var top_margin := 16.0
## Free space kept on each side of the bar (the pips and soul meter live there).
@export var side_clearance := 90.0
@export var notch_width := 2.0

@export_group("Style")
@export var back_color := Color(0.05, 0.06, 0.08, 0.85)
@export var fill_color := Color(0.82, 0.24, 0.22)
@export var phase_two_color := Color(0.8, 0.9, 1.0)
@export var chunk_color := Color(0.98, 0.78, 0.45)
@export var notch_color := Color(1.0, 1.0, 1.0, 0.9)
@export var text_color := Color(0.96, 0.94, 0.88)

@export_group("Feedback")
## The chunk waits this long, then slides down to the real health.
@export var chunk_delay := 0.35
@export var chunk_time := 0.3
@export var fade_time := 0.25
@export var title_font_size := 30

var _max_health := 1
var _health_ratio := 1.0
var _chunk_ratio := 1.0
var _notch_ratio := NO_NOTCH
var _shown := false
var _title_shown := false
var _safe_override := Rect2()
var _chunk_tween: Tween
var _fade_tween: Tween
var _title_tween: Tween

@onready var _root: Control = $Root
@onready var _bar: Control = $Root/Bar
@onready var _back: ColorRect = $Root/Bar/Back
@onready var _chunk: ColorRect = $Root/Bar/Chunk
@onready var _fill: ColorRect = $Root/Bar/Fill
@onready var _notch: ColorRect = $Root/Bar/Notch
@onready var _name: Label = $Root/Bar/Name
@onready var _title: Label = $Root/Title


func _ready() -> void:
	layer = BAR_LAYER
	_back.color = back_color
	_chunk.color = chunk_color
	_notch.color = notch_color
	_name.add_theme_color_override(&"font_color", text_color)
	_name.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_name.add_theme_constant_override(&"outline_size", 3)
	_title.add_theme_color_override(&"font_color", text_color)
	_title.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_title.add_theme_constant_override(&"outline_size", 6)
	_title.add_theme_font_size_override(&"font_size", title_font_size)
	_root.visible = false
	_title.visible = false
	get_viewport().size_changed.connect(_place)
	_place()


## Names the boss and starts from full health. `notch_ratio` marks the phase-two
## threshold (0 to 1 of the bar); leave it out for a boss with one phase.
func setup(boss_name: String, max_health: int, notch_ratio := NO_NOTCH) -> void:
	_name.text = boss_name
	_max_health = maxi(max_health, 1)
	_notch_ratio = notch_ratio
	_kill(_chunk_tween)
	_health_ratio = 1.0
	_chunk_ratio = 1.0
	_place()


## Drains to `current` health; the chunk trails behind after a short delay.
func set_health(current: int) -> void:
	var ratio := clampf(float(current) / float(_max_health), 0.0, 1.0)
	var drained := ratio < _health_ratio
	_health_ratio = ratio
	_kill(_chunk_tween)
	if not drained:
		_chunk_ratio = ratio
		_apply()
		return
	_apply()
	_chunk_tween = create_tween()
	_chunk_tween.tween_interval(chunk_delay)
	_chunk_tween.tween_method(_set_chunk_ratio, _chunk_ratio, ratio, chunk_time)


func show_bar(animated := true) -> void:
	_shown = true
	_kill(_fade_tween)
	_root.visible = true
	_bar.visible = true
	_bar.modulate.a = 1.0
	if animated and fade_time > 0.0:
		_bar.modulate.a = 0.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(_bar, "modulate:a", 1.0, fade_time)


func hide_bar(animated := true) -> void:
	_shown = false
	_kill(_fade_tween)
	_kill(_chunk_tween)
	if not animated or fade_time <= 0.0 or not _bar.visible:
		_bar.visible = false
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_bar, "modulate:a", 0.0, fade_time)
	_fade_tween.tween_callback(_hide_bar_if_still_hidden)


## A short centred title card (the boss name) that fades in and out.
func show_title(text: String, duration: float) -> void:
	_kill(_title_tween)
	_title.text = text
	_title.visible = true
	_title_shown = true
	_root.visible = true
	_title.modulate.a = 0.0
	var fade := minf(fade_time, maxf(duration, 0.0) * 0.4)
	_title_tween = create_tween()
	_title_tween.tween_property(_title, "modulate:a", 1.0, fade)
	_title_tween.tween_interval(maxf(duration - 2.0 * fade, 0.0))
	_title_tween.tween_property(_title, "modulate:a", 0.0, fade)
	_title_tween.tween_callback(_end_title)


func hide_title() -> void:
	_kill(_title_tween)
	_end_title()


func is_bar_shown() -> bool:
	return _shown


func is_title_shown() -> bool:
	return _title_shown


func get_name_text() -> String:
	return _name.text


func get_health_ratio() -> float:
	return _health_ratio


func get_chunk_ratio() -> float:
	return _chunk_ratio


func get_notch_ratio() -> float:
	return _notch_ratio


func is_phase_two_tint() -> bool:
	return _notch_ratio >= 0.0 and _health_ratio <= _notch_ratio


## The bar's rect in viewport pixels (for layout checks).
func get_bar_rect() -> Rect2:
	return Rect2(_bar.position, _bar.size)


## Rect (in viewport pixels) the bar must stay inside: the display's safe area
## on a phone, the whole viewport elsewhere (same rule as HealthHud).
func get_safe_rect() -> Rect2:
	if _safe_override.has_area():
		return _safe_override
	var viewport_rect := get_viewport().get_visible_rect()
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if not OS.has_feature("mobile") or window.x <= 0.0 or window.y <= 0.0 or not safe.has_area():
		return viewport_rect
	var factor := viewport_rect.size / window
	var mapped := Rect2(safe.position * factor, safe.size * factor).intersection(viewport_rect)
	return mapped if mapped.has_area() else viewport_rect


## Pins the safe area to `rect` (viewport pixels), e.g. for tests or previews.
func set_safe_area(rect: Rect2) -> void:
	_safe_override = rect
	_place()


func _place() -> void:
	if not is_node_ready():
		return
	var safe := get_safe_rect()
	var width := clampf(bar_size.x, 0.0, maxf(safe.size.x - 2.0 * side_clearance, 40.0))
	_bar.size = Vector2(width, bar_size.y)
	_bar.position = Vector2(safe.position.x + (safe.size.x - width) * 0.5, safe.position.y + top_margin)
	_name.position = Vector2(0.0, -_name.size.y - 1.0)
	_name.size.x = width
	_title.size = Vector2(safe.size.x, _title.size.y)
	_title.position = Vector2(safe.position.x, safe.position.y + safe.size.y * 0.3)
	_apply()


func _apply() -> void:
	var width := _bar.size.x
	var height := _bar.size.y
	_back.size = Vector2(width, height)
	_fill.size = Vector2(width * _health_ratio, height)
	_chunk.size = Vector2(width * maxf(_chunk_ratio, _health_ratio), height)
	_fill.color = phase_two_color if is_phase_two_tint() else fill_color
	_notch.visible = _notch_ratio >= 0.0
	_notch.size = Vector2(notch_width, height + 4.0)
	_notch.position = Vector2(width * _notch_ratio - notch_width * 0.5, -2.0)


func _set_chunk_ratio(value: float) -> void:
	_chunk_ratio = value
	_apply()


func _hide_bar_if_still_hidden() -> void:
	if not _shown:
		_bar.visible = false


func _end_title() -> void:
	_title_shown = false
	_title.visible = false


func _kill(tween: Tween) -> void:
	if tween != null:
		tween.kill()

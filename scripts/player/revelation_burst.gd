class_name RevelationBurst
extends Node2D
## One-shot violet wave shown when Luz activates Revelation.

@export_range(0.4, 1.5, 0.05) var burst_duration := 0.9
@export_range(40.0, 180.0, 1.0) var max_radius := 104.0

var _elapsed := 0.0
var _active := false


func _ready() -> void:
	visible = false
	set_process(false)


func play_burst() -> void:
	_elapsed = 0.0
	_active = true
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= burst_duration:
		_active = false
		visible = false
		set_process(false)
		return
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var progress := clampf(_elapsed / burst_duration, 0.0, 1.0)
	var expansion := 1.0 - pow(1.0 - progress, 3.0)
	var fade := 1.0 - progress
	var center := Vector2(0.0, -25.0)
	var radius := lerpf(18.0, max_radius, expansion)
	_draw_segmented_ring(center, radius, 0.0, fade)
	_draw_segmented_ring(center, radius * 0.76, 0.28, fade * 0.62)
	_draw_eye_glyph(fade * clampf(1.0 - progress * 0.55, 0.0, 1.0))
	_draw_sparks(center, radius, expansion, fade)


func _draw_segmented_ring(center: Vector2, radius: float, phase: float, alpha: float) -> void:
	const SEGMENTS := 12
	const ARC_GAP := 0.12
	for index in range(SEGMENTS):
		var start := TAU * float(index) / float(SEGMENTS) + phase
		var finish := start + TAU / float(SEGMENTS) - ARC_GAP
		draw_arc(center, radius, start, finish, 12, Color(0.76, 0.28, 1.0, 0.13 * alpha), 12.0, true)
		draw_arc(center, radius, start, finish, 12, Color(0.88, 0.52, 1.0, 0.78 * alpha), 2.4, true)


func _draw_eye_glyph(alpha: float) -> void:
	var eye := PackedVector2Array([
		Vector2(-15.0, -85.0), Vector2(-7.0, -92.0), Vector2(0.0, -95.0),
		Vector2(7.0, -92.0), Vector2(15.0, -85.0), Vector2(7.0, -78.0),
		Vector2(0.0, -75.0), Vector2(-7.0, -78.0), Vector2(-15.0, -85.0)
	])
	draw_polyline(eye, Color(1.0, 0.68, 0.94, 0.9 * alpha), 2.0, true)
	draw_circle(Vector2(0.0, -85.0), 4.0, Color(1.0, 0.84, 0.37, 0.96 * alpha))
	draw_circle(Vector2(0.0, -85.0), 8.0, Color(0.8, 0.4, 1.0, 0.12 * alpha))


func _draw_sparks(center: Vector2, radius: float, expansion: float, alpha: float) -> void:
	for index in range(16):
		var phase := TAU * float(index) / 16.0
		var orbit := radius * (0.48 + 0.16 * sin(float(index) * 3.7 + _elapsed * 2.0))
		var point := center + Vector2.RIGHT.rotated(phase + _elapsed * 0.24) * orbit
		var spark_alpha := alpha * (0.45 + 0.55 * absf(sin(_elapsed * 8.0 + float(index) * 1.9)))
		draw_circle(point, 3.0 + expansion, Color(0.88, 0.42, 1.0, 0.14 * spark_alpha))
		draw_circle(point, 1.2 + expansion * 0.5, Color(1.0, 0.82, 0.98, 0.86 * spark_alpha))

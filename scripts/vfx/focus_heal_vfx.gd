class_name FocusHealVfx
extends Node2D

## Small procedural halo and rising soul motes for Luz's focus channel.

@export var radius := 20.0

var _progress := 0.0
var _elapsed := 0.0
var _flash_left := 0.0
var _active := false


func set_channel_progress(progress: float, elapsed: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_elapsed = elapsed
	_active = true
	visible = true
	queue_redraw()


func complete_channel() -> void:
	_flash_left = 0.24
	visible = true
	queue_redraw()


func cancel_channel() -> void:
	_active = false
	if _flash_left <= 0.0:
		visible = false
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _flash_left == 0.0 and not _active:
			visible = false
		queue_redraw()
	elif _active:
		_elapsed += delta
		queue_redraw()


func _draw() -> void:
	if _active:
		var swell := lerpf(0.65, 1.15, _progress)
		var breath := 0.94 + 0.06 * sin(_elapsed * 7.0)
		var alpha := 0.15 + 0.12 * _progress
		_draw_ring(radius * swell * breath, Color(1.0, 0.93, 0.68, alpha), 1.5)
		_draw_ring(radius * swell * 0.68, Color(1.0, 0.98, 0.84, alpha * 0.55), 1.0)
		for mote in 5:
			var phase := fposmod(_elapsed * 0.7 + float(mote) * 0.21, 1.0)
			var x := sin(float(mote) * 2.4 + _elapsed * 1.8) * radius * 0.55
			var y := 9.0 - phase * 24.0
			draw_circle(Vector2(x, y), 0.65 + phase * 0.5, Color(1.0, 0.95, 0.75, (1.0 - phase) * 0.72))
	if _flash_left > 0.0:
		var phase := 1.0 - _flash_left / 0.24
		var fade := 1.0 - phase
		_draw_flash(phase, fade)


func _draw_flash(phase: float, fade: float) -> void:
	draw_circle(Vector2.ZERO, 3.0 + phase * 7.0, Color(1.0, 0.98, 0.82, 0.34 * fade))
	_draw_ring(radius * (0.55 + phase * 0.8), Color(1.0, 0.93, 0.65, 0.7 * fade), 2.0)


func _draw_ring(size: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for step in 33:
		var angle := TAU * float(step) / 32.0
		points.append(Vector2(cos(angle) * size, sin(angle) * size * 0.42))
	draw_polyline(points, color, width, true)

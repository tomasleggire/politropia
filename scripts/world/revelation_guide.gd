class_name RevelationGuide
extends Node2D
## Temporary dotted path drawn from Luz to a revealed secret chest.

@export_range(0.5, 8.0, 0.1) var duration := 2.8
@export_range(0.1, 2.0, 0.1) var fade_duration := 0.55
@export_range(16.0, 48.0, 1.0) var dot_spacing := 28.0
@export_range(24.0, 220.0, 1.0) var curve_height := 82.0
@export var platform_glow_size := Vector2(58.0, 14.0)

var _route: PackedVector2Array = PackedVector2Array()
var _samples: PackedVector2Array = PackedVector2Array()
var _remaining := 0.0
var _elapsed := 0.0
var _route_length := 0.0


func _ready() -> void:
	hide_guide()


func show_route(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	_route = points.duplicate()
	_build_samples()
	_remaining = duration
	_elapsed = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func hide_guide() -> void:
	_remaining = 0.0
	visible = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining <= 0.0:
		hide_guide()
		return
	queue_redraw()


func _build_samples() -> void:
	_samples.clear()
	_route_length = 0.0
	for segment in range(_route.size() - 1):
		var start := _route[segment]
		var end := _route[segment + 1]
		var lift := curve_height if _route.size() == 2 else curve_height * 0.28
		var control := (start + end) * 0.5 + Vector2(0.0, -lift)
		var steps := maxi(12, int(ceil(start.distance_to(end) / 12.0)))
		for step in range(steps + 1):
			if segment > 0 and step == 0:
				continue
			var t := float(step) / float(steps)
			var one_minus_t := 1.0 - t
			var point := one_minus_t * one_minus_t * start \
					+ 2.0 * one_minus_t * t * control \
					+ t * t * end
			if not _samples.is_empty():
				_route_length += _samples[_samples.size() - 1].distance_to(point)
			_samples.append(point)


func _draw() -> void:
	if not visible or _samples.size() < 2 or _route_length <= 0.0:
		return
	var alpha := 1.0
	if _remaining < fade_duration:
		alpha = _remaining / fade_duration

	# Glow pads are centred on authored intermediate waypoints (if provided).
	for index in range(1, _route.size() - 1):
		var pad := Rect2(_route[index] - platform_glow_size * 0.5, platform_glow_size)
		draw_rect(pad.grow(5.0), Color(0.9, 0.34, 1.0, 0.12 * alpha), true)
		draw_rect(pad, Color(0.92, 0.42, 1.0, 0.92 * alpha), false, 2.0)
		draw_rect(pad.grow(-3.0), Color(1.0, 0.68, 1.0, 0.6 * alpha), false, 1.0)

	var distance := 0.0
	var firefly_index := 0
	while distance <= _route_length:
		var phase := float(firefly_index) * 1.73
		var point := _point_at_distance(distance)
		var tangent := (_point_at_distance(distance + 4.0) - _point_at_distance(distance - 4.0)).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var drift := sin(_elapsed * 1.4 + phase) * 3.5
		var blink := 0.18 + 0.82 * pow(maxf(0.0, sin(_elapsed * 2.6 + phase)), 2.0)
		var size := 1.4 + 1.0 * (0.5 + 0.5 * sin(phase * 2.1))
		point += normal * drift
		draw_circle(point, size * 3.2, Color(1.0, 0.64, 0.22, 0.12 * blink * alpha))
		draw_circle(point, size, Color(1.0, 0.82, 0.48, 0.82 * blink * alpha))
		distance += dot_spacing * (0.78 + 0.22 * absf(sin(phase)))
		firefly_index += 1

	# A few independent fireflies drift along the route at different speeds.
	for index in range(3):
		var travel := fposmod(_elapsed * (36.0 + float(index) * 9.0) + float(index) * _route_length / 3.0, _route_length)
		var firefly := _point_at_distance(travel)
		var blink := 0.35 + 0.65 * absf(sin(_elapsed * 3.0 + float(index) * 2.2))
		draw_circle(firefly, 6.0, Color(1.0, 0.68, 0.25, 0.13 * blink * alpha))
		draw_circle(firefly, 2.2, Color(1.0, 0.91, 0.65, 0.95 * blink * alpha))


func _point_at_distance(distance: float) -> Vector2:
	var remaining_distance := clampf(distance, 0.0, _route_length)
	for index in range(_samples.size() - 1):
		var start := _samples[index]
		var end := _samples[index + 1]
		var segment_length := start.distance_to(end)
		if remaining_distance <= segment_length:
			if segment_length <= 0.001:
				return start
			return start.lerp(end, remaining_distance / segment_length)
		remaining_distance -= segment_length
	return _samples[_samples.size() - 1]

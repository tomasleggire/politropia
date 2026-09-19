extends Control

## Draws a compact gothic analog pad. Touch handling stays in TouchControls so
## multi-touch IDs remain stable even when the finger leaves the visual bounds.

var knob_offset := Vector2.ZERO
var is_active := false
var is_drop_armed := false


func set_pad_state(offset: Vector2, active: bool, drop_armed: bool) -> void:
	knob_offset = offset
	is_active = active
	is_drop_armed = drop_armed
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var outer := 74.0
	var inner := 34.0
	var rim := Color("4f91c8") if is_active else Color(0.25, 0.44, 0.64, 0.70)
	var glow := Color("f0ae4c") if is_drop_armed else rim

	# Layered hard circles echo the environment's cobalt platform rims.
	draw_circle(center, outer + 5.0, Color(0.006, 0.012, 0.035, 0.48))
	draw_circle(center, outer, Color(0.025, 0.055, 0.12, 0.64))
	draw_arc(center, outer, 0.0, TAU, 72, Color(rim, 0.90), 2.0, true)
	draw_arc(center, outer - 8.0, 0.0, TAU, 72, Color(rim, 0.24), 1.0, true)

	_draw_chevron(center + Vector2(0, 61), Vector2(0, 1), glow, is_drop_armed)

	var knob_center := center + knob_offset
	draw_circle(knob_center, inner + 4.0, Color(0.0, 0.0, 0.02, 0.56))
	draw_circle(knob_center, inner, Color(0.055, 0.12, 0.23, 0.90))
	draw_arc(knob_center, inner, 0.0, TAU, 48, Color(glow, 0.95), 2.0, true)
	draw_circle(knob_center, 8.0, Color(glow, 0.72))


func _draw_chevron(origin: Vector2, direction: Vector2, color: Color, selected: bool) -> void:
	var normal := Vector2(-direction.y, direction.x).normalized()
	var tip := origin + direction.normalized() * 8.0
	var back := origin - direction.normalized() * 5.0
	var points := PackedVector2Array([
		back + normal * 6.0,
		tip,
		back - normal * 6.0,
	])
	draw_polyline(
		points,
		Color(color, 1.0 if selected else 0.48),
		3.0 if selected else 2.0,
		true
	)

extends Node2D

## Small hand-drawn candle with restrained flicker and layered warm bloom.

var phase_offset := 0.0
var height := 18.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var time := Time.get_ticks_msec() * 0.001 + phase_offset
	var sway := sin(time * 4.7) * 1.4 + sin(time * 2.1) * 0.6
	var pulse := 0.88 + sin(time * 5.3) * 0.08
	var flame_center := Vector2(sway, -height - 6.0)

	# Several hard-edged translucent circles read as pixel-art bloom at game scale.
	draw_circle(flame_center, 22.0 * pulse, Color(0.92, 0.35, 0.08, 0.035))
	draw_circle(flame_center, 13.0 * pulse, Color(1.0, 0.49, 0.12, 0.075))
	draw_circle(flame_center, 7.0 * pulse, Color(1.0, 0.68, 0.24, 0.13))

	draw_rect(Rect2(-3.0, -height, 6.0, height), Color("b7834f"))
	draw_rect(Rect2(-2.0, -height + 2.0, 2.0, height - 3.0), Color("e5bd77"))
	draw_rect(Rect2(-5.0, -2.0, 10.0, 2.0), Color("342039"))
	draw_line(Vector2(0.0, -height - 1.0), Vector2(0.0, -height - 4.0), Color("20131b"), 1.0)

	var flame := PackedVector2Array([
		flame_center + Vector2(0.0, -7.0 * pulse),
		flame_center + Vector2(3.2, 1.2),
		flame_center + Vector2(0.0, 4.5),
		flame_center + Vector2(-3.2, 1.2),
	])
	draw_colored_polygon(flame, Color("f0ae4c"))
	draw_circle(flame_center + Vector2(0.0, 0.8), 1.8, Color("fff0b0"))

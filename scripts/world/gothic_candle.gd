class_name GothicCandle
extends Node2D

## Small hand-drawn candle with restrained flicker and layered warm bloom.
## With `candelabra` set it becomes a tall three-candle iron stand drawn on the
## art's texel grid, used to flank the Stillness Desk arch.

const TEXEL := 0.175
const IRON_DARK := Color("2a2230")
const IRON_MID := Color("54402f")
const IRON_LIT := Color("b98a4a")
const WAX := Color("d9c9a0")
const WAX_SHADE := Color("a8916a")

@export_group("Candle")
@export var phase_offset := 0.0
@export var height := 18.0

@export_group("Candelabra")
@export var candelabra := false
## Stand height in world units, floor to the rim of the candle cups.
@export_range(30.0, 120.0, 1.0) var stand_height := 74.0
## Which side the light shaft is on: 1 lights the right edge, -1 the left.
@export_range(-1, 1, 2) var lit_side := 1
## Brightness of the flames' glow; the desk FX raise it as the altar wakes.
@export_range(0.0, 2.0, 0.05) var energy := 1.0

@onready var _glow: Node2D = get_node_or_null("Glow") as Node2D


func _process(_delta: float) -> void:
	queue_redraw()
	if candelabra and _glow != null:
		var time := Time.get_ticks_msec() * 0.001 + phase_offset
		var flicker := sin(time * 7.3) * 0.08 + sin(time * 3.1 + 1.2) * 0.06
		_glow.modulate.a = clampf((0.75 + flicker) * energy, 0.0, 1.6)


func _draw() -> void:
	var time := Time.get_ticks_msec() * 0.001 + phase_offset
	if candelabra:
		_draw_candelabra(time)
		return
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


# -- Candelabra ----------------------------------------------------------------
# Everything below is drawn in texels (one art pixel = TEXEL world units), y up
# is negative, origin at the foot.

func _draw_candelabra(time: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * TEXEL)
	var top := stand_height / TEXEL
	var side := float(lit_side)
	var arm_y := -(top - 26.0)
	_draw_stand(top, arm_y, side)
	var cups: Array[Vector2] = [Vector2(0.0, arm_y - 8.0), Vector2(-44.0, arm_y + 4.0), Vector2(44.0, arm_y + 4.0)]
	var candle_heights: Array[float] = [54.0, 42.0, 42.0]
	for i: int in cups.size():
		_draw_candle(cups[i], candle_heights[i], side, time + float(i) * 0.9)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stand(top: float, arm_y: float, side: float) -> void:
	# Foot, stem, two knops and the two curved arms.
	draw_colored_polygon(PackedVector2Array([Vector2(-36, 0), Vector2(36, 0), Vector2(26, -14), Vector2(-26, -14)]), IRON_DARK)
	draw_colored_polygon(PackedVector2Array([Vector2(-20, -14), Vector2(20, -14), Vector2(13, -32), Vector2(-13, -32)]), IRON_MID)
	draw_rect(Rect2(-4, arm_y, 8, -arm_y - 32.0), IRON_DARK)
	draw_rect(Rect2(2.0 if side > 0.0 else -4.0, arm_y, 2, -arm_y - 32.0), IRON_LIT)
	for knop_y: float in [-top * 0.28, -top * 0.58]:
		draw_rect(Rect2(-9, knop_y, 18, 10), IRON_MID)
		draw_rect(Rect2(side * 5.0 - 1.0, knop_y, 3, 10), IRON_LIT)
	for arm_side: float in [-1.0, 1.0]:
		var arm := PackedVector2Array([
			Vector2(0, arm_y + 10), Vector2(arm_side * 14.0, arm_y + 18), Vector2(arm_side * 32.0, arm_y + 14), Vector2(arm_side * 44.0, arm_y + 6),
		])
		draw_polyline(arm, IRON_DARK, 5.0)
		if arm_side == side:
			draw_polyline(arm, IRON_LIT, 2.0)
		draw_rect(Rect2(arm_side * 44.0 - 9.0, arm_y + 4.0, 18, 6), IRON_MID)
	draw_rect(Rect2(-10, arm_y - 8.0, 20, 6), IRON_MID)


func _draw_candle(cup: Vector2, candle_height: float, side: float, time: float) -> void:
	var top := cup + Vector2(0.0, -candle_height)
	draw_rect(Rect2(cup.x - 5.0, top.y, 10, candle_height), WAX)
	draw_rect(Rect2(cup.x - 5.0 if side < 0.0 else cup.x + 1.0, top.y, 4, candle_height), WAX_SHADE)
	var sway := sin(time * 4.7) * 2.0 + sin(time * 2.1) * 1.0
	var pulse := 0.9 + sin(time * 5.3) * 0.1
	var flame_center := top + Vector2(sway, -12.0)
	draw_circle(flame_center, 30.0 * pulse * energy, Color(1.0, 0.49, 0.12, 0.06))
	draw_circle(flame_center, 16.0 * pulse * energy, Color(1.0, 0.68, 0.24, 0.12))
	draw_colored_polygon(PackedVector2Array([
		flame_center + Vector2(0.0, -14.0 * pulse), flame_center + Vector2(7.0, 2.0),
		flame_center + Vector2(0.0, 9.0), flame_center + Vector2(-7.0, 2.0),
	]), Color("f0ae4c"))
	draw_circle(flame_center + Vector2(0.0, 2.0), 3.5, Color("fff0b0"))

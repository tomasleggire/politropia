class_name CollectibleLockBadge
extends Control

## Small padlock drawn as a non-color indicator for locked collectibles.
## It deliberately lives outside the icon control so the silhouette shader
## cannot tint the badge and make it disappear.

const BADGE_COLOR := Color(0.94902, 0.921569, 0.85098, 1.0)
const SHACKLE_COLOR := Color(0.878431, 0.72549, 0.309804, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var extent := minf(size.x, size.y)
	if extent <= 2.0:
		return
	var center := size * 0.5
	var body_size := Vector2(extent * 0.58, extent * 0.42)
	var body_rect := Rect2(center - body_size * 0.5 + Vector2(0.0, extent * 0.10), body_size)
	var shackle_radius := extent * 0.23
	var shackle_center := body_rect.position + Vector2(body_rect.size.x * 0.5, 0.0)
	draw_arc(
		shackle_center,
		shackle_radius,
		PI,
		TAU,
		16,
		SHACKLE_COLOR,
		maxf(2.0, extent * 0.11),
		true
	)
	draw_rect(body_rect, BADGE_COLOR)
	var keyhole := center + Vector2(0.0, extent * 0.10)
	draw_circle(keyhole, maxf(1.4, extent * 0.07), Color(0.043137, 0.062745, 0.12549, 1.0))
	draw_rect(
		Rect2(keyhole + Vector2(-extent * 0.025, 0.0), Vector2(extent * 0.05, extent * 0.12)),
		Color(0.043137, 0.062745, 0.12549, 1.0)
	)

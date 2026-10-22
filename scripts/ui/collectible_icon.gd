class_name CollectibleIcon
extends Control

## Draws the provisional art of a collectible: the optional texture from its
## definition, or a colored gem when the image is empty. Locked items are drawn
## as dark silhouettes so the gallery never reveals their final art.

var definition: CollectibleDefinition
var locked := false
var accent_color := Color(0.36, 0.85, 0.95, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Updates what this control draws. Call it again after changing the state.
func set_definition(value: CollectibleDefinition, is_locked: bool, accent := Color(0.36, 0.85, 0.95, 1.0)) -> void:
	definition = value
	locked = is_locked
	accent_color = accent
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	if radius <= 1.0:
		return

	if locked:
		_draw_silhouette(center, radius)
	elif definition != null and definition.image != null:
		_draw_texture(center)
	else:
		_draw_gem(center, radius)


func _draw_texture(center: Vector2) -> void:
	var texture_size := definition.image.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var available := size * 0.86
	var factor := minf(available.x / texture_size.x, available.y / texture_size.y)
	var draw_size := texture_size * factor
	var draw_rect := Rect2(center - draw_size * 0.5, draw_size)
	draw_texture_rect(definition.image, draw_rect, false)


func _draw_gem(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 1.18, Color(accent_color, 0.1))
	var points := _diamond(center, radius)
	draw_colored_polygon(points, accent_color.darkened(0.35))
	var top := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.72, 0.0),
		center,
		center + Vector2(-radius * 0.72, 0.0),
	])
	var bottom := PackedVector2Array([
		center + Vector2(-radius * 0.72, 0.0),
		center,
		center + Vector2(radius * 0.72, 0.0),
		center + Vector2(0.0, radius),
	])
	draw_colored_polygon(top, accent_color.lightened(0.18))
	draw_colored_polygon(bottom, accent_color.darkened(0.12))
	var facet := PackedVector2Array([
		center + Vector2(-radius * 0.28, -radius * 0.18),
		center + Vector2(radius * 0.16, -radius * 0.32),
		center + Vector2(radius * 0.3, radius * 0.02),
		center + Vector2(-radius * 0.1, radius * 0.18),
	])
	draw_colored_polygon(facet, Color(1.0, 1.0, 1.0, 0.55))
	draw_polyline(_closed(points), accent_color.lightened(0.45), 1.4, true)


func _draw_silhouette(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 1.12, Color(0.02, 0.05, 0.09, 0.55))
	var points := _diamond(center, radius)
	draw_colored_polygon(points, Color(0.025, 0.055, 0.1, 1.0))
	draw_polyline(_closed(points), Color(0.16, 0.24, 0.33, 1.0), 1.2, true)
	var inner := PackedVector2Array([
		center + Vector2(-radius * 0.3, radius * 0.05),
		center + Vector2(0.0, -radius * 0.22),
		center + Vector2(radius * 0.3, radius * 0.05),
	])
	draw_polyline(inner, Color(0.1, 0.17, 0.25, 1.0), 1.0, true)


func _diamond(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.72, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius * 0.72, 0.0),
	])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not closed.is_empty():
		closed.append(closed[0])
	return closed

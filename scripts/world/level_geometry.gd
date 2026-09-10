class_name LevelGeometry
extends RefCounted

## Utilidad para armar colisiones y visuales sólidos de forma prolija.


static func add_solid(
	parent: Node2D,
	rect: Rect2,
	color: Color,
	texture: Texture2D = null
) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5

	var shape := RectangleShape2D.new()
	shape.size = rect.size

	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	var half := rect.size * 0.5
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

	if texture != null:
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		visual.uv = PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(rect.size.x, 0.0),
			Vector2(rect.size.x, rect.size.y),
			Vector2(0.0, rect.size.y),
		])
		visual.color = Color(1, 1, 1, 1)
	else:
		visual.color = color

	body.add_child(visual)
	parent.add_child(body)
	return body


static func add_forest_background(
	parent: Node2D,
	room: Vector2i,
	room_size: Vector2,
	color: Color,
	forest_tex: Texture2D,
	tree_tex: Texture2D = null,
	bush_tex: Texture2D = null
) -> void:
	var origin := Vector2(room) * room_size

	var base := Polygon2D.new()
	base.z_index = -30
	base.color = color
	base.polygon = PackedVector2Array([
		origin,
		origin + Vector2(room_size.x, 0.0),
		origin + room_size,
		origin + Vector2(0.0, room_size.y),
	])
	parent.add_child(base)

	var bg := Sprite2D.new()
	bg.z_index = -25
	bg.texture = forest_tex
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.centered = true
	bg.position = origin + room_size * 0.5
	bg.scale = room_size / Vector2(forest_tex.get_size())
	bg.modulate = Color(0.55, 0.65, 0.55, 1.0)
	parent.add_child(bg)

	if tree_tex != null:
		var tree_spots := [
			Vector2(0.10, 0.78),
			Vector2(0.26, 0.74),
			Vector2(0.44, 0.80),
			Vector2(0.62, 0.73),
			Vector2(0.80, 0.77),
			Vector2(0.18, 0.48),
			Vector2(0.72, 0.46),
			Vector2(0.50, 0.55),
		]
		for ratio in tree_spots:
			var tree := Sprite2D.new()
			tree.z_index = -20
			tree.texture = tree_tex
			tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tree.centered = true
			tree.offset = Vector2(0, -tree_tex.get_height() * 0.4)
			tree.position = origin + Vector2(room_size.x * ratio.x, room_size.y * ratio.y)
			var scale_factor: float = 1.3 + ratio.x * 0.2
			tree.scale = Vector2(scale_factor, scale_factor)
			tree.modulate = Color(0.7, 0.85, 0.7, 0.95)
			parent.add_child(tree)

	if bush_tex != null:
		var bush_spots := [
			Vector2(0.20, 0.92),
			Vector2(0.48, 0.94),
			Vector2(0.76, 0.91),
		]
		for ratio in bush_spots:
			var bush := Sprite2D.new()
			bush.z_index = -18
			bush.texture = bush_tex
			bush.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			bush.centered = true
			bush.position = origin + Vector2(room_size.x * ratio.x, room_size.y * ratio.y)
			bush.scale = Vector2(1.2, 1.2)
			bush.modulate = Color(0.55, 0.7, 0.5, 0.85)
			parent.add_child(bush)

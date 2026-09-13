class_name LevelGeometry
extends RefCounted

## Geometría visual y física construida con colores planos, sin texturas de mundo.

const WALL_THICKNESS := 42.0
const DOOR_GAP := 188.0
const DOOR_TRIM := Color(0.85, 0.68, 0.34, 0.82)
const SHADOW := Color(0.015, 0.02, 0.025, 0.34)


static func add_room(
	background_parent: Node2D,
	solid_parent: Node2D,
	decor_parent: Node2D,
	room: Vector2i,
	room_size: Vector2,
	floor_color: Color,
	wall_color: Color,
	openings: Array[StringName]
) -> void:
	var origin := Vector2(room) * room_size
	_add_rect_visual(background_parent, Rect2(origin, room_size), floor_color, -30)
	_add_rect_visual(
		background_parent,
		Rect2(origin + Vector2(20, 20), room_size - Vector2(40, 40)),
		floor_color.lightened(0.035),
		-29
	)
	_add_floor_pattern(decor_parent, origin, room_size, floor_color.lightened(0.13))

	_add_horizontal_wall(solid_parent, decor_parent, origin, room_size, true, wall_color, openings.has(&"top"))
	_add_horizontal_wall(solid_parent, decor_parent, origin, room_size, false, wall_color, openings.has(&"bottom"))
	_add_vertical_wall(solid_parent, decor_parent, origin, room_size, true, wall_color, openings.has(&"left"))
	_add_vertical_wall(solid_parent, decor_parent, origin, room_size, false, wall_color, openings.has(&"right"))

	for side in openings:
		_add_door_trim(decor_parent, origin, room_size, side)


static func add_solid_rect(parent: Node2D, rect: Rect2, color: Color, shadow := true) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	if shadow:
		var shadow_visual := _polygon_rect(rect.size, SHADOW)
		shadow_visual.position = Vector2(0, 9)
		shadow_visual.z_index = -1
		body.add_child(shadow_visual)

	var visual := _polygon_rect(rect.size, color)
	body.add_child(visual)
	parent.add_child(body)
	return body


static func add_circle_obstacle(parent: Node2D, center: Vector2, radius: float, color: Color) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	var shadow_visual := Polygon2D.new()
	shadow_visual.polygon = circle_points(radius, 24)
	shadow_visual.color = SHADOW
	shadow_visual.position = Vector2(0, 9)
	shadow_visual.z_index = -1
	body.add_child(shadow_visual)

	var visual := Polygon2D.new()
	visual.polygon = circle_points(radius, 24)
	visual.color = color
	body.add_child(visual)

	var cap := Polygon2D.new()
	cap.polygon = circle_points(radius * 0.58, 20)
	cap.color = color.lightened(0.12)
	cap.position = Vector2(-radius * 0.12, -radius * 0.16)
	body.add_child(cap)

	parent.add_child(body)
	return body


static func add_decor_circle(parent: Node2D, center: Vector2, radius: float, color: Color, z := -5) -> Polygon2D:
	var visual := Polygon2D.new()
	visual.position = center
	visual.polygon = circle_points(radius, 20)
	visual.color = color
	visual.z_index = z
	parent.add_child(visual)
	return visual


static func circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _add_horizontal_wall(
	solid_parent: Node2D,
	decor_parent: Node2D,
	origin: Vector2,
	room_size: Vector2,
	is_top: bool,
	color: Color,
	is_open: bool
) -> void:
	var y := origin.y if is_top else origin.y + room_size.y - WALL_THICKNESS
	if is_open:
		var half := (room_size.x - DOOR_GAP) * 0.5
		add_solid_rect(solid_parent, Rect2(origin.x, y, half, WALL_THICKNESS), color, false)
		add_solid_rect(solid_parent, Rect2(origin.x + half + DOOR_GAP, y, half, WALL_THICKNESS), color, false)
	else:
		add_solid_rect(solid_parent, Rect2(origin.x, y, room_size.x, WALL_THICKNESS), color, false)
	_add_wall_highlight(decor_parent, Rect2(origin.x, y, room_size.x, WALL_THICKNESS), is_top)


static func _add_vertical_wall(
	solid_parent: Node2D,
	decor_parent: Node2D,
	origin: Vector2,
	room_size: Vector2,
	is_left: bool,
	color: Color,
	is_open: bool
) -> void:
	var x := origin.x if is_left else origin.x + room_size.x - WALL_THICKNESS
	if is_open:
		var half := (room_size.y - DOOR_GAP) * 0.5
		add_solid_rect(solid_parent, Rect2(x, origin.y, WALL_THICKNESS, half), color, false)
		add_solid_rect(solid_parent, Rect2(x, origin.y + half + DOOR_GAP, WALL_THICKNESS, half), color, false)
	else:
		add_solid_rect(solid_parent, Rect2(x, origin.y, WALL_THICKNESS, room_size.y), color, false)
	var edge_color := Color(1, 1, 1, 0.055)
	var edge_x := x + WALL_THICKNESS - 5.0 if is_left else x
	_add_rect_visual(decor_parent, Rect2(edge_x, origin.y, 5, room_size.y), edge_color, 1)


static func _add_door_trim(parent: Node2D, origin: Vector2, room_size: Vector2, side: StringName) -> void:
	var center := origin + room_size * 0.5
	var rect := Rect2()
	match side:
		&"top":
			rect = Rect2(center.x - DOOR_GAP * 0.5, origin.y + WALL_THICKNESS - 7, DOOR_GAP, 7)
		&"bottom":
			rect = Rect2(center.x - DOOR_GAP * 0.5, origin.y + room_size.y - WALL_THICKNESS, DOOR_GAP, 7)
		&"left":
			rect = Rect2(origin.x + WALL_THICKNESS - 7, center.y - DOOR_GAP * 0.5, 7, DOOR_GAP)
		&"right":
			rect = Rect2(origin.x + room_size.x - WALL_THICKNESS, center.y - DOOR_GAP * 0.5, 7, DOOR_GAP)
	_add_rect_visual(parent, rect, DOOR_TRIM, 2)


static func _add_wall_highlight(parent: Node2D, rect: Rect2, is_top: bool) -> void:
	var y := rect.position.y + rect.size.y - 5.0 if is_top else rect.position.y
	_add_rect_visual(parent, Rect2(rect.position.x, y, rect.size.x, 5), Color(1, 1, 1, 0.06), 1)


static func _add_floor_pattern(parent: Node2D, origin: Vector2, room_size: Vector2, color: Color) -> void:
	for row in 7:
		for column in 4:
			if (row + column) % 3 != 0:
				continue
			var center := origin + Vector2(115 + column * 160, 130 + row * 155)
			var radius := 6.0 + float((row * 5 + column * 3) % 5)
			add_decor_circle(parent, center, radius, Color(color.r, color.g, color.b, 0.14), -9)


static func _add_rect_visual(parent: Node2D, rect: Rect2, color: Color, z: int) -> Polygon2D:
	var visual := Polygon2D.new()
	visual.position = rect.position + rect.size * 0.5
	visual.polygon = PackedVector2Array([
		-rect.size * 0.5,
		Vector2(rect.size.x * 0.5, -rect.size.y * 0.5),
		rect.size * 0.5,
		Vector2(-rect.size.x * 0.5, rect.size.y * 0.5),
	])
	visual.color = color
	visual.z_index = z
	parent.add_child(visual)
	return visual


static func _polygon_rect(size: Vector2, color: Color) -> Polygon2D:
	var half := size * 0.5
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	visual.color = color
	return visual

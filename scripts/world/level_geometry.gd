class_name LevelGeometry
extends RefCounted

## Utilidad para armar colisiones y visuales sólidos de forma prolija.

const TILE_PX := 64.0
const STONE_TINT := Color("b7c9df")
const STONE_SHADOW := Color("02040b")
const EDGE_BLUE := Color("4f91c8")
const EDGE_BLUE_HOT := Color("78b8df")
const RUNE_AMBER := Color("d8792e")


static func add_solid(
	parent: Node2D,
	rect: Rect2,
	color: Color,
	texture: Texture2D = null
) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = rect.size

	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)

	if texture != null:
		_add_stone_visual(body, rect.size, texture, color, false)
	else:
		var half := rect.size * 0.5
		var visual := Polygon2D.new()
		visual.color = color
		visual.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
		body.add_child(visual)

	parent.add_child(body)
	return body


static func add_one_way_platform(
	parent: Node2D,
	rect: Rect2,
	color: Color,
	texture: Texture2D = null
) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("one_way", true)

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.one_way_collision = true
	collision.one_way_collision_margin = 12.0
	body.add_child(collision)

	if texture != null:
		_add_stone_visual(body, rect.size, texture, color, true)
	else:
		var half := rect.size * 0.5
		var visual := Polygon2D.new()
		visual.color = color
		visual.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
		body.add_child(visual)
	parent.add_child(body)
	return body


static func _add_stone_visual(
	body: StaticBody2D,
	size: Vector2,
	texture: Texture2D,
	tint: Color,
	is_one_way: bool
) -> void:
	var half := size * 0.5
	var tex_w := float(texture.get_width())
	var tex_h := float(texture.get_height())

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		0.0,
		0.0,
		(size.x / TILE_PX) * tex_w,
		(size.y / TILE_PX) * tex_h
	)
	sprite.scale = Vector2(TILE_PX / tex_w, TILE_PX / tex_h)
	sprite.modulate = STONE_TINT.lerp(tint, 0.28)
	body.add_child(sprite)

	# The cool cap is the gameplay read: it keeps every walkable edge visible
	# without flattening the masonry into a bright rectangle.
	var cap := Polygon2D.new()
	cap.z_index = 2
	cap.color = EDGE_BLUE_HOT if is_one_way else EDGE_BLUE
	cap.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, -half.y + (3.0 if is_one_way else 4.0)),
		Vector2(-half.x, -half.y + (3.0 if is_one_way else 4.0)),
	])
	body.add_child(cap)

	var bevel := Polygon2D.new()
	bevel.z_index = 1
	bevel.color = Color(0.08, 0.18, 0.31, 0.72)
	bevel.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y + 4.0),
		Vector2(half.x, -half.y + 4.0),
		Vector2(half.x, -half.y + 10.0),
		Vector2(-half.x, -half.y + 10.0),
	])
	body.add_child(bevel)

	var lower_shadow := Polygon2D.new()
	lower_shadow.z_index = 1
	lower_shadow.color = Color(STONE_SHADOW, 0.58)
	lower_shadow.polygon = PackedVector2Array([
		Vector2(-half.x, half.y - minf(12.0, size.y * 0.3)),
		Vector2(half.x, half.y - minf(12.0, size.y * 0.3)),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	body.add_child(lower_shadow)

	if is_one_way:
		_add_platform_runes(body, size)


static func _add_platform_runes(body: StaticBody2D, size: Vector2) -> void:
	var count := maxi(1, floori(size.x / 58.0))
	var spacing := size.x / float(count + 1)
	for i in count:
		var center_x := -size.x * 0.5 + spacing * float(i + 1)
		var rune := Line2D.new()
		rune.z_index = 3
		rune.width = 1.5
		rune.default_color = Color(RUNE_AMBER, 0.72)
		rune.antialiased = false
		rune.points = PackedVector2Array([
			Vector2(center_x - 5.0, -size.y * 0.5 + 8.0),
			Vector2(center_x, -size.y * 0.5 + 4.0),
			Vector2(center_x + 5.0, -size.y * 0.5 + 8.0),
		])
		body.add_child(rune)


static func add_color_rect(parent: Node2D, rect: Rect2, color: Color, z_index := -20) -> Polygon2D:
	var visual := Polygon2D.new()
	visual.z_index = z_index
	visual.color = color
	visual.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
	parent.add_child(visual)
	return visual


static func add_flat_background(
	parent: Node2D,
	room: Vector2i,
	room_size: Vector2,
	color: Color
) -> void:
	var origin := Vector2(room) * room_size
	var visual := Polygon2D.new()
	visual.z_index = -20
	visual.color = color
	visual.polygon = PackedVector2Array([
		origin,
		origin + Vector2(room_size.x, 0.0),
		origin + room_size,
		origin + Vector2(0.0, room_size.y),
	])
	parent.add_child(visual)


static func add_atmosphere_background(
	parent: Node2D,
	room: Vector2i,
	room_size: Vector2,
	top_color: Color,
	bottom_color: Color,
	accent_color: Color
) -> void:
	var origin := Vector2(room) * room_size
	var bands := 8
	for i in bands:
		var t0 := float(i) / float(bands)
		var t1 := float(i + 1) / float(bands)
		var y0 := origin.y + room_size.y * t0
		var y1 := origin.y + room_size.y * t1
		var c := top_color.lerp(bottom_color, (t0 + t1) * 0.5)
		var band := Polygon2D.new()
		band.z_index = -20
		band.color = c
		band.polygon = PackedVector2Array([
			Vector2(origin.x, y0),
			Vector2(origin.x + room_size.x, y0),
			Vector2(origin.x + room_size.x, y1),
			Vector2(origin.x, y1),
		])
		parent.add_child(band)

	# Siluetas lejanas (no colliders).
	for i in 5:
		var sil := Polygon2D.new()
		sil.z_index = -18
		sil.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.18)
		var w := 40.0 + float(i) * 18.0
		var h := 120.0 + float((i * 37) % 90)
		var x := origin.x + 80.0 + float(i) * 120.0
		var y := origin.y + room_size.y - 80.0
		sil.polygon = PackedVector2Array([
			Vector2(x, y),
			Vector2(x + w * 0.5, y - h),
			Vector2(x + w, y),
		])
		parent.add_child(sil)


static func add_dust_motes(
	parent: Node2D,
	room: Vector2i,
	room_size: Vector2,
	count: int,
	color: Color
) -> void:
	var origin := Vector2(room) * room_size
	var dust := Node2D.new()
	dust.z_index = -10
	dust.set_script(load("res://scripts/world/dust_motes.gd"))
	dust.set("room_origin", origin)
	dust.set("room_size", room_size)
	dust.set("mote_count", count)
	dust.set("mote_color", color)
	parent.add_child(dust)


static func add_broken_ledge(
	parent: Node2D,
	rect: Rect2,
	color: Color,
	texture: Texture2D = null
) -> void:
	# Plataforma “rota”: visual irregular + collider un poco más corto.
	add_solid(parent, rect, color, texture)
	var chip := Polygon2D.new()
	chip.z_index = 1
	chip.color = Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, 1.0)
	var tip := rect.position + Vector2(rect.size.x + 8.0, rect.size.y * 0.5)
	chip.polygon = PackedVector2Array([
		tip + Vector2(-18, -10),
		tip + Vector2(10, 0),
		tip + Vector2(-18, 10),
	])
	parent.add_child(chip)

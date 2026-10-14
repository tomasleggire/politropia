class_name ZoneBounds
extends RefCounted

## Finds the area a zone's camera can roam, from its CameraRegion areas
## (`camara_region.gd`): the union of every region's limits. Shared by the
## ambience and parallax prefabs so they need no per-zone numbers.

const MIN_SIZE := Vector2(400.0, 200.0)


## Union of the camera limits of every region under `zone`. A zone without
## regions falls back to the extent of its painted tiles, then to `fallback`.
static func find_rect(zone: Node, fallback: Rect2) -> Rect2:
	if zone == null:
		return fallback
	var found := false
	var left := INF
	var top := INF
	var right := -INF
	var bottom := -INF
	for node: Node in zone.find_children("*", "Area2D", true, false):
		if not "limite_izquierdo" in node:
			continue
		found = true
		left = minf(left, float(node.get("limite_izquierdo")))
		top = minf(top, float(node.get("limite_superior")))
		right = maxf(right, float(node.get("limite_derecho")))
		bottom = maxf(bottom, float(node.get("limite_inferior")))
	if not found:
		return _tile_rect(zone, fallback)
	var rect := Rect2(left, top, right - left, bottom - top)
	if rect.size.x < MIN_SIZE.x or rect.size.y < MIN_SIZE.y:
		return _tile_rect(zone, fallback)
	return rect


## Bounding box of every non-empty TileMapLayer, in the zone's local space.
static func _tile_rect(zone: Node, fallback: Rect2) -> Rect2:
	var rect := Rect2()
	var any := false
	for node: Node in zone.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		var used := layer.get_used_rect()
		if layer.tile_set == null or used.size == Vector2i.ZERO:
			continue
		var cell := Vector2(layer.tile_set.tile_size)
		var local := Rect2(Vector2(used.position) * cell, Vector2(used.size) * cell)
		var world := (layer.global_transform * local) if layer.is_inside_tree() else local
		rect = world if not any else rect.merge(world)
		any = true
	if not any or rect.size.x < MIN_SIZE.x or rect.size.y < MIN_SIZE.y:
		return fallback
	return rect

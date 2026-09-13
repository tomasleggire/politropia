class_name RoomPathfinder
extends RefCounted

## A* de una habitación: las celdas sólidas salen de la geometría física real.

const CELL := 40.0

var origin := Vector2.ZERO
var size := Vector2.ZERO

var _grid: AStarGrid2D
var _cols := 0
var _rows := 0


func build(world: World2D, room_origin: Vector2, room_size: Vector2) -> void:
	origin = room_origin
	size = room_size
	_cols = int(room_size.x / CELL)
	_rows = int(room_size.y / CELL)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _cols, _rows)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = room_origin
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()

	var space := world.direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 17.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for y in _rows:
		for x in _cols:
			var center := origin + Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
			query.transform = Transform2D(0.0, center)
			if not space.intersect_shape(query, 1).is_empty():
				_grid.set_point_solid(Vector2i(x, y), true)
	_grid.update()


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _grid == null:
		return PackedVector2Array()
	var start := _nearest_open(_cell_for(from))
	var goal := _nearest_open(_cell_for(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector2Array()
	var cells := _grid.get_id_path(start, goal)
	var points := PackedVector2Array()
	for cell in cells:
		points.append(origin + Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * CELL)
	return points


func _cell_for(world_position: Vector2) -> Vector2i:
	var local := world_position - origin
	return Vector2i(
		clampi(int(local.x / CELL), 0, _cols - 1),
		clampi(int(local.y / CELL), 0, _rows - 1)
	)


func _nearest_open(cell: Vector2i) -> Vector2i:
	if _is_open(cell):
		return cell
	for radius in range(1, 8):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var candidate := cell + Vector2i(x, y)
				if _is_open(candidate):
					return candidate
	return Vector2i(-1, -1)


func _is_open(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= _cols or cell.y >= _rows:
		return false
	return not _grid.is_point_solid(cell)

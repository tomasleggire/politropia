@tool
class_name SecretChamber
extends Node2D

## Dark back wall for a secret room carved out of the solid tiles, plus the
## cover that hides the room until its wall is broken.
## Drop `scenes/world/secret_chamber.tscn` over the carved space: the node's
## position is its TOP-LEFT corner and `size` its width and height in pixels
## (a multiple of the tile size, 8). It sits behind the tiles (z_index -1).
##
## HIDING: the carved space would show the room from outside. Set
## `source_layer` (path from this node to the zone's solid TileMapLayer, usually
## `../TilemapLayers/Ground/Platforms`) and `cover_sample_offset`, a shift in
## tiles to a patch of plain solid fill (a multiple of 8 keeps the tile pattern
## aligned). The chamber paints that patch over itself, so it looks like solid
## wall, and fades it out when the wall named in `reveal_wall_id` breaks.
##
## Put a `BreakableWall` at the entrance (same id in `reveal_wall_id`), a
## `SoulCache` inside, and tune the glow from the chest's own light.

@export var size := Vector2(112.0, 80.0):
	set(value):
		size = value
		queue_redraw()
## Back wall colour; a touch lighter than the black tiles around it.
@export var color := Color(0.055, 0.042, 0.05):
	set(value):
		color = value
		queue_redraw()
## Width in pixels of the darker band that frames the room.
@export_range(0.0, 24.0, 1.0) var rim_width := 10.0:
	set(value):
		rim_width = value
		queue_redraw()

@export_group("Cover")
## Path from this node to the zone's solid TileMapLayer.
@export var source_layer: NodePath
## Tiles to shift from this room to reach a patch of plain solid fill.
@export var cover_sample_offset := Vector2i.ZERO
## `wall_id` of the BreakableWall that reveals the room when it breaks.
@export var reveal_wall_id: StringName = &""
@export_range(0.05, 3.0, 0.05) var reveal_time := 0.7

signal revealed

const GROUP := &"secret_chambers"

var _cover: CanvasItem


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	var progress := get_node_or_null("/root/SecretProgress")
	if progress == null or reveal_wall_id.is_empty() or progress.is_wall_broken(reveal_wall_id):
		return
	_cover = _build_cover()
	if _cover != null:
		progress.wall_broken.connect(_on_wall_broken)


func is_covered() -> bool:
	return is_instance_valid(_cover)


## True when the world point lies inside the room.
func contains(point: Vector2) -> bool:
	return Rect2(global_position, size).has_point(point)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var steps := int(rim_width / 2.0)
	for i in steps:
		var inset := float(i) * 2.0
		var band := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
		draw_rect(band, Color(0.0, 0.0, 0.0, 0.225 * (1.0 - float(i) / float(steps))), false, 2.0)


func _build_cover() -> CanvasItem:
	var source := get_node_or_null(source_layer) as TileMapLayer
	if source == null:
		var flat := ColorRect.new()
		flat.color = Color.BLACK
		flat.size = size
		add_child(flat)
		return flat
	var layer := TileMapLayer.new()
	layer.name = "RoomCover"
	layer.tile_set = source.tile_set
	layer.collision_enabled = false
	layer.navigation_enabled = false
	var first := source.local_to_map(source.to_local(global_position + Vector2.ONE * 0.5))
	var last := source.local_to_map(source.to_local(global_position + size - Vector2.ONE * 0.5))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var sample := Vector2i(x, y) + cover_sample_offset
			var source_id := source.get_cell_source_id(sample)
			if source_id != -1:
				layer.set_cell(Vector2i(x, y), source_id, source.get_cell_atlas_coords(sample), source.get_cell_alternative_tile(sample))
	source.add_child(layer)
	return layer


func _on_wall_broken(wall_id: StringName) -> void:
	if wall_id != reveal_wall_id or not is_instance_valid(_cover):
		return
	revealed.emit()
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", 0.0, reveal_time)
	tween.tween_callback(_cover.queue_free)

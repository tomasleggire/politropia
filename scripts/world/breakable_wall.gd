@tool
class_name BreakableWall
extends StaticBody2D

## A wall Luz can break with her attack, hiding a secret room behind it.
## Drag `scenes/world/breakable_wall.tscn` into a zone and cover the part of the
## wall that should open: the node's position is the TOP-LEFT corner and `size`
## its width and height in pixels (multiples of the tile size, 8 px).
##
## LOOK: point `source_layer` at the zone's solid TileMapLayer (Ground/Platforms).
## At start the wall copies the tiles under its rectangle into its own layer and
## removes them from the zone, so it looks exactly like the surrounding wall
## and, once broken, the opening is a plain gap. Without a `source_layer` it
## tiles `look_texture` (or fills `fallback_color`) instead.
##
## HITS: Luz's attack reaches the wall through its `Hurtbox` area, which calls
## `receive_hit()` (the same seam enemies use). Each hit
## shakes the wall and chips off debris; the last one crumbles it. It never
## gives soul because it is not in the enemies group.
##
## MEMORY: a broken wall is recorded in `SecretProgress` under `wall_id`, so it
## stays open when Luz leaves the room and comes back. New Game forgets it.
## Leave `wall_id` empty to use the scene path plus the node name.

signal hit(count: int, required: int)
signal broken(wall_id: StringName)

const SOLID_LAYER := 1
const DEBRIS_GRAVITY := 520.0
const EDITOR_OUTLINE := Color(1.0, 0.35, 0.3, 0.9)
const EDITOR_FILL := Color(1.0, 0.35, 0.3, 0.14)

@export_group("Wall")
## Unique name of this wall; empty = scene path + node name.
@export var wall_id: StringName = &""
## Hits from Luz's attack needed to crumble it.
@export_range(1, 20) var hits_required := 3
## Width and height in pixels. Keep it a multiple of the tile size (8).
@export var size := Vector2(24.0, 48.0):
	set(value):
		size = value
		_apply_size()

@export_group("Look")
## The zone's solid TileMapLayer, as a path from this node (usually
## `../TilemapLayers/Ground/Platforms`). The wall copies the tiles under its
## rectangle, so it matches the wall around it.
@export var source_layer: NodePath
## Used only when there is no `source_layer`: tiled over the rectangle.
@export var look_texture: Texture2D
## Used when there is neither a `source_layer` nor a `look_texture`.
@export var fallback_color := Color(0.05, 0.04, 0.05)

@export_group("Feedback")
## Colour of the chips that fly off (pick something close to the wall).
@export var debris_color := Color(0.62, 0.52, 0.4)
## How far the wall jolts on a hit, in pixels.
@export_range(0.0, 6.0, 0.1) var shake_pixels := 1.5
## Brightness flash on a hit (1 = none).
@export_range(1.0, 2.5, 0.05) var flash_strength := 1.6
## Seconds before the same swing can count another hit.
@export_range(0.0, 0.6, 0.01) var hit_cooldown := 0.18

var _hits := 0
var _broken := false
var _cooldown := 0.0
var _look: CanvasItem
var _source: TileMapLayer
var _tween: Tween

@onready var _shape: CollisionShape2D = $Shape
@onready var _hurt_shape: CollisionShape2D = $Hurtbox/HurtShape


func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	set_process(true)
	collision_layer = SOLID_LAYER
	collision_mask = 0
	_source = get_node_or_null(source_layer) as TileMapLayer
	if _source == null and not source_layer.is_empty():
		push_warning("BreakableWall '%s': source_layer %s is not a TileMapLayer." % [name, source_layer])
	if _already_broken():
		_clear_source_cells()
		queue_free()
		return
	_build_look()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), EDITOR_FILL)
		draw_rect(Rect2(Vector2.ZERO, size), EDITOR_OUTLINE, false, 1.0)


## Called by Luz's attack hitbox. Returns true when the hit counted.
func receive_hit(_damage: int, source_position: Vector2, _attack_name: StringName = &"") -> bool:
	if _broken or _cooldown > 0.0:
		return false
	_cooldown = hit_cooldown
	_hits += 1
	hit.emit(_hits, hits_required)
	if _hits >= hits_required:
		_crumble(source_position)
	else:
		_chip(source_position)
	return true


func is_broken() -> bool:
	return _broken


func get_hits() -> int:
	return _hits


## `wall_id`, or the scene path plus node name when it was left empty.
func get_effective_id() -> StringName:
	if not wall_id.is_empty():
		return wall_id
	var scene_path := owner.scene_file_path if owner != null else ""
	return StringName("%s#%s" % [scene_path, name])


func _apply_size() -> void:
	if _shape == null or _hurt_shape == null:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	_shape.shape = rectangle
	_shape.position = size * 0.5
	_hurt_shape.shape = rectangle.duplicate()
	_hurt_shape.position = size * 0.5
	queue_redraw()


func _already_broken() -> bool:
	var progress := get_node_or_null("/root/SecretProgress")
	return progress != null and progress.is_wall_broken(get_effective_id())


## Cells of `_source` under the wall rectangle.
func _covered_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _source == null:
		return cells
	var first := _source.local_to_map(_source.to_local(global_position + Vector2.ONE * 0.5))
	var last := _source.local_to_map(_source.to_local(global_position + size - Vector2.ONE * 0.5))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _clear_source_cells() -> void:
	for cell in _covered_cells():
		_source.erase_cell(cell)


func _build_look() -> void:
	if _source != null:
		_look = _build_tile_look()
	else:
		_look = _build_flat_look()


## Moves the covered tiles into a layer of our own that draws where the zone's
## layer did, so the wall is the same picture as the wall around it.
func _build_tile_look() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "WallLook"
	layer.tile_set = _source.tile_set
	layer.collision_enabled = false
	layer.navigation_enabled = false
	for cell in _covered_cells():
		var source_id := _source.get_cell_source_id(cell)
		if source_id == -1:
			continue
		layer.set_cell(cell, source_id, _source.get_cell_atlas_coords(cell), _source.get_cell_alternative_tile(cell))
		_source.erase_cell(cell)
	_source.add_child(layer)
	return layer


func _build_flat_look() -> CanvasItem:
	if look_texture != null:
		var tiles := TextureRect.new()
		tiles.texture = look_texture
		tiles.stretch_mode = TextureRect.STRETCH_TILE
		tiles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tiles.size = size
		add_child(tiles)
		return tiles
	var flat := ColorRect.new()
	flat.color = fallback_color
	flat.size = size
	add_child(flat)
	return flat


func _chip(source_position: Vector2) -> void:
	_burst(source_position, 7, 70.0)
	if _tween != null:
		_tween.kill()
	if _look == null:
		return
	var direction := -1.0 if source_position.x > global_position.x + size.x * 0.5 else 1.0
	_look.position = Vector2(direction * shake_pixels, 0.0)
	_look.modulate = Color(flash_strength, flash_strength, flash_strength)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_look, "position", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_look, "modulate", Color.WHITE, 0.2)


func _crumble(source_position: Vector2) -> void:
	_broken = true
	_shape.set_deferred(&"disabled", true)
	_hurt_shape.set_deferred(&"disabled", true)
	var progress := get_node_or_null("/root/SecretProgress")
	if progress != null:
		progress.break_wall(get_effective_id())
	_burst(source_position, 26, 120.0)
	broken.emit(get_effective_id())
	if _tween != null:
		_tween.kill()
	if _look == null:
		queue_free()
		return
	_look.modulate = Color(flash_strength, flash_strength, flash_strength)
	_tween = create_tween()
	_tween.tween_property(_look, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.22)
	_tween.tween_callback(_finish_crumble)


func _finish_crumble() -> void:
	if is_instance_valid(_look):
		_look.queue_free()
	queue_free()


## One-shot burst of square chips from the face Luz hit.
func _burst(source_position: Vector2, amount: int, speed: float) -> void:
	var rect := Rect2(global_position, size)
	var origin := Vector2(
		clampf(source_position.x, rect.position.x, rect.end.x),
		clampf(source_position.y - 18.0, rect.position.y, rect.end.y),
	)
	var outward := Vector2(-1.0 if source_position.x < rect.get_center().x else 1.0, 0.0)
	var chips := CPUParticles2D.new()
	chips.top_level = true
	chips.global_position = origin
	chips.z_index = 5
	chips.amount = amount
	chips.lifetime = 0.7
	chips.one_shot = true
	chips.explosiveness = 1.0
	chips.direction = outward + Vector2(0.0, -0.7)
	chips.spread = 55.0
	chips.initial_velocity_min = speed * 0.5
	chips.initial_velocity_max = speed
	chips.gravity = Vector2(0.0, DEBRIS_GRAVITY)
	chips.scale_amount_min = 1.5
	chips.scale_amount_max = 3.0
	chips.color = debris_color
	chips.finished.connect(chips.queue_free)
	# Parented to the zone, not to the wall: the wall frees itself while they fly.
	get_parent().add_child(chips)
	chips.emitting = true

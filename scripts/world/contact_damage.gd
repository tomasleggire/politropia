class_name ContactDamage
extends Area2D

## Reusable damage source. As an ENEMY it hurts the player on contact and
## again every time her i-frames end while she is still inside (Hollow Knight
## enemies behave this way). As a HAZARD (spikes and the like) a hit takes the
## damage and then moves her back to the last safe ground, so she never stands
## in it. Place it as a child of an enemy or alone; it only watches the player
## layer and is invisible to everything else.

enum Kind { ENEMY, HAZARD }

const PLAYER_LAYER := 1
## Hazards register here so the player can keep safe ground away from them.
const HAZARD_GROUP := &"damage_hazard"

@export var damage := 1
@export var kind := Kind.ENEMY


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	if kind == Kind.HAZARD:
		add_to_group(HAZARD_GROUP)
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape != null:
		# Instances of the scene would otherwise share one resizable shape.
		shape_node.shape = shape_node.shape.duplicate()
	body_entered.connect(_on_body_entered)


## Resizes the hit area to `size`, centred on this node.
func set_area_size(size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	($CollisionShape2D as CollisionShape2D).shape = shape


## The hit area in world space (rectangle shapes only).
func get_world_rect() -> Rect2:
	var shape := ($CollisionShape2D as CollisionShape2D).shape as RectangleShape2D
	if shape == null:
		return Rect2(global_position, Vector2.ZERO)
	return Rect2(global_position - shape.size * 0.5, shape.size)


## Deferred: the hit changes the player's own areas, which physics forbids
## while it is still flushing the query that raised this signal.
func _on_body_entered(body: Node2D) -> void:
	_try_hurt.call_deferred(body)


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	for body: Node2D in get_overlapping_bodies():
		_try_hurt(body)


func _try_hurt(body: Node2D) -> void:
	if not monitoring:
		return
	var player := body as Player
	if player == null:
		return
	if kind == Kind.HAZARD:
		player.take_hazard_damage(damage, global_position)
	else:
		player.take_damage(damage, global_position)

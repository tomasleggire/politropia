class_name ContactDamage
extends Area2D

## Reusable damage source: hurts the player on contact and again every time
## her i-frames end while she is still inside (Hollow Knight spikes and
## enemies behave this way). Place it as a child of an enemy or alone as a
## hazard; it only watches the player layer and is invisible to everything.

const PLAYER_LAYER := 1

@export var damage := 1


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER
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
	var player := body as Player
	if player != null:
		player.take_damage(damage, global_position)

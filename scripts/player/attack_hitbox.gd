class_name AttackHitbox
extends Area2D

## Player attack hitbox. The player script positions/sizes it and toggles it
## on for the active frames of exactly one attack at a time. It is collision-
## only and intentionally has no on-screen debug rendering.

signal attack_hit(target: Node2D, attack_name: StringName)

@onready var _shape: CollisionShape2D = $CollisionShape2D

var _active_name := &""


func _ready() -> void:
	monitoring = false
	monitorable = false
	_shape.shape = _shape.shape.duplicate()
	_shape.disabled = true
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## size/offset are in the hitbox's local space; offset already carries the
## caller's facing sign.
func configure(size: Vector2, offset: Vector2) -> void:
	var shape := _shape.shape as RectangleShape2D
	shape.size = size
	_shape.position = offset


func activate(attack_name: StringName) -> void:
	_active_name = attack_name
	_shape.disabled = false
	monitoring = true


func deactivate() -> void:
	_shape.disabled = true
	monitoring = false
	_active_name = &""


func _on_body_entered(body: Node2D) -> void:
	attack_hit.emit(body, _active_name)


func _on_area_entered(area: Area2D) -> void:
	attack_hit.emit(area, _active_name)

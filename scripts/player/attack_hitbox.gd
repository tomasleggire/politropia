class_name AttackHitbox
extends Area2D

## Player attack hitbox. The player script positions/sizes it and toggles it
## on for the active frames of exactly one attack at a time, and draws a
## translucent placeholder slash while active (no combat art yet).

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
	queue_redraw()


func activate(attack_name: StringName) -> void:
	_active_name = attack_name
	_shape.disabled = false
	monitoring = true
	queue_redraw()


func deactivate() -> void:
	_shape.disabled = true
	monitoring = false
	_active_name = &""
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	attack_hit.emit(body, _active_name)


func _on_area_entered(area: Area2D) -> void:
	attack_hit.emit(area, _active_name)


func _draw() -> void:
	if _shape.disabled:
		return
	var shape := _shape.shape as RectangleShape2D
	var half := shape.size * 0.5
	var rect := Rect2(_shape.position - half, shape.size)
	draw_rect(rect, Color(0.85, 0.72, 0.35, 0.35), true)
	draw_rect(rect, Color(0.96, 0.82, 0.45, 0.85), false, 2.0)

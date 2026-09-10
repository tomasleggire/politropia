class_name SpinningPickup
extends Area2D

## Moneda/estrella decorativa que gira en el lugar.

@export var spin_speed: float = 2.4
@export var bob_amplitude: float = 8.0
@export var bob_speed: float = 2.0
@export var pickup_color: Color = Color(1.0, 0.84, 0.2, 1.0)

var _visual: Polygon2D
var _base_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_base_y = position.y
	_visual = Polygon2D.new()
	_visual.color = pickup_color
	_visual.polygon = _make_star_points(18.0, 8.0)
	add_child(_visual)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	collision.shape = shape
	add_child(collision)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_visual.rotation += spin_speed * delta
	position.y = _base_y + sin(_time * bob_speed) * bob_amplitude


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		queue_free()


func _make_star_points(outer_r: float, inner_r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2.0 + float(i) * PI / 5.0
		var radius := outer_r if i % 2 == 0 else inner_r
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

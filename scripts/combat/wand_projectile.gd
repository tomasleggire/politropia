class_name WandProjectile
extends CharacterBody2D

## Bolita en línea recta. Choca contra sólidos y no cruza de sala.

const ROOM_SIZE := Vector2(720, 1280)

var team := &"player"
var speed := 620.0
var range_pixels := 837.0
var orb_color := Color("7ee8d8")
var glow_color := Color(0.42, 0.95, 0.86, 0.26)

var _direction := Vector2.RIGHT
var _traveled := 0.0
var _home_room := Vector2i.ZERO


func launch(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	_direction = direction.normalized()
	z_index = 8
	_home_room = _room_for(global_position)
	var group := &"player" if team == &"player" else &"enemy"
	for node in get_tree().get_nodes_in_group(group):
		if node is PhysicsBody2D:
			add_collision_exception_with(node)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING

	var shape := CircleShape2D.new()
	shape.radius = 11.0
	var hit := CollisionShape2D.new()
	hit.shape = shape
	add_child(hit)

	var glow := Polygon2D.new()
	glow.polygon = LevelGeometry.circle_points(16, 16)
	glow.color = glow_color
	add_child(glow)

	var ball := Polygon2D.new()
	ball.polygon = LevelGeometry.circle_points(11, 16)
	ball.color = orb_color
	add_child(ball)

	var core := Polygon2D.new()
	core.polygon = LevelGeometry.circle_points(5, 12)
	core.position = Vector2(-2, -2)
	core.color = Color(0.96, 1.0, 0.98, 0.94)
	add_child(core)


func _physics_process(delta: float) -> void:
	var remaining := range_pixels - _traveled
	if remaining <= 0.0:
		queue_free()
		return
	var step := minf(speed * delta, remaining)
	var collision := move_and_collide(_direction * step)
	_traveled += step
	if collision != null:
		_apply_hit(collision.get_collider())
		queue_free()
		return
	if _room_for(global_position) != _home_room:
		queue_free()
		return
	if _traveled >= range_pixels:
		queue_free()


func _apply_hit(collider: Object) -> void:
	if collider == null or not collider.has_method("take_damage"):
		return
	var hit_player := collider is Node and (collider as Node).is_in_group(&"player")
	if team == &"player" and not hit_player:
		collider.take_damage(1, _direction)
	elif team == &"enemy" and hit_player:
		collider.take_damage(1, _direction)


func _room_for(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / ROOM_SIZE.x),
		floori(world_position.y / ROOM_SIZE.y)
	)

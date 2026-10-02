@tool
class_name Flyer
extends FlyingEnemy

## Chases Luz through the air (the Vengefly). Acceleration is steered, so it
## overshoots a little, and the sideways part of the acceleration is weaker
## than the forward part: it turns slower than it speeds up. It slides along
## walls and never goes through them. Light: hits knock it back hard.
## Placeholder visuals only; the Greek look comes later.

@export_group("Chase")
@export var chase_acceleration := 420.0
@export var chase_max_speed := 150.0
## Share of the acceleration that bends the flight path (1 turns as fast as
## it accelerates).
@export_range(0.1, 1.0) var turn_factor := 0.55


func _engaged_think(delta: float) -> void:
	var to_player := _player_center() - get_body_center()
	_face_x(to_player.x)
	var push := to_player.normalized() * chase_acceleration * delta
	velocity = (velocity + _weaken_turn(push)).limit_length(chase_max_speed)


## Keeps the part of `push` along the current heading and scales the rest.
func _weaken_turn(push: Vector2) -> Vector2:
	if velocity.length_squared() < 1.0:
		return push
	var heading := velocity.normalized()
	var forward := heading * push.dot(heading)
	return forward + (push - forward) * turn_factor

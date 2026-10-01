extends Camera2D
@export var follow_speed := 5.0
@export var target: Node2D

func _process(delta):
	if target:
		global_position = global_position.lerp(
			target.global_position,
			follow_speed * delta
		)

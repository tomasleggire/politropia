class_name VenomProjectile
extends EnemyProjectile

## Projectile of toxic venom shot by the snake.
## Rotates in flight to align with its trajectory and emits poison trail particles.

@onready var _trail_particles: CPUParticles2D = get_node_or_null("TrailParticles") as CPUParticles2D
@onready var _visual: Node2D = get_node_or_null("Visual") as Node2D


func launch(from: Vector2, direction: Vector2, speed: float) -> void:
	super.launch(from, direction, speed)
	rotation = direction.angle()
	if _visual != null:
		_visual.visible = true
	if _trail_particles != null:
		_trail_particles.restart()
		_trail_particles.emitting = true


func deactivate() -> void:
	if _trail_particles != null:
		_trail_particles.emitting = false
	super.deactivate()

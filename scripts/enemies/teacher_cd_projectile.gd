class_name TeacherCDProjectile
extends EnemyProjectile

## Teacher's CD: a compact, iridescent disc that spins as it flies.

const DISC_COLORS: Array[Color] = [
	Color("#9feaff"), Color("#cc9cff"), Color("#ff9cc8"),
	Color("#ffe3a0"), Color("#a6f1e1"), Color("#a9bfff"),
]

var _spin_direction := 1.0


func launch(from: Vector2, direction: Vector2, speed: float) -> void:
	_spin_direction = 1.0 if direction.x >= 0.0 else -1.0
	rotation = 0.0
	super.launch(from, direction, speed)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if is_active():
		rotation += delta * 12.0 * _spin_direction
	super._physics_process(delta)


func _draw() -> void:
	var center := Vector2.ZERO
	var radius := 8.0
	draw_circle(center, radius + 1.0, Color("#21192d"))
	draw_circle(center, radius, Color("#d6d4e4"))
	for i: int in DISC_COLORS.size():
		var start := TAU * float(i) / float(DISC_COLORS.size())
		var finish := TAU * float(i + 1) / float(DISC_COLORS.size())
		var points := PackedVector2Array([center])
		for step: int in 5:
			var angle := lerpf(start, finish, float(step) / 4.0)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, DISC_COLORS[i])
	draw_arc(center, radius, 0.0, TAU, 32, Color("#36253e"), 1.1, true)
	draw_circle(center, 2.2, Color("#302338"))
	draw_circle(center, 0.8, Color("#eee6f0"))

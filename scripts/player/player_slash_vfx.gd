class_name PlayerSlashVfx
extends Node2D

const DURATION := 0.16
const PARTICLE_VELOCITIES := [
	Vector2(-24.0, -28.0),
	Vector2(-10.0, -38.0),
	Vector2(10.0, -36.0),
	Vector2(25.0, -24.0),
	Vector2(17.0, -10.0),
	Vector2(-17.0, -12.0),
]

var _slash_kind: StringName = &"ground"
var _variant := 0
var _facing := 1
var _time_left := 0.0


func _ready() -> void:
	visible = false
	set_process(false)


func play_slash(slash_kind: StringName, variant: int, facing: int) -> void:
	_slash_kind = slash_kind
	_variant = clampi(variant, 0, 2)
	_facing = -1 if facing < 0 else 1
	_time_left = DURATION
	visible = true
	set_process(true)
	queue_redraw()


func stop_slash() -> void:
	_time_left = 0.0
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_time_left = maxf(_time_left - delta, 0.0)
	if is_zero_approx(_time_left):
		stop_slash()
	else:
		queue_redraw()


func _draw() -> void:
	var progress := 1.0 - (_time_left / DURATION)
	var alpha := 1.0 - progress * 0.35
	var style := _style_for_kind()
	var points: PackedVector2Array = style.points
	var mirrored_points := PackedVector2Array()
	for point in points:
		mirrored_points.append(Vector2(point.x * float(_facing), point.y))
	draw_polyline(mirrored_points, Color(0.98, 0.86, 0.57, alpha), style.width, false)
	draw_polyline(mirrored_points, Color(1.0, 0.98, 0.86, alpha), maxf(style.width - 2.0, 1.0), false)
	_draw_particles(progress, alpha, style.particle_count)


func _style_for_kind() -> Dictionary:
	if _slash_kind == &"up":
		return {
			points = PackedVector2Array([
				Vector2(-20.0, -45.0), Vector2(-17.0, -62.0), Vector2(-8.0, -78.0),
				Vector2(5.0, -86.0), Vector2(19.0, -83.0), Vector2(29.0, -72.0),
			]),
			width = 4.0,
			particle_count = 4,
		}

	var vertical_adjustment := 0.0
	if _slash_kind == &"crouch":
		vertical_adjustment = 20.0
	elif _slash_kind == &"air":
		vertical_adjustment = -8.0

	var points_by_variant: Array[PackedVector2Array] = [
		PackedVector2Array([
			Vector2(-12.0, -35.0), Vector2(0.0, -44.0), Vector2(16.0, -45.0),
			Vector2(32.0, -38.0), Vector2(47.0, -25.0),
		]),
		PackedVector2Array([
			Vector2(-10.0, -46.0), Vector2(3.0, -51.0), Vector2(21.0, -44.0),
			Vector2(39.0, -30.0), Vector2(53.0, -13.0),
		]),
		PackedVector2Array([
			Vector2(-16.0, -27.0), Vector2(-1.0, -43.0), Vector2(19.0, -49.0),
			Vector2(41.0, -40.0), Vector2(62.0, -21.0),
		]),
	]
	var points := PackedVector2Array()
	for point in points_by_variant[_variant]:
		points.append(point + Vector2(0.0, vertical_adjustment))
	return {
		points = points,
		width = [4.0, 3.0, 6.0][_variant],
		particle_count = [3, 4, 6][_variant],
	}


func _draw_particles(progress: float, alpha: float, particle_count: int) -> void:
	var travel := progress * 0.16
	for index in range(particle_count):
		var velocity: Vector2 = PARTICLE_VELOCITIES[index]
		var sign := float(_facing) if _slash_kind != &"up" else 1.0
		var position := Vector2(velocity.x * sign, velocity.y) * travel
		var particle_size := 3.0 if index % 2 == 0 else 2.0
		var color := Color(1.0, 0.95, 0.78, alpha) if index % 2 == 0 else Color(0.86, 0.63, 0.31, alpha)
		draw_rect(Rect2(position, Vector2.ONE * particle_size), color, true)

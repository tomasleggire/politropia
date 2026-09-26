extends Control

## Draws a circular gothic touch button with a simple vector icon. Touch
## handling and multitouch ID tracking stay in TouchControls; this node only
## renders whatever state it is told to.

enum Icon { JUMP, DASH, ATTACK }

@export var icon: Icon = Icon.JUMP

var is_pressed := false


func set_button_state(pressed: bool) -> void:
	if is_pressed == pressed:
		return
	is_pressed = pressed
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := size.x * 0.5
	var rim := Color("d8792e") if is_pressed else Color(0.25, 0.44, 0.64, 0.72)
	var fill_alpha := 0.66 if is_pressed else 0.5

	draw_circle(center, radius + 4.0, Color(0.006, 0.012, 0.035, 0.42))
	draw_circle(center, radius, Color(0.025, 0.055, 0.12, fill_alpha))
	draw_arc(center, radius, 0.0, TAU, 64, Color(rim, 0.92), 2.5, true)
	draw_arc(center, radius - 8.0, 0.0, TAU, 64, Color(rim, 0.28), 1.0, true)

	var extent := radius * 0.42
	match icon:
		Icon.JUMP:
			_draw_chevron(center, extent, rim, Vector2.UP)
		Icon.DASH:
			_draw_chevron(center + Vector2(-extent * 0.65, 0.0), extent * 0.85, rim, Vector2.RIGHT)
			_draw_chevron(center + Vector2(extent * 0.65, 0.0), extent * 0.85, rim, Vector2.RIGHT)
		Icon.ATTACK:
			_draw_slash(center, radius * 0.5, rim)


func _draw_chevron(origin: Vector2, extent: float, color: Color, direction: Vector2) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var tip := origin + direction * extent
	var back := origin - direction * extent * 0.6
	var points := PackedVector2Array([back + normal * extent, tip, back - normal * extent])
	draw_polyline(points, color, 4.0, true)


func _draw_slash(center: Vector2, extent: float, color: Color) -> void:
	draw_line(center + Vector2(-extent, extent), center + Vector2(extent, -extent), color, 5.0, true)
	draw_line(
		center + Vector2(-extent * 0.35, extent * 1.05),
		center + Vector2(extent * 1.05, -extent * 0.35),
		Color(color, 0.55),
		3.0,
		true
	)

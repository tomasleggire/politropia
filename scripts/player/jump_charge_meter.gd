class_name JumpChargeMeter
extends Node2D

## Indicador radial de carga del salto.
## Se dibuja con primitivas (sin texturas) para mantenerlo liviano en mobile.

@export var radius: float = 22.0
@export var line_width: float = 5.0
@export var track_color: Color = Color(1, 1, 1, 0.22)
@export var fill_color: Color = Color(0.95, 0.82, 0.25, 0.95)
@export var full_color: Color = Color(1.0, 0.45, 0.2, 1.0)

var _ratio: float = 0.0


func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, track_color, line_width, true)

	if _ratio <= 0.0:
		return

	var color := fill_color.lerp(full_color, _ratio)
	# Arranca desde arriba (-PI/2) y llena en sentido horario visual (clockwise en pantalla).
	var end_angle := -PI / 2.0 + TAU * _ratio
	draw_arc(Vector2.ZERO, radius, -PI / 2.0, end_angle, 48, color, line_width, true)

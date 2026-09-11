class_name JumpChargeMeter
extends Node2D

## Barra de carga discreta estilo Jump King (~36 ticks / frames).

@export var radius: float = 22.0
@export var line_width: float = 5.0
@export var track_color: Color = Color(1, 1, 1, 0.22)
@export var fill_color: Color = Color(0.95, 0.82, 0.25, 0.95)
@export var full_color: Color = Color(1.0, 0.45, 0.2, 1.0)
@export var tick_color: Color = Color(1, 1, 1, 0.35)

var _frame: int = 0
var _max_frames: int = 36


func configure_ticks(max_frames: int) -> void:
	_max_frames = maxi(max_frames, 1)
	queue_redraw()


func set_frame(frame: int) -> void:
	_frame = clampi(frame, 0, _max_frames)
	queue_redraw()


func set_ratio(ratio: float) -> void:
	# Compat: convierte ratio continuo a tick discreto.
	set_frame(int(round(clampf(ratio, 0.0, 1.0) * float(_max_frames))))


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, track_color, line_width, true)

	# Marcas discretas (cada 3 frames ≈ 12 divisiones visibles).
	var major_every := 3
	for i in range(0, _max_frames + 1, major_every):
		var t := float(i) / float(_max_frames)
		var ang := -PI / 2.0 + TAU * t
		var inner := Vector2(cos(ang), sin(ang)) * (radius - 3.0)
		var outer := Vector2(cos(ang), sin(ang)) * (radius + 3.0)
		draw_line(inner, outer, tick_color, 1.5, true)

	if _frame <= 0:
		return

	var ratio := float(_frame) / float(_max_frames)
	var color := fill_color.lerp(full_color, ratio)
	var end_angle := -PI / 2.0 + TAU * ratio
	draw_arc(Vector2.ZERO, radius, -PI / 2.0, end_angle, 48, color, line_width, true)

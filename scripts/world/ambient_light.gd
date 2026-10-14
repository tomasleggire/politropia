@tool
class_name AmbientLight
extends PointLight2D

## Soft round light with an optional candle flicker. Drag
## `scenes/world/ambient_light.tscn` (or `candle_light.tscn`) next to a lamp,
## candle, window or desk and tune it from the Inspector. No shadows, so it is
## cheap: keep a zone under about 8 of these.

@export_group("Light")
@export var light_color := Color(1.0, 0.74, 0.42):
	set(value):
		light_color = value
		color = value
## Brightness when not flickering.
@export_range(0.0, 3.0, 0.05) var base_energy := 0.8:
	set(value):
		base_energy = value
		energy = value
## Reach of the light, in world pixels.
@export_range(16.0, 600.0, 1.0) var radius := 96.0:
	set(value):
		radius = value
		_apply_radius()

@export_group("Flicker")
## 0 keeps the light steady; around 0.15 reads as a candle.
@export_range(0.0, 1.0, 0.01) var flicker_amount := 0.0:
	set(value):
		flicker_amount = value
		_update_process()
@export_range(0.5, 20.0, 0.1) var flicker_speed := 6.0
## Shifts the flicker so neighbouring lights do not pulse together.
@export var phase_offset := 0.0


func _ready() -> void:
	color = light_color
	energy = base_energy
	shadow_enabled = false
	_apply_radius()
	_update_process()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 * flicker_speed + phase_offset
	var wave := sin(t) * 0.5 + sin(t * 2.31 + 1.7) * 0.3 + sin(t * 5.17 + 0.4) * 0.2
	energy = base_energy * (1.0 + flicker_amount * wave)


func _apply_radius() -> void:
	if texture == null:
		return
	texture_scale = radius / (float(texture.get_width()) * 0.5)


func _update_process() -> void:
	set_process(flicker_amount > 0.0 and not Engine.is_editor_hint())

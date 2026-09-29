class_name AltarLightShaft
extends Sprite2D

## The one vertical light of the level: a warm beam falling from above the arch
## onto the altar and Luz's seat. `set_shaft_intensity()` sets its base level
## (dormant subtle, awakened warmer, resting brightest); it breathes on top of
## that with the altar's breath clock. Driven by `StillnessDeskFx`.

@export_group("Look")
@export_range(0.05, 0.6, 0.01) var strength := 0.45
@export_range(0.0, 2.0, 0.05) var stria_speed := 0.35

@export_group("Breathing")
@export_range(0.0, 0.5, 0.01) var idle_swing := 0.05
@export_range(0.0, 0.6, 0.01) var resting_swing := 0.22

## Base level before breathing; tweened by `set_shaft_intensity()`.
var level := 0.5

var _material: ShaderMaterial
var _phase := 0.0
var _effective := 0.0
var _tweens: Dictionary = {}


func _ready() -> void:
	_material = material as ShaderMaterial
	_material.set_shader_parameter(&"strength", strength)
	step(0.0, 0.5, 0.0)


## Sets the base level over `time` seconds (immediately when `time` is 0).
## Also the hook for the celebration's pillar swell.
func set_shaft_intensity(value: float, time := 0.0) -> void:
	if time <= 0.0:
		var previous := _tweens.get(&"level") as Tween
		if previous != null:
			previous.kill()
		level = value
		return
	AltarFxKit.ease_property(self, _tweens, self, &"level", value, time)


## Level including the breathing swing; what the shader is fed.
func get_effective_level() -> float:
	return _effective


## `breath` is 0..1; `breath_weight` blends the idle swing into the resting one.
func step(delta: float, breath: float, breath_weight: float) -> void:
	_phase += delta * stria_speed
	var swing := lerpf(idle_swing, resting_swing, breath_weight)
	_effective = maxf(level * (1.0 + (breath - 0.5) * 2.0 * swing), 0.0)
	_material.set_shader_parameter(&"intensity", _effective)
	_material.set_shader_parameter(&"phase", _phase)

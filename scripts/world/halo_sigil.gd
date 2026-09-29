class_name HaloSigil
extends Sprite2D

## Vertical protractor halo behind the seated Luz. Dormant it is a faint,
## slowly turning cold-gold engraving; awakened it is warm with every tick
## lit; resting its ticks breathe with Luz. It replaces the floor ring and
## keeps the same beats: a first activation fills the ticks clockwise like a
## clock, the peak flares the whole ring, and time stops (hand and ring) while
## the pendulum is still. Shader uniforms are mirrored as `fill`, `flare`,
## `intensity` and `spin` so the staged celebration can drive them directly.

const FILL_TIME := 1.2
const REPEAT_FILL_TIME := 0.3
const FLARE_TIME := 0.6
const RETUNE_TIME := 0.8
const WARMTH_AWAKENED := 0.6

@export_group("Levels")
@export_range(0.0, 1.5, 0.01) var dormant_level := 0.45
@export_range(0.0, 1.5, 0.01) var awakened_level := 0.8
@export_range(0.0, 1.5, 0.01) var ritual_level := 1.15
@export_range(0.0, 1.5, 0.01) var resting_level := 0.95

@export_group("Motion")
@export_range(0.0, 0.5, 0.005) var spin_speed := 0.05
@export_range(0.0, 1.0, 0.01) var hand_speed := 0.35
@export_range(0.0, 0.6, 0.01) var breath_amplitude := 0.3

var intensity := 0.0
## Fraction of ticks lit clockwise, 0..1.
var fill := 0.0
## Full-ring flash, 0..1.
var flare := 0.0
var warmth := 0.0
## Ring rotation in radians.
var spin := 0.0
var breath_weight := 0.0

var _material: ShaderMaterial
var _hand := 0.0
var _tweens: Dictionary = {}


func _ready() -> void:
	_material = material as ShaderMaterial
	set_idle(false, 0.0)
	step(0.0, 0.5, 1.0)


## Idle look: engraved and dormant, or warm with every tick lit when the
## checkpoint is active. Immediate when `time` is 0.
func set_idle(awakened: bool, time: float) -> void:
	_tune(&"intensity", awakened_level if awakened else dormant_level, time)
	_tune(&"warmth", WARMTH_AWAKENED if awakened else 0.0, time)
	_tune(&"fill", 1.0 if awakened else 0.0, time)
	_tune(&"breath_weight", 0.0, time)
	_tune(&"flare", 0.0, time)


func celebrate(first: bool) -> void:
	_tune(&"warmth", 1.0, 0.5)
	_tune(&"intensity", ritual_level, 0.6)
	if first:
		fill = 0.0
		AltarFxKit.ease_property(self, _tweens, self, &"fill", 1.0, FILL_TIME, Tween.EASE_IN_OUT, Tween.TRANS_QUAD)
	else:
		_tune(&"fill", 1.0, REPEAT_FILL_TIME)


func peak() -> void:
	flare = 1.0
	AltarFxKit.ease_property(self, _tweens, self, &"flare", 0.0, FLARE_TIME, Tween.EASE_OUT, Tween.TRANS_CUBIC)


func settle_into_rest() -> void:
	_tune(&"intensity", resting_level, 0.9)
	_tune(&"breath_weight", 1.0, 0.9)


## `time_scale` 0 freezes the hand and ring: time stops while Luz rests.
func step(delta: float, breath: float, time_scale: float) -> void:
	spin = fposmod(spin + delta * spin_speed * time_scale, TAU)
	_hand = fposmod(_hand + delta * hand_speed * time_scale, TAU)
	_material.set_shader_parameter(&"intensity", intensity)
	_material.set_shader_parameter(&"fill", clampf(fill, 0.0, 1.0))
	_material.set_shader_parameter(&"flare", clampf(flare, 0.0, 1.0))
	_material.set_shader_parameter(&"rotation", spin)
	_material.set_shader_parameter(&"hand", _hand)
	_material.set_shader_parameter(&"warmth", warmth)
	_material.set_shader_parameter(&"breath", breath)
	_material.set_shader_parameter(&"breath_swing", breath_weight * breath_amplitude)


func _tune(property: StringName, value: float, time: float) -> void:
	if time <= 0.0:
		var previous := _tweens.get(property) as Tween
		if previous != null:
			previous.kill()
		set(property, value)
		return
	AltarFxKit.ease_property(self, _tweens, self, property, value, time)

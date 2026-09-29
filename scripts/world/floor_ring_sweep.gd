class_name FloorRingSweep
extends Node

## Lights the floor ring: on a first activation a clock-hand sweep reveals it,
## a repeat activation just fades it in. It peaks with the celebration and then
## breathes with Luz while she rests.

const SWEEP_TIME := 1.2
const REPEAT_FADE_TIME := 0.3
const PEAK_LEVEL := 1.0
const FADE_OUT_TIME := 0.7

@export_group("Alpha Targets")
@export_range(0.0, 1.0, 0.05) var sweep_alpha := 1.0
@export_range(0.0, 1.0, 0.05) var repeat_alpha := 0.85
@export_range(0.0, 1.0, 0.05) var resting_alpha := 0.7
@export_range(0.0, 0.5, 0.01) var breath_amplitude := 0.18

var level := 0.0
var breath_weight := 0.0
var progress := 1.0

var _ring: Node2D
var _material: ShaderMaterial
var _tweens: Dictionary = {}


func setup(ring: Node2D) -> void:
	_ring = ring
	for child in ring.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		if _material == null:
			_material = (sprite.material as ShaderMaterial).duplicate() as ShaderMaterial
		sprite.material = _material
	_apply(0.5)


func celebrate(first: bool) -> void:
	if first:
		progress = 0.0
		AltarFxKit.ease_property(self, _tweens, self, &"level", sweep_alpha, 0.15)
		AltarFxKit.ease_property(self, _tweens, self, &"progress", 1.0, SWEEP_TIME, Tween.EASE_IN_OUT, Tween.TRANS_QUAD)
	else:
		progress = 1.0
		AltarFxKit.ease_property(self, _tweens, self, &"level", repeat_alpha, REPEAT_FADE_TIME, Tween.EASE_OUT)


func peak() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"level", PEAK_LEVEL, 0.25, Tween.EASE_OUT)


func settle_into_rest() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"level", resting_alpha, 0.9)
	AltarFxKit.ease_property(self, _tweens, self, &"breath_weight", 1.0, 0.9)


func release() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"level", 0.0, FADE_OUT_TIME)
	AltarFxKit.ease_property(self, _tweens, self, &"breath_weight", 0.0, FADE_OUT_TIME)


func get_alpha() -> float:
	return _ring.modulate.a


func step(breath: float) -> void:
	_apply(breath)


func _apply(breath: float) -> void:
	if _ring == null:
		return
	var alpha := level + breath_weight * (breath - 0.5) * 2.0 * breath_amplitude
	_ring.modulate.a = clampf(alpha, 0.0, 1.0) if level > 0.0 else 0.0
	if _material != null:
		_material.set_shader_parameter(&"progress", progress)

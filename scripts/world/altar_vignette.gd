class_name AltarVignette
extends CanvasLayer

## Screen-edge vignette that fades in while Luz sits still at the altar. Owned
## by the desk FX; sits above the level's atmosphere and below the touch UI.

var level := 0.0

var _material: ShaderMaterial
var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = 30
	_rect = $Shade as ColorRect
	_material = _rect.material as ShaderMaterial
	set_level(0.0, 0.0)


## Fades to `value` over `time` seconds (immediately when `time` is 0).
func set_level(value: float, time: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if time <= 0.0:
		_apply(value)
		return
	_rect.visible = true
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_apply, level, value, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply(value: float) -> void:
	level = value
	_material.set_shader_parameter(&"level", value)
	_rect.visible = value > 0.001

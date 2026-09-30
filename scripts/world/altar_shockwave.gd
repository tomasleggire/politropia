class_name AltarShockwave
extends Sprite2D

## Expanding ring of light thrown from the halo at the first-activation peak.
## Additive, fades out by about twice the halo's radius; sits behind Luz.

const DURATION := 0.9

var progress := 0.0

var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_material = material as ShaderMaterial
	reset()


func fire() -> void:
	if _tween != null:
		_tween.kill()
	progress = 0.0
	visible = true
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "progress", 1.0, DURATION).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(reset)


## Off and invisible; also the abort path.
func reset() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	progress = 0.0
	visible = false
	_material.set_shader_parameter(&"progress", 0.0)


func is_active() -> bool:
	return visible


func _process(_delta: float) -> void:
	if visible:
		_material.set_shader_parameter(&"progress", progress)

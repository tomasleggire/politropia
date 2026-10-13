class_name ScreenFlash
extends CanvasLayer

## Full-screen flash, one reused node. `flash()` fades in, then out, in real
## time, so it keeps its rhythm while the world is frozen or in slow motion.
## Expects a child ColorRect named `Rect` that starts hidden.

@onready var _rect: ColorRect = $Rect

var _tween: Tween


## `peak` is the maximum opacity (0 to 1).
func flash(peak: float, fade_in: float, fade_out: float) -> void:
	if _tween != null:
		_tween.kill()
	_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_rect.visible = true
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.tween_property(_rect, "color:a", clampf(peak, 0.0, 1.0), maxf(fade_in, 0.001))
	_tween.tween_property(_rect, "color:a", 0.0, maxf(fade_out, 0.001))
	_tween.tween_callback(_hide)


func is_flashing() -> bool:
	return _rect.visible


## Current opacity of the flash (0 when idle).
func get_alpha() -> float:
	return _rect.color.a if _rect.visible else 0.0


func _hide() -> void:
	_rect.visible = false

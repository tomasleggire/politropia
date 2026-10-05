class_name ScreenFade
extends CanvasLayer

## Full-screen dark veil whose opacity the owner drives directly (the player
## uses it for the hazard return). Above the vignette (30) and below the
## health HUD (40), so the pips stay readable while the world goes dark.

const FADE_LAYER := 35

var _veil := ColorRect.new()


func _ready() -> void:
	layer = FADE_LAYER
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	set_alpha(0.0)


func set_alpha(alpha: float) -> void:
	_veil.modulate.a = clampf(alpha, 0.0, 1.0)
	_veil.visible = alpha > 0.0


func get_alpha() -> float:
	return _veil.modulate.a

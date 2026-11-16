class_name BossSpriteFx
extends RefCounted

## Telegraph glow and hit flash drawn on a boss sprite itself (shaders/sprite_glow.gdshader)
## instead of a polygon overlay, so they follow the exact silhouette of the art. The
## boss owns one of these per sprite: BossTelegraph drives the glow through it and the
## boss drives the flash. Nothing in here knows a boss by name.

const SHADER := preload("res://shaders/sprite_glow.gdshader")

var _material := ShaderMaterial.new()
var _glow := 0.0
var _flash := false


## Puts the glow material on `sprite` (the sprite keeps it for its whole life).
func _init(sprite: CanvasItem) -> void:
	_material.shader = SHADER
	sprite.material = _material
	set_glow(Color.WHITE, 0.0)
	set_flash(false)


## Tints the sprite with `color`; `amount` 0 hides it and 1 is the full glow.
func set_glow(color: Color, amount: float) -> void:
	_glow = clampf(amount, 0.0, 1.0)
	_material.set_shader_parameter(&"glow_color", color)
	_material.set_shader_parameter(&"glow_amount", _glow)


func glow_amount() -> float:
	return _glow


func is_glowing() -> bool:
	return _glow > 0.0


## Shows or clears the white hit flash.
func set_flash(on: bool) -> void:
	_flash = on
	_material.set_shader_parameter(&"flash_amount", 1.0 if on else 0.0)


func is_flashing() -> bool:
	return _flash

class_name MenuShade
extends Control
## Screen-space legibility shading of the main menu: a dark gradient behind the
## UI column on the left and a soft vignette over the whole frame.

@export_group("Shading")
@export var left_shade_alpha := 0.82
@export var left_shade_width := 0.46  # Fraction of the screen width.
@export var vignette_alpha := 0.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_make_layer(_left_gradient()))
	add_child(_make_layer(_vignette()))


func _make_layer(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect


func _left_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, left_shade_width * 0.5, left_shade_width])
	gradient.colors = PackedColorArray([
		Color(0.02, 0.02, 0.06, left_shade_alpha),
		Color(0.02, 0.02, 0.06, left_shade_alpha * 0.6),
		Color(0.02, 0.02, 0.06, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 4
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	return texture


func _vignette() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.01, 0.0, 0.03, vignette_alpha),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.2, 0.5)
	texture.width = 128
	texture.height = 128
	return texture

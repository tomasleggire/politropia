class_name AltarFxKit
extends RefCounted

## Shared, lazily built resources and helpers for the Stillness Desk FX so each
## effect node stays small and no texture or material is built twice.

const GLOW_SIZE := 64

static var _glow_texture: GradientTexture2D
static var _dot_texture: ImageTexture
static var _additive: CanvasItemMaterial


## Soft round falloff, white at the centre and transparent at the rim.
static func glow_texture() -> Texture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.width = GLOW_SIZE
		_glow_texture.height = GLOW_SIZE
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
	return _glow_texture


## Hard 2x2 pixel used as the firefly core.
static func dot_texture() -> Texture2D:
	if _dot_texture == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_dot_texture = ImageTexture.create_from_image(image)
	return _dot_texture


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func make_sprite(parent: Node, texture: Texture2D, additive: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	if additive:
		sprite.material = additive_material()
	parent.add_child(sprite)
	return sprite


## Tweens a float property on `target`, replacing any earlier tween that
## `tweens` holds for it. The tween keeps running while the tree is paused.
static func ease_property(
	owner: Node,
	tweens: Dictionary,
	target: Object,
	property: StringName,
	value: float,
	duration: float,
	easing := Tween.EASE_IN_OUT,
	trans := Tween.TRANS_SINE,
) -> Tween:
	var previous := tweens.get(property) as Tween
	if previous != null:
		previous.kill()
	var tween := owner.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(target, NodePath(property), value, maxf(duration, 0.001)).set_ease(easing).set_trans(trans)
	tweens[property] = tween
	return tween

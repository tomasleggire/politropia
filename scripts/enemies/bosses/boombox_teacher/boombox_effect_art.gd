class_name BoomboxEffectArt
extends RefCounted

## The drawn props and effects of the Boombox Teacher (manifest entries "props" and "fx",
## and the "blackboard" texture): builds the sprites its hazards and effects show and
## scales each one from the content box the manifest records. `BoomboxHazard` stays
## the one that hurts; this only decides what is seen. Without art every call returns
## null and the caller keeps its placeholder.

const PROPS := "props"
const FX := "fx"
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
## Frames per second of the looping effects (the briefcase tumble, the steam).
const LOOP_FPS := {&"briefcase_spin": 10.0, &"steam": 6.0}
## The puff and the spark rise and fade over this time, growing from this scale to 1.
const PUFF_TIME := 0.35
const PUFF_START_SCALE := 0.6
const PUFF_RISE := 10.0
const PUFF_Z := 4

var _catalog: BossAnimationCatalog
var _frames := {}


func _init(catalog: BossAnimationCatalog) -> void:
	_catalog = catalog
	for key: String in [PROPS, FX]:
		if not catalog.manifest_entry(key).is_empty():
			_frames[key] = _loop_clips(catalog.build_entry_frames(key))


func has_clip(key: String, clip: StringName) -> bool:
	return _frames.has(key) and (_frames[key] as SpriteFrames).has_animation(clip)


## Size of the drawn clip in sheet px (ZERO when unknown).
func content(key: String, clip: StringName) -> Vector2:
	return _catalog.content_size(key, clip)


## `content`, or, when the manifest names no content box for the clip, the size of one
## frame (the whole cell). A safe stand-in: scaling from it never oversizes the art, which
## a missing box read as "1 px" or "scale 1" would. ZERO only when there is no such clip.
func art_size(key: String, clip: StringName) -> Vector2:
	var box := content(key, clip)
	if box.x > 0.0 and box.y > 0.0:
		return box
	if not has_clip(key, clip):
		return Vector2.ZERO
	var frames := _frames[key] as SpriteFrames
	var texture := frames.get_frame_texture(clip, 0) if frames.get_frame_count(clip) > 0 else null
	return texture.get_size() if texture != null else Vector2.ZERO


## A playing sprite of `clip` scaled to fit the hazard `box`; null when there is no such clip.
func fit_sprite(key: String, clip: StringName, box: Vector2, fit: BoomboxHazard.ArtFit, flip := false) -> AnimatedSprite2D:
	return sprite(key, clip, BoomboxHazard.art_scale(art_size(key, clip), box, fit), flip)


## A playing sprite of `clip` at `scale`, centred on its node; null when there is no such clip.
func sprite(key: String, clip: StringName, scale: Vector2, flip := false) -> AnimatedSprite2D:
	if not has_clip(key, clip):
		return null
	var node := AnimatedSprite2D.new()
	node.sprite_frames = _frames[key]
	node.texture_filter = FILTER
	node.scale = Vector2(-scale.x if flip else scale.x, scale.y)
	node.play(clip)
	return node


## Crests of `clip` side by side along a floor `strip` (its centre on the node origin), as
## tall as the strip and standing on its bottom edge, enough of them to cover its width.
func floor_sprites(key: String, clip: StringName, strip: Vector2) -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	var box := content(key, clip)
	if not has_clip(key, clip) or box.x <= 0.0 or box.y <= 0.0 or strip.x <= 0.0 or strip.y <= 0.0:
		return sprites
	var fit := strip.y / box.y
	var count := maxi(ceili(strip.x / (box.x * fit)), 1)
	for i: int in count:
		var node := sprite(key, clip, Vector2.ONE * fit)
		node.position = Vector2(-strip.x * 0.5 + (float(i) + 0.5) * strip.x / float(count), strip.y * 0.5 - box.y * fit * 0.5)
		sprites.append(node)
	return sprites


## A one-shot puff of `clip` that is `width` px wide: grows, rises, fades and frees itself.
func puff(parent: Node, key: String, clip: StringName, at: Vector2, width: float) -> Node2D:
	var node := sprite(key, clip, Vector2.ONE * (width / maxf(art_size(key, clip).x, 1.0)))
	if node == null or parent == null:
		return null
	node.top_level = true
	node.z_index = PUFF_Z
	parent.add_child(node)
	node.global_position = at
	var full := node.scale
	node.scale = full * PUFF_START_SCALE
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", full, PUFF_TIME)
	tween.tween_property(node, "global_position:y", at.y - PUFF_RISE, PUFF_TIME)
	tween.tween_property(node, "modulate:a", 0.0, PUFF_TIME)
	tween.chain().tween_callback(node.queue_free)
	return node


func blackboard() -> Texture2D:
	return _catalog.blackboard_texture()


func _loop_clips(frames: SpriteFrames) -> SpriteFrames:
	var fps := _loop_fps()
	for clip: StringName in fps:
		if frames.has_animation(clip):
			frames.set_animation_loop(clip, true)
			frames.set_animation_speed(clip, float(fps[clip]))
	return frames


## The looping clips and their speed; a boss with other loops overrides it.
func _loop_fps() -> Dictionary:
	return LOOP_FPS

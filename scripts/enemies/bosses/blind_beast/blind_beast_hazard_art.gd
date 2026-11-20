class_name BlindBeastHazardArt
extends BoomboxEffectArt

## The drawn props and effects of El Topo (manifest entries "props" and "fx"): the dirt
## mound, the cracks, the eruption column, the braille spikes, the thrown rocks, the
## tremor pulse and the dust puffs. `BlindBeastBoss` stays the one that hurts; this only
## keeps one sprite per live hazard and decides what is seen. Without art every call
## returns null or does nothing and the boss keeps drawing its placeholders.

const MOUND := &"mound"
const ROCK := &"rock"
const ROCK_ALT := &"rock_alt"
const CRACK := &"crack"
const SPIKE := &"spike"
const COLUMN := &"erupt_column"
const PULSE := &"pulse_wave"
const DUST := &"dust_puff"
const ROCK_IMPACT := &"rock_impact"
const DIG_DIRT := &"dig_dirt"
const CLAW := &"claw_swipe"
## The last frame of the claw swipe stays this long after the strike, fading out.
const LINGER_TIME := 0.25
## Frames per second of the looping clips (the mound heaves, the pulse ripples).
const BEAST_LOOP_FPS := {&"mound": 6.0, &"pulse_wave": 8.0}

## kind -> {hazard: sprite}
var _live := {}


func _loop_fps() -> Dictionary:
	return BEAST_LOOP_FPS


## Keeps exactly one sprite per item of `items` under `parent`: `make` builds the sprite
## of a new item (it may return null: the item stays a placeholder), `place` positions
## and shapes it on every call, and the sprite of an item that is gone is freed.
func sync(parent: Node2D, kind: StringName, items: Array, make: Callable, place: Callable) -> void:
	var live: Dictionary = _live.get(kind, {})
	_live[kind] = live
	for item: Variant in live.keys():
		if not items.has(item):
			_free_sprite(parent, live[item] as Node)
			live.erase(item)
	for item: Variant in items:
		if not live.has(item):
			var node := make.call(item) as AnimatedSprite2D
			if node == null:
				continue
			parent.add_child(node)
			live[item] = node
		place.call(item, live[item])


## Frees every sprite this keeps.
func clear(parent: Node2D) -> void:
	for kind: Variant in _live:
		for node: Variant in (_live[kind] as Dictionary).values():
			_free_sprite(parent, node as Node)
	_live.clear()


func sprite_count() -> int:
	var count := 0
	for kind: Variant in _live:
		count += (_live[kind] as Dictionary).size()
	return count


## `sprite` stands on the floor at `x`: its bottom edge on `floor_y`, centred on `x`.
func stand_on_floor(sprite: AnimatedSprite2D, key: String, clip: StringName, x: float, floor_y: float) -> void:
	var height := art_size(key, clip).y * absf(sprite.scale.y)
	sprite.position = Vector2(x, floor_y - height * 0.5)


## Shows frame `progress` (0..1) of the clip instead of playing it, so it follows the
## hazard's own clock rather than the sprite's speed.
func show_progress(sprite: AnimatedSprite2D, progress: float) -> void:
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.pause()
	sprite.frame = clampi(int(clampf(progress, 0.0, 1.0) * float(count)), 0, maxi(count - 1, 0))


## Shows frame `frame` of the clip (clamped) instead of playing it.
func show_frame(sprite: AnimatedSprite2D, frame: int) -> void:
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.pause()
	sprite.frame = clampi(frame, 0, maxi(count - 1, 0))


## A purely cosmetic one-shot: the last frame of `clip`, `width` px wide, standing on the
## floor at `at`, fading out and freeing itself. It is not one of the live hazard sprites.
func linger(parent: Node, key: String, clip: StringName, at: Vector2, width: float, flip := false) -> Node2D:
	var node := sprite(key, clip, Vector2.ONE * (width / maxf(art_size(key, clip).x, 1.0)), flip)
	if node == null or parent == null:
		return null
	show_frame(node, node.sprite_frames.get_frame_count(clip) - 1)
	node.top_level = true
	node.z_index = PUFF_Z
	parent.add_child(node)
	node.global_position = Vector2(at.x, at.y - art_size(key, clip).y * absf(node.scale.y) * 0.5)
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, LINGER_TIME)
	tween.tween_callback(node.queue_free)
	return node


func _free_sprite(parent: Node2D, node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() == parent:
		parent.remove_child(node)
	node.queue_free()

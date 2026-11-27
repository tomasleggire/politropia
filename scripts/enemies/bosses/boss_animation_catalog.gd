class_name BossAnimationCatalog
extends RefCounted

## Builds a boss's SpriteFrames from an animation manifest written by
## tools/boss_sheet_pipeline.py (see tools/process_boombox_teacher_sheets.py). Every
## frame is a uniform grid cell with the soles on one shared row, so the catalog only
## slices regions. A generic version of ArtemisAnimationCatalog for any boss: the
## manifest path, the fallbacks, the speeds and the looping clips come from the boss.
##
## The boss asks for clips by their CONTRACT names. A clip that is not drawn resolves
## through the fallbacks to the closest clip that exists, then to the default clip, so
## art can arrive sheet by sheet. A missing manifest or texture is not an error: the
## catalog stays empty (`has_art()` is false) and the boss keeps its placeholders.

const DEFAULT_FPS := 8.0
const DEFAULT_SPRITE_SCALE := 0.2896

var _manifest_path := ""
var _fallbacks: Dictionary = {}
var _speeds: Dictionary = {}
var _looping: Array = []
var _default_clip := &"idle"
var _manifest: Dictionary = {}
var _frames: SpriteFrames


## `fallbacks`: clip -> candidates (closest first). `speeds`: clip -> frames per second
## (DEFAULT_FPS otherwise). `looping`: clips that repeat; the others play once and hold
## their last frame. `default_clip`: what stands in for a clip with no art at all.
func _init(manifest_path: String, fallbacks := {}, speeds := {}, looping := [], default_clip := &"idle") -> void:
	_manifest_path = manifest_path
	_fallbacks = fallbacks
	_speeds = speeds
	_looping = looping
	_default_clip = default_clip
	_manifest = _read_manifest()


## One animation per drawn clip of every sheet that loads. Empty (but valid) when the
## manifest or every texture is missing. Built once; later calls return the same resource.
func build_sprite_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	_frames = _new_frames()
	var sheets: Variant = _manifest.get("sheets")
	if not sheets is Dictionary:
		return _frames
	for sheet_name: String in sheets:
		_add_sheet(_frames, sheets[sheet_name] as Dictionary, sheet_name)
	return _frames


## The props sheet (manifest key "props"): its own cell size, same rules.
func build_props_frames() -> SpriteFrames:
	return build_entry_frames("props")


## The frames of any sheet entry outside "sheets" (props, fx): its own cell size, same rules.
func build_entry_frames(key: String) -> SpriteFrames:
	var frames := _new_frames()
	var entry := manifest_entry(key)
	if not entry.is_empty():
		_add_sheet(frames, entry, String(entry.get("sheet", "")))
	return frames


## The box (sheet px) that holds the art of `clip` of entry `key` in every frame, as the
## processing script measured it; ZERO when the manifest does not say.
func content_size(key: String, clip: StringName) -> Vector2:
	var content: Variant = manifest_entry(key).get("content")
	if not content is Dictionary:
		return Vector2.ZERO
	var box: Variant = (content as Dictionary).get(String(clip))
	if not box is Array or (box as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((box as Array)[0]), float((box as Array)[1]))


## The single blackboard texture (manifest key "blackboard"), or null without art.
func blackboard_texture() -> Texture2D:
	return _load_texture(String(manifest_entry("blackboard").get("texture", "")))


## True when the default clip exists: the boss can then show its sprite.
func has_art() -> bool:
	return build_sprite_frames().has_animation(_default_clip)


## The drawn clip that stands in for `clip`: the clip itself, else the first fallback
## that exists, else the default clip, else an empty name (no art at all).
func resolve_clip(clip: StringName) -> StringName:
	var frames := build_sprite_frames()
	if frames.has_animation(clip):
		return clip
	for candidate: Variant in _fallbacks.get(String(clip), []):
		if frames.has_animation(StringName(candidate)):
			return StringName(candidate)
	return _default_clip if frames.has_animation(_default_clip) else &""


## The frame of `clip` where its event happens (a strike, a release), 0 when the
## manifest names none. Events are written per sheet.
func event_frame(clip: StringName) -> int:
	var sheets: Variant = _manifest.get("sheets")
	if not sheets is Dictionary:
		return 0
	for sheet: Variant in (sheets as Dictionary).values():
		var events: Variant = (sheet as Dictionary).get("events", {})
		if events is Dictionary and (events as Dictionary).has(String(clip)):
			return int((events as Dictionary)[String(clip)])
	return 0


## Scale the sprite node needs (processed pixels to screen pixels).
func sprite_scale() -> float:
	return float(_manifest.get("sprite_scale", DEFAULT_SPRITE_SCALE))


## `AnimatedSprite2D.offset` that puts the feet row on the node origin: the cell centre
## is on the node, the feet are `feet_row - cell / 2` texture pixels below it.
func sprite_offset() -> Vector2:
	var cell := float(_manifest.get("cell", 0.0))
	return Vector2(0.0, -(float(_manifest.get("feet_row", cell * 0.5)) - cell * 0.5))


## One manifest key as a Dictionary (empty when missing).
func manifest_entry(key: String) -> Dictionary:
	var entry: Variant = _manifest.get(key)
	return entry as Dictionary if entry is Dictionary else {}


func _new_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	return frames


func _add_sheet(frames: SpriteFrames, sheet: Dictionary, sheet_name: String) -> void:
	var atlas := _load_texture(sheet_name)
	if atlas == null or not sheet.get("clips") is Dictionary or not sheet.get("grid") is Dictionary:
		return
	var grid: Dictionary = sheet["grid"]
	var clips: Dictionary = sheet["clips"]
	for clip_name: String in clips:
		_add_clip(frames, clip_name, atlas, grid, clips[clip_name] as Array)


func _add_clip(frames: SpriteFrames, clip_name: String, atlas: Texture2D, grid: Dictionary, indices: Array) -> void:
	# A clip named by two sheets is a manifest mistake: the first sheet keeps it, the
	# second must not stack its frames on top (and `add_animation` would log an error).
	if frames.has_animation(clip_name):
		push_warning("%s: clip '%s' is drawn by more than one sheet; the first one is kept" % [_manifest_path, clip_name])
		return
	frames.add_animation(clip_name)
	frames.set_animation_speed(clip_name, float(_speeds.get(clip_name, DEFAULT_FPS)))
	frames.set_animation_loop(clip_name, clip_name in _looping)
	for index: Variant in indices:
		frames.add_frame(clip_name, _frame_texture(atlas, grid, int(index)))


static func _frame_texture(atlas: Texture2D, grid: Dictionary, frame_index: int) -> AtlasTexture:
	var columns := maxi(int(grid["columns"]), 1)
	var cell_width := int(grid["cell_width"])
	var cell_height := int(grid["cell_height"])
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	@warning_ignore("integer_division")
	atlas_texture.region = Rect2((frame_index % columns) * cell_width, (frame_index / columns) * cell_height, cell_width, cell_height)
	return atlas_texture


## The imported texture, or the PNG read straight from disk when it was never imported
## (a fixture); null, and silent, when neither exists.
func _load_texture(sheet_name: String) -> Texture2D:
	if sheet_name.is_empty():
		return null
	var path := _manifest_path.get_base_dir().path_join(sheet_name)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		return ImageTexture.create_from_image(image) if image != null else null
	return null


func _read_manifest() -> Dictionary:
	var file := FileAccess.open(_manifest_path, FileAccess.READ)
	if file == null:
		return {}
	# `JSON.new().parse` reports a malformed file through its return code, not the log.
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data if json.data is Dictionary else {}

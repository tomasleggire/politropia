class_name LuzAnimationCatalog
extends RefCounted

## Builds Luz's SpriteFrames from assets/player/luz/animation_manifest.json.
## tools/process_luz_sheet.py repacks every sheet into a uniform per-sheet
## grid (currently 4x4 512x512 cells) with each frame already placed so its
## feet land on the same canvas row and its horizontal position matches the
## legacy catalog math -- so this catalog only has to slice plain grid
## regions out of the sheet; no per-frame margin/offset correction needed.

const MANIFEST_PATH := "res://assets/player/luz/animation_manifest.json"
const ASSET_ROOT := "res://assets/player/luz/"

## Default playback speed (frames per second) for each animation. Attack and
## other timing-critical clips get overridden at build time from the
## player's own exported durations (see build_sprite_frames); these defaults
## only apply when no duration override is supplied.
const CLIP_SPEEDS := {
	"idle": 3.0,
	"walk": 9.0,
	"crouch": 4.0,
	"jump": 6.0,
	"fall": 5.0,
	"land": 8.0,
	"ground_dash": 9.0,
	"air_dash": 9.0,
	"wall_cling": 4.0,
	"wall_jump": 7.0,
	"ledge_hang": 4.0,
	"ledge_climb": 8.0,
	"attack_1": 10.0,
	"attack_2": 10.0,
	"attack_3": 10.0,
	"crouch_attack": 9.0,
	"up_attack": 10.0,
	"air_attack": 10.0,
	"plunge": 10.0,
	"plunge_land": 10.0,
}

## Animations that should hold/repeat while their state persists, rather
## than play once and freeze on the last frame.
const LOOPING_CLIPS := [
	"idle", "walk", "crouch", "jump", "fall",
	"ground_dash", "air_dash", "wall_cling", "ledge_hang",
]

const CLIP_SOURCE_NAMES := {
	"idle": "idle_breathing",
	"walk": "run",
	"jump": "jump_ascent",
	"attack_1": "ground_attack_1",
	"attack_2": "ground_attack_2",
	"attack_3": "ground_attack_3",
	"air_attack": "air_horizontal_attack",
}

## Animations whose manifest "contact_frames" entry (if any) should be
## honored: their frames get stretched/compressed so the contact frame's
## *start* time lines up exactly with attack_startup_time (see
## _frame_durations). Every other animation ignores contact_frames even if
## the manifest happened to define one for its source clip.
const CONTACT_SYNCED_CLIPS := [
	"attack_1", "attack_2", "attack_3", "crouch_attack", "up_attack", "air_attack",
]


## clip_durations optionally maps an animation name (StringName or String) to
## a target total playback duration in seconds; the resulting speed is
## derived as frame_count / duration so the clip finishes exactly when the
## matching gameplay window/timer does. Animations not present keep their
## CLIP_SPEEDS default.
##
## attack_startup_time is the player's exported startup phase length
## (seconds) shared by every attack state; for a CONTACT_SYNCED_CLIPS
## animation whose clip has a manifest "contact_frames" entry, frame
## durations are adjusted so that frame starts showing at exactly
## attack_startup_time -- i.e. precisely when the attack's hitbox
## activates -- instead of every frame getting an equal slice of the clip.
static func build_sprite_frames(clip_durations: Dictionary = {}, attack_startup_time := 0.0) -> SpriteFrames:
	var manifest := _read_manifest()
	var frames := SpriteFrames.new()
	for animation_name in CLIP_SPEEDS:
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, animation_name in LOOPING_CLIPS)

	for sheet_name in manifest["sheets"]:
		var sheet: Dictionary = manifest["sheets"][sheet_name]
		var atlas := _load_sheet_texture(sheet_name, sheet)
		var grid: Dictionary = sheet["grid"]
		var clips: Dictionary = sheet["clips"]
		var contact_frames: Dictionary = sheet.get("contact_frames", {})
		for clip_name in clips:
			var animation_name := _animation_name_for(clip_name)
			if animation_name.is_empty():
				continue
			var frame_indices: Array = clips[clip_name]
			var frame_count := frame_indices.size()
			var speed := _clip_speed(animation_name, frame_count, clip_durations)
			frames.set_animation_speed(animation_name, speed)

			var contact_index := int(contact_frames.get(clip_name, -1))
			var total_duration: float = clip_durations.get(animation_name, float(frame_count) / speed)
			var seconds := _frame_seconds(
				animation_name, frame_count, contact_index, total_duration, attack_startup_time
			)
			for i in frame_count:
				var texture := _build_frame_texture(atlas, grid, int(frame_indices[i]))
				frames.add_frame(animation_name, texture, seconds[i] * speed)

	return frames


## Per-frame duration (seconds) for a clip: equal shares of total_duration,
## unless this animation is contact-synced and its clip has a manifest
## contact_frame, in which case frames 0..contact_index-1 are compressed to
## fit exactly into attack_startup_time and frames contact_index..end are
## stretched to fill the remaining (total_duration - attack_startup_time).
static func _frame_seconds(
	animation_name: String, frame_count: int, contact_index: int,
	total_duration: float, attack_startup_time: float
) -> Array[float]:
	var uniform: Array[float] = []
	uniform.resize(frame_count)
	uniform.fill(total_duration / float(frame_count))

	var synced := (
		animation_name in CONTACT_SYNCED_CLIPS
		and contact_index > 0 and contact_index < frame_count
		and attack_startup_time > 0.0 and attack_startup_time < total_duration
	)
	if not synced:
		return uniform

	var result: Array[float] = []
	result.resize(frame_count)
	var lead_frame_seconds := attack_startup_time / float(contact_index)
	for i in contact_index:
		result[i] = lead_frame_seconds
	var trail_frame_count := frame_count - contact_index
	var trail_frame_seconds := (total_duration - attack_startup_time) / float(trail_frame_count)
	for i in range(contact_index, frame_count):
		result[i] = trail_frame_seconds
	return result


static func _load_sheet_texture(sheet_name: String, sheet: Dictionary) -> Texture2D:
	var atlas := load(ASSET_ROOT + sheet_name) as Texture2D
	assert(atlas != null, "Missing Luz animation sheet: %s" % sheet_name)
	var grid: Dictionary = sheet["grid"]
	var expected_size := Vector2(int(grid["columns"]) * int(grid["cell_width"]), int(grid["rows"]) * int(grid["cell_height"]))
	assert(atlas.get_size() == expected_size, "Unexpected Luz sheet dimensions: %s" % sheet_name)
	return atlas


## Frames per second for a clip: derived from clip_durations when the caller
## supplies a target duration for this animation (frame_count / duration, so
## the clip finishes exactly when the matching gameplay window/timer does),
## otherwise the CLIP_SPEEDS default.
static func _clip_speed(animation_name: String, frame_count: int, clip_durations: Dictionary) -> float:
	if clip_durations.has(animation_name):
		var duration: float = clip_durations[animation_name]
		if duration > 0.0:
			return float(frame_count) / duration
	return CLIP_SPEEDS.get(animation_name, 8.0)


static func _animation_name_for(clip_name: String) -> String:
	for animation_name in CLIP_SPEEDS:
		if CLIP_SOURCE_NAMES.get(animation_name, animation_name) == clip_name:
			return animation_name
	return ""


static func _build_frame_texture(atlas: Texture2D, grid: Dictionary, frame_index: int) -> AtlasTexture:
	var columns := int(grid["columns"])
	var rows := int(grid["rows"])
	var cell_width := int(grid["cell_width"])
	var cell_height := int(grid["cell_height"])
	assert(frame_index >= 0 and frame_index < columns * rows, "Invalid Luz frame index: %d" % frame_index)
	var column := frame_index % columns
	@warning_ignore("integer_division")
	var row := frame_index / columns
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(column * cell_width, row * cell_height, cell_width, cell_height)
	return atlas_texture


static func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert(file != null, "Cannot read Luz animation manifest")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid Luz animation manifest JSON")
	return parsed

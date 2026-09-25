class_name LuzAnimationCatalog
extends RefCounted

## Builds Luz's SpriteFrames from assets/player/luz/animation_manifest.json.
## The manifest describes each generated sheet as a nominal 4x4 grid of
## 313x313 cells, but the generated art is not an exact even grid, so cells
## are actually cut at the per-sheet "safe_cuts" pixel boundaries (with rare
## per-frame "frame_overrides" for cells the shared grid cuts through a
## neighbor's content). Because those cut regions vary in size/position per
## frame, every frame is placed at a fixed offset from its *nominal* grid
## cell inside a shared virtual canvas (via AtlasTexture.margin) so its
## position stays comparable across frames, then nudged by a measured
## per-frame "foot_offsets" correction so every frame's opaque bottom lands
## on the same canvas row -- keeping Luz's feet anchored without jitter even
## though the underlying cells are not uniform.

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


## clip_durations optionally maps an animation name (StringName or String) to
## a target total playback duration in seconds; the resulting speed is
## derived as frame_count / duration so the clip finishes exactly when the
## matching gameplay window/timer does. Animations not present keep their
## CLIP_SPEEDS default.
static func build_sprite_frames(clip_durations: Dictionary = {}) -> SpriteFrames:
	var manifest := _read_manifest()
	var frames := SpriteFrames.new()
	for animation_name in CLIP_SPEEDS:
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, animation_name in LOOPING_CLIPS)

	for sheet_name in manifest["sheets"]:
		var sheet: Dictionary = manifest["sheets"][sheet_name]
		var atlas := _load_sheet_texture(sheet_name, sheet)
		var clips: Dictionary = sheet["clips"]
		for clip_name in clips:
			var animation_name := _animation_name_for(clip_name)
			if animation_name.is_empty():
				continue
			var frame_indices: Array = clips[clip_name]
			frames.set_animation_speed(animation_name, _clip_speed(animation_name, frame_indices.size(), clip_durations))
			for frame_index in frame_indices:
				frames.add_frame(animation_name, _build_frame_texture(atlas, sheet, int(frame_index), manifest))

	return frames


static func _load_sheet_texture(sheet_name: String, sheet: Dictionary) -> Texture2D:
	var atlas := load(ASSET_ROOT + sheet_name) as Texture2D
	assert(atlas != null, "Missing Luz animation sheet: %s" % sheet_name)
	assert(atlas.get_size() == Vector2(sheet["width"], sheet["height"]), "Unexpected Luz sheet dimensions: %s" % sheet_name)
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


static func _build_frame_texture(atlas: Texture2D, sheet: Dictionary, frame_index: int, manifest: Dictionary) -> AtlasTexture:
	var region := _frame_region(sheet, frame_index)
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = region
	atlas_texture.margin = _frame_margin(sheet, region, frame_index, manifest)
	assert(atlas_texture.get_size() == Vector2(manifest["frame_canvas"][0], manifest["frame_canvas"][1]), "Luz frame margin did not preserve its virtual canvas: %s" % atlas_texture.get_size())
	return atlas_texture


static func _frame_region(sheet: Dictionary, frame_index: int) -> Rect2:
	var overrides: Dictionary = sheet.get("frame_overrides", {})
	var override_key := str(frame_index)
	if overrides.has(override_key):
		var box: Dictionary = overrides[override_key]
		return Rect2(box["x0"], box["y0"], box["x1"] - box["x0"], box["y1"] - box["y0"])
	var columns := 4
	var rows := 4
	assert(frame_index >= 0 and frame_index < columns * rows, "Invalid Luz frame index: %d" % frame_index)
	var vertical_cuts: Array = sheet["safe_cuts"]["vertical"]
	var horizontal_cuts: Array = sheet["safe_cuts"]["horizontal"]
	var x_edges := [0, vertical_cuts[0], vertical_cuts[1], vertical_cuts[2], int(sheet["width"])]
	var y_edges := [0, horizontal_cuts[0], horizontal_cuts[1], horizontal_cuts[2], int(sheet["height"])]
	var column := frame_index % columns
	@warning_ignore("integer_division")
	var row := frame_index / columns
	return Rect2(x_edges[column], y_edges[row], x_edges[column + 1] - x_edges[column], y_edges[row + 1] - y_edges[row])


static func _frame_margin(sheet: Dictionary, region: Rect2, frame_index: int, manifest: Dictionary) -> Rect2:
	var columns := int(manifest["columns"])
	var cell_width := int(manifest["cell_width"])
	var cell_height := int(manifest["cell_height"])
	@warning_ignore("integer_division")
	var cell_origin := Vector2((frame_index % columns) * cell_width, (frame_index / columns) * cell_height)
	var canvas := Vector2(manifest["frame_canvas"][0], manifest["frame_canvas"][1])
	var padding := int(manifest["frame_padding"])
	var foot_offsets: Array = sheet.get("foot_offsets", [])
	var foot_correction := float(foot_offsets[frame_index]) if frame_index < foot_offsets.size() else 0.0
	var leading := Vector2(padding, padding) + region.position - cell_origin
	leading.y += foot_correction
	var trailing := canvas - leading - region.size
	assert(leading.x >= 0 and leading.y >= 0 and trailing.x >= 0 and trailing.y >= 0, "Luz frame region exceeds its virtual canvas")
	return Rect2(leading, canvas - region.size)


static func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert(file != null, "Cannot read Luz animation manifest")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid Luz animation manifest JSON")
	return parsed

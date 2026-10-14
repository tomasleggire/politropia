class_name ArtemisAnimationCatalog
extends RefCounted

## Builds Artemis's SpriteFrames from assets/enemies/artemis/animation_manifest.json
## (written by tools/process_artemis_sheets.py). Every frame is a uniform grid
## cell with the soles on one shared row, so the catalog only slices regions.
##
## The boss asks for clips by their CONTRACT names (docs/bosses/ARTEMIS_ANIMATIONS.md,
## section 3). Clips that are not drawn yet resolve through FALLBACKS to the closest
## clip that exists, so the demo set already covers every move and the full set
## only has to add sheets with the missing names: no logic change.

const MANIFEST_PATH := "res://assets/enemies/artemis/animation_manifest.json"
const ASSET_ROOT := "res://assets/enemies/artemis/"

## Fallback when a requested clip (or its whole fallback chain) has no art.
const DEFAULT_CLIP := &"idle"

## Default playback speed (frames per second) of each drawn clip. The boss
## overrides it with `speed_scale` so a clip lasts exactly as long as the timer it
## illustrates (see ArtemisBoss._play).
const CLIP_SPEEDS := {
	"idle": 8.0,
	"walk_fwd": 12.0,
	"walk_back": 12.0,
	"shot_draw": 12.0,
	"shot_hold": 8.0,
	"shot_release": 20.0,
	"shot_recover": 10.0,
	"rain_draw": 12.0,
	"rain_release": 20.0,
	"rain_recover": 10.0,
	"fan_draw": 12.0,
	"fan_hold": 8.0,
	"fan_release": 20.0,
	"dagger_windup": 12.0,
	"dagger_slash": 24.0,
	"dagger_flip": 14.0,
	"dagger_recover": 12.0,
	"dive_leap": 12.0,
	"dive_fall": 12.0,
	"dive_stuck": 10.0,
	"backstep": 14.0,
	"dodge": 14.0,
	"interrupt_flinch": 20.0,
	"stagger_in": 20.0,
	"stagger_loop": 8.0,
	"vault_crouch": 14.0,
	"vault_air": 8.0,
	"vault_land": 12.0,
	"defeat": 10.0,
	"feint_dash": 14.0,
	"feint_stop": 20.0,
	"feint_retreat": 14.0,
}

## Clips that repeat while their state lasts; every other clip plays once and
## holds its last frame.
const LOOPING_CLIPS := ["idle", "walk_fwd", "walk_back", "stagger_loop", "dive_fall", "feint_dash"]

## Clips built by playing another clip's frames backwards (no extra art): she
## retreats while facing Luz.
const REVERSED_CLIPS := {"walk_back": "walk_fwd"}

## Contract clip -> candidates, closest first. Names without an entry use the clip
## itself, then DEFAULT_CLIP.
const FALLBACKS := {
	"stag_cast": ["idle"],
	"stag_summon": ["shot_release"],
	"stag_recover": ["shot_recover"],
	"phase_transition": ["idle"],
	"fan_recover": ["shot_recover"],
	"shot_hold": ["shot_draw"],
	"stagger_in": ["stagger_loop"],
	"dodge": ["backstep"],
}


## Reads the manifest and builds one animation per drawn clip. Returns an empty
## SpriteFrames (so the boss keeps working without art) when the manifest is missing.
static func build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	var manifest := _read_manifest()
	if manifest.is_empty():
		return frames
	var sheets: Dictionary = manifest["sheets"]
	for sheet_name: String in sheets:
		var sheet: Dictionary = sheets[sheet_name]
		var atlas := load(ASSET_ROOT + sheet_name) as Texture2D
		if atlas == null:
			push_warning("ArtemisAnimationCatalog: missing sheet %s" % sheet_name)
			continue
		var grid: Dictionary = sheet["grid"]
		var clips: Dictionary = sheet["clips"]
		for clip_name: String in clips:
			var indices: Array = clips[clip_name]
			_add_clip(frames, clip_name, atlas, grid, indices)
	for reversed_name: String in REVERSED_CLIPS:
		var source: String = REVERSED_CLIPS[reversed_name]
		if frames.has_animation(source) and not frames.has_animation(reversed_name):
			_add_reversed(frames, reversed_name, source)
	return frames


## The drawn clip that stands in for `clip`: the clip itself, else the first
## fallback that exists, else DEFAULT_CLIP, else an empty name (no art at all).
static func resolve_clip(frames: SpriteFrames, clip: StringName) -> StringName:
	if frames == null:
		return &""
	if frames.has_animation(clip):
		return clip
	for candidate: String in FALLBACKS.get(String(clip), []):
		if frames.has_animation(candidate):
			return StringName(candidate)
	return DEFAULT_CLIP if frames.has_animation(DEFAULT_CLIP) else &""


static func _add_clip(frames: SpriteFrames, clip_name: String, atlas: Texture2D, grid: Dictionary, indices: Array) -> void:
	frames.add_animation(clip_name)
	frames.set_animation_speed(clip_name, CLIP_SPEEDS.get(clip_name, 8.0))
	frames.set_animation_loop(clip_name, clip_name in LOOPING_CLIPS)
	for index: Variant in indices:
		frames.add_frame(clip_name, _frame_texture(atlas, grid, int(index)))


static func _add_reversed(frames: SpriteFrames, clip_name: String, source: String) -> void:
	frames.add_animation(clip_name)
	frames.set_animation_speed(clip_name, CLIP_SPEEDS.get(clip_name, frames.get_animation_speed(source)))
	frames.set_animation_loop(clip_name, clip_name in LOOPING_CLIPS)
	for i: int in range(frames.get_frame_count(source) - 1, -1, -1):
		frames.add_frame(clip_name, frames.get_frame_texture(source, i))


static func _frame_texture(atlas: Texture2D, grid: Dictionary, frame_index: int) -> AtlasTexture:
	var columns := int(grid["columns"])
	var cell_width := int(grid["cell_width"])
	var cell_height := int(grid["cell_height"])
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	var column := frame_index % columns
	@warning_ignore("integer_division")
	var row := frame_index / columns
	atlas_texture.region = Rect2(column * cell_width, row * cell_height, cell_width, cell_height)
	return atlas_texture


static func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

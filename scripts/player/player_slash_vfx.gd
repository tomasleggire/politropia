class_name PlayerSlashVfx
extends Node2D

## Plays a pre-rendered Blasphemous-style crescent slash smear over Luz's
## attacks (see tools/generate_luz_slash_smears.py). Presentation only: this
## node never touches collision, damage, or gameplay state -- player.gd owns
## the AttackHitbox independently and just tells this node which variant to
## play and what hitbox rect it should visually cover.

const TEXTURE_PATH := "res://assets/player/luz/vfx/luz_slash_smears.png"
const MANIFEST_PATH := "res://assets/player/luz/vfx/luz_slash_smears_manifest.json"

## Same numeric texture_filter as the character AnimatedSprite2D
## (scripts/player/player.gd / scenes/player/player.tscn), so the smear is
## filtered/scaled the same way as Luz's own art (the art-pixel "chunkiness"
## comes from the low native resolution both textures share, not from
## nearest-neighbor filtering).
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

const TOTAL_DURATION := 0.14

const VARIANT_BY_KIND_AND_INDEX := {
	&"ground": ["ground_1", "ground_2", "ground_3"],
	&"crouch": ["crouch"],
	&"up": ["up"],
	&"air": ["air"],
}

var _manifest: Dictionary
var _texture: Texture2D
var _sprite: Sprite2D
var _frame_textures_by_variant: Dictionary = {}  # String -> Array[AtlasTexture]
var _frame_duration := TOTAL_DURATION / 5.0

var _active_frames: Array = []
var _elapsed := 0.0
var _current_frame := -1


func _ready() -> void:
	visible = false
	set_process(false)
	_manifest = _read_manifest()
	_texture = load(TEXTURE_PATH) as Texture2D
	assert(_texture != null, "Missing Luz slash smear sheet")
	_frame_duration = TOTAL_DURATION / float(_manifest["frame_count"])
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.texture_filter = TEXTURE_FILTER
	# This short-lived presentation sprite is configured between physics
	# ticks; never interpolate its first visible transform from defaults.
	_sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_sprite)
	for variant_name in _manifest["variants"]:
		_frame_textures_by_variant[variant_name] = _build_frame_textures(variant_name)
	# Prime a valid atlas frame while the parent effect remains hidden. This is
	# required frame initialization, but it does not replace the interpolation
	# guard below: first visibility also resets the configured transform history.
	var initial_frames: Array = _frame_textures_by_variant.get("ground_1", [])
	assert(not initial_frames.is_empty(), "Missing initial Luz slash smear frame")
	_sprite.texture = initial_frames[0] as Texture2D


## hitbox_size/hitbox_offset are the attack's current (unsigned, right-facing)
## hitbox tunables -- see player.gd's _hitbox_config_for -- so the smear is
## always scaled/positioned to cover exactly the hitbox that is actually
## active, even if those tunables change later without regenerating art.
func play_slash(
	slash_kind: StringName, variant: int, facing: int, hitbox_size: Vector2, hitbox_offset: Vector2
) -> void:
	var variant_name := _variant_name_for(slash_kind, variant)
	if variant_name.is_empty() or not _frame_textures_by_variant.has(variant_name):
		return
	var config: Dictionary = _manifest["variants"][variant_name]
	var reference_size: Array = config["reference_hitbox_size"]
	var display_scale: float = _manifest["display_scale"]

	# Mirroring uses scale.x sign, never Sprite2D.flip_h: a Sprite2D's
	# _get_rects() computes dst_rect.position = offset - frame_size/2 and,
	# for flip_h, only negates dst_rect.size.x -- the position (and
	# therefore the reflection axis) stays fixed at that offset-derived
	# point, NOT at local x=0 (verified against Godot 4.7's own
	# scene/2d/sprite_2d.cpp). Since this sprite's own offset.x is the
	# swing's pivot/anchor (never 0 except for "up"), flip_h left every
	# ground/crouch/air smear anchored on the right side even when facing
	# left. A negative node scale.x instead mirrors the whole transform
	# (offset included) about this node's own local origin, which IS the
	# player's origin -- the correct axis regardless of anchor.
	var facing_sign := 1.0 if facing >= 0 else -1.0
	_sprite.scale = Vector2(
		display_scale * (hitbox_size.x / float(reference_size[0])) * facing_sign,
		display_scale * (hitbox_size.y / float(reference_size[1])),
	)
	var anchor: Array = config["anchor"]
	_sprite.offset = Vector2(
		float(_manifest["cell_width"]) * 0.5 - float(anchor[0]),
		float(_manifest["cell_height"]) * 0.5 - float(anchor[1]),
	)
	_active_frames = _frame_textures_by_variant[variant_name]
	_elapsed = 0.0
	_current_frame = -1
	_advance_frame(0)
	_sprite.reset_physics_interpolation()
	visible = true
	set_process(true)


func stop_slash() -> void:
	_elapsed = 0.0
	_current_frame = -1
	_active_frames = []
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= TOTAL_DURATION:
		stop_slash()
		return
	var frame_index := clampi(int(_elapsed / _frame_duration), 0, _active_frames.size() - 1)
	_advance_frame(frame_index)


func _advance_frame(frame_index: int) -> void:
	if frame_index == _current_frame or _active_frames.is_empty():
		return
	_current_frame = frame_index
	_sprite.texture = _active_frames[frame_index]


func _variant_name_for(slash_kind: StringName, variant: int) -> String:
	var names: Array = VARIANT_BY_KIND_AND_INDEX.get(slash_kind, [])
	var index := clampi(variant, 0, names.size() - 1) if not names.is_empty() else -1
	return names[index] if index >= 0 else ""


func _build_frame_textures(variant_name: String) -> Array:
	var config: Dictionary = _manifest["variants"][variant_name]
	var row := int(config["row"])
	var cell_width := int(_manifest["cell_width"])
	var cell_height := int(_manifest["cell_height"])
	var frame_count := int(_manifest["frame_count"])
	var textures: Array = []
	for frame in frame_count:
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = _texture
		atlas_texture.region = Rect2(frame * cell_width, row * cell_height, cell_width, cell_height)
		textures.append(atlas_texture)
	return textures


static func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert(file != null, "Cannot read Luz slash smear manifest")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid Luz slash smear manifest JSON")
	return parsed

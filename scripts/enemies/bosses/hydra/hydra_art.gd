class_name HydraArt
extends BoomboxEffectArt

## The drawn art of La Hidra, read from its manifest (docs/bosses/HYDRA_ANIMATIONS.md):
## the body clips, one sheet per head (manifest entries "head_biter", "head_spitter",
## "head_sweeper"), the props (stump, venom, platforms) and the neck tile. `HydraBoss`,
## `HydraHead` and `HydraVenom` stay the ones that move and hurt; this only decides what
## is seen. Every piece is independent: a missing sheet or clip leaves its own placeholder
## and nothing else, and without any art every call returns null or false.

const BITER_HEAD := "head_biter"
const SPITTER_HEAD := "head_spitter"
const SWEEPER_HEAD := "head_sweeper"
const NECK := "neck"
const STUMP := &"stump"
const VENOM_GLOB := &"venom_glob"
const VENOM_POOL := &"venom_pool"
const VENOM_SPLASH := &"venom_splash"
const PLATFORM := &"platform"
const PLATFORM_ALT := &"platform_alt"
const DEFAULT_CLIP := &"idle"
## Name of the sprite a dressed platform keeps (so a rescan reuses it).
const PLATFORM_SPRITE := "HydraArt"
const CLIP_SPEEDS := {
	"idle": 6.0, "roar": 8.0, "defeat": 8.0,
	"telegraph": 8.0, "attack": 12.0, "dazed": 8.0,
}
## Clips that repeat; every other clip plays once and holds its last frame.
const LOOPING_CLIPS := ["idle"]
## Contract clip -> candidates, closest first, for a clip with no art yet (then `idle`).
const CLIP_FALLBACKS := {
	"dazed": ["idle"], "roar": ["attack", "idle"], "telegraph": ["idle"],
}
const POOL_FPS := 6.0
## HydraHead.Kind -> manifest entry (BITER, SPITTER, SWEEPER).
const HEAD_ENTRIES := [BITER_HEAD, SPITTER_HEAD, SWEEPER_HEAD]

var _manifest_path := ""
var _head_frames := {}


## The art of the manifest at `manifest_path` (a missing file is no art at all).
static func load_from(manifest_path: String) -> HydraArt:
	var catalog := BossAnimationCatalog.new(manifest_path, CLIP_FALLBACKS, CLIP_SPEEDS, LOOPING_CLIPS, DEFAULT_CLIP)
	var art := HydraArt.new(catalog)
	art._manifest_path = manifest_path
	return art


func catalog() -> BossAnimationCatalog:
	return _catalog


## -- Body ----------------------------------------------------------------------------------

func has_body() -> bool:
	return _catalog.has_art()


## -- Heads ---------------------------------------------------------------------------------

func has_head(kind: int) -> bool:
	return head_frames(kind).has_animation(DEFAULT_CLIP)


## The frames of the head of `kind` (empty, but valid, without a sheet). Built once.
func head_frames(kind: int) -> SpriteFrames:
	if not _head_frames.has(kind):
		_head_frames[kind] = _catalog.build_entry_frames(HEAD_ENTRIES[kind])
	return _head_frames[kind]


func head_scale(kind: int) -> float:
	return float(_catalog.manifest_entry(HEAD_ENTRIES[kind]).get("sprite_scale", BossAnimationCatalog.DEFAULT_SPRITE_SCALE))


## The drawn clip of the head of `kind` that stands in for `clip`: the clip itself, else the
## first fallback that exists, else `idle`, else an empty name.
func resolve_head_clip(kind: int, clip: StringName) -> StringName:
	var frames := head_frames(kind)
	if frames.has_animation(clip):
		return clip
	for candidate: Variant in CLIP_FALLBACKS.get(String(clip), []):
		if frames.has_animation(StringName(candidate)):
			return StringName(candidate)
	return DEFAULT_CLIP if frames.has_animation(DEFAULT_CLIP) else &""


## -- Neck ----------------------------------------------------------------------------------

## The seamless horizontal neck tile, or null without art.
func neck_texture() -> Texture2D:
	var file := String(_catalog.manifest_entry(NECK).get("texture", ""))
	if file.is_empty():
		return null
	var path := _manifest_path.get_base_dir().path_join(file)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		return ImageTexture.create_from_image(image) if image != null else null
	return null


## On-screen thickness (px) of the neck, as the processing script recorded it.
func neck_thickness() -> float:
	return float(_catalog.manifest_entry(NECK).get("thickness", 0.0))


## -- Props ---------------------------------------------------------------------------------

## A sprite of `clip` that is `width` px wide (`flip`: facing left); null without that clip.
func width_sprite(clip: StringName, width: float, flip := false) -> AnimatedSprite2D:
	return fit_sprite(PROPS, clip, Vector2(width, width), BoomboxHazard.ArtFit.WIDTH, flip)


## Puts a sprite on `platform` (a body with a `CollisionShape2D` rectangle) that is as wide as
## the shape, its top edge on the collision top (the art may hang below it), and hides the
## placeholder `Visual`. Called again on every rescan: a dressed platform is refitted, not
## doubled. False (and nothing touched) when there is no art for it or no rectangle.
func dress_platform(platform: Node, alt: bool) -> bool:
	var clip := PLATFORM_ALT if alt and has_clip(PROPS, PLATFORM_ALT) else PLATFORM
	var shape_node := platform.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not has_clip(PROPS, clip) or shape_node == null or not shape_node.shape is RectangleShape2D:
		return false
	var size := (shape_node.shape as RectangleShape2D).size
	var sprite := platform.get_node_or_null(PLATFORM_SPRITE) as AnimatedSprite2D
	if sprite != null and sprite.animation != clip:
		platform.remove_child(sprite)
		sprite.queue_free()
		sprite = null
	if sprite == null:
		sprite = width_sprite(clip, size.x)
		sprite.name = PLATFORM_SPRITE
		platform.add_child(sprite)
	var fit := BoomboxHazard.art_scale(art_size(PROPS, clip), Vector2(size.x, size.x), BoomboxHazard.ArtFit.WIDTH)
	sprite.scale = fit
	var height := art_size(PROPS, clip).y * fit.y
	sprite.position = Vector2(shape_node.position.x, shape_node.position.y - size.y * 0.5 + height * 0.5)
	var placeholder := platform.get_node_or_null("Visual") as CanvasItem
	if placeholder != null:
		placeholder.visible = false
	return true


func _loop_fps() -> Dictionary:
	return {VENOM_POOL: POOL_FPS}

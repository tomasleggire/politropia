@tool
class_name BossTelegraph
extends Node2D

## Placeholder telegraph FX shared by boss attacks. It can show a coloured
## glow over the boss body, an aim line and a pool of floor markers. Every node
## is built once in `_ready` and only reused afterwards, so showing, moving and
## hiding a telegraph allocates nothing. Final art replaces the visuals, not the
## calls: the boss logic only talks to this API.
##
## Glyph art (manifest key "glyphs") replaces the plain floor markers and the aim
## line when a caller names a glyph and the art exists; the white glyphs are tinted
## by the same colour language. Without the art, or for a marker with no glyph
## (vault, transition, dive column), the polygon look is kept.
##
## Colour language: amber warns of a ranged attack, red of melee, pale
## moon-silver marks phase two, and plain white marks her vault over Luz.

const RANGED_COLOR := Color(1.0, 0.72, 0.25)
const MELEE_COLOR := Color(0.95, 0.25, 0.2)
const MOON_COLOR := Color(0.8, 0.9, 1.0)
const VAULT_COLOR := Color(1.0, 1.0, 1.0)

## A rain draws one marker per zone, split where its floor changes height.
const MARKER_POOL_SIZE := 16
## Aim lines available at once (a fan draws one per arrow).
const LINE_POOL_SIZE := 5
## Share of a floor marker's width taken by each bright edge.
const MARKER_EDGE_SHARE := 0.07
const MARKER_EDGE_ALPHA := 0.85
const GLOW_MAX_ALPHA := 0.65
const MARKER_ALPHA := 0.38
const LINE_WIDTH := 3.0
## Dotted aim line: the dot texture is padded to this many dot widths per period.
const DOT_PERIOD := 3.0
const DOTTED_LINE_WIDTH := 6.0
## A strip glyph is as wide as its rect but never taller than this many rect heights.
const STRIP_MAX_HEIGHT_FACTOR := 2.0
## Glyph art is dim next to its alpha budget: the pulse alpha is lifted by these.
const GLYPH_ALPHA_GAIN := 1.4
const GLYPH_ALPHA_BIAS := 0.15
## An aim line that still follows Luz is dimmer than a locked one.
const LINE_TRACKING_ALPHA := 0.45

var _glow: Polygon2D
var _lines: Array[Line2D] = []
var _markers: Array[Polygon2D] = []
var _glyph_sprites: Array[Sprite2D] = []
var _glyphs := {}
var _dot_normal: Texture2D
var _dot_hot: Texture2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_glyphs = ArtemisAnimationCatalog.build_glyph_textures()
	_dot_normal = _build_dot_texture(_glyphs.get(&"dot") as AtlasTexture)
	_dot_hot = _build_dot_texture(_glyphs.get(&"dot_hot") as AtlasTexture)
	_build_lines()
	_build_markers()


## Hands the telegraph the boss body so the glow can mirror its silhouette.
func bind_body(body: Polygon2D) -> void:
	_glow = Polygon2D.new()
	_glow.polygon = body.polygon
	_glow.visible = false
	var parent := body.get_parent()
	parent.add_child(_glow)
	parent.move_child(_glow, body.get_index() + 1)


## Tints the body with `color`; `amount` 0 hides it and 1 is the full glow.
func set_glow(color: Color, amount: float) -> void:
	if _glow == null:
		return
	_glow.visible = amount > 0.0
	_glow.color = Color(color, clampf(amount, 0.0, 1.0) * GLOW_MAX_ALPHA)


## A line of `length` px from `from` along `direction` (normalized), both in
## world space. A `locked` line is solid: the aim will not move any more. Use
## `slot` to draw several lines at once (one per fan arrow).
func show_aim_line(from: Vector2, direction: Vector2, length: float, color: Color, locked: bool, slot := 0) -> void:
	var line := _lines[slot]
	line.set_point_position(0, to_local(from))
	line.set_point_position(1, to_local(from + direction * length))
	line.default_color = Color(color, 1.0 if locked else LINE_TRACKING_ALPHA)
	_style_line(line, _dot_hot if locked else _dot_normal)
	line.visible = true


func hide_aim_line() -> void:
	for line: Line2D in _lines:
		line.visible = false


## A rectangle on the floor (world space) in marker slot `slot`, with brighter
## edges. `alpha` lets the caller pulse it. `glyph` (`rain`, `dive` or `stag`) draws
## that glyph art, tinted by `color`, in the rect instead of the polygon, and `hot`
## swaps in its brighter "about to strike" version; an empty or unknown glyph, or
## missing art, keeps the polygon.
func show_floor_marker(slot: int, rect: Rect2, color: Color, alpha := MARKER_ALPHA, glyph := &"", hot := false) -> void:
	var marker := _markers[slot]
	marker.global_position = rect.position
	marker.scale = rect.size
	marker.color = Color(color, alpha)
	for edge: Node in marker.get_children():
		(edge as Polygon2D).color = Color(color, MARKER_EDGE_ALPHA)
	marker.visible = true
	var texture := _glyph_texture(glyph, hot)
	# The polygon stays the marker's state (visible, position); the glyph only hides its drawing.
	marker.modulate.a = 1.0 if texture == null else 0.0
	if texture != null:
		_show_glyph(_glyph_sprites[slot], texture, rect, Color(color, clampf(alpha * GLYPH_ALPHA_GAIN + GLYPH_ALPHA_BIAS, 0.0, 1.0)), glyph == &"stag")
	else:
		_glyph_sprites[slot].visible = false


func hide_floor_marker(slot: int) -> void:
	_markers[slot].visible = false
	_glyph_sprites[slot].visible = false


func hide_floor_markers() -> void:
	for slot: int in _markers.size():
		hide_floor_marker(slot)


func clear() -> void:
	set_glow(Color.WHITE, 0.0)
	hide_aim_line()
	hide_floor_markers()


func is_aim_line_visible(slot := 0) -> bool:
	return slot < _lines.size() and _lines[slot].visible


func visible_aim_line_count() -> int:
	var count := 0
	for line: Line2D in _lines:
		count += 1 if line.visible else 0
	return count


func is_glowing() -> bool:
	return _glow != null and _glow.visible


func is_floor_marker_visible(slot: int) -> bool:
	return _markers[slot].visible


func _glyph_texture(glyph: StringName, hot: bool) -> Texture2D:
	if glyph.is_empty() or not (glyph in [&"rain", &"dive", &"stag"]):
		return null
	return _glyphs.get(StringName(String(glyph) + ("_hot" if hot else ""))) as Texture2D


## Fits a glyph to `rect`, resting on its bottom edge. A strip is as wide as the rect
## and keeps its proportions up to `STRIP_MAX_HEIGHT_FACTOR` rect heights; the tall
## wall glyph is contained, so the stag head is never squashed.
func _show_glyph(sprite: Sprite2D, texture: Texture2D, rect: Rect2, tint: Color, contain: bool) -> void:
	var size := texture.get_size()
	var fit := Vector2.ONE
	if contain:
		var uniform := minf(rect.size.x / size.x, rect.size.y / size.y)
		fit = Vector2(uniform, uniform)
	else:
		var across := rect.size.x / size.x
		fit = Vector2(across, minf(across, STRIP_MAX_HEIGHT_FACTOR * rect.size.y / size.y))
	sprite.texture = texture
	sprite.scale = fit
	sprite.modulate = tint
	sprite.global_position = Vector2(rect.get_center().x - size.x * fit.x * 0.5, rect.end.y - size.y * fit.y)
	sprite.visible = true


## One dot padded on the right so a tiled Line2D reads as dots with gaps.
func _build_dot_texture(source: AtlasTexture) -> Texture2D:
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	var padded := Image.create_empty(int(image.get_width() * DOT_PERIOD), image.get_height(), false, Image.FORMAT_RGBA8)
	padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(padded)


## A dotted line when there is a dot texture; the plain round-capped line otherwise.
func _style_line(line: Line2D, dot: Texture2D) -> void:
	line.texture = dot
	line.width = LINE_WIDTH if dot == null else DOTTED_LINE_WIDTH
	var cap := Line2D.LINE_CAP_ROUND if dot == null else Line2D.LINE_CAP_NONE
	line.begin_cap_mode = cap
	line.end_cap_mode = cap


func _build_lines() -> void:
	for i: int in LINE_POOL_SIZE:
		var line := Line2D.new()
		line.width = LINE_WIDTH
		line.z_index = 2
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.add_point(Vector2.ZERO)
		line.add_point(Vector2.ZERO)
		line.visible = false
		add_child(line)
		_lines.append(line)


## Unit squares positioned and scaled per use, so a marker never rebuilds its
## polygon.
func _build_markers() -> void:
	var unit := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for i: int in MARKER_POOL_SIZE:
		var marker := Polygon2D.new()
		marker.polygon = unit
		marker.top_level = true
		marker.z_index = -1
		marker.visible = false
		marker.add_child(_make_edge(0.0))
		marker.add_child(_make_edge(1.0 - MARKER_EDGE_SHARE))
		add_child(marker)
		_markers.append(marker)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.top_level = true
		sprite.z_index = -1
		sprite.visible = false
		add_child(sprite)
		_glyph_sprites.append(sprite)


func _make_edge(left: float) -> Polygon2D:
	var edge := Polygon2D.new()
	var right := left + MARKER_EDGE_SHARE
	edge.polygon = PackedVector2Array([Vector2(left, 0.0), Vector2(right, 0.0), Vector2(right, 1.0), Vector2(left, 1.0)])
	return edge

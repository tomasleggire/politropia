class_name HydraHead
extends Area2D

## One head of the Hydra: a hurtbox part with its own health, a neck back to the
## body and an attack hitbox. Luz's slash lands on the head (collision layer 8,
## like any enemy) and the head hands the hit to the boss, which owns the shared
## health pool, the bar, the phases and the final blow. The head only knows its
## own health, where it rests, where it is heading and how it looks.
##
## A head with no health is severed for good (until the boss resets): no hurtbox,
## no hitbox, just a dark stump.
##
## Art (docs/bosses/HYDRA_ANIMATIONS.md): `bind_art` dresses the head with a sprite, the
## neck with a textured line and the stump with a sprite. Each is independent: a piece
## with no art keeps drawing its placeholder, so a missing sheet never breaks the others.

enum Kind { BITER, SPITTER, SWEEPER }
## Which of the three tiers the head rests at: the lowest level, the middle one
## and the highest one of the arena platforms.
enum Tier { LOW, MID, HIGH }

const ENEMY_LAYER := 8
const PLAYER_LAYER := 1
const NECK_COLOR_SHADE := 0.7
const STUMP_COLOR := Color(0.2, 0.17, 0.2)
const FLASH_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const EYE_COLOR := Color(1.0, 0.95, 0.5)
const NECK_WIDTH := 16.0
const STUMP_DROOP := 8.0
const HEAD_POLYGON := [
	Vector2(-30.0, -6.0), Vector2(-20.0, -19.0), Vector2(4.0, -22.0), Vector2(22.0, -13.0),
	Vector2(25.0, 9.0), Vector2(6.0, 20.0), Vector2(-20.0, 14.0), Vector2(-31.0, 5.0),
]
const JAW_POLYGON := [Vector2(-30.0, 5.0), Vector2(-20.0, 14.0), Vector2(6.0, 20.0), Vector2(0.0, 9.0)]
const ROAR_GAPE := 9.0
## Art: the neck sags a little between its ends (never in a sweep) and the stump is this wide.
const NECK_SAG := 0.08
const NECK_MAX_SAG := 12.0
const NECK_SEGMENTS := 8
const STUMP_ART_WIDTH := 38.0
const STUMP_ROOT_INSET := 8.0
const IDLE := &"idle"
const TELEGRAPH := &"telegraph"
const ATTACK := &"attack"
const DAZED := &"dazed"
const ROAR := &"roar"

@export var kind := Kind.BITER
@export var tier := Tier.LOW

@export_group("Health")
@export var head_max_health := 12
## Seconds the head stays white after a hit.
@export var flash_time := 0.1

@export_group("Placement")
## Horizontal rest offset from the boss root (negative: to its left).
@export var rest_dx := -190.0
## Where the neck leaves the body, in boss space.
@export var shoulder := Vector2(-48.0, -30.0)
@export var hurtbox_size := Vector2(48.0, 44.0)
## How far a severed neck reaches before it stops.
@export var stump_length := 28.0

@export_group("Look")
@export var head_color := Color(0.8, 0.25, 0.25)

var health := 0
## World-space rest position of the head, set by the boss from the platform tiers.
var rest_global := Vector2.ZERO
## Where the head is heading and how fast (px/s); the boss moves it every frame.
var goal := Vector2.ZERO
var speed := 600.0
var hitbox: Area2D

var _boss: Node
var _hurtbox: CollisionShape2D
var _hitbox_shape: CollisionShape2D
var _severed := false
var _stuck := false
var _horizontal_neck := false
var _flash_left := 0.0
var _roar_left := 0.0
var _roar_clip := ROAR
var _roar_restart := false
var _pose := IDLE
var _clip := &""
var _art: HydraArt
var _sprite: AnimatedSprite2D
var _sprite_fx: BossSpriteFx
var _neck: Line2D
var _stump_sprite: AnimatedSprite2D
var _stuck_mark: StuckMark


## The cross over a stuck head whose art has no `dazed` pose of its own.
class StuckMark extends Node2D:
	func _draw() -> void:
		draw_line(Vector2(-10.0, -12.0), Vector2(-2.0, -4.0), Color.BLACK, 2.0)
		draw_line(Vector2(-2.0, -12.0), Vector2(-10.0, -4.0), Color.BLACK, 2.0)


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	z_index = 1
	_build_hurtbox()
	_build_hitbox()
	health = head_max_health
	rest_global = global_position
	goal = global_position


func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_roar_left = maxf(_roar_left - delta, 0.0)
	_sync_art()
	queue_redraw()


func _draw() -> void:
	var shoulder_local := to_local(_shoulder_global())
	if _severed:
		if _stump_sprite == null:
			_draw_stump(shoulder_local)
		return
	if _neck == null:
		_draw_neck(shoulder_local)
	if _sprite == null:
		_draw_head()


func _draw_neck(shoulder_local: Vector2) -> void:
	var neck_from := shoulder_local
	if _horizontal_neck:
		neck_from = Vector2(shoulder_local.x, 0.0)
	draw_line(neck_from, Vector2.ZERO, head_color.darkened(1.0 - NECK_COLOR_SHADE), NECK_WIDTH)
	draw_circle(neck_from, NECK_WIDTH * 0.5, head_color.darkened(1.0 - NECK_COLOR_SHADE))


func _draw_head() -> void:
	draw_colored_polygon(PackedVector2Array(HEAD_POLYGON), head_color)
	var jaw := PackedVector2Array(JAW_POLYGON)
	if _roar_left > 0.0:
		for i: int in jaw.size():
			jaw[i] += Vector2(0.0, ROAR_GAPE)
	draw_colored_polygon(jaw, head_color.darkened(0.25))
	draw_circle(Vector2(-6.0, -8.0), 4.0, EYE_COLOR)
	if _stuck:
		draw_line(Vector2(-10.0, -12.0), Vector2(-2.0, -4.0), Color.BLACK, 2.0)
		draw_line(Vector2(-2.0, -12.0), Vector2(-10.0, -4.0), Color.BLACK, 2.0)
	if _flash_left > 0.0:
		draw_colored_polygon(PackedVector2Array(HEAD_POLYGON), FLASH_COLOR)


## Binds the boss that owns the shared pool (duck-typed: it needs `hit_head`).
func bind_boss(boss: Node) -> void:
	_boss = boss


## Luz's slash lands here (see Player's attack hit seam). The boss decides.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if _severed or _boss == null:
		return false
	return bool(_boss.call(&"hit_head", self, damage, source_position, attack_name))


func is_severed() -> bool:
	return _severed


func is_stuck() -> bool:
	return _stuck


func is_roaring() -> bool:
	return _roar_left > 0.0


func is_flashing() -> bool:
	return _flash_left > 0.0


## The clip the head sprite is showing (the contract name asked for, not its fallback).
func get_clip() -> StringName:
	return _clip


func get_sprite() -> AnimatedSprite2D:
	return _sprite


func get_neck() -> Line2D:
	return _neck


func get_stump_sprite() -> AnimatedSprite2D:
	return _stump_sprite


func is_hurtbox_enabled() -> bool:
	return _hurtbox != null and not _hurtbox.disabled and monitorable


func is_hitbox_armed() -> bool:
	return hitbox != null and hitbox.monitoring


## The world rectangle of the hurtbox.
func get_hurtbox_rect() -> Rect2:
	return Rect2(global_position - hurtbox_size * 0.5, hurtbox_size)


func get_shoulder_global() -> Vector2:
	return _shoulder_global()


func flash() -> void:
	_flash_left = flash_time
	if _sprite_fx != null:
		_sprite_fx.set_flash(true)


## Opens the jaw for `duration` seconds. `clip` is the art that plays meanwhile: the roar of
## a phase change, or the attack when the spitter throws a glob (each call restarts it).
func roar(duration: float, clip := ROAR) -> void:
	_roar_left = duration
	_roar_clip = clip
	_roar_restart = true


## The clip of the attack in progress (`telegraph`, `attack`) or `idle`; a stuck head and a
## roar override it. The boss sets it at the start of every phase of a run.
func set_pose(clip: StringName) -> void:
	_pose = clip


func set_stuck(on: bool) -> void:
	_stuck = on


## A neck laid flat at the head's height (the sweep) instead of reaching diagonally.
func set_horizontal_neck(on: bool) -> void:
	_horizontal_neck = on


## Moves toward `goal` by the speed of this frame.
func advance(delta: float) -> void:
	if _severed:
		return
	global_position = global_position.move_toward(goal, speed * delta)


func at_goal() -> bool:
	return global_position.distance_to(goal) < 0.5


## Places the head on `point` at once (layout, reset).
func snap_to(point: Vector2) -> void:
	global_position = point
	goal = point


## Sets the hitbox to a rectangle in head space (centre and size).
func set_hitbox_rect(rect: Rect2) -> void:
	var shape := _hitbox_shape.shape as RectangleShape2D
	shape.size = rect.size
	_hitbox_shape.position = rect.get_center()


## Severed for good: no hurtbox, no hitbox, a stump instead of a head.
func sever() -> void:
	_severed = true
	_stuck = false
	_horizontal_neck = false
	_flash_left = 0.0
	_roar_left = 0.0
	_pose = IDLE
	_set_hurtbox(false)
	_set_hitbox_off()
	_sync_art()
	queue_redraw()


## Full health, hurtbox back, resting at `point`.
func restore(point: Vector2) -> void:
	_severed = false
	_stuck = false
	_horizontal_neck = false
	_flash_left = 0.0
	_roar_left = 0.0
	_pose = IDLE
	_clip = &""
	health = head_max_health
	rest_global = point
	global_position = point
	goal = point
	_set_hurtbox(true)
	_set_hitbox_off()
	_sync_art()
	queue_redraw()


## -- Art -------------------------------------------------------------------------------------

## Dresses the head with whatever `art` draws: the head sprite, the textured neck and the
## stump sprite. A piece the art does not have keeps its placeholder.
func bind_art(art: HydraArt) -> void:
	_art = art
	_build_sprite()
	_build_neck()
	_build_stump()
	_clip = &""
	_sync_art()
	queue_redraw()


func _build_sprite() -> void:
	if not _art.has_head(kind):
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = _art.head_frames(kind)
	_sprite.texture_filter = BoomboxEffectArt.FILTER
	# The art faces right; the head faces the arena, to the left.
	var art_scale := _art.head_scale(kind)
	_sprite.scale = Vector2(-art_scale, art_scale)
	add_child(_sprite)
	_sprite_fx = BossSpriteFx.new(_sprite)
	_stuck_mark = StuckMark.new()
	_stuck_mark.visible = false
	add_child(_stuck_mark)


## A tiled line from the shoulder to the head: behind the head, never over it.
func _build_neck() -> void:
	var texture := _art.neck_texture()
	if texture == null or _art.neck_thickness() <= 0.0:
		return
	_neck = Line2D.new()
	_neck.name = "Neck"
	_neck.texture = texture
	_neck.texture_mode = Line2D.LINE_TEXTURE_TILE
	_neck.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_neck.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_neck.width = _art.neck_thickness()
	_neck.show_behind_parent = true
	add_child(_neck)


func _build_stump() -> void:
	_stump_sprite = _art.width_sprite(HydraArt.STUMP, STUMP_ART_WIDTH, true)
	if _stump_sprite == null:
		return
	_stump_sprite.name = "Stump"
	_stump_sprite.visible = false
	add_child(_stump_sprite)


## Keeps the art pieces in step with the head. A pure read of the head's own state.
func _sync_art() -> void:
	if _art == null:
		return
	_sync_neck()
	_sync_stump()
	_sync_sprite()


func _sync_neck() -> void:
	if _neck == null:
		return
	_neck.visible = not _severed
	if not _severed:
		_neck.points = _neck_points(to_local(_shoulder_global()))


## From the shoulder to the head origin, flat in a sweep and with a slight sag otherwise.
## Both ends are exact.
func _neck_points(shoulder_local: Vector2) -> PackedVector2Array:
	var from := shoulder_local
	var sag := 0.0
	if _horizontal_neck:
		from.y = 0.0
	else:
		sag = minf(from.length() * NECK_SAG, NECK_MAX_SAG)
	var points := PackedVector2Array([from])
	for i: int in range(1, NECK_SEGMENTS):
		var u := float(i) / float(NECK_SEGMENTS)
		points.append(from.lerp(Vector2.ZERO, u) + Vector2(0.0, sag * sin(PI * u)))
	points.append(Vector2.ZERO)
	return points


func _sync_stump() -> void:
	if _stump_sprite == null:
		return
	_stump_sprite.visible = _severed
	if not _severed:
		return
	var half := STUMP_ART_WIDTH * 0.5
	_stump_sprite.position = to_local(_shoulder_global()) + Vector2(STUMP_ROOT_INSET - half, STUMP_DROOP * 0.5)


func _sync_sprite() -> void:
	if _sprite == null:
		return
	_sprite.visible = not _severed
	if _severed:
		_sprite_fx.set_flash(false)
		_stuck_mark.visible = false
		return
	var wanted := _wanted_clip()
	if wanted != _clip or _roar_restart:
		_play(wanted)
	_roar_restart = false
	_sprite_fx.set_flash(_flash_left > 0.0)
	_stuck_mark.visible = _stuck and _art.resolve_head_clip(kind, DAZED) != DAZED


func _wanted_clip() -> StringName:
	if _roar_left > 0.0:
		return _roar_clip
	if _stuck:
		return DAZED
	return _pose


## Plays `clip` (or the closest drawn one); a clip asked for again restarts only when a roar
## did it, so a pose held for a while is never reset.
func _play(clip: StringName) -> void:
	_clip = clip
	var resolved := _art.resolve_head_clip(kind, clip)
	if resolved.is_empty():
		return
	var duration := _roar_left if clip == _roar_clip and _roar_left > 0.0 else 0.0
	var frames := _sprite.sprite_frames
	var fit := 1.0
	var count := frames.get_frame_count(resolved)
	var fps := frames.get_animation_speed(resolved)
	if duration > 0.0 and count > 0 and fps > 0.0:
		fit = (float(count) / fps) / duration
	if _sprite.animation == resolved and _roar_restart:
		_sprite.stop()
	_sprite.play(resolved, fit)


func _shoulder_global() -> Vector2:
	var host := get_parent()
	var anchor := host.get_parent() as Node2D if host != null else null
	if anchor == null:
		return global_position + shoulder
	return anchor.to_global(shoulder)


func _build_hurtbox() -> void:
	_hurtbox = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = hurtbox_size
	_hurtbox.shape = shape
	add_child(_hurtbox)


## The head's attack box: off the enemy layer, it only watches Luz.
func _build_hitbox() -> void:
	hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = PLAYER_LAYER
	hitbox.monitoring = false
	hitbox.monitorable = false
	_hitbox_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(44.0, 44.0)
	_hitbox_shape.shape = shape
	hitbox.add_child(_hitbox_shape)
	add_child(hitbox)


## Deferred: a hit that severs a head arrives from inside Luz's physics callback.
func _set_hurtbox(on: bool) -> void:
	_hurtbox.set_deferred(&"disabled", not on)
	set_deferred(&"monitorable", on)


func _set_hitbox_off() -> void:
	if hitbox != null:
		hitbox.set_deferred(&"monitoring", false)


func _draw_stump(shoulder_local: Vector2) -> void:
	var tip := shoulder_local + Vector2(-stump_length, STUMP_DROOP)
	draw_line(shoulder_local, tip, STUMP_COLOR, NECK_WIDTH + 2.0)
	draw_circle(tip, (NECK_WIDTH + 2.0) * 0.5, STUMP_COLOR.lightened(0.08))

class_name BoomboxHazard
extends Node2D

## One placeholder hazard of the Boombox Teacher: a thrust, a kick, a sound wave, a
## note, the briefcase, a falling letter or the bass shock. It is an axis aligned box
## in world space that hurts Luz at most once, polled every physics frame against her
## live collider (so a crouch really lowers her hurtbox). It lives beside the boss,
## never under it, and removes itself when its lifetime, its walls or its floor say so.
##
## Motions: STATIC stays put, LINEAR moves with `velocity` (plus gravity and an
## optional floor bounce), BOOMERANG flies out to `far_point` and comes back to `home`.
## Dash i-frames: a hazard that touches her while she is dash-invulnerable is DODGED
## and cannot hurt her until it has stopped overlapping her (so her i-frames ending
## inside the same hazard never hurts). A hit refused for any other reason, such as
## the i-frames after a hurt, is retried on the next frame.

enum Motion { STATIC, LINEAR, BOOMERANG }
enum Look { RECT, POINTER, DISC, GLYPH }

const OUTLINE_LIGHTEN := 0.45
const OUTLINE_WIDTH := 2.0
const PENDING_ALPHA := 0.35
const FILL_ALPHA := 0.85
const GLYPH_FONT_SIZE := 26
const POINTER_TIP := 14.0
const FALLBACK_LUZ_SIZE := Vector2(29.0, 46.0)
const LUZ_SHAPE_PATH := "CollisionShape2D"

## Half size of the box; the node position is its centre.
var half_extents := Vector2(10.0, 10.0)
var color := Color.WHITE
var look := Look.RECT
## -1 or 1: the side a POINTER look points to.
var dir := 1
var motion := Motion.STATIC
var velocity := Vector2.ZERO
var gravity := 0.0
## Upward speed given on touching `floor_y` (0 disables the bounce).
var bounce_speed := 0.0
var floor_y := 0.0
var despawn_at_floor := false
var wall_left := -INF
var wall_right := INF
var lifetime := 1.0
## Seconds drawn dim and harmless before the hazard becomes dangerous.
var arm_delay := 0.0
var damage := 1
## Cleared with its attack when the attack is cut short (thrusts, kicks, shocks).
var bound := false
var glyph := ""
var target: Player
var far_point := Vector2.ZERO
var out_time := 1.0
var back_time := 1.0
var home := Callable()

var _age := 0.0
var _origin := Vector2.ZERO
var _alive := true
var _spent := false
var _dodged := false


func _init() -> void:
	top_level = true
	z_index = 3


func _ready() -> void:
	_origin = position


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_age += delta
	_advance(delta)
	if not _alive:
		return
	_try_hurt()
	queue_redraw()


func _draw() -> void:
	var live := _age >= arm_delay
	var fill := Color(color, FILL_ALPHA) if live else Color(color, PENDING_ALPHA)
	var edge := color.lightened(OUTLINE_LIGHTEN)
	var box := Rect2(-half_extents, half_extents * 2.0)
	match look:
		Look.DISC:
			draw_circle(Vector2.ZERO, half_extents.x, fill)
			draw_arc(Vector2.ZERO, half_extents.x, 0.0, TAU, 20, edge, OUTLINE_WIDTH)
		Look.GLYPH:
			draw_rect(box, Color(color, 0.35))
			draw_rect(box, edge, false, OUTLINE_WIDTH)
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(-half_extents.x * 0.45, half_extents.y * 0.45), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, GLYPH_FONT_SIZE, Color.WHITE)
		Look.POINTER:
			draw_rect(box, fill)
			var tip_x := float(dir) * half_extents.x
			draw_colored_polygon(PackedVector2Array([
				Vector2(tip_x, -half_extents.y - 3.0),
				Vector2(tip_x + float(dir) * POINTER_TIP, 0.0),
				Vector2(tip_x, half_extents.y + 3.0),
			]), edge)
		_:
			draw_rect(box, fill)
			draw_rect(box, edge, false, OUTLINE_WIDTH)


## Luz's live hurtbox in world space (it shrinks while she crouches).
static func luz_rect(player: Player) -> Rect2:
	var shape_node := player.get_node_or_null(LUZ_SHAPE_PATH) as CollisionShape2D
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2(player.global_position - Vector2(FALLBACK_LUZ_SIZE.x * 0.5, FALLBACK_LUZ_SIZE.y), FALLBACK_LUZ_SIZE)
	var size := (shape_node.shape as RectangleShape2D).size
	return Rect2(shape_node.global_position - size * 0.5, size)


func get_rect() -> Rect2:
	return Rect2(position - half_extents, half_extents * 2.0)


func is_alive() -> bool:
	return _alive


## True once the hazard hurt Luz (it never hurts twice).
func has_hurt() -> bool:
	return _spent


## True while Luz dashed into the hazard and is still inside it.
func is_dodged() -> bool:
	return _dodged


## Hides, stops and frees the hazard at once: it can no longer hurt her this frame.
func retire() -> void:
	if not _alive:
		return
	_alive = false
	visible = false
	set_physics_process(false)
	queue_free()


func _advance(delta: float) -> void:
	match motion:
		Motion.STATIC:
			if _age >= lifetime:
				retire()
		Motion.LINEAR:
			_advance_linear(delta)
		Motion.BOOMERANG:
			_advance_boomerang()


func _advance_linear(delta: float) -> void:
	velocity.y += gravity * delta
	position += velocity * delta
	if bounce_speed > 0.0 and position.y >= floor_y:
		position.y = floor_y
		velocity.y = -bounce_speed
	var out_of_walls := position.x < wall_left - half_extents.x or position.x > wall_right + half_extents.x
	var landed := despawn_at_floor and position.y >= floor_y
	if out_of_walls or landed or _age >= lifetime:
		retire()


## Out with an ease-out (slowing at the far point), back with an ease-in.
func _advance_boomerang() -> void:
	if _age < out_time:
		position = _origin.lerp(far_point, sin(_age / out_time * PI * 0.5))
		return
	if not home.is_valid() or _age >= out_time + back_time:
		retire()
		return
	var back := (_age - out_time) / back_time
	position = far_point.lerp(home.call() as Vector2, 1.0 - cos(back * PI * 0.5))


func _try_hurt() -> void:
	if _spent or _age < arm_delay or not is_instance_valid(target):
		return
	if not get_rect().intersects(luz_rect(target)):
		_dodged = false
		return
	if target.is_dash_invulnerable():
		_dodged = true
		return
	if not _dodged and target.take_damage(damage, global_position):
		_spent = true

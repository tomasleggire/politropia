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
	queue_redraw()


func _draw() -> void:
	var shoulder_local := to_local(_shoulder_global())
	if _severed:
		_draw_stump(shoulder_local)
		return
	var neck_from := shoulder_local
	if _horizontal_neck:
		neck_from = Vector2(shoulder_local.x, 0.0)
	draw_line(neck_from, Vector2.ZERO, head_color.darkened(1.0 - NECK_COLOR_SHADE), NECK_WIDTH)
	draw_circle(neck_from, NECK_WIDTH * 0.5, head_color.darkened(1.0 - NECK_COLOR_SHADE))
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


func roar(duration: float) -> void:
	_roar_left = duration


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
	_set_hurtbox(false)
	_set_hitbox_off()
	queue_redraw()


## Full health, hurtbox back, resting at `point`.
func restore(point: Vector2) -> void:
	_severed = false
	_stuck = false
	_horizontal_neck = false
	_flash_left = 0.0
	_roar_left = 0.0
	health = head_max_health
	rest_global = point
	global_position = point
	goal = point
	_set_hurtbox(true)
	_set_hitbox_off()
	queue_redraw()


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

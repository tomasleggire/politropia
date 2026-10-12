@tool
class_name SpectralStag
extends Area2D

## Artemis's phase-two summon: a silver stag that charges along the floor and
## hurts Luz once per pass. It is one node that Artemis reuses for every charge
## (`launch` revives it, `deactivate` parks it), so a charge allocates nothing.
##
## The hitbox is `WIDTH` x `HEIGHT` and stands on the floor, lower than a normal
## jump (84 px) and brief enough for a dash, so both answer it. Luz's own damage
## gate decides about dash i-frames and i-frames after a hit. Placeholder visual
## only: the animation contract replaces it without touching this logic.

## Keep in step with the CollisionShape2D of the scene.
const WIDTH := 60.0
const HEIGHT := 48.0
const PLAYER_MASK := 1
const DAMAGE := 1

var _active := false
var _dir := 1
var _speed := 0.0
var _end_x := 0.0
var _hit := false
var _target: Player


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = PLAYER_MASK
	top_level = true
	deactivate()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	global_position.x += float(_dir) * _speed * delta
	_poll_target()
	if (global_position.x - _end_x) * float(_dir) >= 0.0:
		deactivate()


func is_active() -> bool:
	return _active


## True once this charge has hurt Luz.
func has_hit() -> bool:
	return _hit


func get_direction() -> int:
	return _dir


## Starts a charge at `from` (floor level, world space) toward `dir` (-1 or 1);
## it parks itself when its centre reaches `end_x`.
func launch(from: Vector2, dir: int, speed: float, end_x: float, target: Player) -> void:
	global_position = from
	_dir = dir
	_speed = speed
	_end_x = end_x
	_target = target
	_hit = false
	_active = true
	scale.x = float(dir)
	visible = true
	set_deferred(&"monitoring", true)
	set_physics_process(true)
	reset_physics_interpolation()


func deactivate() -> void:
	_active = false
	visible = false
	set_deferred(&"monitoring", false)
	set_physics_process(false)


## Once per pass. `overlaps_body` allocates nothing, unlike listing the bodies.
func _poll_target() -> void:
	if _hit or not monitoring or not is_instance_valid(_target):
		return
	if overlaps_body(_target) and _target.take_damage(DAMAGE, global_position):
		_hit = true

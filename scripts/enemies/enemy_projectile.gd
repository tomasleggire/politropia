class_name EnemyProjectile
extends Area2D

## A shot fired by the Shooter. It flies straight, costs Luz one pip when it
## touches her and dies on solids, on her, after `lifetime` seconds, or when
## her slash cuts it. `receive_hit` destroys it and returns false, so cutting it
## gives no soul.
##
## Instances are pooled by their shooter: `launch()` revives one and
## `deactivate()` parks it, so nothing is allocated while enemies fight.

const ENEMY_LAYER := 8
const SOLIDS_AND_PLAYER_MASK := 1

@export var damage := 1
@export var lifetime := 3.0

var _active := false
var _velocity := Vector2.ZERO
var _life_left := 0.0


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = SOLIDS_AND_PLAYER_MASK
	top_level = true
	body_entered.connect(_on_body_entered)
	deactivate()


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life_left -= delta
	if _life_left <= 0.0:
		deactivate()


func is_active() -> bool:
	return _active


func get_velocity() -> Vector2:
	return _velocity


## Fires from `from` along `direction` (normalized) at `speed` px/s.
func launch(from: Vector2, direction: Vector2, speed: float) -> void:
	global_position = from
	_velocity = direction * speed
	_life_left = lifetime
	_active = true
	visible = true
	set_deferred(&"monitoring", true)
	set_deferred(&"monitorable", true)
	set_physics_process(true)
	reset_physics_interpolation()


func deactivate() -> void:
	_active = false
	_velocity = Vector2.ZERO
	visible = false
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	set_physics_process(false)


## Luz's slash lands here (see Player's attack hit seam). False on purpose:
## it is not a target that recoils or bounces her.
func receive_hit(_damage: int, _source_position: Vector2, _attack_name: StringName = &"") -> bool:
	if _active:
		deactivate()
	return false


func _on_body_entered(body: Node2D) -> void:
	if not _active:
		return
	var player := body as Player
	if player != null and player.is_dash_invulnerable():
		# Dash i-frames: the shot passes through her.
		return
	if player != null:
		# Deferred: hurting her touches her own areas, which physics forbids
		# while it is still flushing the query that raised this signal.
		player.take_damage.call_deferred(damage, global_position)
	deactivate()

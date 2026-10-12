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
const ONE_WAY_MASK := 2
## Matches the circle shape of the scene: the leading edge of the shot.
const SHOT_RADIUS := 5.0

@export var damage := 1
@export var lifetime := 3.0
## Stops on the top of a one-way platform when moving down, like Luz's feet do.
## Moving up or sideways it passes. Off for plain shooters.
@export var stops_on_one_ways := false

var _active := false
var _velocity := Vector2.ZERO
var _life_left := 0.0
var _one_way_probe: RayCast2D


func _ready() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = SOLIDS_AND_PLAYER_MASK
	top_level = true
	body_entered.connect(_on_body_entered)
	if stops_on_one_ways:
		_build_one_way_probe()
	deactivate()


func _physics_process(delta: float) -> void:
	var step := _velocity * delta
	if stops_on_one_ways and step.y > 0.0 and _lands_on_one_way(step):
		return
	global_position += step
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


## One reusable ray per shot (no allocation while flying). Only layer 2 is seen:
## solids are the Area2D's job.
func _build_one_way_probe() -> void:
	_one_way_probe = RayCast2D.new()
	_one_way_probe.collision_mask = ONE_WAY_MASK
	_one_way_probe.enabled = false
	add_child(_one_way_probe)


## Casts this step (plus the shot's radius ahead) and parks the shot on the hit.
## A downward ray hits a one-way top; an upward or flat one never does, and a
## shot already inside the platform is not caught by it.
func _lands_on_one_way(step: Vector2) -> bool:
	var reach := step + step.normalized() * SHOT_RADIUS
	_one_way_probe.target_position = _one_way_probe.to_local(global_position + reach)
	_one_way_probe.force_raycast_update()
	if not _one_way_probe.is_colliding():
		return false
	global_position = _one_way_probe.get_collision_point() - step.normalized() * SHOT_RADIUS
	deactivate()
	return true


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

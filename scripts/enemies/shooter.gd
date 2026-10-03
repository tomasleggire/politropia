@tool
class_name Shooter
extends FlyingEnemy

## Keeps its distance from Luz and shoots at her (the Aspid). Once it sees her
## it hovers 170 to 230 px away, a little above her, and every `fire_interval`
## seconds swells for `telegraph_time` and fires a spread of projectiles aimed
## at where she stood when it fired.
##
## Projectiles are pooled here and never outlive their room: they are cleared
## when the shooter pauses (Luz left its room), resets or dies.
## Placeholder visuals only; the Greek look comes later.

const PROJECTILE_SCENE := preload("res://scenes/enemies/enemy_projectile.tscn")
const GLOW_MIN_SCALE := 0.4
const GLOW_MAX_SCALE := 1.6

@export_group("Distance")
@export var near_distance := 170.0
@export var far_distance := 230.0
## Preferred height of its centre above her centre.
@export var hover_above := 60.0
@export var move_speed := 110.0
@export var move_acceleration := 360.0
@export var vertical_deadband := 12.0

@export_group("Fire")
@export var fire_interval := 1.6
@export var telegraph_time := 0.35
@export_range(1, 3) var volley_count := 3
@export var spread_degrees := 15.0
@export var projectile_speed := 210.0

@onready var _mouth: Node2D = $Visual/Mouth
@onready var _glow: Node2D = $Visual/Glow

var _pool: Array[EnemyProjectile] = []
var _fire_wait := 0.0
var _telegraph_left := 0.0
var _telegraphing := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	for i: int in volley_count * 2:
		_pool.append(_make_projectile())
	_set_glow(0.0)


func _engaged_think(delta: float) -> void:
	var to_player := _player_center() - get_body_center()
	_face_x(to_player.x)
	velocity = velocity.move_toward(_wanted_velocity(-to_player), move_acceleration * delta)
	_update_fire_cycle(delta)


## Projectiles never survive the room: a pause means Luz left.
func set_ai_active(active: bool) -> void:
	super.set_ai_active(active)
	if not active:
		clear_projectiles()


func make_corpse_at(at: Vector2, facing: int) -> void:
	clear_projectiles()
	super.make_corpse_at(at, facing)


func clear_projectiles() -> void:
	for shot: EnemyProjectile in _pool:
		shot.deactivate()


func active_projectile_count() -> int:
	var count := 0
	for shot: EnemyProjectile in _pool:
		count += 1 if shot.is_active() else 0
	return count


func get_active_projectiles() -> Array[EnemyProjectile]:
	var shots: Array[EnemyProjectile] = []
	for shot: EnemyProjectile in _pool:
		if shot.is_active():
			shots.append(shot)
	return shots


func is_telegraphing() -> bool:
	return _telegraphing


func _reset_ai() -> void:
	super._reset_ai()
	clear_projectiles()
	_cancel_telegraph()
	_fire_wait = 0.0


func _on_engaged() -> void:
	_fire_wait = fire_interval - telegraph_time
	_cancel_telegraph()


## Away from her when too close, toward her when too far, and up to its
## preferred height. `away` points from Luz to the shooter.
func _wanted_velocity(away: Vector2) -> Vector2:
	var distance := away.length()
	var wanted := Vector2.ZERO
	if distance < near_distance and distance > 0.001:
		wanted = away / distance * move_speed
	elif distance > far_distance:
		wanted = -away / distance * move_speed
	var height_error := -hover_above - away.y
	if absf(height_error) > vertical_deadband:
		wanted.y = clampf(wanted.y + height_error * 2.0, -move_speed, move_speed)
	return wanted


func _update_fire_cycle(delta: float) -> void:
	if _telegraphing:
		_telegraph_left -= delta
		_set_glow(1.0 - maxf(_telegraph_left, 0.0) / telegraph_time)
		if _telegraph_left <= 0.0:
			_fire()
			_cancel_telegraph()
			_fire_wait = fire_interval - telegraph_time
		return
	_fire_wait -= delta
	if _fire_wait <= 0.0 and _sees_player:
		_telegraphing = true
		_telegraph_left = telegraph_time


func _cancel_telegraph() -> void:
	_telegraphing = false
	_telegraph_left = 0.0
	_set_glow(0.0)


func _set_glow(amount: float) -> void:
	_glow.visible = amount > 0.0
	_glow.scale = Vector2.ONE * lerpf(GLOW_MIN_SCALE, GLOW_MAX_SCALE, amount)


## Aims at where Luz is right now; the spread fans out around that line.
func _fire() -> void:
	var from := _visual.to_global(_mouth.position)
	var aim := (_player_center() - from).normalized()
	for i: int in volley_count:
		var angle := 0.0
		if volley_count > 1:
			angle = deg_to_rad(lerpf(-spread_degrees, spread_degrees, float(i) / float(volley_count - 1)))
		_acquire_projectile().launch(from, aim.rotated(angle), projectile_speed)


func _acquire_projectile() -> EnemyProjectile:
	for shot: EnemyProjectile in _pool:
		if not shot.is_active():
			return shot
	var extra := _make_projectile()
	_pool.append(extra)
	return extra


func _make_projectile() -> EnemyProjectile:
	var shot := PROJECTILE_SCENE.instantiate() as EnemyProjectile
	add_child(shot)
	return shot

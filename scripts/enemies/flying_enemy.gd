@tool
class_name FlyingEnemy
extends Enemy

## Shared base of the airborne archetypes (Flyer, Shooter).
##
## Idle: hovers at its spawn with a gentle bob. A sight check (one ray against
## solids, at most every `sight_interval` seconds and only while Luz is within
## range) decides when to engage. Engaged behaviour comes from
## `_engaged_think()`. It gives up after losing sight for `lose_sight_time`
## or straying more than `leash_distance` from its spawn, flies home and
## hovers again; it ignores Luz while returning.
##
## Gravity applies only to a corpse, which falls and rests on the floor.
## Placeholder visuals only.

enum Mode { IDLE, ENGAGED, RETURN }

const ARRIVE_DISTANCE := 6.0
## Where the sight ray aims: the middle of Luz's body, her origin being her feet.
const PLAYER_CENTER_OFFSET := Vector2(0.0, -29.0)
## Proportional gain of `_fly_to`: the approach eases out inside speed / gain px.
const ARRIVE_GAIN := 3.0

@export_group("Aggro")
## Distance at which Luz, in line of sight, is noticed.
@export var aggro_range := 220.0
@export var lose_sight_time := 2.5
## Straying further than this from the spawn sends it home.
@export var leash_distance := 420.0
## Seconds between sight rays. Keeps the raycast off the per-frame path.
@export var sight_interval := 0.1

@export_group("Hover")
@export var hover_bob_height := 6.0
@export var hover_bob_speed := 2.2
@export var hover_speed := 70.0
@export var return_speed := 110.0

@onready var _sight: RayCast2D = $SightProbe

var _mode := Mode.IDLE
var _sees_player := false
var _sight_clock := 0.0
var _sight_lost := 0.0
var _bob_time := 0.0
var _body_offset := Vector2.ZERO


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	floor_snap_length = 0.0
	var body := $CollisionShape2D as CollisionShape2D
	_body_offset = body.position


func _think(delta: float) -> void:
	_bob_time += delta
	_tick_sight(delta)
	match _mode:
		Mode.IDLE:
			_fly_to(_spawn_position + Vector2(0.0, _bob_offset()), hover_speed, delta)
			if _sees_player:
				_engage()
		Mode.ENGAGED:
			_engaged_think(delta)
			if _should_give_up():
				_mode = Mode.RETURN
		Mode.RETURN:
			_fly_to(_spawn_position, return_speed, delta)
			if global_position.distance_to(_spawn_position) < ARRIVE_DISTANCE:
				_enter_idle()


## -- Public API ----------------------------------------------------------------

func is_engaged() -> bool:
	return _mode == Mode.ENGAGED


func is_returning() -> bool:
	return _mode == Mode.RETURN


func get_body_center() -> Vector2:
	return global_position + _body_offset


## -- Hooks -----------------------------------------------------------------------

## Moves while engaged. Sets `velocity`; the base class moves the body.
func _engaged_think(_delta: float) -> void:
	pass


func _on_engaged() -> void:
	pass


## -- Internals ---------------------------------------------------------------------

func _reset_ai() -> void:
	_enter_idle()
	_bob_time = 0.0


func _on_player_found(player: Node) -> void:
	_sight.add_exception(player as CollisionObject2D)


func _apply_gravity(delta: float) -> void:
	if _dead:
		super._apply_gravity(delta)


## A hit stops the vertical drift too; the base class only sets the recoil x.
func _start_recoil(source_position: Vector2) -> void:
	super._start_recoil(source_position)
	velocity.y = 0.0


func _bob_offset() -> float:
	return sin(_bob_time * hover_bob_speed) * hover_bob_height


func _player_center() -> Vector2:
	return (_player_ref as Node2D).global_position + PLAYER_CENTER_OFFSET


func _has_player() -> bool:
	return is_instance_valid(_player_ref) and _player_ref is Node2D


func _engage() -> void:
	_mode = Mode.ENGAGED
	_sight_lost = 0.0
	_on_engaged()


func _enter_idle() -> void:
	_mode = Mode.IDLE
	_sees_player = false
	_sight_clock = 0.0
	_sight_lost = 0.0


func _should_give_up() -> bool:
	return _sight_lost >= lose_sight_time \
			or global_position.distance_to(_spawn_position) > leash_distance


## Refreshes `_sees_player` on the sight interval. While idle the ray is only
## cast when Luz is already within range.
func _tick_sight(delta: float) -> void:
	if _mode == Mode.ENGAGED and not _sees_player:
		_sight_lost += delta
	_sight_clock -= delta
	if _sight_clock > 0.0 or _mode == Mode.RETURN or not _has_player():
		return
	_sight_clock = sight_interval
	var target := _player_center()
	if _mode == Mode.IDLE and get_body_center().distance_to(target) > aggro_range:
		_sees_player = false
		return
	_sees_player = _line_of_sight_to(target)
	if _sees_player:
		_sight_lost = 0.0


func _line_of_sight_to(target: Vector2) -> bool:
	_sight.global_position = get_body_center()
	_sight.target_position = target - _sight.global_position
	_sight.force_raycast_update()
	return not _sight.is_colliding()


func _face_x(dx: float) -> void:
	var side := 1 if dx >= 0.0 else -1
	if side == _facing:
		return
	_facing = side
	_apply_visual()


## Steers the velocity toward `point`, easing out as it gets close.
func _fly_to(point: Vector2, speed: float, delta: float) -> void:
	var wanted := ((point - global_position) * ARRIVE_GAIN).limit_length(speed)
	velocity = velocity.move_toward(wanted, speed * 6.0 * delta)

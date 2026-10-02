@tool
class_name Charger
extends Walker

## Patrols like the Walker until Luz is ahead and in sight, then commits to a
## charge (the Husk): telegraph, a straight run, a recovery window, patrol.
## A hit during the telegraph neither cancels nor pushes it; during the charge
## it only shoves a little. The run ends at a wall or a ledge, never off it.
## Placeholder visuals only; the Greek look comes later.

enum Phase { PATROL, TELEGRAPH, CHARGE, RECOVER }

const SHAKE_PIXELS := 1.5
const SHAKE_HZ := 40.0
const HEAD_UP := Vector2(9.0, -42.0)
const HEAD_LOWERED := Vector2(15.0, -30.0)
const TELEGRAPH_TINT := Color(1.0, 0.7, 0.7)

@export_group("Detection")
@export var detect_range := 260.0
@export var detect_height := 60.0
## Seconds between sight checks while patrolling.
@export var sight_interval := 0.1

@export_group("Charge")
@export var telegraph_time := 0.45
@export var charge_speed := 300.0
@export var charge_time := 1.1
@export var recover_time := 0.6
## Share of the normal recoil that a hit during the charge still applies.
@export_range(0.0, 1.0) var charge_recoil_scale := 0.25

@onready var _sight: RayCast2D = $SightProbe
@onready var _head: Node2D = $Visual/Head

var _phase := Phase.PATROL
var _phase_left := 0.0
var _sight_clock := 0.0
var _shake_time := 0.0


func _think(delta: float) -> void:
	match _phase:
		Phase.PATROL:
			super._think(delta)
			_look_for_player(delta)
		Phase.TELEGRAPH:
			_update_telegraph(delta)
		Phase.CHARGE:
			_update_charge(delta)
		Phase.RECOVER:
			velocity.x = 0.0
			_phase_left -= delta
			if _phase_left <= 0.0:
				_set_phase(Phase.PATROL)


func get_phase() -> Phase:
	return _phase


func _reset_ai() -> void:
	super._reset_ai()
	_sight_clock = 0.0
	_set_phase(Phase.PATROL)


func _on_player_found(player: Node) -> void:
	super._on_player_found(player)
	_sight.add_exception(player as CollisionObject2D)


## Committed: nothing moves it while it winds up, and a charge shrugs it off.
func _start_recoil(source_position: Vector2) -> void:
	if _phase == Phase.TELEGRAPH:
		return
	super._start_recoil(source_position)
	if _phase == Phase.CHARGE:
		_recoil_velocity *= charge_recoil_scale


## Resets the shake and head pose together with the facing flip.
func _apply_visual() -> void:
	super._apply_visual()
	if _visual == null:
		return
	_visual.position.x = 0.0
	if _phase == Phase.TELEGRAPH and not _dead:
		_visual.modulate = TELEGRAPH_TINT
	if _head != null:
		_head.position = HEAD_LOWERED if _phase == Phase.CHARGE else HEAD_UP


func _look_for_player(delta: float) -> void:
	_sight_clock -= delta
	if _sight_clock > 0.0 or not is_on_floor() or not is_instance_valid(_player_ref):
		return
	_sight_clock = sight_interval
	if _player_is_in_reach() and _line_of_sight_to_player():
		_set_phase(Phase.TELEGRAPH)


## Ahead of its facing, within the horizontal range and the vertical band.
func _player_is_in_reach() -> bool:
	var offset := (_player_ref as Node2D).global_position - global_position
	var ahead := offset.x * float(_facing)
	return ahead > 0.0 and ahead <= detect_range and absf(offset.y) <= detect_height


func _line_of_sight_to_player() -> bool:
	var from := global_position + Vector2(0.0, -24.0)
	_sight.global_position = from
	_sight.target_position = (_player_ref as Node2D).global_position + Vector2(0.0, -29.0) - from
	_sight.force_raycast_update()
	return not _sight.is_colliding()


func _update_telegraph(delta: float) -> void:
	velocity.x = 0.0
	_shake_time += delta
	_visual.position.x = sin(_shake_time * TAU * SHAKE_HZ) * SHAKE_PIXELS
	_phase_left -= delta
	if _phase_left <= 0.0:
		_set_phase(Phase.CHARGE)


func _update_charge(delta: float) -> void:
	_phase_left -= delta
	if _phase_left <= 0.0 or is_on_wall() or not _has_floor_ahead():
		_set_phase(Phase.RECOVER)
		velocity.x = 0.0
		return
	velocity.x = float(_facing) * charge_speed


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_shake_time = 0.0
	match phase:
		Phase.TELEGRAPH:
			_phase_left = telegraph_time
			velocity.x = 0.0
		Phase.CHARGE:
			_phase_left = charge_time
		Phase.RECOVER:
			_phase_left = recover_time
	_apply_visual()


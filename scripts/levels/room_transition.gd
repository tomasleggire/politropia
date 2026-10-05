class_name RoomTransition
extends Node

## Hollow Knight style room change: a short dark fade, a hard camera cut while
## the screen is black, then Luz comes out of the door she entered through.
##
## A horizontal doorway locks her input and walks her on at run speed; while
## black she is placed just inside the next room at that door and walks
## `walk_out_distance` px out of it as the fade lifts. A vertical opening keeps
## her momentum instead (and lifts her out of it when she rises through it).
## The fade is the player's own veil, so it never stacks with the hazard return: the level only starts a transition while she is free, and a death,
## respawn or fall ends it at once.

## Emitted while the screen is black, after the camera bounds switched.
signal room_switched(from_room: String, to_room: String)
## Emitted when control is back, or when the transition was cut short.
signal finished

enum Phase { IDLE, FADE_OUT, FADE_IN }

@export_group("Timing")
@export var fade_out_time := 0.12
@export var fade_in_time := 0.18

@export_group("Doorway")
## How far she walks out of the door while the fade lifts.
@export var walk_out_distance := 32.0
## Extra height cleared above the lip when she rises into a room.
@export var lip_clearance := 24.0
## A blocked walk-out is given up this long after the fade ended.
@export var walk_timeout := 0.3

var _player: Player
var _camera: RoomCamera
var _phase := Phase.IDLE
var _time := 0.0
var _door: Dictionary = {}
var _from_room := ""
var _to_room := ""
var _walking := false
var _walk_start_x := 0.0


func setup(player: Player, camera: RoomCamera) -> void:
	_player = player
	_camera = camera


func is_active() -> bool:
	return _phase != Phase.IDLE


## Starts crossing `door` from `from_room` into `to_room`. False when one is
## already running or the player cannot be taken over right now.
func begin(door: Dictionary, from_room: String, to_room: String) -> bool:
	if is_active() or _player == null or _player.is_input_locked():
		return false
	_door = door
	_from_room = from_room
	_to_room = to_room
	var travel := GreeceLayout.travel_direction(door, to_room)
	_walking = door["orientation"] == GreeceLayout.HORIZONTAL
	_player.begin_room_transition(int(travel.x) if _walking else 0)
	_phase = Phase.FADE_OUT
	_time = 0.0
	return true


## Ends the transition at once. The veil is cleared unless the hazard return
## owns it.
func abort() -> void:
	if not is_active():
		return
	_phase = Phase.IDLE
	if is_instance_valid(_player) and not _player.is_returning_to_safe_ground():
		_player.get_screen_fade().set_alpha(0.0)
	finished.emit()


func _physics_process(delta: float) -> void:
	if not is_active():
		return
	if not is_instance_valid(_player) or not _player.is_in_room_transition():
		abort()
		return
	_time += delta
	if _phase == Phase.FADE_OUT:
		_update_fade_out()
	else:
		_update_fade_in()


func _update_fade_out() -> void:
	var fade := _player.get_screen_fade()
	fade.set_alpha(_time / maxf(fade_out_time, 0.001))
	if _time >= fade_out_time:
		fade.set_alpha(1.0)
		_switch_room()
		_phase = Phase.FADE_IN
		_time = 0.0


func _update_fade_in() -> void:
	var walked := absf(_player.global_position.x - _walk_start_x) >= walk_out_distance
	var blocked := _time > 0.0 and _player.is_on_wall()
	if _walking and (walked or blocked or _time >= fade_in_time + walk_timeout):
		_player.stop_auto_walk()
		_walking = false
	_player.get_screen_fade().set_alpha(1.0 - _time / maxf(fade_in_time, 0.001))
	if _time >= fade_in_time and not _walking:
		_finish()


func _finish() -> void:
	_phase = Phase.IDLE
	_player.get_screen_fade().set_alpha(0.0)
	_player.end_room_transition()
	finished.emit()


## The cut: new bounds with no blend, Luz placed (doorways) or lifted
## (openings in a floor), then the camera snapped onto her.
func _switch_room() -> void:
	if _walking:
		var travel := GreeceLayout.travel_direction(_door, _to_room)
		_player.place_for_transition(GreeceLayout.arrival_point(_door, _to_room), int(travel.x))
		_walk_start_x = _player.global_position.x
	else:
		_lift_out_of_opening()
	_camera.set_room_bounds(GreeceLayout.camera_bounds(_to_room), 0.0)
	_camera.snap_to_target()
	room_switched.emit(_from_room, _to_room)


## Rising out of an opening, she is lifted until her body clears its upper
## edge (and, for a floor hole, until her feet clear the lip), so she is not
## still inside the passage when control returns and falling back through it.
func _lift_out_of_opening() -> void:
	if GreeceLayout.travel_direction(_door, _to_room).y >= 0.0:
		return
	var top: float = (_door["rect"] as Rect2).position.y
	var feet_y := _player.global_position.y
	var height := feet_y + GreeceLayout.BODY_CENTER_OFFSET.y - top + lip_clearance
	var lip := GreeceLayout.entry_lip_y(_door, _to_room)
	if not is_nan(lip):
		height = maxf(height, feet_y - lip + lip_clearance)
	_player.boost_upward(height)

class_name RoomCamera
extends Camera2D

## Cámara de pantallas fijas con snap suave corto.

signal room_changed(room: Vector2i)

@export var target: Node2D
@export var room_size: Vector2 = Vector2(720, 1280)
@export var snap_seconds: float = 0.18

var _current_room: Vector2i = Vector2i(999, 999)
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _snap_t: float = 1.0


func _ready() -> void:
	make_current()
	_snap_to_target_room(true)


func _physics_process(delta: float) -> void:
	_snap_to_target_room(false)
	if _snap_t < 1.0:
		_snap_t = minf(_snap_t + delta / maxf(snap_seconds, 0.01), 1.0)
		var t := _snap_t * _snap_t * (3.0 - 2.0 * _snap_t)
		global_position = _from.lerp(_to, t)


func _snap_to_target_room(instant: bool) -> void:
	if target == null:
		return

	var room := Vector2i(
		floori(target.global_position.x / room_size.x),
		floori(target.global_position.y / room_size.y)
	)
	var desired := Vector2(room) * room_size + room_size * 0.5
	if room != _current_room:
		_current_room = room
		room_changed.emit(room)
		if instant:
			global_position = desired
			_to = desired
			_snap_t = 1.0
		else:
			_from = global_position
			_to = desired
			_snap_t = 0.0
	elif _snap_t >= 1.0:
		global_position = desired

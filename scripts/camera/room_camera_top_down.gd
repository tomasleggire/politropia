class_name RoomCamera
extends Camera2D

## Cámara de cuartos fijos con barrido corto al cruzar una puerta.

signal room_changed(room: Vector2i, direction: Vector2i)

@export var room_size := Vector2(720, 1280)
@export var transition_seconds := 0.34

var target: Node2D
var _current_room := Vector2i.ZERO
var _transition: Tween


func _ready() -> void:
	make_current()


func follow(node: Node2D) -> void:
	target = node
	_current_room = _room_for_position(target.global_position)
	global_position = _center_for_room(_current_room)


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var next_room := _room_for_position(target.global_position)
	if next_room == _current_room:
		return
	var direction := next_room - _current_room
	_current_room = next_room
	_start_transition(next_room, direction)


func _start_transition(room: Vector2i, direction: Vector2i) -> void:
	if is_instance_valid(_transition):
		_transition.kill()
	if target.has_method("begin_room_transition"):
		target.begin_room_transition(Vector2(direction), transition_seconds * 0.72)
	room_changed.emit(room, direction)
	_transition = create_tween()
	_transition.set_trans(Tween.TRANS_QUINT)
	_transition.set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(self, "global_position", _center_for_room(room), transition_seconds)


func _room_for_position(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / room_size.x),
		floori(world_position.y / room_size.y)
	)


func _center_for_room(room: Vector2i) -> Vector2:
	return Vector2(room) * room_size + room_size * 0.5

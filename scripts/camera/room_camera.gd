class_name RoomCamera
extends Camera2D

## Cámara de pantallas fijas (estilo Jump King).
## La vista llena la pantalla y solo cambia cuando el jugador
## entra a otra habitación (arriba, abajo o lateral).

## Nodo que la cámara debe seguir por habitaciones.
@export var target: Node2D

## Tamaño de cada habitación en píxeles (debe coincidir con el viewport).
@export var room_size: Vector2 = Vector2(720, 1280)


func _ready() -> void:
	make_current()
	_snap_to_target_room()


func _physics_process(_delta: float) -> void:
	_snap_to_target_room()


func _snap_to_target_room() -> void:
	if target == null:
		return

	var room := Vector2i(
		floori(target.global_position.x / room_size.x),
		floori(target.global_position.y / room_size.y)
	)
	# Centramos la cámara en la habitación actual.
	global_position = Vector2(room) * room_size + room_size * 0.5

class_name SpawnPoint
extends Marker2D

## Punto de aparición (SpawnPoint) que se coloca libremente en cualquier escena.
## Se vincula con un identificador del catálogo DoorID.
## Cuando una puerta (SceneTransitionArea) apunta a este ID, el jugador aparecerá
## exactamente en las coordenadas de este Marker2D.
## Si una escena no tiene SpawnPoint o la puerta apunta a NONE, el jugador conserva
## la posición por defecto con la que se configuró en la escena en Godot.

@export var spawn_id: DoorID.ID = DoorID.ID.NONE


func _ready() -> void:
	add_to_group(&"spawn_points")
	gizmo_extents = 24.0

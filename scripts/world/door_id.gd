class_name DoorID
extends RefCounted

## Catálogo de identificadores de puertas y puntos de enlace entre escenas.
## Al ser un enum en una clase registrada, Godot lo expone automáticamente como
## un menú desplegable (dropdown) en el Inspector, evitando errores de tipeo.
##
## Para añadir nuevas puertas en el futuro, simplemente agrega nuevas entradas a este enum.

enum ID {
	NONE,

	# --- Zona 1 <-> Zona 2 ---
	ZONE_1_TO_ZONE_2,
	ZONE_2_TO_ZONE_1,

	# --- Zona 2 <-> Zona 3 ---
	ZONE_2_TO_ZONE_3,
	ZONE_3_TO_ZONE_2,

	# --- Zona 3 <-> Zona 4 ---
	ZONE_3_TO_ZONE_4,
	ZONE_4_TO_ZONE_3,

	# --- Zona 4 <-> Zona 5 ---
	ZONE_4_TO_ZONE_5,
	ZONE_5_TO_ZONE_4,

	# --- Zona 2 <-> Zona 4 ---
	ZONE_2_TO_ZONE_4,
	ZONE_4_TO_ZONE_2,

	# --- Zona 3 <-> Zona 5 ---
	ZONE_3_TO_ZONE_5,
	ZONE_5_TO_ZONE_3,

	# --- Zona 4 <-> Zona 6 ---
	ZONE_4_TO_ZONE_6,
	ZONE_6_TO_ZONE_4,

	# --- Puertas Genéricas / Nuevas Zonas ---
	DOOR_A,
	DOOR_B,
	DOOR_C,
	DOOR_D,
	DOOR_E,
	DOOR_F,
	HEALING,
	LECTERN,
}


## Retorna el nombre en texto del ID seleccionado para mensajes de depuración o logs.
static func get_id_name(id: ID) -> String:
	return ID.keys()[id]

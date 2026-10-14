class_name DoorID
extends RefCounted

## Catálogo de identificadores de puertas y puntos de enlace entre escenas.
## Al ser un enum en una clase registrada, Godot lo expone automáticamente como
## un menú desplegable (dropdown) en el Inspector, evitando errores de tipeo.
##
## Para añadir nuevas puertas en el futuro, simplemente agrega nuevas entradas AL FINAL de este enum
## (las escenas guardan el número, así que no reordenes ni borres entradas existentes).

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
	## Door of the healing room (the one that leads back to the zone it hangs from).
	HEALING,
	## Door of the lectern room (the one that leads back to the zone it hangs from).
	LECTERN,

	# --- Healing / lectern rooms and Greece zone 5 <-> zone 6 ---
	ZONE_4_TO_HEALING,
	ZONE_5_TO_LECTERN,
	ZONE_5_TO_ZONE_6,
	ZONE_6_TO_ZONE_5,

	# --- Greece: healing room <-> Artemis room ---
	HEALING_TO_ARTEMIS,
	ARTEMIS_TO_HEALING,

	# --- Greece: zone 1 shortcut <-> Artemis room ---
	ZONE_1_TO_ARTEMIS,
	ARTEMIS_TO_ZONE_1,

	# --- Demo shortcut (one way): library zone 1 -> Artemis room ---
	LIBRARY_TO_ARTEMIS_DEMO,
}


## Retorna el nombre en texto del ID seleccionado para mensajes de depuración o logs.
static func get_id_name(id: ID) -> String:
	return ID.keys()[id]

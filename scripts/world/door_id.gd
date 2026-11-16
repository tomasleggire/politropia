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

	# --- Lectern <-> Zona 6 ---
	LECTERN_TO_ZONE_6,
	ZONE_6_TO_LECTERN,

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

	# --- Greece: zone 5 <-> Artemis room ---
	ZONE_5_TO_ARTEMIS,
	ARTEMIS_TO_ZONE_5,

	# --- Demo shortcut: library zone 1 -> Artemis room. Kept under this name and value
	# (zone_1 saves the number); it now leads to the boss test hub, which reaches Artemis. ---
	LIBRARY_TO_ARTEMIS_DEMO,
	
	# --- Biblioteca --- Zona 5 <-> Teacher ---
	ZONE_5_TO_TEACHER,
	TEACHER_TO_ZONE_5,

	# --- Demo scaffolding: library zone 1 <-> boss test hub <-> the three boss test rooms ---
	BOSS_HUB_TO_ARTEMIS_DEMO,
	BOSS_HUB_TO_LIBRARY,
	BOSS_HUB_TO_TEACHER_ROOM,
	TEACHER_ROOM_TO_BOSS_HUB,
	BOSS_HUB_TO_BLIND_BEAST_ROOM,
	BLIND_BEAST_ROOM_TO_BOSS_HUB,
	BOSS_HUB_TO_HYDRA_ROOM,
	HYDRA_ROOM_TO_BOSS_HUB,
}


## Retorna el nombre en texto del ID seleccionado para mensajes de depuración o logs.
static func get_id_name(id: ID) -> String:
	return ID.keys()[id]

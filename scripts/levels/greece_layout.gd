class_name GreeceLayout
extends RefCounted

## Pure data for the Greece level: room interiors, collision rects, doorways and
## markers. World pixels, y down. Every solid is a wall, floor or ceiling at
## least 64 px thick unless noted. No nodes live here, so tests can validate it.

const WORLD_SIZE := Vector2(3664.0, 2784.0)
const SPAWN := Vector2(760.0, 2720.0)
const DESK_POSITION := Vector2(1050.0, 1200.0)
const WALL := 64.0
const PLATFORM_THICKNESS := 20.0
const GATE := Rect2(2780.0, 2520.0, 350.0, 200.0)

## Medal alcove off the shaft: a corridor whose floor is a sill (take-off), a
## pit and the medal floor. Nothing in the shaft reaches past the sill, so the
## pit can only be crossed with a jump plus an air dash.
const ALCOVE_FLOOR_Y := 1330.0
const ALCOVE_SILL_END := 2040.0
const ALCOVE_FAR_START := 2260.0
const ALCOVE_PIT_FLOOR_Y := 1496.0

## Shaft interior and its climbing one-way platforms: [side, top y, width].
## Sides alternate (L is against the left wall, R against the right wall); the
## runs of L at 1380 / 1290 / 1200 form a ladder next to the altar sill.
const SHAFT_X0 := 1500.0
const SHAFT_X1 := 1860.0
const SHAFT_STEPS: Array = [
	["R", 2630.0, 120.0], ["L", 2540.0, 120.0], ["R", 2450.0, 120.0],
	["L", 2360.0, 120.0], ["R", 2265.0, 120.0], ["L", 2170.0, 120.0],
	["R", 2075.0, 120.0], ["L", 1980.0, 120.0],
	["R", 1880.0, 220.0],  # sill of the exit branch
	["L", 1780.0, 120.0], ["R", 1680.0, 120.0], ["L", 1580.0, 120.0],
	["R", 1480.0, 120.0],
	["R", 1390.0, 120.0],  # steps up onto the medal alcove sill
	["L", 1290.0, 120.0],
	["L", 1200.0, 150.0],  # sill of the altar branch
	["R", 1110.0, 120.0], ["L", 1020.0, 120.0], ["R", 930.0, 120.0],
	["L", 835.0, 100.0],
	["R", 740.0, 80.0],  # 180 px dash-assisted crossing
	["L", 640.0, 140.0], ["R", 640.0, 140.0],
]


## Interior (walkable air) of every room, by name. Used for backgrounds and
## per-room camera bounds.
static func rooms() -> Dictionary:
	return {
		"T1": _rect(64, 64, 1000, 544),
		"T2": _rect(1064, 64, 2600, 544),
		"T3": _rect(2664, 64, 3600, 544),
		"Shaft": _rect(1500, 544, 1860, 2240),
		"ShaftAlcove": _rect(1860, 1170, 2464, 1496),
		"Altar": _rect(760, 880, 1436, 1200),
		"Exit": _rect(1924, 1560, 2600, 1880),
		"Entrada": _rect(600, 2240, 1100, 2720),
		"B2": _rect(1164, 2240, 2000, 2720),
		"B3": _rect(2064, 2360, 3500, 2720),
	}


## Openings between rooms. `rect` is the free passage; a wider-than-tall rect
## is a vertical hole in a floor or ceiling.
static func doorways() -> Array[Dictionary]:
	return [
		_door("T1", "T2", _rect(1000, 404, 1064, 544)),
		_door("T2", "T3", _rect(2600, 404, 2664, 544)),
		_door("T2", "Shaft", _rect(1500, 544, 1860, 608)),
		_door("Shaft", "Altar", _rect(1436, 1040, 1500, 1200)),
		_door("Shaft", "ShaftAlcove", _rect(1860, 1170, 1924, 1330)),
		_door("Shaft", "Exit", _rect(1860, 1720, 1924, 1880)),
		_door("Shaft", "B2", _rect(1500, 2176, 1860, 2240)),
		_door("Entrada", "B2", _rect(1100, 2560, 1164, 2720)),
		_door("B2", "B3", _rect(2000, 2560, 2064, 2720)),
	]


static func solids() -> Array[Rect2]:
	var list: Array[Rect2] = []
	list.append_array(_top_row_solids())
	list.append_array(_shaft_solids())
	list.append_array(_branch_solids())
	list.append_array(_bottom_row_solids())
	return list


static func one_ways() -> Array[Rect2]:
	var list: Array[Rect2] = []
	list.append_array(_top_row_one_ways())
	list.append_array(_shaft_one_ways())
	return list


## Marker name -> position (feet level for floor markers).
static func markers() -> Dictionary:
	return {
		"Medal1": Vector2(210, 400),
		"Medal2": Vector2(2470, 230),
		"Medal3": Vector2(2370, 1330),
		"Medal4": Vector2(3300, 2680),
		"ExitDoor": Vector2(2500, 1880),
		"BossArena": Vector2(3380, 544),
		"DoubleJumpGate": GATE.get_center(),
	}


static func marker_group(marker_name: String) -> StringName:
	if marker_name.begins_with("Medal"):
		return &"greece_medal_spot"
	match marker_name:
		"ExitDoor":
			return &"greece_exit_door"
		"BossArena":
			return &"greece_boss_arena"
		_:
			return &"greece_double_jump_gate"


static func _top_row_solids() -> Array[Rect2]:
	return [
		_rect(0, 0, 3664, 64),          # ceiling
		_rect(0, 64, 64, 544),          # T1 left wall
		_rect(3600, 64, 3664, 544),     # T3 right wall
		_rect(1000, 64, 1064, 404),     # T1|T2 wall above the doorway
		_rect(2600, 64, 2664, 404),     # T2|T3 wall above the doorway
		_rect(0, 544, 380, 708),        # T1 floor, left of the pit
		_rect(380, 644, 590, 708),      # T1 pit bottom (100 deep)
		_rect(590, 544, 1500, 644),     # T1 right floor through T2 left floor
		_rect(1860, 544, 3664, 608),    # T2 right floor through T3 floor
	]


static func _top_row_one_ways() -> Array[Rect2]:
	return [
		_platform(120, 444, 180),       # T1 medal ledge
		_platform(1960, 450, 140),      # T2 climb to the medal
		_platform(2180, 360, 140),
		_platform(2400, 270, 140),      # T2 medal platform
		_platform(2780, 440, 180),      # T3 boss arena platforms
		_platform(3060, 350, 180),
		_platform(3300, 440, 180),
	]


static func _shaft_solids() -> Array[Rect2]:
	return [
		_rect(1436, 644, 1500, 1040),   # left shaft wall above the altar door
		_rect(1436, 1264, 1500, 2176),  # left shaft wall below the altar floor
		_rect(1860, 608, 1924, 1106),   # right shaft wall above the alcove
		_rect(1860, 1560, 1924, 1720),  # right wall between alcove and exit door
		_rect(1860, 1880, 1924, 2176),  # right wall below the exit door
	]


static func _branch_solids() -> Array[Rect2]:
	return [
		_rect(696, 816, 1436, 880),     # altar ceiling
		_rect(696, 816, 760, 1264),     # altar left wall
		_rect(696, 1200, 1500, 1264),   # altar floor (includes the door sill)
		_rect(1860, 1106, 2528, 1170),  # alcove lintel, thinner than 80 so it cannot be gripped
		_rect(2464, 1170, 2528, 1330),  # alcove back wall
		_rect(1860, 1330, 2040, 1560),  # alcove sill, grippable from the pit to climb out
		_rect(2260, 1330, 2528, 1496),  # medal floor, wider than tall so it cannot be gripped
		_rect(1924, 1496, 2664, 1560),  # exit room ceiling
		_rect(2600, 1560, 2664, 1944),  # exit room right wall
		_rect(1924, 1880, 2664, 1944),  # exit room floor
	]


static func _bottom_row_solids() -> Array[Rect2]:
	return [
		_rect(536, 2176, 1500, 2240),   # Entrada and B2 ceiling, left of the shaft
		_rect(1860, 2176, 2064, 2240),  # B2 ceiling, right of the shaft
		_rect(2064, 2176, 3564, 2360),  # B3 ceiling, low so wall kicks cannot top the gate
		_rect(536, 2240, 600, 2784),    # left wall
		_rect(3500, 2360, 3564, 2720),  # right wall
		_rect(536, 2720, 3564, 2784),   # floor
		_rect(1100, 2240, 1164, 2560),  # Entrada|B2 wall above the doorway
		_rect(2000, 2240, 2064, 2560),  # B2|B3 wall above the doorway
		_rect(900, 2640, 1040, 2720),   # onboarding step, 80 up
		GATE,                           # double jump gate, wider than tall
	]


static func _shaft_one_ways() -> Array[Rect2]:
	var list: Array[Rect2] = []
	for step: Array in SHAFT_STEPS:
		var width: float = step[2]
		var x := SHAFT_X0 if step[0] == "L" else SHAFT_X1 - width
		list.append(_platform(x, step[1], width))
	return list


static func _platform(x: float, top: float, width: float) -> Rect2:
	return Rect2(x, top, width, PLATFORM_THICKNESS)


## Rect from corner coordinates.
static func _rect(x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(x0, y0, x1 - x0, y1 - y0)


static func _door(from_room: String, to_room: String, opening: Rect2) -> Dictionary:
	return {"from": from_room, "to": to_room, "rect": opening}

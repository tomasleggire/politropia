class_name MapRoom
extends Resource

## One room of a `MapLayout`: which zone scene it is, where it is drawn on the
## map and which rooms it connects to.
##
## USAGE: create it from the Inspector inside a MapLayout's `rooms` array
## ("New MapRoom"), pick the zone scene, name it and move `map_rect`. The rect is
## in map units (about 1 unit = 60 world pixels), only the proportions matter:
## the map screen scales the whole layout to fit.

## Icon drawn on a room so Luz can find it on the map.
enum Landmark { NONE, BOSS, REST, LECTERN, SECRET }

## Zone scene (.tscn) this room stands for. Luz "visits" it by loading it.
@export_file("*.tscn") var scene_path := ""
## Name shown on the map when it fits inside the room.
@export var display_name := ""
## Position and size on the map, in map units. Rooms that touch through a door
## are usually placed side by side.
@export var map_rect := Rect2(0.0, 0.0, 20.0, 12.0)
## Scenes of the rooms this one has a door to. The connector is drawn once both
## ends have been visited.
@export_file("*.tscn") var connects_to: Array[String] = []
## Icon shown on the room: the boss arena, a stillness desk, a lectern. `SECRET`
## stays hidden until Luz has visited the room.
@export var landmark := Landmark.NONE

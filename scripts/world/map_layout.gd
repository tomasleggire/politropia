class_name MapLayout
extends Resource

## Map of one level: its name and its rooms (see `MapRoom`).
##
## USAGE (add a room without code): open `data/maps/<level>.tres`, add a MapRoom
## to `rooms`, choose its zone scene, name and `map_rect`. To map a new level,
## duplicate one of those files into `data/maps/` and fill it: the map screen
## finds every layout in that folder by itself.

## Where layouts live.
const LAYOUT_DIR := "res://data/maps"

## Level name shown at the top of the map ("Biblioteca", "Grecia").
@export var level_name := ""
@export var rooms: Array[MapRoom] = []
## Draws every room of the level, the ones Luz has not visited as a dim outline,
## so she can see where to go. Turn it off to show only visited rooms.
@export var reveal_unvisited := true


## The room for `scene_path`, or null when this layout does not draw it.
func find_room(scene_path: String) -> MapRoom:
	for room in rooms:
		if room != null and room.scene_path == scene_path:
			return room
	return null


## Landmark kinds present in the layout (without NONE), in enum order.
func landmark_kinds() -> Array[int]:
	var kinds: Array[int] = []
	for room in rooms:
		if room != null and room.landmark != MapRoom.Landmark.NONE and not kinds.has(room.landmark):
			kinds.append(room.landmark)
	kinds.sort()
	return kinds


func has_scene(scene_path: String) -> bool:
	return find_room(scene_path) != null


## Rectangle that holds every room, in map units.
func bounds() -> Rect2:
	var result := Rect2()
	var first := true
	for room in rooms:
		if room == null:
			continue
		result = room.map_rect if first else result.merge(room.map_rect)
		first = false
	return result


## Every layout found in `LAYOUT_DIR`.
static func load_all() -> Array[MapLayout]:
	var layouts: Array[MapLayout] = []
	var names := DirAccess.get_files_at(LAYOUT_DIR)
	names.sort()
	for file_name in names:
		# Exported projects list resources as "<name>.tres.remap".
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var layout := load("%s/%s" % [LAYOUT_DIR, clean]) as MapLayout
		if layout != null:
			layouts.append(layout)
	return layouts


## The layout that draws `scene_path`, or null.
static func find_for_scene(scene_path: String) -> MapLayout:
	for layout in load_all():
		if layout.has_scene(scene_path):
			return layout
	return null

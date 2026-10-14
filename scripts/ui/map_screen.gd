extends CanvasLayer

## Map screen (autoload `MapScreen`), Hollow Knight style: only rooms Luz has
## visited are drawn, her room is highlighted, and the level name and the
## fragments found are shown.
##
## USAGE: nothing to place. It enables the "Mapa" button of the pause menu and
## opens on top of it; "Volver" or Escape return to the pause menu. To add rooms
## edit `data/maps/<level>.tres` (see `MapLayout`). Anything else can call
## `MapScreen.open()` / `close()` (for example a future "map" key).

signal opened
signal closed

@export_group("Texts")
@export var default_title := "Mapa"
@export var fragments_format := "Fragmentos %d/%d"
@export var unknown_text := "Todavía no exploraste esta zona."

var _open := false
var _paused_by_me := false
var _layout: MapLayout

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Frame/Box/Header/Title
@onready var _fragments: Label = $Root/Frame/Box/Header/Fragments
@onready var _view: MapView = $Root/Frame/Box/MapView
@onready var _hint: Label = $Root/Frame/Box/Footer/Hint
@onready var _back: Button = $Root/Frame/Box/Footer/Back


func _ready() -> void:
	_root.visible = false
	_back.pressed.connect(close)
	var pause := get_node_or_null("/root/PauseMenu")
	if pause != null:
		pause.map_requested.connect(open)
		pause.set_map_enabled(true)


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
		_set_touch_blocked(true)
	_refresh()
	_root.visible = true
	_back.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false
		_set_touch_blocked(false)
	closed.emit()


func _refresh() -> void:
	var progress := get_node_or_null("/root/MapProgress")
	var current: String = progress.current_scene_path() if progress != null else ""
	var found := MapLayout.find_for_scene(current)
	if found != null:
		_layout = found
	var visited: Dictionary = {}
	if _layout != null and progress != null:
		for room in _layout.rooms:
			if room != null and progress.has_visited(room.scene_path):
				visited[room.scene_path] = true
	_title.text = _layout.level_name if _layout != null and not _layout.level_name.is_empty() else default_title
	_view.show_map(_layout, visited, current)
	var room := _layout.find_room(current) if _layout != null else null
	_hint.text = room.display_name if room != null else unknown_text
	var fragment_progress := get_node_or_null("/root/FragmentProgress")
	_fragments.text = fragments_format % [fragment_progress.count(), fragment_progress.total()] if fragment_progress != null else ""


func _set_touch_blocked(blocked: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_input_blocked"):
		touch.call(&"set_input_blocked", blocked)

extends CanvasLayer

## Pause menu and touch pause button (autoload `PauseMenu`).
##
## USAGE: nothing to place. In a zone (anywhere a node of group `player`
## exists) the top-right button, or Escape (`ui_cancel`), opens the menu,
## which pauses the whole tree. It is inert in the main menu and the intro.
## It sets itself apart from the touch layer: while open, `TouchControls`
## ignores every touch and releases whatever it held, so nothing leaks into
## the paused or the resumed game.
##
## Hooking the map (D6): set `map_enabled = true` and connect `map_requested`
## (or call `set_map_enabled(true)`); the "Mapa" button stays disabled until then.
##   PauseMenu.set_map_enabled(true)
##   PauseMenu.map_requested.connect(_open_my_map)
## Call `PauseMenu.close()` from the handler if the map should replace the menu.

signal opened
signal closed
## Emitted when the (enabled) "Mapa" button is pressed.
signal map_requested

@export_group("Menu")
## Master switch; turn it off for cutscenes or scenes that must not pause.
@export var pause_enabled := true
## Enables the "Mapa" button. Off until the map exists.
@export var map_enabled := false:
	set(value):
		map_enabled = value
		_refresh_map_button()
## Scene the "Menú principal" button loads. Empty means the project's main scene.
@export_file("*.tscn") var main_menu_scene := ""
@export_range(0.0, 1.0, 0.01) var fade_time := 0.18

@export_group("Touch button")
@export var show_touch_button := true
## Show the button even when no touchscreen is in use (mouse testing).
@export var show_button_without_touch := false
## Distance from the top-right corner, in viewport pixels.
@export var button_margin := Vector2(10.0, 8.0)
## Keep the button clear of the notch and rounded corners on phones.
@export var apply_safe_area := true

var _open := false
var _fade: Tween

@onready var _button: Button = $PauseButton
@onready var _menu: Control = $Menu
@onready var _resume: Button = $Menu/Center/Panel/Margin/Box/Resume
@onready var _map: Button = $Menu/Center/Panel/Margin/Box/Map
@onready var _quit: Button = $Menu/Center/Panel/Margin/Box/Quit


func _ready() -> void:
	_menu.visible = false
	_menu.modulate.a = 0.0
	_button.pressed.connect(open)
	_resume.pressed.connect(close)
	_map.pressed.connect(func() -> void: map_requested.emit())
	_quit.pressed.connect(_on_quit_pressed)
	get_viewport().size_changed.connect(_place_button)
	_place_button()
	_refresh_map_button()
	_button.visible = false


func _process(_delta: float) -> void:
	_button.visible = show_touch_button and not _open and _in_game() and _wants_button()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _open:
		close()
		get_viewport().set_input_as_handled()
	elif can_pause():
		open()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


## True while Luz is in a scene and nothing else has paused the game.
func can_pause() -> bool:
	return pause_enabled and not _open and not get_tree().paused and _in_game()


func set_map_enabled(enabled: bool) -> void:
	map_enabled = enabled


func open() -> void:
	if not can_pause():
		return
	_open = true
	get_tree().paused = true
	_set_touch_blocked(true)
	_menu.visible = true
	_fade_menu(1.0)
	_resume.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	get_tree().paused = false
	_set_touch_blocked(false)
	_fade_menu(0.0)
	closed.emit()


func _on_quit_pressed() -> void:
	Player.clear_transition_state()
	var path := main_menu_scene
	if path.is_empty():
		path = str(ProjectSettings.get_setting("application/run/main_scene"))
	_open = false
	get_tree().paused = false
	_set_touch_blocked(false)
	_menu.visible = false
	_menu.modulate.a = 0.0
	closed.emit()
	get_tree().change_scene_to_file(path)


func _in_game() -> bool:
	return get_tree().get_first_node_in_group(&"player") != null


func _wants_button() -> bool:
	if show_button_without_touch:
		return true
	var touch := get_node_or_null("/root/TouchControls") as CanvasLayer
	return touch != null and touch.visible


func _set_touch_blocked(blocked: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_input_blocked"):
		touch.call(&"set_input_blocked", blocked)


func _fade_menu(alpha: float) -> void:
	if _fade != null:
		_fade.kill()
	_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(_menu, "modulate:a", alpha, fade_time)
	if alpha <= 0.0:
		_fade.tween_callback(func() -> void: _menu.visible = _open)


func _refresh_map_button() -> void:
	if _map != null:
		_map.disabled = not map_enabled


## Puts the button in the top-right corner, inside the phone's safe area.
func _place_button() -> void:
	var inset := Vector2.ZERO
	if apply_safe_area and OS.has_feature("mobile"):
		var window := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var scale := get_viewport().get_visible_rect().size.x / maxf(window.x, 1.0)
		inset = Vector2(maxf(window.x - safe.end.x, 0.0), maxf(safe.position.y, 0.0)) * scale
	var size := _button.custom_minimum_size
	_button.offset_right = -(button_margin.x + inset.x)
	_button.offset_left = _button.offset_right - size.x
	_button.offset_top = button_margin.y + inset.y
	_button.offset_bottom = _button.offset_top + size.y

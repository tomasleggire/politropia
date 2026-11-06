extends CanvasLayer

## Full-screen GAME OVER overlay (autoload `GameOver`).
##
## The player asks for it once the existing death beat has finished. From that
## moment the whole tree is paused and only this layer keeps processing, so the
## level cannot respawn, enemies cannot touch Luz and the pause menu cannot open
## on top. The screen stays up until one of its two buttons is pressed:
##
## - REINTENTAR: resumes the tree and runs the same post-death respawn the game
##   already used (checkpoint / zone start, full health, resettable enemies).
## - MENÚ PRINCIPAL: leaves the run and loads the existing main menu.
##
## `enabled = false` (or a player with no running scene, as in standalone test
## rigs) makes the player fall back to its old automatic respawn.

signal shown
signal retried
signal main_menu_requested

@export var enabled := true
## Scene loaded by MENÚ PRINCIPAL. Same destination as PauseMenu's quit button.
@export_file("*.tscn") var main_menu_scene := "res://scenes/ui/main_menu.tscn"

@export_group("Reveal")
## The black veil fades in first; the title and buttons follow.
@export var backdrop_fade_time := 0.45
@export var content_delay := 0.08
@export var content_fade_time := 0.35

var _active := false
var _accepting_input := false
var _resolving := false
var _player: Player
var _reveal_tween: Tween

@onready var _overlay: Control = %Overlay
@onready var _backdrop: ColorRect = %Backdrop
@onready var _content: Control = %Content
@onready var _retry_button: Button = %Retry
@onready var _main_menu_button: Button = %MainMenu


func _ready() -> void:
	# The tree pauses while this screen is up; it must still animate and take input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_backdrop.color.a = 0.0
	_content.modulate.a = 0.0
	_retry_button.pressed.connect(_on_retry_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)


## True while the screen owns the game (shown, or fading in).
func is_active() -> bool:
	return _active


## True once the reveal finished and the buttons may act.
func is_accepting_input() -> bool:
	return _accepting_input


## Called by Player at the end of its death beat. Returns false when the
## overlay should not take over, so the player can keep its old respawn path.
func show_game_over(player: Player) -> bool:
	if _active:
		return true
	if not enabled or not is_instance_valid(player) or get_tree().current_scene == null:
		return false

	_active = true
	_resolving = false
	_accepting_input = false
	_player = player

	# Close a pause menu left open by an external caller: GAME OVER owns the
	# pause state while it is visible and must never sit under another menu.
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu != null and pause_menu.has_method(&"is_open") and bool(pause_menu.call(&"is_open")):
		pause_menu.call(&"close")

	get_tree().paused = true
	_set_touch_blocked(true)
	_reveal()
	shown.emit()
	return true


func _reveal() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()

	_overlay.visible = true
	_backdrop.color.a = 0.0
	_content.modulate.a = 0.0

	_reveal_tween = create_tween()
	# TWEEN_PAUSE_PROCESS keeps the reveal running after the tree is paused.
	_reveal_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal_tween.set_trans(Tween.TRANS_SINE)
	_reveal_tween.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_backdrop, "color:a", 1.0, backdrop_fade_time)
	if content_delay > 0.0:
		_reveal_tween.tween_interval(content_delay)
	_reveal_tween.tween_property(_content, "modulate:a", 1.0, content_fade_time)
	_reveal_tween.tween_callback(_on_reveal_finished)


func _on_reveal_finished() -> void:
	if not _active:
		return
	_accepting_input = true
	_retry_button.grab_focus()


func _on_retry_pressed() -> void:
	if not _can_resolve():
		return
	_resolving = true
	var player := _player
	_player = null
	_close_overlay()
	_set_touch_blocked(false)
	get_tree().paused = false

	if is_instance_valid(player):
		# The same path the automatic death respawn used: checkpoint (or zone
		# start), full health, death/damage/movement state cleared, enemies reset.
		player.respawn_after_game_over()
	else:
		get_tree().reload_current_scene()

	retried.emit()
	_resolving = false


func _on_main_menu_pressed() -> void:
	if not _can_resolve():
		return
	_resolving = true
	_player = null
	_close_overlay()
	_set_touch_blocked(false)
	get_tree().paused = false
	Player.clear_transition_state()
	main_menu_requested.emit()

	var path := main_menu_scene
	if path.is_empty():
		path = str(ProjectSettings.get_setting("application/run/main_scene"))
	get_tree().change_scene_to_file(path)
	_resolving = false


func _can_resolve() -> bool:
	return _active and _accepting_input and not _resolving


## Hides the overlay and forgets who owns it, without touching the pause state.
## The caller decides whether the game resumes or changes scene.
func _close_overlay() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
		_reveal_tween = null
	_active = false
	_accepting_input = false
	_overlay.visible = false
	_backdrop.color.a = 0.0
	_content.modulate.a = 0.0
	get_viewport().gui_release_focus()


func _set_touch_blocked(blocked: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_input_blocked"):
		touch.call(&"set_input_blocked", blocked)

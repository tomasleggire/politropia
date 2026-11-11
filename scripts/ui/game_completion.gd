extends CanvasLayer

## Final completion screen: shown once after Artemisa (the last boss) is
## defeated, when the fight's ending beat has played out. It pauses the run,
## blocks every other menu and only leaves through MENÚ PRINCIPAL.
##
## The trigger is owned by BossArena (Artemisa's arena). This autoload only
## presents the screen and resolves it, the same way GameOver owns its own flow.

signal shown
signal main_menu_requested

@export var enabled := true
## Scene loaded by MENÚ PRINCIPAL.
@export_file("*.tscn") var main_menu_scene := "res://scenes/ui/main_menu.tscn"

@export_group("Reveal")
@export var backdrop_fade_time := 0.55
@export var content_delay := 0.1
@export var content_fade_time := 0.45

@export_group("Option feedback")
## Same typographic feedback as the main menu and GAME OVER.
@export var selected_outline_color := Color(1.0, 0.72, 0.3, 0.3)
@export var selected_outline_size := 3
@export_range(1.0, 1.15, 0.01) var selected_scale := 1.03
@export_range(0.0, 1.0, 0.01) var feedback_time := 0.12

var _active := false
var _accepting_input := false
var _resolving := false
var _reveal_tween: Tween
var _options: Array[Button] = []

@onready var _overlay: Control = %Overlay
@onready var _backdrop: ColorRect = %Backdrop
@onready var _content: Control = %Content
@onready var _main_menu_button: Button = %MainMenu


func _ready() -> void:
	# The tree pauses while this screen is up; it must still animate and take input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_backdrop.color.a = 0.0
	_content.modulate.a = 0.0
	_options = [_main_menu_button]
	for option: Button in _options:
		_setup_option(option)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)


func _setup_option(option: Button) -> void:
	option.focus_entered.connect(_on_option_focused.bind(option))
	option.focus_exited.connect(_on_option_unfocused.bind(option))
	option.mouse_entered.connect(_on_option_mouse_entered.bind(option))
	option.resized.connect(_sync_option_pivot.bind(option))
	_sync_option_pivot(option)
	_reset_option_visual(option)


func _sync_option_pivot(option: Button) -> void:
	option.pivot_offset = option.size * 0.5


func _on_option_focused(option: Button) -> void:
	option.add_theme_constant_override(&"outline_size", selected_outline_size)
	option.add_theme_color_override(&"font_outline_color", selected_outline_color)
	_animate_option_scale(option, Vector2.ONE * selected_scale)


func _on_option_unfocused(option: Button) -> void:
	option.remove_theme_constant_override(&"outline_size")
	option.remove_theme_color_override(&"font_outline_color")
	_animate_option_scale(option, Vector2.ONE)


func _on_option_mouse_entered(option: Button) -> void:
	if _active and not _resolving:
		option.grab_focus()


func _animate_option_scale(option: Button, target: Vector2) -> void:
	var previous := _option_tween(option)
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(option, "scale", target, feedback_time)
	option.set_meta(&"feedback_tween", tween)


func _option_tween(option: Button) -> Tween:
	if not option.has_meta(&"feedback_tween"):
		return null
	return option.get_meta(&"feedback_tween") as Tween


func _reset_option_visual(option: Button) -> void:
	var previous := _option_tween(option)
	if previous != null and previous.is_valid():
		previous.kill()
	option.remove_meta(&"feedback_tween")
	option.remove_theme_constant_override(&"outline_size")
	option.remove_theme_color_override(&"font_outline_color")
	option.scale = Vector2.ONE


## True while the screen owns the game (shown, or fading in).
func is_active() -> bool:
	return _active


## True once the reveal finished and the option may act.
func is_accepting_input() -> bool:
	return _accepting_input


## Takes over the game with the completion screen. Returns false when it
## cannot or must not take over (disabled, already active, or no live scene).
func show_completion() -> bool:
	if _active:
		return true
	if not enabled or get_tree().current_scene == null:
		return false

	_active = true
	_resolving = false
	_accepting_input = false
	for option: Button in _options:
		_reset_option_visual(option)
	get_viewport().gui_release_focus()

	# Own the pause state alone: no other menu may sit on top of the ending.
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
	_main_menu_button.grab_focus()


func _on_main_menu_pressed() -> void:
	if not _can_resolve():
		return
	_resolving = true
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


## Hides the overlay and forgets its state without touching the pause state.
func _close_overlay() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
		_reveal_tween = null
	_active = false
	_accepting_input = false
	_overlay.visible = false
	_backdrop.color.a = 0.0
	_content.modulate.a = 0.0
	for option: Button in _options:
		_reset_option_visual(option)
	get_viewport().gui_release_focus()


func _set_touch_blocked(blocked: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_input_blocked"):
		touch.call(&"set_input_blocked", blocked)

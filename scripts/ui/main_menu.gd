extends Control

const GAME_SCENE := "res://scenes/levels/library/zone_1.tscn"
const INTRO_SCENE := "res://scenes/ui/new_game_intro.tscn"
const GALLERY_SCENE := "res://scenes/ui/collectibles_gallery.tscn"

@export_group("Opening")
@export var fade_in_time := 0.8
@export var ui_stagger := 0.12

@export_group("New game cinematic")
@export var ui_fade_out_time := 0.3
@export var walk_time := 1.6
@export var walk_distance := 230.0  # Art px.
@export var flash_delay := 0.5
@export var flash_time := 1.3
@export var finish_delay := 0.2

@export_group("Selected row")
@export var selected_outline_color := Color(1.0, 0.72, 0.3, 0.3)
@export var selected_outline_size := 3

## Replaces the final scene change (tests inject their own); empty uses the tree.
var scene_changer := Callable()
var input_locked := false

var _buttons: Array[Button] = []

@onready var btn_new_game: Button = %NewGame
@onready var btn_continue: Button = %Continue
@onready var btn_collectables: Button = %Collectables
@onready var btn_achievements: Button = %Achievements
@onready var _stage: MainMenuStage = %Stage
@onready var _ui: Control = %Ui
@onready var _logo: Control = %Logo
@onready var _logo_glow: TextureRect = %LogoGlow
@onready var _selector: MenuSelector = %Selector
@onready var _fade_black: ColorRect = %FadeBlack
@onready var _gold_flash: ColorRect = %GoldFlash


func _ready() -> void:
	# Disable touch controls while in the main menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		false
	)

	btn_continue.disabled = not SaveService.has_save()
	_buttons = [btn_new_game, btn_continue, btn_collectables, btn_achievements]
	for button in _buttons:
		_setup_button(button)
	_rebuild_focus_chain()

	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_collectables.pressed.connect(_on_collectables_pressed)
	btn_achievements.pressed.connect(_on_achievements_pressed)

	btn_new_game.grab_focus()
	_place_selector.call_deferred()
	_play_opening()

	MusicManager.play_menu_music()
	# Start loading the game scene in the background.
	ResourceLoader.load_threaded_request(GAME_SCENE)


func _exit_tree() -> void:
	# Restore touch controls when leaving the menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		true
	)


func _process(delta: float) -> void:
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0015)
	_logo_glow.modulate.a = 0.05 + 0.2 * breath


func _setup_button(button: Button) -> void:
	button.focus_entered.connect(_on_button_focused.bind(button))
	button.focus_exited.connect(_on_button_unfocused.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))


## Disabled rows are skipped by navigation; the enabled ones wrap top to bottom.
func _rebuild_focus_chain() -> void:
	var enabled: Array[Button] = []
	for button in _buttons:
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		if not button.disabled:
			enabled.append(button)
	for i in enabled.size():
		var above := enabled[(i - 1 + enabled.size()) % enabled.size()]
		var below := enabled[(i + 1) % enabled.size()]
		enabled[i].focus_neighbor_top = enabled[i].get_path_to(above)
		enabled[i].focus_neighbor_bottom = enabled[i].get_path_to(below)


func _place_selector() -> void:
	_selector.set_span(_buttons[0], _buttons[_buttons.size() - 1])
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button:
		_selector.select(focused as Button, false)


func _on_button_focused(button: Button) -> void:
	button.add_theme_constant_override(&"outline_size", selected_outline_size)
	button.add_theme_color_override(&"font_outline_color", selected_outline_color)
	_selector.select(button)


func _on_button_unfocused(button: Button) -> void:
	button.remove_theme_constant_override(&"outline_size")


func _on_button_hovered(button: Button) -> void:
	if not input_locked and not button.disabled:
		button.grab_focus()


func _play_opening() -> void:
	_fade_black.color.a = 1.0
	_logo.modulate.a = 0.0
	_selector.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_fade_black, "color:a", 0.0, fade_in_time)
	tween.tween_property(_logo, "modulate:a", 1.0, 0.5).set_delay(ui_stagger)
	tween.tween_property(_selector, "modulate:a", 1.0, 0.5).set_delay(ui_stagger * 2.0)
	for i in _buttons.size():
		_buttons[i].modulate.a = 0.0
		var delay := ui_stagger * (2.0 + 0.6 * i)
		tween.tween_property(_buttons[i], "modulate:a", 1.0, 0.4).set_delay(delay)


func _on_new_game_pressed() -> void:
	if input_locked:
		return
	input_locked = true
	for button in _buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().gui_release_focus()
	_play_new_game_cinematic()


## Fades the UI out while Luz walks into the light and the screen goes gold.
func _play_new_game_cinematic() -> void:
	var luz := _stage.luz
	luz.play(&"walk")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ui, "modulate:a", 0.0, ui_fade_out_time)
	tween.tween_property(luz, "position:x", luz.position.x + walk_distance, walk_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(luz, "modulate", Color(1.4, 1.2, 0.9), walk_time)
	tween.tween_property(_gold_flash, "color:a", 1.0, flash_time) \
		.set_delay(flash_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_interval(finish_delay)
	tween.chain().tween_callback(_finish_new_game)


func _finish_new_game() -> void:
	_reset_new_game_progress()
	SaveService.begin_new_game(GAME_SCENE)
	MusicManager.stop_music()
	if scene_changer.is_valid():
		scene_changer.call(INTRO_SCENE)
	else:
		get_tree().change_scene_to_file(INTRO_SCENE)


func _on_continue_pressed() -> void:
	if input_locked or btn_continue.disabled:
		return
	input_locked = true
	get_viewport().gui_release_focus()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ui, "modulate:a", 0.0, 0.3)
	tween.tween_property(_fade_black, "color:a", 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_callback(_continue_from_save)


func _continue_from_save() -> void:
	if SaveService.continue_game():
		return
	input_locked = false
	btn_continue.disabled = true
	_ui.modulate.a = 1.0
	_fade_black.color.a = 0.0
	_rebuild_focus_chain()
	btn_new_game.grab_focus()
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null:
		toast.show_toast("No se pudo cargar la partida guardada.")


func _reset_new_game_progress() -> void:
	var service_paths := [
		"/root/CheckpointService",
		"/root/EnemyRegistry",
		"/root/BossProgress",
		"/root/FragmentProgress",
		"/root/MapProgress",
		"/root/SecretProgress",
		"/root/AbilityProgress",
		"/root/Collectibles",
		"/root/BlindQuestProgress"
	]

	for service_path in service_paths:
		var service := get_node_or_null(service_path)

		if service != null and service.has_method("clear"):
			service.call("clear")

	TutorialSign.reset_seen()
	Player.clear_transition_state()


func _on_collectables_pressed() -> void:
	if input_locked:
		return
	get_tree().change_scene_to_file(GALLERY_SCENE)


func _on_achievements_pressed() -> void:
	if input_locked:
		return
	_show_coming_soon_toast()


func _show_coming_soon_toast() -> void:
	var toast := get_node_or_null("/root/PickupToast")

	if toast != null:
		toast.show_toast("Coming soon")

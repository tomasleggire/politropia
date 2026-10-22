extends Control

const GAME_SCENE := "res://scenes/levels/library/zone_1.tscn"
const INTRO_SCENE := "res://scenes/ui/new_game_intro.tscn"
const GALLERY_SCENE := "res://scenes/ui/collectibles_gallery.tscn"

@onready var btn_new_game: Button = %NewGame
@onready var btn_continue: Button = %Continue
@onready var btn_collectables: Button = %Collectables
@onready var btn_achievements: Button = %Achievements


func _ready() -> void:
	# Disable touch controls while in the main menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		false
	)

	btn_continue.disabled = true  # No save data available yet.

	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_collectables.pressed.connect(_on_collectables_pressed)
	btn_achievements.pressed.connect(_on_achievements_pressed)

	btn_new_game.grab_focus()

	# Start loading the game scene in the background.
	ResourceLoader.load_threaded_request(GAME_SCENE)


func _exit_tree() -> void:
	# Restore touch controls when leaving the menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		true
	)


func _on_new_game_pressed() -> void:
	# Prevent multiple button presses.
	btn_new_game.disabled = true
	_reset_new_game_progress()
	get_tree().change_scene_to_file(INTRO_SCENE)


func _reset_new_game_progress() -> void:
	var service_paths := [
		"/root/CheckpointService",
		"/root/EnemyRegistry",
		"/root/BossProgress",
		"/root/FragmentProgress",
		"/root/MapProgress",
		"/root/SecretProgress",
		"/root/AbilityProgress",
		"/root/Collectibles"
	]

	for service_path in service_paths:
		var service := get_node_or_null(service_path)

		if service != null and service.has_method("clear"):
			service.call("clear")

	TutorialSign.reset_seen()
	Player.clear_transition_state()


func _on_collectables_pressed() -> void:
	get_tree().change_scene_to_file(GALLERY_SCENE)


func _on_achievements_pressed() -> void:
	_show_coming_soon_toast()


func _show_coming_soon_toast() -> void:
	var toast := get_node_or_null("/root/PickupToast")

	if toast != null:
		toast.show_toast("Coming soon")

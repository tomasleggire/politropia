extends Node

## Saves a screenshot of the GAME OVER overlay for the project docs.
## Run non-headless from the project root:
##   godot --path . --resolution 1280x720 res://tools/capture/game_over_capture.tscn

const OUTPUT_PATH := "res://docs/screenshots/game_over.png"
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(player)
	await get_tree().process_frame

	var game_over := get_node("/root/GameOver")
	game_over.backdrop_fade_time = 0.0
	game_over.content_delay = 0.0
	game_over.content_fade_time = 0.0
	game_over.show_game_over(player)

	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("game_over_capture: could not save %s (%s)" % [OUTPUT_PATH, error_string(error)])
	get_tree().quit(0 if error == OK else 1)

extends Control

const FIRST_LEVEL := "res://scenes/levels/library/zone_1.tscn"
const VIDEO_PATH := "res://assets/videos/intro_nueva_partida.ogv"

@onready var _video: VideoStreamPlayer = $VideoStreamPlayer
@onready var _skip_button: Button = $SkipButton

var _leaving_intro := false


func _ready() -> void:
	# Diferido: así corre después del _exit_tree del menú, que los prende.
	get_tree().call_group.call_deferred(&"touch_controls", &"set_controls_enabled", false)
	_video.finished.connect(_on_video_finished)
	_skip_button.pressed.connect(_start_first_level)
	var stream := VideoStreamTheora.new()
	stream.file = VIDEO_PATH
	_video.stream = stream
	_video.play()
	_skip_button.grab_focus()


func _exit_tree() -> void:
	# Al pasar al primer nivel se restauran los controles.
	get_tree().call_group(&"touch_controls", &"set_controls_enabled", true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_start_first_level()
		get_viewport().set_input_as_handled()


func _on_video_finished() -> void:
	_start_first_level()


func _start_first_level() -> void:
	if _leaving_intro:
		return
	_leaving_intro = true
	_video.stop()
	get_tree().call_deferred("change_scene_to_file", FIRST_LEVEL)

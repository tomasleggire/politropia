extends Control

const GREECE_LEVEL := "res://scenes/levels/greece/zone_1.tscn"
const VIDEO_PATH := "res://assets/videos/paso-de-nivel-1.ogv"

@onready var _video: VideoStreamPlayer = $VideoStreamPlayer
@onready var _skip_button: Button = $SkipButton

var _leaving_transition := false


func _ready() -> void:
	_video.finished.connect(_on_video_finished)
	_skip_button.pressed.connect(_go_to_greece)
	var stream := VideoStreamTheora.new()
	stream.file = VIDEO_PATH
	_video.stream = stream
	_video.play()
	_skip_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_to_greece()
		get_viewport().set_input_as_handled()


func _on_video_finished() -> void:
	_go_to_greece()


func _go_to_greece() -> void:
	if _leaving_transition:
		return
	_leaving_transition = true
	_video.stop()
	get_tree().call_deferred("change_scene_to_file", GREECE_LEVEL)

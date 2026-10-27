extends Node2D

func _ready() -> void:
	MusicManager.play_gameplay_music()
	ScenePreloader.preload_demo_scenes()

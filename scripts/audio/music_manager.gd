extends Node

## Música global. Autoload para que sobreviva a los cambios de escena.

@export var gameplay_volume_db: float = -25.0
@export var menu_volume_db: float = -35.0

const MENU_MUSIC: AudioStream = preload("res://assets/audio/song_lament.wav")
const GAMEPLAY_MUSIC: AudioStream = preload("res://assets/audio/song_curious_ambiance.wav")

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = &"Master"
	add_child(_player)


func play_menu_music() -> void:
	_play_music(MENU_MUSIC, menu_volume_db)


func play_gameplay_music() -> void:
	_play_music(GAMEPLAY_MUSIC, gameplay_volume_db)


func stop_music() -> void:
	_player.stop()
	_player.stream = null


func _play_music(music: AudioStream, music_volume_db: float) -> void:
	_player.stop()
	_player.stream = music
	_player.volume_db = music_volume_db
	_player.play()

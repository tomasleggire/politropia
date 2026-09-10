extends Node

## Música / ambiente global. Autoload para que no dependa de la escena del nivel.

@export var ambient_stream: AudioStream
@export var volume_db: float = -14.0

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "AmbientPlayer"
	_player.bus = &"Master"
	_player.volume_db = volume_db
	_player.max_polyphony = 1
	add_child(_player)

	if ambient_stream == null:
		ambient_stream = load("res://assets/audio/ambient_curious.wav")

	_configure_and_play()


func _configure_and_play() -> void:
	if ambient_stream == null:
		push_warning("AmbientMusic: no hay stream de ambiente.")
		return

	var stream := ambient_stream.duplicate()
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.mix_rate = 22050
	_player.stream = stream
	_player.volume_db = volume_db
	_player.play()


func _process(_delta: float) -> void:
	# Si por algún motivo se corta (foco, export iOS), lo reanudamos.
	if _player != null and _player.stream != null and not _player.playing:
		_player.play()

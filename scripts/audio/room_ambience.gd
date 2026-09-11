class_name RoomAmbience
extends Node

## Ambiente A/B con crossfade según habitación de la cámara.

signal room_changed(room: Vector2i)

@export var volume_db: float = -16.0
@export var fade_seconds: float = 1.1

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: int = 0
var _current_room: Vector2i = Vector2i(999, 999)
var _fade_t: float = 1.0
var _fading: bool = false
var _stream_start: AudioStream
var _stream_upper: AudioStream
var _enter_sfx: AudioStreamPlayer
var _enter_stream: AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stream_start = load("res://assets/audio/ambient_room_a.wav")
	_stream_upper = load("res://assets/audio/ambient_room_b.wav")
	_enter_stream = load("res://assets/audio/room_enter.wav")

	_player_a = _make_player("AmbientA")
	_player_b = _make_player("AmbientB")
	_enter_sfx = AudioStreamPlayer.new()
	_enter_sfx.name = "RoomEnter"
	_enter_sfx.bus = &"Master"
	_enter_sfx.volume_db = -10.0
	_enter_sfx.stream = _enter_stream
	add_child(_enter_sfx)

	_play_on(_player_a, _looped(_stream_start))
	_player_a.volume_db = volume_db
	_player_b.volume_db = -80.0


func _make_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = &"Master"
	p.max_polyphony = 1
	add_child(p)
	return p


func _looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var copy := stream.duplicate()
	if copy is AudioStreamWAV:
		(copy as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return copy


func _play_on(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null:
		return
	player.stream = stream
	player.play()


func update_room(room: Vector2i) -> void:
	if room == _current_room:
		return
	var first := _current_room.x == 999
	_current_room = room
	room_changed.emit(room)
	if first:
		# Ya arrancamos con bed A (sala inicio).
		if room.y < 0:
			_crossfade_to(_stream_upper)
		return
	if _enter_sfx.stream != null:
		_enter_sfx.play()
	var target_stream := _stream_start if room.y >= 0 else _stream_upper
	_crossfade_to(target_stream)


func _crossfade_to(stream: AudioStream) -> void:
	if stream == null:
		return
	var incoming := _player_b if _active == 0 else _player_a
	var outgoing := _player_a if _active == 0 else _player_b
	_play_on(incoming, _looped(stream))
	incoming.volume_db = -80.0
	_active = 1 if _active == 0 else 0
	_fade_t = 0.0
	_fading = true
	# Keep refs for process
	set_meta("incoming", incoming)
	set_meta("outgoing", outgoing)


func _process(delta: float) -> void:
	# Keep beds alive on iOS focus quirks.
	if _player_a.stream != null and not _player_a.playing:
		_player_a.play()
	if _player_b.stream != null and not _player_b.playing and _fading:
		_player_b.play()

	if not _fading:
		return
	_fade_t = minf(_fade_t + delta / maxf(fade_seconds, 0.05), 1.0)
	var incoming: AudioStreamPlayer = get_meta("incoming")
	var outgoing: AudioStreamPlayer = get_meta("outgoing")
	incoming.volume_db = lerpf(-80.0, volume_db, _fade_t)
	outgoing.volume_db = lerpf(volume_db, -80.0, _fade_t)
	if _fade_t >= 1.0:
		_fading = false
		outgoing.stop()

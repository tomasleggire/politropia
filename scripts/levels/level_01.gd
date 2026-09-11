extends Node2D

## Dos pantallas verticales pulidas: Umbral → Lo que se aclara.

const ROOM_SIZE := Vector2(720, 1280)

const PLAT_COLOR := Color(0.40, 0.52, 0.30, 1.0)
const FLOOR_COLOR := Color(0.28, 0.34, 0.22, 1.0)
const WALL_COLOR := Color(0.33, 0.28, 0.24, 1.0)

const TEX_DIRT := preload("res://assets/world/tex_dirt.png")
const TEX_STONE := preload("res://assets/world/tex_stone.png")
const SFX_PICKUP := preload("res://assets/audio/pickup_chime.wav")
const SFX_NOTICE := preload("res://assets/audio/item_notice.wav")
const SFX_WHISPER := preload("res://assets/audio/mark_whisper.wav")

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _solids: Node2D = $Solids
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _pickups: Node2D = $Pickups
@onready var _decor: Node2D = $Decor
@onready var _story: StoryLine = $StoryLine
@onready var _ambience: RoomAmbience = $RoomAmbience

var _upper_seal: RoomMark


func _ready() -> void:
	_player.add_to_group("player")
	_camera.target = _player
	_camera.room_changed.connect(_on_room_changed)
	_build_level()
	_ambience.update_room(Vector2i(0, 0))


func _plat(rect: Rect2) -> void:
	LevelGeometry.add_solid(_solids, rect, PLAT_COLOR, TEX_DIRT)


func _floor(rect: Rect2) -> void:
	LevelGeometry.add_solid(_solids, rect, FLOOR_COLOR, null)


func _wall(rect: Rect2) -> void:
	LevelGeometry.add_solid(_solids, rect, WALL_COLOR, TEX_STONE)


func _build_level() -> void:
	_build_start_room()
	_build_upper_room()


func _build_start_room() -> void:
	# Sala 1 — El umbral (cálida, polvo, tutorial implícito).
	LevelGeometry.add_atmosphere_background(
		_backgrounds,
		Vector2i(0, 0),
		ROOM_SIZE,
		Color(0.62, 0.48, 0.36, 1.0),
		Color(0.42, 0.30, 0.24, 1.0),
		Color(0.25, 0.18, 0.14, 1.0)
	)
	LevelGeometry.add_dust_motes(
		_decor, Vector2i(0, 0), ROOM_SIZE, 22, Color(1.0, 0.9, 0.7, 0.22)
	)

	_floor(Rect2(0, 1240, 720, 40))
	_wall(Rect2(0, 0, 56, 1280))
	_wall(Rect2(664, 0, 56, 1280))

	# Escalones bajos: tap hops.
	_plat(Rect2(120, 1120, 150, 24))
	_plat(Rect2(380, 1020, 140, 24))
	_plat(Rect2(160, 900, 130, 24))

	# Plataforma del ítem-gancho (visible de entrada).
	_plat(Rect2(300, 780, 200, 24))
	var hook := HookItem.new()
	hook.position = Vector2(400, 730)
	hook.pickup_stream = SFX_PICKUP
	hook.notice_stream = SFX_NOTICE
	hook.story_text = "queda algo arriba"
	hook.setup(_story)
	_pickups.add_child(hook)

	# Ruta hacia arriba + ledge rota (invita bounce).
	_plat(Rect2(100, 660, 120, 24))
	LevelGeometry.add_broken_ledge(_solids, Rect2(420, 560, 130, 24), PLAT_COLOR, TEX_DIRT)
	_plat(Rect2(180, 440, 140, 24))
	_plat(Rect2(400, 300, 150, 24))
	_plat(Rect2(220, 160, 160, 24))
	_plat(Rect2(360, 40, 180, 24))

	_add_mark(Vector2(90, 1080), &"m1", "…no…", false, Color(0.95, 0.82, 0.62, 0.8))
	_add_mark(Vector2(620, 860), &"m2", "¿otra vez?", false, Color(0.95, 0.82, 0.62, 0.8))
	_add_mark(Vector2(90, 480), &"m3", "", false, Color(0.95, 0.82, 0.62, 0.55))


func _build_upper_room() -> void:
	# Sala 2 — Lo que se aclara (más fría, saltos cargados + wall bounce).
	LevelGeometry.add_atmosphere_background(
		_backgrounds,
		Vector2i(0, -1),
		ROOM_SIZE,
		Color(0.34, 0.36, 0.48, 1.0),
		Color(0.22, 0.24, 0.34, 1.0),
		Color(0.16, 0.14, 0.28, 1.0)
	)
	LevelGeometry.add_dust_motes(
		_decor, Vector2i(0, -1), ROOM_SIZE, 16, Color(0.75, 0.8, 1.0, 0.18)
	)

	_wall(Rect2(0, -1280, 56, 1280))
	_wall(Rect2(664, -1280, 56, 1280))
	_wall(Rect2(0, -1280, 720, 56))

	# Entrada desde abajo.
	_plat(Rect2(56, -28, 160, 24))
	_plat(Rect2(500, -28, 160, 24))

	_plat(Rect2(240, -160, 130, 24))
	_plat(Rect2(90, -320, 110, 24))
	# Momento pared → plataforma (rebote útil).
	_plat(Rect2(520, -460, 100, 24))
	_plat(Rect2(200, -620, 140, 24))
	_plat(Rect2(430, -780, 150, 24))
	_plat(Rect2(160, -940, 160, 24))
	_plat(Rect2(300, -1100, 220, 28))

	# Franja de marcas alineadas (resolución).
	_add_mark(Vector2(120, -1080), &"u1", "", true, Color(0.85, 0.9, 1.0, 0.9))
	_add_mark(Vector2(200, -1080), &"u2", "", true, Color(0.85, 0.9, 1.0, 0.9))
	_upper_seal = _add_mark(
		Vector2(360, -1080),
		&"u_seal",
		"podés subir igual",
		true,
		Color(1.0, 0.92, 0.55, 0.95)
	)


func _add_mark(
	pos: Vector2,
	mark_id: StringName,
	text: String,
	resolved: bool,
	color: Color
) -> RoomMark:
	var mark := RoomMark.new()
	mark.position = pos
	mark.mark_id = mark_id
	mark.story_text = text
	mark.resolved = resolved
	mark.glyph_color = color
	mark.whisper_stream = SFX_WHISPER
	mark.setup(_story)
	if mark_id == &"u_seal":
		mark.revealed.connect(_on_seal_revealed)
	_decor.add_child(mark)
	return mark


func _on_seal_revealed(_id: StringName) -> void:
	if _player.has_meta("has_fragment") and bool(_player.get_meta("has_fragment")):
		_story.show_line("el fragmento encaja", &"fragment_fit")


func _on_room_changed(room: Vector2i) -> void:
	_ambience.update_room(room)

extends Node2D

## Nivel de prueba con 3 habitaciones de pantalla completa.

const ROOM_SIZE := Vector2(720, 1280)
const SOLID_COLOR := Color(0.32, 0.48, 0.36, 1.0)
const WOOD_COLOR := Color(0.45, 0.28, 0.14, 1.0)

const TEX_GROUND := preload("res://assets/world/ground.png")
const TEX_WOOD := preload("res://assets/world/wood.png")
const TEX_FOREST := preload("res://assets/world/forest_bg.png")
const TEX_TREE := preload("res://assets/world/tree.png")
const TEX_BUSH := preload("res://assets/world/bush.png")

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _solids: Node2D = $Solids
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _pickups: Node2D = $Pickups


func _ready() -> void:
	_camera.target = _player
	_build_level()


func _plat(rect: Rect2) -> void:
	LevelGeometry.add_solid(_solids, rect, SOLID_COLOR, TEX_GROUND)


func _wood(rect: Rect2) -> void:
	LevelGeometry.add_solid(_solids, rect, WOOD_COLOR, TEX_WOOD)


func _build_level() -> void:
	_build_start_room()
	_build_upper_room()
	_build_side_room()


func _build_start_room() -> void:
	LevelGeometry.add_forest_background(
		_backgrounds, Vector2i(0, 0), ROOM_SIZE, Color(0.04, 0.07, 0.05, 1.0), TEX_FOREST, TEX_TREE, TEX_BUSH
	)

	_plat(Rect2(0, 1240, 720, 40))
	_wood(Rect2(0, 0, 48, 1280))
	_wood(Rect2(672, 0, 48, 1000))

	_plat(Rect2(120, 1080, 120, 24))
	_plat(Rect2(420, 1000, 90, 24))
	_plat(Rect2(250, 880, 160, 24))
	_plat(Rect2(70, 760, 70, 24))
	_plat(Rect2(480, 700, 140, 24))
	_plat(Rect2(200, 560, 100, 24))
	_plat(Rect2(430, 450, 180, 24))
	_plat(Rect2(90, 330, 80, 24))
	_plat(Rect2(300, 220, 130, 24))
	_plat(Rect2(500, 110, 110, 24))


func _build_upper_room() -> void:
	LevelGeometry.add_forest_background(
		_backgrounds, Vector2i(0, -1), ROOM_SIZE, Color(0.03, 0.05, 0.04, 1.0), TEX_FOREST, TEX_TREE, TEX_BUSH
	)

	_wood(Rect2(0, -1280, 48, 1280))
	_wood(Rect2(672, -1280, 48, 1280))
	_wood(Rect2(0, -1280, 720, 48))

	_plat(Rect2(48, -28, 140, 24))
	_plat(Rect2(532, -28, 140, 24))

	_plat(Rect2(280, -160, 90, 24))
	_plat(Rect2(90, -280, 120, 24))
	_plat(Rect2(460, -360, 80, 24))
	_plat(Rect2(220, -500, 150, 24))
	_plat(Rect2(520, -620, 70, 24))
	_plat(Rect2(140, -760, 100, 24))
	_plat(Rect2(380, -900, 160, 24))
	_plat(Rect2(300, -1080, 120, 28))

	var star := SpinningPickup.new()
	star.position = Vector2(360, -1160)
	_pickups.add_child(star)


func _build_side_room() -> void:
	LevelGeometry.add_forest_background(
		_backgrounds, Vector2i(1, 0), ROOM_SIZE, Color(0.04, 0.06, 0.04, 1.0), TEX_FOREST, TEX_TREE, TEX_BUSH
	)

	_plat(Rect2(720, 1240, 720, 40))
	_wood(Rect2(720, 0, 48, 1000))
	_wood(Rect2(1392, 0, 48, 1280))
	_wood(Rect2(720, 0, 720, 48))

	_plat(Rect2(820, 1120, 100, 24))
	_plat(Rect2(1050, 1000, 160, 24))
	_plat(Rect2(1280, 880, 80, 24))
	_plat(Rect2(940, 760, 120, 24))
	_plat(Rect2(1180, 640, 90, 24))

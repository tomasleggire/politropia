extends Node2D

## Prototipo horizontal corto para aprender el control por gestos.

const WORLD_SIZE := Vector2(6400.0, 720.0)
const FLOOR_Y := 620.0

const BACKGROUND := preload("res://assets/art/greece/Background/background_greece.jpeg")

const SOLID := Color("101a33")
const SOLID_ALT := Color("182b4f")
const ONE_WAY := Color("24558a")
const TEXT := Color("c7d8ec")
const TEXT_MUTED := Color("8198b6")
const AMBER := Color("f0ae4c")

const CHECKPOINTS := [
	Vector2(180, FLOOR_Y),
	Vector2(1380, FLOOR_Y),
	Vector2(2680, FLOOR_Y),
	Vector2(4220, FLOOR_Y),
	Vector2(5350, FLOOR_Y),
]

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _backgrounds: Node2D = $Backgrounds

var _checkpoint_index := 0


func _ready() -> void:
	_player.add_to_group(&"player")
	_camera.target = _player
	_build_course()
	_player.set_checkpoint(CHECKPOINTS[0])
	_camera.snap_to_target()


func _physics_process(_delta: float) -> void:
	if _player.global_position.y > 820.0:
		_player.respawn()
		_camera.snap_to_target()


func _build_course() -> void:
	_build_backgrounds()


func _build_backgrounds() -> void:
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 0, WORLD_SIZE.x, WORLD_SIZE.y), Color("02040b"), -40)
	var room_tints := [
		Color("8b9ab8"),
		Color("788bab"),
		Color("6f7fa1"),
		Color("857b9e"),
		Color("718ead"),
	]
	
	for room_index in 5:
		var background := Sprite2D.new()
		background.texture = BACKGROUND
		background.centered = true
		background.position = Vector2(float(room_index) * 1280.0 + 640.0, 360.0)
		background.scale = Vector2(
			1280.0 / float(BACKGROUND.get_width()),
			720.0 / float(BACKGROUND.get_height())
		)
		background.flip_h = room_index % 2 == 1
		background.modulate = room_tints[room_index]
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		background.z_index = -30
		_backgrounds.add_child(background)

		# Each stretch gets a slightly different color veil, which avoids the
		# repeated architecture feeling stamped while keeping one art language.
		var veil_color := Color(0.015, 0.025, 0.07, 0.12 + float(room_index % 3) * 0.035)
		LevelGeometry.add_color_rect(
			_backgrounds,
			Rect2(float(room_index) * 1280.0, 0.0, 1280.0, 720.0),
			veil_color,
			-28
		)
		LevelGeometry.add_dust_motes(
			_backgrounds,
			Vector2i(room_index, 0),
			Vector2(1280.0, 720.0),
			18,
			Color(0.38, 0.58, 0.82, 0.16)
		)

	# Deep mist anchors the collision layer and keeps the blue rims legible.
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 585, WORLD_SIZE.x, 135), Color(0.005, 0.008, 0.02, 0.74), -18)

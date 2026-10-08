extends Node2D

## Prototipo horizontal corto para probar el moveset definitivo.

const WORLD_SIZE := Vector2(6400.0, 720.0)
const FLOOR_Y := 620.0

const BACKGROUND := preload("res://assets/art/gothic/library_background.png")
const STONE := preload("res://assets/art/gothic/stone_tile.png")

const SOLID := Color("101a33")
const SOLID_ALT := Color("182b4f")
const ONE_WAY := Color("24558a")

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _solids: Node2D = $Solids


func _ready() -> void:
	# Player already adds itself to the "player" group in its own _ready().
	_camera.target = _player
	_player.respawned.connect(_camera.snap_to_target)
	_player.safe_ground_returned.connect(_camera.snap_to_target)
	_build_course()
	CheckpointService.restore_player_for_scene(_player, scene_file_path)
	_camera.snap_to_target()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_player) and _player.global_position.y > 820.0:
		_player.fall_out_of_bounds()


func _build_course() -> void:
	_build_backgrounds()
	_build_boundaries()
	_build_zone_run()
	_build_zone_jump()
	_build_zone_drop()
	_build_zone_flow()


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
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 505, WORLD_SIZE.x, 215), Color(0.01, 0.02, 0.055, 0.52), -19)
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 585, WORLD_SIZE.x, 135), Color(0.005, 0.008, 0.02, 0.74), -18)


func _build_boundaries() -> void:
	_solid(Rect2(-60, 0, 60, 720))
	_solid(Rect2(WORLD_SIZE.x, 0, 60, 720))


func _build_zone_run() -> void:
	_solid(Rect2(0, FLOOR_Y, 1120, 100))
	# Pequeños cambios de altura para sentir aceleración y caída sin castigo.
	_solid(Rect2(520, 570, 180, 50), SOLID_ALT)
	_solid(Rect2(760, 530, 150, 90), SOLID_ALT)
	_one_way(Rect2(930, 470, 150, 20))


func _build_zone_jump() -> void:
	_solid(Rect2(1250, FLOOR_Y, 1110, 100))
	_one_way(Rect2(1510, 520, 170, 20))
	_one_way(Rect2(1780, 455, 180, 20))
	_one_way(Rect2(2070, 390, 190, 20))
	# Segundo hueco, un poco más ancho: premia llegar corriendo.
	_solid(Rect2(2540, FLOOR_Y, 560, 100))
	_one_way(Rect2(2320, 500, 150, 20))


func _build_zone_drop() -> void:
	_solid(Rect2(3100, FLOOR_Y, 1900, 100))
	# Escalera que enseña plataformas atravesables.
	_one_way(Rect2(2800, 520, 170, 20))
	_one_way(Rect2(2990, 445, 170, 20))
	_solid(Rect2(3100, 420, 70, 200))
	_one_way(Rect2(3160, 375, 300, 22))
	_one_way(Rect2(3460, 375, 300, 22))
	_one_way(Rect2(3760, 375, 300, 22))
	# Esta pared cierra el camino alto: hay que bajar antes y cruzar el túnel.
	_solid(Rect2(4060, 0, 90, 505))


func _build_zone_flow() -> void:
	_one_way(Rect2(4380, 520, 170, 20))
	_one_way(Rect2(4620, 455, 170, 20))
	# Hueco final ancho: requiere envión, pero admite coyote time y buffer.
	_solid(Rect2(5250, FLOOR_Y, 1150, 100))
	_one_way(Rect2(4870, 390, 150, 20))
	_one_way(Rect2(5150, 490, 150, 20))
	_one_way(Rect2(5480, 520, 160, 20))
	_one_way(Rect2(5720, 445, 170, 20))
	_one_way(Rect2(5960, 365, 190, 20))


func _solid(rect: Rect2, color := SOLID) -> void:
	LevelGeometry.add_solid(_solids, rect, color, STONE)


func _one_way(rect: Rect2) -> void:
	LevelGeometry.add_one_way_platform(_solids, rect, ONE_WAY, STONE)



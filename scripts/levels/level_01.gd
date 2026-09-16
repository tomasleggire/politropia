extends Node2D

## Prototipo horizontal corto para aprender el control por gestos.

const WORLD_SIZE := Vector2(6400.0, 720.0)
const FLOOR_Y := 620.0

const SOLID := Color("263238")
const SOLID_ALT := Color("37474f")
const ONE_WAY := Color("f9a825")
const TEXT := Color("f4f1de")

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
@onready var _solids: Node2D = $Solids
@onready var _decor: Node2D = $Decor

var _checkpoint_index := 0


func _ready() -> void:
	_player.add_to_group(&"player")
	_camera.target = _player
	_build_course()
	_player.set_checkpoint(CHECKPOINTS[0])
	_camera.snap_to_target()


func _physics_process(_delta: float) -> void:
	_update_checkpoint()
	if _player.global_position.y > 820.0:
		_player.respawn()
		_camera.snap_to_target()


func _build_course() -> void:
	_build_backgrounds()
	_build_boundaries()
	_build_zone_run()
	_build_zone_jump()
	_build_zone_drop()
	_build_zone_flow()


func _build_backgrounds() -> void:
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 0, 1280, 720), Color("23395b"))
	LevelGeometry.add_color_rect(_backgrounds, Rect2(1280, 0, 1280, 720), Color("35524a"))
	LevelGeometry.add_color_rect(_backgrounds, Rect2(2560, 0, 1600, 720), Color("4a3f62"))
	LevelGeometry.add_color_rect(_backgrounds, Rect2(4160, 0, 2240, 720), Color("6b3f47"))
	# Una banda tenue mantiene legible el suelo sin usar texturas.
	LevelGeometry.add_color_rect(_backgrounds, Rect2(0, 520, WORLD_SIZE.x, 200), Color(0.05, 0.07, 0.09, 0.18), -19)


func _build_boundaries() -> void:
	_solid(Rect2(-60, 0, 60, 720))
	_solid(Rect2(WORLD_SIZE.x, 0, 60, 720))


func _build_zone_run() -> void:
	_solid(Rect2(0, FLOOR_Y, 1120, 100))
	_add_title(Vector2(180, 180), "01 · IMPULSO", "Deslizá y sostené hacia la derecha\nSoltá para frenar · cambiá de lado para girar")
	# Pequeños cambios de altura para sentir aceleración y caída sin castigo.
	_solid(Rect2(520, 570, 180, 50), SOLID_ALT)
	_solid(Rect2(760, 530, 150, 90), SOLID_ALT)
	_one_way(Rect2(930, 470, 150, 20))


func _build_zone_jump() -> void:
	_solid(Rect2(1250, FLOOR_Y, 1110, 100))
	_add_title(Vector2(1380, 170), "02 · SALTO CON ENVÍO", "Mantené derecha y deslizá también hacia arriba\nEl salto conserva tu velocidad horizontal")
	_one_way(Rect2(1510, 520, 170, 20))
	_one_way(Rect2(1780, 455, 180, 20))
	_one_way(Rect2(2070, 390, 190, 20))
	# Segundo hueco, un poco más ancho: premia llegar corriendo.
	_solid(Rect2(2540, FLOOR_Y, 560, 100))
	_one_way(Rect2(2320, 500, 150, 20))


func _build_zone_drop() -> void:
	_solid(Rect2(3100, FLOOR_Y, 1900, 100))
	_add_title(Vector2(2660, 155), "03 · ATRAVESAR", "Subí a las plataformas amarillas\nArriba de ellas, deslizá hacia abajo")
	# Escalera que enseña plataformas atravesables.
	_one_way(Rect2(2800, 520, 170, 20))
	_one_way(Rect2(2990, 445, 170, 20))
	_solid(Rect2(3100, 420, 70, 200))
	_one_way(Rect2(3160, 375, 300, 22))
	_one_way(Rect2(3460, 375, 300, 22))
	_one_way(Rect2(3760, 375, 300, 22))
	# Esta pared cierra el camino alto: hay que bajar antes y cruzar el túnel.
	_solid(Rect2(4060, 0, 90, 505))
	_add_marker(Vector2(3810, 330), "↓")
	_add_marker(Vector2(4200, 575), "BIEN")


func _build_zone_flow() -> void:
	_add_title(Vector2(4300, 165), "04 · FLUJO", "Combiná carrera, salto y correcciones en el aire")
	_one_way(Rect2(4380, 520, 170, 20))
	_one_way(Rect2(4620, 455, 170, 20))
	# Hueco final ancho: requiere envión, pero admite coyote time y buffer.
	_solid(Rect2(5250, FLOOR_Y, 1150, 100))
	_one_way(Rect2(4870, 390, 150, 20))
	_one_way(Rect2(5150, 490, 150, 20))
	_one_way(Rect2(5480, 520, 160, 20))
	_one_way(Rect2(5720, 445, 170, 20))
	_one_way(Rect2(5960, 365, 190, 20))
	_add_title(Vector2(5710, 170), "PRUEBA COMPLETA", "El recorrido termina acá por ahora")
	_add_marker(Vector2(6220, 330), "◆")


func _solid(rect: Rect2, color := SOLID) -> void:
	LevelGeometry.add_solid(_solids, rect, color, null)


func _one_way(rect: Rect2) -> void:
	LevelGeometry.add_one_way_platform(_solids, rect, ONE_WAY)


func _add_title(position: Vector2, title: String, subtitle: String) -> void:
	var title_label := Label.new()
	title_label.position = position
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", TEXT)
	_decor.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.position = position + Vector2(0, 48)
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color(TEXT, 0.78))
	_decor.add_child(subtitle_label)


func _add_marker(position: Vector2, text: String) -> void:
	var label := Label.new()
	label.position = position
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", ONE_WAY)
	_decor.add_child(label)


func _update_checkpoint() -> void:
	var next_index := _checkpoint_index + 1
	if next_index >= CHECKPOINTS.size():
		return
	if _player.global_position.x >= CHECKPOINTS[next_index].x:
		_checkpoint_index = next_index
		_player.set_checkpoint(CHECKPOINTS[_checkpoint_index])

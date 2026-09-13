extends Node2D

## Tres habitaciones top-down conectadas, enteramente dibujadas con colores planos.

const ROOM_SIZE := Vector2(720, 1280)
const TOTAL_SPARKS := 3

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _decor: Node2D = $Decor
@onready var _solids: Node2D = $Solids
@onready var _pickups: Node2D = $Pickups
@onready var _top_card: Panel = $Interface/Root/TopCard
@onready var _room_title: Label = $Interface/Root/TopCard/RoomTitle
@onready var _room_subtitle: Label = $Interface/Root/TopCard/RoomSubtitle
@onready var _counter: Label = $Interface/Root/Counter/Text
@onready var _hint: Panel = $Interface/Root/Hint
@onready var _overlay: ColorRect = $Interface/Root/TransitionOverlay

var _collected := 0
var _title_tween: Tween
var _hint_tween: Tween


func _ready() -> void:
	_player.add_to_group(&"player")
	_build_level()
	_camera.room_changed.connect(_on_room_changed)
	_camera.follow(_player)
	_show_room_title(Vector2i.ZERO, true)
	_update_counter()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(4.8)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.65)


func _build_level() -> void:
	_build_threshold_room()
	_build_chamber_room()
	_build_sanctuary_room()


func _build_threshold_room() -> void:
	LevelGeometry.add_room(
		_backgrounds, _solids, _decor, Vector2i(0, 0), ROOM_SIZE,
		Color("283941"), Color("4c6067"), [&"right"]
	)
	LevelGeometry.add_solid_rect(_solids, Rect2(92, 250, 176, 78), Color("526d70"))
	LevelGeometry.add_circle_obstacle(_solids, Vector2(520, 356), 62, Color("49676a"))
	LevelGeometry.add_solid_rect(_solids, Rect2(225, 860, 270, 92), Color("425e62"))
	LevelGeometry.add_circle_obstacle(_solids, Vector2(145, 1040), 46, Color("4f6a6d"))
	_add_room_rug(Vector2(360, 625), Vector2(250, 300), Color(0.32, 0.56, 0.56, 0.11))
	_add_spark(Vector2(360, 438), Color("66d9c8"))


func _build_chamber_room() -> void:
	var origin := Vector2(ROOM_SIZE.x, 0)
	LevelGeometry.add_room(
		_backgrounds, _solids, _decor, Vector2i(1, 0), ROOM_SIZE,
		Color("393447"), Color("655b73"), [&"left", &"top"]
	)
	LevelGeometry.add_solid_rect(_solids, Rect2(origin + Vector2(245, 430), Vector2(230, 220)), Color("625975"))
	LevelGeometry.add_circle_obstacle(_solids, origin + Vector2(555, 315), 53, Color("74667f"))
	LevelGeometry.add_circle_obstacle(_solids, origin + Vector2(140, 930), 58, Color("695f78"))
	LevelGeometry.add_solid_rect(_solids, Rect2(origin + Vector2(405, 970), Vector2(178, 82)), Color("5a506b"))
	_add_room_rug(origin + Vector2(360, 770), Vector2(330, 270), Color(0.69, 0.45, 0.72, 0.10))
	_add_spark(origin + Vector2(560, 820), Color("c18ee0"))


func _build_sanctuary_room() -> void:
	var origin := Vector2(ROOM_SIZE.x, -ROOM_SIZE.y)
	LevelGeometry.add_room(
		_backgrounds, _solids, _decor, Vector2i(1, -1), ROOM_SIZE,
		Color("2f443d"), Color("557166"), [&"bottom"]
	)
	LevelGeometry.add_circle_obstacle(_solids, origin + Vector2(170, 350), 56, Color("557569"))
	LevelGeometry.add_circle_obstacle(_solids, origin + Vector2(550, 350), 56, Color("557569"))
	LevelGeometry.add_solid_rect(_solids, Rect2(origin + Vector2(135, 770), Vector2(145, 78)), Color("4c6b60"))
	LevelGeometry.add_solid_rect(_solids, Rect2(origin + Vector2(440, 770), Vector2(145, 78)), Color("4c6b60"))
	_add_room_rug(origin + Vector2(360, 590), Vector2(315, 390), Color(0.45, 0.73, 0.59, 0.105))
	_add_spark(origin + Vector2(360, 510), Color("f1c75b"))


func _add_room_rug(center: Vector2, size: Vector2, color: Color) -> void:
	var rug := Polygon2D.new()
	rug.position = center
	rug.z_index = -8
	rug.color = color
	var half := size * 0.5
	rug.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	_decor.add_child(rug)


func _add_spark(position: Vector2, color: Color) -> void:
	var spark := Area2D.new()
	spark.position = position
	spark.collision_layer = 0
	spark.collision_mask = 1
	spark.z_index = 4

	var shape := CircleShape2D.new()
	shape.radius = 32.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	spark.add_child(collision)

	var shadow := Polygon2D.new()
	shadow.position = Vector2(0, 9)
	shadow.polygon = LevelGeometry.circle_points(27, 20)
	shadow.color = Color(0.01, 0.015, 0.02, 0.32)
	shadow.z_index = -1
	spark.add_child(shadow)

	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([Vector2(0, -27), Vector2(22, 0), Vector2(0, 27), Vector2(-22, 0)])
	diamond.color = color
	spark.add_child(diamond)

	var core := Polygon2D.new()
	core.polygon = LevelGeometry.circle_points(10, 16)
	core.color = color.lightened(0.36)
	spark.add_child(core)

	_pickups.add_child(spark)
	spark.body_entered.connect(_on_spark_collected.bind(spark))
	var float_tween := spark.create_tween().set_loops()
	float_tween.set_trans(Tween.TRANS_SINE)
	float_tween.tween_property(spark, "position:y", position.y - 7.0, 0.72)
	float_tween.tween_property(spark, "position:y", position.y + 7.0, 0.72)


func _on_spark_collected(body: Node2D, spark: Area2D) -> void:
	if body != _player or not is_instance_valid(spark) or not spark.monitoring:
		return
	spark.set_deferred("monitoring", false)
	_collected += 1
	_update_counter()
	var collect_tween := create_tween().set_parallel(true)
	collect_tween.set_trans(Tween.TRANS_BACK)
	collect_tween.set_ease(Tween.EASE_IN)
	collect_tween.tween_property(spark, "scale", Vector2(1.8, 1.8), 0.22)
	collect_tween.tween_property(spark, "modulate:a", 0.0, 0.22)
	collect_tween.chain().tween_callback(spark.queue_free)
	_flash(Color(0.95, 0.82, 0.45, 1), 0.15)
	if _collected == TOTAL_SPARKS:
		_room_subtitle.text = "Prototipo completo"
		_room_subtitle.visible = true
		_room_title.text = "LOS TRES DESTELLOS"
		_show_top_card()


func _update_counter() -> void:
	_counter.text = "◆  %d / %d" % [_collected, TOTAL_SPARKS]


func _on_room_changed(room: Vector2i, _direction: Vector2i) -> void:
	_show_room_title(room, false)
	_flash(Color(0.70, 0.90, 0.87, 1), 0.11)


func _show_room_title(room: Vector2i, instant: bool) -> void:
	match room:
		Vector2i(0, 0):
			_room_title.text = "EL UMBRAL"
			_room_subtitle.text = ""
		Vector2i(1, 0):
			_room_title.text = "LA CÁMARA"
			_room_subtitle.text = "Encontrá el camino hacia arriba"
		Vector2i(1, -1):
			_room_title.text = "EL SANTUARIO"
			_room_subtitle.text = "La última luz espera"
		_:
			_room_title.text = "POLITROPIA"
			_room_subtitle.text = ""
	_room_subtitle.visible = not _room_subtitle.text.is_empty()
	if instant:
		_top_card.modulate.a = 1.0
		return
	_show_top_card()


func _show_top_card() -> void:
	if is_instance_valid(_title_tween):
		_title_tween.kill()
	_top_card.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_top_card, "modulate:a", 1.0, 0.18)
	_title_tween.tween_interval(1.55)
	_title_tween.tween_property(_top_card, "modulate:a", 0.18, 0.42)


func _flash(color: Color, peak_alpha: float) -> void:
	_overlay.color = color
	_overlay.modulate.a = peak_alpha
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, 0.32)

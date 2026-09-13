extends Node2D

## Tres habitaciones top-down conectadas, enteramente dibujadas con colores planos.

const HunterScript := preload("res://scripts/combat/hunter_enemy.gd")
const BossScript := preload("res://scripts/combat/boss_enemy.gd")
const PathfinderScript := preload("res://scripts/combat/room_pathfinder.gd")
const ROOM_SIZE := Vector2(720, 1280)
const FIRST_ROOM_SPAWN := Vector2(360, 640)
const DOOR_LOCK_DELAY := 0.35 ## Tiempo para terminar de cruzar el vano antes de sellarlo.

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _decor: Node2D = $Decor
@onready var _solids: Node2D = $Solids
@onready var _hunters: Node2D = $Hunters
@onready var _boss_container: Node2D = $Boss
@onready var _overlay: ColorRect = $Interface/Root/TransitionOverlay
@onready var _boss_bar: Control = $Interface/Root/BossBar
@onready var _boss_bar_fill: Control = $Interface/Root/BossBar/Track/Fill

var _pathfinder
var _boss_pathfinder
var _door_threshold_chamber: RoomDoor
var _door_chamber_sanctuary: RoomDoor
var _chamber_bleed_guard: Polygon2D
var _sanctuary_bleed_guard: Polygon2D
var _hunter_spawns: Array[Dictionary] = []
var _hunters_remaining := 0
var _chamber_locked := false
var _chamber_cleared := false
var _boss: BossEnemy
var _boss_locked := false
var _boss_cleared := false


func _ready() -> void:
	_player.add_to_group(&"player")
	_build_level()
	_build_doors()
	_build_bleed_guards()
	_player.mark_checkpoint(FIRST_ROOM_SPAWN)
	_player.died.connect(_on_player_died)
	_camera.room_changed.connect(_on_room_changed)
	_camera.follow(_player)
	_apply_boss_bar_safe_area()
	call_deferred("_setup_hunters")


func _apply_boss_bar_safe_area() -> void:
	var inset := SafeArea.top_inset(get_viewport())
	if inset <= 0.0:
		return
	_boss_bar.offset_top += inset
	_boss_bar.offset_bottom += inset


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
	_add_wand_pedestal(Vector2(360, 548))


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


func _build_doors() -> void:
	# Puerta entre el vestíbulo y la cámara (cazadores): sella el paso lateral.
	var threshold_chamber_rect := Rect2(
		ROOM_SIZE.x - LevelGeometry.WALL_THICKNESS,
		ROOM_SIZE.y * 0.5 - LevelGeometry.DOOR_GAP * 0.5,
		LevelGeometry.WALL_THICKNESS * 2.0,
		LevelGeometry.DOOR_GAP
	)
	_door_threshold_chamber = LevelGeometry.add_door(_solids, threshold_chamber_rect)

	# Puerta entre la cámara y el santuario: sella el paso superior.
	var chamber_sanctuary_rect := Rect2(
		ROOM_SIZE.x * 1.5 - LevelGeometry.DOOR_GAP * 0.5,
		-LevelGeometry.WALL_THICKNESS,
		LevelGeometry.DOOR_GAP,
		LevelGeometry.WALL_THICKNESS * 2.0
	)
	_door_chamber_sanctuary = LevelGeometry.add_door(_solids, chamber_sanctuary_rect)


func _build_bleed_guards() -> void:
	# El "expand" del proyecto (para llenar la pantalla real, sin bordes
	# negros) revela un poco de mundo más allá de una sala en dispositivos
	# cuya proporción no es exactamente 720:1280. La única puerta vertical
	# (cámara-santuario) deja asomar la sala vecina por ahí; estos parches
	# tapan ese asomo con el piso de la sala en la que estás parado, y se
	# activan/desactivan solos según en qué sala estés (_update_bleed_guards).
	var gap_x := ROOM_SIZE.x * 1.5 - LevelGeometry.DOOR_GAP * 0.5
	var guard_depth := 260.0
	_chamber_bleed_guard = _make_bleed_guard(
		Rect2(gap_x, -guard_depth, LevelGeometry.DOOR_GAP, guard_depth), Color("393447")
	)
	_sanctuary_bleed_guard = _make_bleed_guard(
		Rect2(gap_x, 0.0, LevelGeometry.DOOR_GAP, guard_depth), Color("2f443d")
	)
	_update_bleed_guards(Vector2i(0, 0))


func _make_bleed_guard(rect: Rect2, color: Color) -> Polygon2D:
	var guard := Polygon2D.new()
	var half := rect.size * 0.5
	guard.position = rect.position + half
	guard.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	guard.color = color
	guard.z_index = 4
	_decor.add_child(guard)
	return guard


func _update_bleed_guards(room: Vector2i) -> void:
	_chamber_bleed_guard.visible = room == Vector2i(1, 0)
	_sanctuary_bleed_guard.visible = room == Vector2i(1, -1)


func _setup_hunters() -> void:
	_pathfinder = PathfinderScript.new()
	_pathfinder.build(get_world_2d(), Vector2(ROOM_SIZE.x, 0.0), ROOM_SIZE)
	_hunter_spawns = [
		{"kind": HunterScript.Kind.MELEE, "position": Vector2(ROOM_SIZE.x + 560.0, 248.0)},
		{"kind": HunterScript.Kind.RANGED, "position": Vector2(ROOM_SIZE.x + 168.0, 1088.0)},
	]


func _start_chamber_encounter() -> void:
	_chamber_locked = true
	_spawn_room_hunters()
	_wake_hunters()
	Input.vibrate_handheld(24, 0.5)
	_flash(Color(0.86, 0.42, 0.36, 1), 0.16)
	# Se cierra un instante después de cruzar el umbral: si sella la puerta en
	# el mismo frame en que se detecta la entrada, el jugador todavía está
	# físicamente atravesando el vano y la física lo empuja de vuelta afuera.
	get_tree().create_timer(DOOR_LOCK_DELAY).timeout.connect(_lock_chamber_doors_deferred)


func _lock_chamber_doors_deferred() -> void:
	if _chamber_locked:
		_set_chamber_doors_locked(true)


func _spawn_room_hunters() -> void:
	for child in _hunters.get_children():
		child.queue_free()
	_hunters_remaining = _hunter_spawns.size()
	for spawn in _hunter_spawns:
		_spawn_hunter(spawn.kind, spawn.position)


func _spawn_hunter(kind: int, world_position: Vector2) -> void:
	var enemy := HunterScript.new()
	enemy.setup(kind, Vector2(ROOM_SIZE.x, 0.0), _pathfinder)
	enemy.defeated.connect(_on_hunter_defeated)
	_hunters.add_child(enemy)
	enemy.global_position = world_position


func _wake_hunters() -> void:
	var delay := 0.16
	for child in _hunters.get_children():
		if child.has_method("wake_up"):
			child.wake_up(delay)
			delay += 0.28


func _on_hunter_defeated() -> void:
	_hunters_remaining -= 1
	if _chamber_locked and _hunters_remaining <= 0:
		_clear_chamber()


func _clear_chamber() -> void:
	_chamber_locked = false
	_chamber_cleared = true
	_set_chamber_doors_locked(false)
	Input.vibrate_handheld(18, 0.4)
	_flash(Color(0.62, 0.95, 0.88, 1), 0.2)


func _start_boss_encounter() -> void:
	_boss_locked = true
	_spawn_boss()
	_show_boss_bar()
	_boss.wake_up(0.6)
	Input.vibrate_handheld(30, 0.6)
	_flash(Color(0.55, 0.18, 0.28, 1), 0.2)
	get_tree().create_timer(DOOR_LOCK_DELAY).timeout.connect(_lock_boss_door_deferred)


func _lock_boss_door_deferred() -> void:
	if _boss_locked:
		_door_chamber_sanctuary.close_door()


func _spawn_boss() -> void:
	if is_instance_valid(_boss):
		_boss.queue_free()
	var origin := Vector2(ROOM_SIZE.x, -ROOM_SIZE.y)
	if _boss_pathfinder == null:
		_boss_pathfinder = PathfinderScript.new()
		_boss_pathfinder.build(get_world_2d(), origin, ROOM_SIZE)
	_boss = BossScript.new()
	_boss.setup(origin, _boss_pathfinder)
	_boss.health_changed.connect(_update_boss_bar)
	_boss.defeated.connect(_on_boss_defeated)
	_boss_container.add_child(_boss)
	_boss.global_position = origin + Vector2(360.0, 470.0)
	_update_boss_bar(1.0)


func _on_boss_defeated() -> void:
	_boss_locked = false
	_boss_cleared = true
	_door_chamber_sanctuary.open_door()
	_hide_boss_bar()
	Input.vibrate_handheld(40, 0.75)
	_flash(Color(0.62, 0.95, 0.88, 1), 0.24)


func _show_boss_bar() -> void:
	_boss_bar.visible = true
	_boss_bar.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_boss_bar, "modulate:a", 1.0, 0.3)


func _hide_boss_bar() -> void:
	var tween := create_tween()
	tween.tween_property(_boss_bar, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): _boss_bar.visible = false)


func _update_boss_bar(fraction: float) -> void:
	var tween := create_tween()
	tween.tween_property(_boss_bar_fill, "anchor_right", fraction, 0.22)


func _on_player_died() -> void:
	if _chamber_locked:
		_chamber_locked = false
		_set_chamber_doors_locked(false)
	if _boss_locked:
		_boss_locked = false
		_door_chamber_sanctuary.open_door()
		_hide_boss_bar()


func _set_chamber_doors_locked(locked: bool) -> void:
	if locked:
		_door_threshold_chamber.close_door()
		_door_chamber_sanctuary.close_door()
	else:
		_door_threshold_chamber.open_door()
		_door_chamber_sanctuary.open_door()


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


func _add_wand_pedestal(position: Vector2) -> void:
	var pedestal := Node2D.new()
	pedestal.position = position
	pedestal.z_index = 3
	_decor.add_child(pedestal)

	var shadow := Polygon2D.new()
	shadow.position = Vector2(0, 18)
	shadow.polygon = LevelGeometry.circle_points(34, 20)
	shadow.color = Color(0.01, 0.015, 0.02, 0.34)
	shadow.z_index = -1
	pedestal.add_child(shadow)

	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-32, 6), Vector2(32, 6), Vector2(24, 22), Vector2(-24, 22),
	])
	base.color = Color("3a484b")
	pedestal.add_child(base)

	var column := Polygon2D.new()
	column.polygon = PackedVector2Array([
		Vector2(-16, 8), Vector2(16, 8), Vector2(13, -10), Vector2(-13, -10),
	])
	column.color = Color("536366")
	pedestal.add_child(column)

	var cap := Polygon2D.new()
	cap.position = Vector2(0, -14)
	cap.polygon = PackedVector2Array([
		Vector2(-22, 6), Vector2(22, 6), Vector2(18, -4), Vector2(-18, -4),
	])
	cap.color = Color("6a7577")
	pedestal.add_child(cap)

	var inlay := Polygon2D.new()
	inlay.position = Vector2(0, -16)
	inlay.polygon = LevelGeometry.circle_points(9, 14)
	inlay.color = Color("7d8d82")
	pedestal.add_child(inlay)

	var wand := Area2D.new()
	wand.position = Vector2(4, -46)
	wand.collision_layer = 0
	wand.collision_mask = 1
	pedestal.add_child(wand)

	var shape := CircleShape2D.new()
	shape.radius = 40.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wand.add_child(collision)

	var shaft := Polygon2D.new()
	shaft.polygon = PackedVector2Array([
		Vector2(-4, 22), Vector2(3, 24), Vector2(7, -18), Vector2(-1, -20),
	])
	shaft.color = Color("c4a15a")
	wand.add_child(shaft)

	var wrap := Polygon2D.new()
	wrap.polygon = PackedVector2Array([
		Vector2(-3, 2), Vector2(6, 4), Vector2(5, -2), Vector2(-4, -4),
	])
	wrap.color = Color("8d6a32")
	wand.add_child(wrap)

	var glow := Polygon2D.new()
	glow.position = Vector2(4, -26)
	glow.polygon = LevelGeometry.circle_points(16, 16)
	glow.color = Color(0.55, 0.95, 0.88, 0.28)
	wand.add_child(glow)

	var gem := Polygon2D.new()
	gem.position = Vector2(4, -26)
	gem.polygon = LevelGeometry.circle_points(9, 16)
	gem.color = Color("7ee8d8")
	wand.add_child(gem)

	var gem_core := Polygon2D.new()
	gem_core.position = Vector2(2, -28)
	gem_core.polygon = LevelGeometry.circle_points(4, 12)
	gem_core.color = Color(0.96, 1.0, 0.98, 0.92)
	wand.add_child(gem_core)

	wand.body_entered.connect(_on_wand_collected.bind(wand))
	var float_tween := wand.create_tween().set_loops()
	float_tween.set_trans(Tween.TRANS_SINE)
	float_tween.tween_property(wand, "position:y", -52.0, 0.78)
	float_tween.tween_property(wand, "position:y", -40.0, 0.78)


func _on_wand_collected(body: Node2D, wand: Area2D) -> void:
	if body != _player or not is_instance_valid(wand) or not wand.monitoring:
		return
	wand.set_deferred("monitoring", false)
	_player.unlock_wand()
	Input.vibrate_handheld(28, 0.42)
	var collect_tween := create_tween().set_parallel(true)
	collect_tween.set_trans(Tween.TRANS_BACK)
	collect_tween.set_ease(Tween.EASE_IN)
	collect_tween.tween_property(wand, "scale", Vector2(1.7, 1.7), 0.2)
	collect_tween.tween_property(wand, "modulate:a", 0.0, 0.2)
	collect_tween.chain().tween_callback(wand.queue_free)
	_flash(Color(0.62, 0.95, 0.88, 1), 0.16)


func _on_room_changed(room: Vector2i, _direction: Vector2i) -> void:
	_clear_projectiles()
	_update_bleed_guards(room)
	if room == Vector2i(1, 0) and not _chamber_cleared:
		_start_chamber_encounter()
		return
	if room == Vector2i(1, -1) and not _boss_cleared:
		_start_boss_encounter()
		return


func _clear_projectiles() -> void:
	var projectiles := get_node_or_null("Projectiles")
	if projectiles == null:
		return
	for child in projectiles.get_children():
		child.queue_free()


func _flash(color: Color, peak_alpha: float) -> void:
	_overlay.color = color
	_overlay.modulate.a = peak_alpha
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, 0.32)

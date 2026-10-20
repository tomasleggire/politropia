class_name SceneTransitionArea
extends Area2D

## Door between two scenes: fades to black, loads the target scene and places
## Luz at the matching door of that scene, just inside the room and facing in.
##
## HOW TO USE (drag and drop):
## 1. Instance `scenes/world/change_scene_vertical.tscn` (tall strip: a doorway in a
##    left or right wall) or `change_scene_horizontal.tscn` (wide strip: an opening in
##    a floor or ceiling) and place it on the exit. Resize its CollisionShape2D to
##    cover the opening.
## 2. Set `Target Scene Path` to the room it leads to.
## 3. Pair the doors: give this door a `Door Id` and set `Target Door Id` to the
##    `Door Id` of the door you want to arrive at in the target scene. The target
##    scene must hold that door (another SceneTransitionArea, or a SpawnPoint with
##    the same id). Both ends of a connection use mirrored ids, e.g.
##        in zone 2: door_id = ZONE_2_TO_ZONE_3, target_door_id = ZONE_3_TO_ZONE_2
##        in zone 3: door_id = ZONE_3_TO_ZONE_2, target_door_id = ZONE_2_TO_ZONE_3
## 4. If Luz lands in the wrong spot, set `Arrival Offset` on the door she arrives
##    at (the one whose `Door Id` is the target): it moves her relative to that door.
##
## A missing target door id is reported with push_warning and Luz then stays at the
## default position of the target scene. Run tests/door_links_test.gd to check every
## door of the game.

signal transition_started(target_name: String)
signal screen_faded_out
signal screen_faded_in

## How far past the edge of the door's trigger Luz appears when the door is left on
## automatic arrival, so she does not touch the trigger she just came through.
const ARRIVAL_CLEARANCE := 40.0
## How far the arrival spot may be moved up or down to find free ground under it.
const ARRIVAL_MAX_LIFT := 96.0
const ARRIVAL_MAX_DROP := 200.0
const ARRIVAL_STEP := 8.0
## How far it may slide sideways, toward the inside of the room, when the door opens
## onto a hole in the floor (the arrival spot is then the ledge beside the hole).
const ARRIVAL_MAX_SLIDE := 240.0
## Extra room kept between Luz and the edge of that ledge.
const ARRIVAL_EDGE_MARGIN := 24.0
## A doorway in a wall is meant to end at the floor; Luz is placed this far above it.
const ARRIVAL_FLOOR_INSET := 2.0
const _DEFAULT_BODY_SIZE := Vector2(29.0, 46.0)

## Turns the door off without deleting it (e.g. a demo shortcut). A disabled door never
## triggers, but it can still be arrived at.
@export var enabled: bool = true

@export_group("Target Scene")
## Scene (.tscn) this door leads to.
@export_file("*.tscn") var target_scene_path: String = ""
## Alternatively, assign the target PackedScene directly.
@export var target_scene: PackedScene

@export_group("Door Pairing")
## Id of THIS door in its own scene. The door you arrive from in the other scene
## points its `Target Door Id` at this value. Convention: ZONE_<this>_TO_<neighbour>.
@export var door_id: DoorID.ID = DoorID.ID.NONE
## Id of the door (or SpawnPoint) in the TARGET scene where Luz must arrive.
## Convention: ZONE_<neighbour>_TO_<this>. NONE = she appears at the default
## position of the target scene.
@export var target_door_id: DoorID.ID = DoorID.ID.NONE

@export_group("Arrival")
## Where Luz appears when she ARRIVES through this door, relative to this node.
## ZERO = automatic: just inside the room (toward where the scene starts), standing on
## the floor and facing into the room. Set it only when the automatic spot is wrong.
@export var arrival_offset: Vector2 = Vector2.ZERO

@export_group("Transition Settings")
## Duración del fade out a negro y del fade in a la nueva escena (en segundos). 0.5s = 500ms.
@export_range(0.05, 5.0, 0.05) var fade_duration: float = 0.5
## Color del fundido (por defecto negro pleno).
@export var fade_color: Color = Color.BLACK
## Bloquear la velocidad y física del jugador durante la transición para evitar caídas o movimientos en negro.
@export var lock_player: bool = true
## Capa física del jugador (Capa 1 por defecto en el proyecto).
@export_flags_2d_physics var player_collision_mask: int = 1

enum LoadingAnimationMode {
	PULSE,
	SPIN,
	PULSE_AND_SPIN,
	NONE,
}

@export_group("Loading Indicator")
## Si es verdadero, muestra un asset o indicador visual mientras se carga la nueva escena.
@export var show_loading_asset: bool = true
## Textura o icono para el indicador de carga. Si no se asigna, se utiliza un asset temático por defecto (el grimorio).
@export var loading_asset_texture: Texture2D = null
## Texto opcional mostrado junto al indicador de carga (dejar vacío si solo se quiere el icono).
@export var loading_text: String = "Cargando..."
## Tamaño de la fuente del texto de carga en píxeles.
@export_range(8, 64, 1) var loading_font_size: int = 18
## Tamaño del icono o libro en píxeles (ancho y alto).
@export_range(16.0, 256.0, 2.0) var loading_icon_size: float = 60.0
## Estilo de animación del asset indicador de carga (pulso, giro, pulso y giro o estático).
@export var loading_animation_mode: LoadingAnimationMode = LoadingAnimationMode.PULSE
## Escala de la animación de pulso (ej: 1.25 = aumenta un 25% su tamaño al pulsar).
@export_range(1.0, 2.5, 0.05) var loading_animation_scale: float = 1.25
## Tiempo mínimo en segundos para mantener visible el asset de carga y evitar parpadeos si la carga es instantánea.
@export_range(0.0, 3.0, 0.05) var min_loading_screen_time: float = 0.35
## Escena completa personalizada opcional si se desea una pantalla de carga personalizada en vez del widget integrado.
@export var custom_loading_scene: PackedScene = null

@export_group("Scene Name Display")
## Si es verdadero, muestra un texto centrado en pantalla con el nombre de la escena a la que se transiciona.
@export var show_scene_name: bool = true
## Nombre personalizado para mostrar (ej: "Pozo de libros"). Si se deja vacío, se detecta automáticamente.
@export var scene_display_name: String = ""
## Si es verdadero y no hay nombre manual, incluye el prefijo del nivel (ej: "Biblioteca - Pozo de libros").
@export var include_level_prefix: bool = true
## Tamaño de la fuente del nombre centrado de la escena en píxeles.
@export_range(10, 64, 1) var scene_name_font_size: int = 22

## Bandera temporal para evitar re-triggers mientras la pantalla está en transición.
static var is_transition_in_progress: bool = false

var _triggered: bool = false
var _spawn_overlapping: bool = false


func _ready() -> void:
	add_to_group(&"scene_transition_area")
	collision_layer = 0
	collision_mask = player_collision_mask
	monitoring = enabled
	monitorable = false

	# Duplica el recurso de CollisionShape2D para que cambiar el tamaño en una instancia
	# no afecte a las demás en el editor.
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape != null:
		shape_node.shape = shape_node.shape.duplicate()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		_spawn_overlapping = false


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not enabled:
		return
	if not _is_player(body):
		return
	if is_transition_in_progress:
		_spawn_overlapping = true
		return
	if _spawn_overlapping:
		return

	if target_scene == null and target_scene_path.is_empty():
		push_warning("SceneTransitionArea: No se definió una escena destino en '%s'." % name)
		return

	_triggered = true
	var destination_name := target_scene.resource_path if target_scene != null else target_scene_path
	transition_started.emit(destination_name)

	if lock_player:
		apply_player_lock(body)
	if body is Player:
		(body as Player).save_for_transition()

	var final_scene_name := ""
	if show_scene_name:
		final_scene_name = resolve_scene_name(destination_name, scene_display_name, include_level_prefix)

	start_transition(
		get_tree(),
		target_scene,
		target_scene_path,
		fade_duration,
		fade_color,
		target_door_id,
		lock_player,
		show_loading_asset,
		loading_asset_texture,
		loading_text,
		min_loading_screen_time,
		loading_animation_mode,
		custom_loading_scene,
		loading_font_size,
		loading_icon_size,
		loading_animation_scale,
		show_scene_name,
		final_scene_name,
		scene_name_font_size
	)


func _is_player(body: Node2D) -> bool:
	if body is Player:
		return true
	if body.is_in_group(&"player"):
		return true
	return false


## Normaliza una ruta que puede venir como "uid://..." o "res://..." a su ruta estándar "res://...".
static func normalize_scene_path(path_or_uid: String) -> String:
	if path_or_uid.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path_or_uid)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			var res_path := ResourceUID.get_id_path(id)
			if not res_path.is_empty():
				return res_path
		if ResourceLoader.exists(path_or_uid):
			var res := ResourceLoader.load(path_or_uid)
			if res != null and not res.resource_path.is_empty():
				return res.resource_path
	return path_or_uid


## Resuelve el nombre visible de una escena usando MapLayout/MapRoom o el nombre del archivo.
static func resolve_scene_name(target_path: String, custom_name: String = "", with_level_prefix: bool = true) -> String:
	if not custom_name.strip_edges().is_empty():
		return custom_name.strip_edges()

	if target_path.is_empty():
		return ""

	var normalized_target := normalize_scene_path(target_path)

	if ResourceLoader.exists("res://scripts/world/map_layout.gd"):
		var layouts: Array[MapLayout] = MapLayout.load_all()
		for layout in layouts:
			if layout == null:
				continue
			var room: MapRoom = null
			for r in layout.rooms:
				if r != null:
					if r.scene_path == normalized_target or normalize_scene_path(r.scene_path) == normalized_target:
						room = r
						break
			if room != null and not room.display_name.is_empty():
				if with_level_prefix and not layout.level_name.is_empty():
					return "%s - %s" % [layout.level_name, room.display_name]
				return room.display_name

	var file_name := normalized_target.get_file().get_basename()
	var clean := file_name.replace("_", " ").capitalize()
	if clean.begins_with("Zone "):
		clean = clean.replace("Zone ", "Zona ")
	return clean


## Inicia la transición con pantalla a negro desde cualquier lugar por código.
static func start_transition(
	tree: SceneTree,
	scene_resource: PackedScene,
	scene_path: String,
	duration: float = 0.5,
	color: Color = Color.BLACK,
	target_door: DoorID.ID = DoorID.ID.NONE,
	lock_p: bool = true,
	show_loading: bool = true,
	loading_tex: Texture2D = null,
	loading_msg: String = "Cargando...",
	min_load_time: float = 0.35,
	anim_mode: LoadingAnimationMode = LoadingAnimationMode.PULSE,
	custom_loading: PackedScene = null,
	font_sz: int = 24,
	icon_sz: float = 60.0,
	anim_scale: float = 1.25,
	show_title: bool = true,
	title_text: String = "",
	title_font_sz: int = 22
) -> void:
	var overlay := ScreenFadeOverlay.new(
		color,
		duration,
		scene_resource,
		scene_path,
		target_door,
		lock_p,
		show_loading,
		loading_tex,
		loading_msg,
		min_load_time,
		anim_mode,
		custom_loading,
		font_sz,
		icon_sz,
		anim_scale,
		show_title,
		title_text,
		title_font_sz
	)
	tree.root.add_child(overlay)
	overlay.run_transition()


## Busca al jugador de manera confiable en la escena actual.
static func _find_player(tree: SceneTree) -> Node2D:
	if tree == null:
		return null
	var player := tree.get_first_node_in_group(&"player") as Node2D
	if player != null:
		return player
	if tree.current_scene != null:
		player = tree.current_scene.find_child("Player*", true, false) as Node2D
		if player != null:
			return player
	return null


## Finds the door Luz must arrive at in the current scene: a SpawnPoint wins over a
## SceneTransitionArea with the same `door_id`. Returns null when `target_id` is NONE
## or the scene has no such door.
static func find_door(tree: SceneTree, target_id: DoorID.ID) -> Node2D:
	if target_id == DoorID.ID.NONE or tree == null:
		return null
	for node in tree.get_nodes_in_group(&"spawn_points"):
		if node is Node2D and node.get("spawn_id") == target_id:
			return node
	for node in tree.get_nodes_in_group(&"scene_transition_area"):
		if node is SceneTransitionArea and node.door_id == target_id:
			return node
	return null


## Where Luz appears when she arrives through `door`, as {position: Vector2, facing: int,
## slide: float} (facing 0 = leave it as is; slide = side to search toward, see settle_position). `origin` is the default position of the scene's player,
## which tells which side of the door is inside the room.
static func resolve_arrival(door: Node2D, origin: Vector2) -> Dictionary:
	if not door is SceneTransitionArea:
		return {"position": door.global_position, "facing": 0, "slide": 0.0}
	var area := door as SceneTransitionArea
	var half := area._half_extents()
	var to_origin := origin - area.global_position
	var through_wall := half.y >= half.x
	var inward := Vector2.ZERO
	if through_wall:
		inward.x = 1.0 if to_origin.x >= 0.0 else -1.0
	else:
		inward.y = 1.0 if to_origin.y >= 0.0 else -1.0
	var slide := 1.0 if to_origin.x >= 0.0 else -1.0
	var facing := int(inward.x) if through_wall else int(slide)
	if area.arrival_offset != Vector2.ZERO:
		if not is_zero_approx(area.arrival_offset.x):
			facing = 1 if area.arrival_offset.x > 0.0 else -1
		return {"position": area.global_position + area.arrival_offset, "facing": facing, "slide": 0.0}
	var center := area._shape_center()
	var distance := (half.x if through_wall else half.y) + ARRIVAL_CLEARANCE
	var spot := center + inward * distance
	if through_wall:
		# The bottom of a doorway in a wall is its floor: arrive standing there.
		spot.y = center.y + half.y - ARRIVAL_FLOOR_INSET
	return {"position": spot, "facing": facing, "slide": slide}


## Finds the standing spot for the body near `wanted`: free of solid geometry and on the
## floor. It tries the vertical neighbourhood first (up, then down) and, when `slide` is
## -1 or 1, then slides that way until it finds ground (the ledge beside a hole in the
## floor). Returns `wanted` unchanged when nothing fits, so Luz falls from there.
## Needs the physics space to know the scene's colliders (wait two physics frames after
## the scene loads).
static func settle_position(body: CharacterBody2D, wanted: Vector2, slide: float = 0.0) -> Vector2:
	var shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var shape: Shape2D = RectangleShape2D.new()
	(shape as RectangleShape2D).size = _DEFAULT_BODY_SIZE
	var local := Vector2(0.0, -_DEFAULT_BODY_SIZE.y * 0.5)
	if shape_node != null and shape_node.shape != null:
		shape = shape_node.shape
		local = shape_node.position
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = body.collision_mask
	params.exclude = [body.get_rid()]
	var space := body.get_world_2d().direct_space_state
	var side := signf(slide)
	var steps := int(ARRIVAL_MAX_SLIDE / ARRIVAL_STEP) if side != 0.0 else 0
	for i in range(steps + 1):
		var dx := float(i) * ARRIVAL_STEP * side
		var spot: Variant = _stand_near(space, params, local, wanted + Vector2(dx, 0.0))
		if spot == null:
			continue
		if i == 0:
			return spot
		# Keep clear of the ledge edge: stand a little further along it.
		var clear: Variant = _stand_near(space, params, local, wanted + Vector2(dx + side * ARRIVAL_EDGE_MARGIN, 0.0))
		if clear != null and absf((clear as Vector2).y - (spot as Vector2).y) <= ARRIVAL_STEP:
			return clear
	return wanted


## Free spot with floor under `at`, within the vertical reach of the arrival, or null.
static func _stand_near(space: PhysicsDirectSpaceState2D, params: PhysicsShapeQueryParameters2D, local: Vector2, at: Vector2) -> Variant:
	for shift: float in _arrival_shifts():
		params.motion = Vector2.ZERO
		params.transform = Transform2D(0.0, at + Vector2(0.0, shift) + local)
		if not space.intersect_shape(params, 1).is_empty():
			continue
		params.motion = Vector2(0.0, ARRIVAL_MAX_DROP)
		var fractions := space.cast_motion(params)
		if fractions.size() != 2 or fractions[0] >= 1.0:
			continue
		var spot := at + Vector2(0.0, shift + ARRIVAL_MAX_DROP * fractions[0])
		if spot.y - at.y <= ARRIVAL_MAX_DROP and at.y - spot.y <= ARRIVAL_MAX_LIFT:
			return spot
	return null


## Vertical shifts to try, in order: none, up to ARRIVAL_MAX_LIFT, then down to ARRIVAL_MAX_DROP.
static func _arrival_shifts() -> Array[float]:
	var shifts: Array[float] = [0.0]
	var up := ARRIVAL_STEP
	while up <= ARRIVAL_MAX_LIFT:
		shifts.append(-up)
		up += ARRIVAL_STEP
	var down := ARRIVAL_STEP
	while down <= ARRIVAL_MAX_DROP:
		shifts.append(down)
		down += ARRIVAL_STEP
	return shifts


## Half size of this door's trigger in world units.
func _half_extents() -> Vector2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		return (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs() * 0.5
	return Vector2(32.0, 32.0)


func _shape_center() -> Vector2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	return shape_node.global_position if shape_node != null else global_position


## Resetea el suavizado y encuadre de las cámaras para evitar sacudidas al cambiar de coordenadas.
static func _reset_cameras(player: Node2D) -> void:
	if player == null or not player.is_inside_tree():
		return
	var tree := player.get_tree()
	if tree == null:
		return

	# Si el jugador tiene una Camera2D propia (ej. CamaraJugador)
	var player_cam := player.get_node_or_null("Camera2D") as Camera2D
	if player_cam != null:
		player_cam.reset_smoothing()

	# Si la escena tiene una RoomCamera activa
	var room_cams := tree.get_nodes_in_group(&"room_camera")
	for rc in room_cams:
		if rc.has_method(&"snap_to_target"):
			rc.snap_to_target()

	# Cualquier otra cámara en el grupo player_camera
	var player_cams := tree.get_nodes_in_group(&"player_camera")
	for pc in player_cams:
		if pc is Camera2D and pc != player_cam:
			pc.reset_smoothing()


## Aplica bloqueo de controles y física al jugador.
static func apply_player_lock(player: Node2D) -> void:
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)


## Desbloquea los controles y física del jugador.
static func unlock_player(player: Node2D) -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)


## Clase interna que crea temporalmente un CanvasLayer en /root/ para persistir
## únicamente durante la transición y destruirse al finalizar.
class ScreenFadeOverlay extends CanvasLayer:
	var fade_color: Color
	var duration: float
	var target_scene: PackedScene
	var target_scene_path: String
	var target_door: DoorID.ID
	var should_lock_player: bool
	var show_loading_asset: bool
	var loading_texture: Texture2D
	var loading_text: String
	var min_loading_time: float
	var loading_anim_mode: SceneTransitionArea.LoadingAnimationMode
	var custom_loading_scene: PackedScene
	var loading_font_size: int
	var loading_icon_size: float
	var loading_anim_scale: float
	var show_scene_name: bool
	var scene_name_text: String
	var scene_name_font_size: int

	var color_rect: ColorRect
	var loading_container: Control
	var loading_tween: Tween

	func _init(
		p_color: Color,
		p_duration: float,
		p_target_scene: PackedScene,
		p_target_scene_path: String,
		p_target_door: DoorID.ID = DoorID.ID.NONE,
		p_should_lock_player: bool = true,
		p_show_loading: bool = true,
		p_loading_texture: Texture2D = null,
		p_loading_text: String = "Cargando...",
		p_min_loading_time: float = 0.35,
		p_loading_anim_mode: SceneTransitionArea.LoadingAnimationMode = SceneTransitionArea.LoadingAnimationMode.PULSE,
		p_custom_loading_scene: PackedScene = null,
		p_loading_font_size: int = 24,
		p_loading_icon_size: float = 60.0,
		p_loading_anim_scale: float = 1.25,
		p_show_scene_name: bool = true,
		p_scene_name_text: String = "",
		p_scene_name_font_size: int = 22
	) -> void:
		fade_color = p_color
		duration = p_duration
		target_scene = p_target_scene
		target_scene_path = p_target_scene_path
		target_door = p_target_door
		should_lock_player = p_should_lock_player
		show_loading_asset = p_show_loading
		loading_texture = p_loading_texture
		loading_text = p_loading_text
		min_loading_time = p_min_loading_time
		loading_anim_mode = p_loading_anim_mode
		custom_loading_scene = p_custom_loading_scene
		loading_font_size = p_loading_font_size
		loading_icon_size = p_loading_icon_size
		loading_anim_scale = p_loading_anim_scale
		show_scene_name = p_show_scene_name
		scene_name_text = p_scene_name_text
		scene_name_font_size = p_scene_name_font_size

		if show_scene_name and scene_name_text.is_empty():
			var eff_path := target_scene_path
			if eff_path.is_empty() and target_scene != null:
				eff_path = target_scene.resource_path
			scene_name_text = SceneTransitionArea.resolve_scene_name(eff_path, "", true)

		layer = 128 # Capa alta por encima de todo HUD, cámara o interfaz
		process_mode = Node.PROCESS_MODE_ALWAYS

		color_rect = ColorRect.new()
		color_rect.color = fade_color
		color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.modulate.a = 0.0
		add_child(color_rect)

		_build_loading_ui()


	func _build_loading_ui() -> void:
		if not show_loading_asset and not show_scene_name and custom_loading_scene == null:
			return

		if custom_loading_scene != null:
			var custom_node := custom_loading_scene.instantiate() as Control
			if custom_node != null:
				loading_container = custom_node
				loading_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
				loading_container.modulate.a = 0.0
				add_child(loading_container)
			return

		loading_container = Control.new()
		loading_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		loading_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		loading_container.modulate.a = 0.0
		add_child(loading_container)

		# 1. Título centrado mostrando el nombre de la escena que se está cargando
		if show_scene_name and not scene_name_text.is_empty():
			var center_container := CenterContainer.new()
			center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
			center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			loading_container.add_child(center_container)

			var title_label := Label.new()
			title_label.text = scene_name_text
			title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			var font_path := "res://assets/ui/Cinzel-Bold.ttf"
			if ResourceLoader.exists(font_path):
				var font := load(font_path) as Font
				if font != null:
					title_label.add_theme_font_override("font", font)
			title_label.add_theme_font_size_override("font_size", scene_name_font_size)
			title_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 0.96))
			title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			title_label.add_theme_constant_override("shadow_offset_x", 1)
			title_label.add_theme_constant_override("shadow_offset_y", 1)
			center_container.add_child(title_label)

		# 2. Indicador inferior derecho (icono del libro y texto secundario)
		if show_loading_asset:
			var margin := MarginContainer.new()
			margin.set_anchors_preset(Control.PRESET_FULL_RECT)
			margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			margin.add_theme_constant_override("margin_right", 24)
			margin.add_theme_constant_override("margin_bottom", 20)
			loading_container.add_child(margin)

			var hbox := HBoxContainer.new()
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.alignment = BoxContainer.ALIGNMENT_END
			hbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
			hbox.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
			hbox.add_theme_constant_override("separation", 12)
			margin.add_child(hbox)

			if not loading_text.is_empty():
				var label := Label.new()
				label.text = loading_text
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				var font_path := "res://assets/ui/Cinzel-Bold.ttf"
				if ResourceLoader.exists(font_path):
					var font := load(font_path) as Font
					if font != null:
						label.add_theme_font_override("font", font)
				label.add_theme_font_size_override("font_size", loading_font_size)
				label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.72, 0.95))
				hbox.add_child(label)

			var icon_tex := loading_texture
			if icon_tex == null:
				var default_paths: Array[String] = [
					"res://assets/world/grimorio_completo.png",
					"res://assets/world/fragmento_libro.png",
					"res://assets/ui/logo.png"
				]
				for p in default_paths:
					if ResourceLoader.exists(p):
						icon_tex = load(p) as Texture2D
						if icon_tex != null:
							break

			if icon_tex != null:
				var icon := TextureRect.new()
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.custom_minimum_size = Vector2(loading_icon_size, loading_icon_size)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.pivot_offset = Vector2(loading_icon_size * 0.5, loading_icon_size * 0.5)
				icon.texture = icon_tex
				hbox.add_child(icon)

				if loading_anim_mode != SceneTransitionArea.LoadingAnimationMode.NONE:
					loading_tween = icon.create_tween()
					loading_tween.set_loops()
					loading_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
					loading_tween.set_trans(Tween.TRANS_SINE)
					loading_tween.set_ease(Tween.EASE_IN_OUT)

					var max_scale := Vector2(loading_anim_scale, loading_anim_scale)
					var min_scale := Vector2(maxf(0.8, 2.0 - loading_anim_scale), maxf(0.8, 2.0 - loading_anim_scale))

					match loading_anim_mode:
						SceneTransitionArea.LoadingAnimationMode.PULSE:
							loading_tween.tween_property(icon, "scale", max_scale, 0.6)
							loading_tween.parallel().tween_property(icon, "modulate:a", 0.7, 0.6)
							loading_tween.tween_property(icon, "scale", min_scale, 0.6)
							loading_tween.parallel().tween_property(icon, "modulate:a", 1.0, 0.6)
						SceneTransitionArea.LoadingAnimationMode.SPIN:
							loading_tween.set_trans(Tween.TRANS_LINEAR)
							loading_tween.tween_property(icon, "rotation", TAU, 1.2).as_relative()
						SceneTransitionArea.LoadingAnimationMode.PULSE_AND_SPIN:
							loading_tween.tween_property(icon, "scale", max_scale, 0.6)
							loading_tween.tween_property(icon, "scale", min_scale, 0.6)
							var spin_tween := icon.create_tween()
							spin_tween.set_loops()
							spin_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
							spin_tween.set_trans(Tween.TRANS_LINEAR)
							spin_tween.tween_property(icon, "rotation", TAU, 1.2).as_relative()


	func _place_player(player: Node2D, at: Vector2) -> void:
		player.global_position = at
		if player is CharacterBody2D:
			player.velocity = Vector2.ZERO
		if player.has_method(&"reset_physics_interpolation"):
			player.reset_physics_interpolation()


	func run_transition() -> void:
		var tree := get_tree()
		if tree == null:
			queue_free()
			return

		SceneTransitionArea.is_transition_in_progress = true

		# 1. Fade out de la escena actual hacia negro
		var tween_out := create_tween()
		tween_out.set_trans(Tween.TRANS_SINE)
		tween_out.set_ease(Tween.EASE_IN_OUT)
		tween_out.tween_property(color_rect, "modulate:a", 1.0, duration)
		if loading_container != null:
			tween_out.parallel().tween_property(loading_container, "modulate:a", 1.0, duration * 0.6).set_delay(duration * 0.4)
		await tween_out.finished

		var load_start_time := Time.get_ticks_msec()

		# 2. Cambio a la escena destino en pleno negro
		var old_scene := tree.current_scene
		Player.save_player_for_transition(tree)

		if target_scene != null:
			tree.change_scene_to_packed(target_scene)
		elif not target_scene_path.is_empty():
			if ResourceLoader.has_cached(target_scene_path):
				var cached := ResourceLoader.load(target_scene_path) as PackedScene
				if cached != null:
					tree.change_scene_to_packed(cached)
				else:
					tree.change_scene_to_file(target_scene_path)
			else:
				var req_err := ResourceLoader.load_threaded_request(target_scene_path)
				if req_err == OK or req_err == ERR_ALREADY_IN_USE:
					while true:
						var status := ResourceLoader.load_threaded_get_status(target_scene_path)
						if status == ResourceLoader.THREAD_LOAD_LOADED:
							var packed := ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
							if packed != null:
								tree.change_scene_to_packed(packed)
							else:
								tree.change_scene_to_file(target_scene_path)
							break
						elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
							await tree.process_frame
						else:
							tree.change_scene_to_file(target_scene_path)
							break
				else:
					tree.change_scene_to_file(target_scene_path)
		else:
			push_error("ScreenFadeOverlay: Error al cambiar de escena, no se especificó un destino válido.")
			SceneTransitionArea.is_transition_in_progress = false
			queue_free()
			return

		# Esperar activamente a que tree.current_scene cambie al nuevo nivel
		while tree.current_scene == old_scene or tree.current_scene == null:
			await tree.process_frame

		# Esperar a que la nueva escena y sus nodos completen _ready()
		if not tree.current_scene.is_node_ready():
			await tree.current_scene.ready
		await tree.process_frame

		# Bloquear al nuevo jugador durante el fade in si corresponde
		var new_player := SceneTransitionArea._find_player(tree)
		if new_player != null and should_lock_player:
			SceneTransitionArea.apply_player_lock(new_player)

		# 2.5 Find the matching door of the target scene. With target_door NONE Luz keeps the
		# default position of the scene; a missing id is reported instead of failing silently.
		var door := SceneTransitionArea.find_door(tree, target_door)
		if target_door != DoorID.ID.NONE and door == null:
			push_warning("SceneTransitionArea: door '%s' not found in '%s'; Luz stays at the scene start." % [DoorID.get_id_name(target_door), tree.current_scene.scene_file_path])
		var arrival := {}
		if door != null and new_player != null:
			arrival = SceneTransitionArea.resolve_arrival(door, new_player.global_position)
			_place_player(new_player, arrival.position)

		# Wait two physics frames so the new scene's colliders exist before touching the floor
		await tree.physics_frame
		await tree.physics_frame

		if not arrival.is_empty() and new_player is CharacterBody2D:
			var settled := SceneTransitionArea.settle_position(new_player, arrival.position, arrival.slide)
			_place_player(new_player, settled)
			if arrival.facing != 0 and new_player.has_method(&"place_for_transition"):
				new_player.place_for_transition(settled, arrival.facing)
			if new_player.has_method(&"set_checkpoint"):
				new_player.set_checkpoint(settled)
			SceneTransitionArea._reset_cameras(new_player)
			await tree.physics_frame

		# Desarmar SOLAMENTE los triggers que realmente solapan con el jugador en su posición de aparición
		if new_player != null:
			var areas := tree.get_nodes_in_group(&"scene_transition_area")
			for area in areas:
				if area is SceneTransitionArea:
					area._spawn_overlapping = area.overlaps_body(new_player)

		# Respetar tiempo mínimo en pantalla de carga si no es un test automatizado muy rápido
		var effective_min_time := min_loading_time if duration > 0.15 else 0.0
		var elapsed_sec := float(Time.get_ticks_msec() - load_start_time) / 1000.0
		if effective_min_time > elapsed_sec:
			await tree.create_timer(effective_min_time - elapsed_sec).timeout

		# 3. Fade in hacia la nueva escena descubriendo desde negro
		var tween_in := create_tween()
		tween_in.set_trans(Tween.TRANS_SINE)
		tween_in.set_ease(Tween.EASE_IN_OUT)
		tween_in.tween_property(color_rect, "modulate:a", 0.0, duration)
		if loading_container != null:
			tween_in.parallel().tween_property(loading_container, "modulate:a", 0.0, minf(duration * 0.5, 0.2))
		await tween_in.finished

		if loading_tween != null and loading_tween.is_valid():
			loading_tween.kill()

		# Finalizar transición y desbloquear al jugador
		SceneTransitionArea.is_transition_in_progress = false
		if new_player != null and should_lock_player:
			SceneTransitionArea.unlock_player(new_player)

		# Re-verificar que las puertas donde el jugador NO esté dentro queden 100% armadas y listas
		var all_areas := tree.get_nodes_in_group(&"scene_transition_area")
		for area in all_areas:
			if area is SceneTransitionArea:
				area._triggered = false
				if new_player != null and not area.overlaps_body(new_player):
					area._spawn_overlapping = false

		# 4. Limpieza del overlay (no deja nada en memoria)
		queue_free()

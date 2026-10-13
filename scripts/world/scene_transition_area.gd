class_name SceneTransitionArea
extends Area2D

## Área de impacto (hitbox / trigger) para cambiar de escena con fundido a negro (fade in/out).
## Diseñado para activarse cuando el jugador entra al área, realizando una transición
## a pantalla completa totalmente por código (500 ms de fade out a negro, cambio de escena,
## y 500 ms de fade in hacia la nueva escena).
##
## Soporta puntos de aparición (SpawnPoint) colocados libremente en cada escena:
## - 'target_door_id': ID del SpawnPoint al que debe llegar el jugador en la escena destino.
##   Si se deja en NONE (o no existe SpawnPoint con ese ID en la escena destino),
##   el jugador aparecerá en la posición por defecto configurada en esa escena en Godot.
## - 'door_id': ID propio de esta puerta por si se desea usar como destino directo.

signal transition_started(target_name: String)
signal screen_faded_out
signal screen_faded_in

@export_group("Target Scene")
## Ruta de la escena destino (.tscn) a cargar.
@export_file("*.tscn") var target_scene_path: String = ""
## Alternativamente, puedes asignar directamente una PackedScene en este campo.
@export var target_scene: PackedScene

@export_group("Spawn Target")
## Identificador de la puerta o SpawnPoint al que se debe llegar en la escena destino.
## Si se deja en NONE, se utilizará la posición por defecto del Player en la escena destino.
@export var target_door_id: DoorID.ID = DoorID.ID.NONE
## Identificador propio de esta puerta en la escena actual (opcional).
@export var door_id: DoorID.ID = DoorID.ID.NONE

@export_group("Transition Settings")
## Duración del fade out a negro y del fade in a la nueva escena (en segundos). 0.5s = 500ms.
@export_range(0.05, 5.0, 0.05) var fade_duration: float = 0.5
## Color del fundido (por defecto negro pleno).
@export var fade_color: Color = Color.BLACK
## Bloquear la velocidad y física del jugador durante la transición para evitar caídas o movimientos en negro.
@export var lock_player: bool = true
## Capa física del jugador (Capa 1 por defecto en el proyecto).
@export_flags_2d_physics var player_collision_mask: int = 1

## Bandera temporal para evitar re-triggers mientras la pantalla está en transición.
static var is_transition_in_progress: bool = false

var _triggered: bool = false
var _spawn_overlapping: bool = false


func _ready() -> void:
	add_to_group(&"scene_transition_area")
	collision_layer = 0
	collision_mask = player_collision_mask
	monitoring = true
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
	if _triggered:
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

	start_transition(get_tree(), target_scene, target_scene_path, fade_duration, fade_color, target_door_id, lock_player)


func _is_player(body: Node2D) -> bool:
	if body is Player:
		return true
	if body.is_in_group(&"player"):
		return true
	return false


## Inicia la transición con pantalla a negro desde cualquier lugar por código.
static func start_transition(
	tree: SceneTree,
	scene_resource: PackedScene,
	scene_path: String,
	duration: float = 0.5,
	color: Color = Color.BLACK,
	target_door: DoorID.ID = DoorID.ID.NONE,
	lock_p: bool = true
) -> void:
	var overlay := ScreenFadeOverlay.new(color, duration, scene_resource, scene_path, target_door, lock_p)
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


## Busca la posición de spawn según el target_id en la nueva escena:
## 1. Prioriza nodos SpawnPoint colocados en la escena.
## 2. Si no hay SpawnPoint, busca una SceneTransitionArea con ese ID.
## 3. Si no existe ninguno o target_id es NONE, retorna null (usa posición por defecto de la escena).
static func _find_spawn_position(tree: SceneTree, target_id: DoorID.ID) -> Variant:
	if target_id == DoorID.ID.NONE or tree == null:
		return null

	# 1. Buscar entre los nodos del grupo 'spawn_points'
	var spawn_nodes := tree.get_nodes_in_group(&"spawn_points")
	for node in spawn_nodes:
		if node is SpawnPoint and node.spawn_id == target_id:
			return node.global_position
		elif node is Marker2D and node.get("spawn_id") == target_id:
			return node.global_position

	# Búsqueda recursiva en la escena por si el grupo no sincronizó
	if tree.current_scene != null:
		var markers := tree.current_scene.find_children("*", "Marker2D", true, false)
		for marker in markers:
			if marker is SpawnPoint and marker.spawn_id == target_id:
				return marker.global_position
			elif marker.get("spawn_id") == target_id:
				return marker.global_position

	# 2. Alternativa: buscar SceneTransitionArea con ese door_id
	var areas := tree.get_nodes_in_group(&"scene_transition_area")
	for area in areas:
		if area is SceneTransitionArea and area.door_id == target_id:
			return area.global_position

	if tree.current_scene != null:
		var areas_rec := tree.current_scene.find_children("*", "Area2D", true, false)
		for area in areas_rec:
			if area is SceneTransitionArea and area.door_id == target_id:
				return area.global_position

	return null


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
	var color_rect: ColorRect

	func _init(
		p_color: Color,
		p_duration: float,
		p_target_scene: PackedScene,
		p_target_scene_path: String,
		p_target_door: DoorID.ID = DoorID.ID.NONE,
		p_should_lock_player: bool = true
	) -> void:
		fade_color = p_color
		duration = p_duration
		target_scene = p_target_scene
		target_scene_path = p_target_scene_path
		target_door = p_target_door
		should_lock_player = p_should_lock_player

		layer = 128 # Capa alta por encima de todo HUD, cámara o interfaz
		process_mode = Node.PROCESS_MODE_ALWAYS

		color_rect = ColorRect.new()
		color_rect.color = fade_color
		color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		color_rect.modulate.a = 0.0
		add_child(color_rect)


	func run_transition() -> void:
		var tree := get_tree()
		if tree == null:
			queue_free()
			return

		SceneTransitionArea.is_transition_in_progress = true

		# 1. Fade out de la escena actual hacia negro (500 ms)
		var tween_out := create_tween()
		tween_out.set_trans(Tween.TRANS_SINE)
		tween_out.set_ease(Tween.EASE_IN_OUT)
		tween_out.tween_property(color_rect, "modulate:a", 1.0, duration)
		await tween_out.finished

		# 2. Cambio a la escena destino en pleno negro
		var old_scene := tree.current_scene

		if target_scene != null:
			tree.change_scene_to_packed(target_scene)
		elif not target_scene_path.is_empty():
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

		# 2.5 Buscar punto de aparición (SpawnPoint / puerta destino)
		# Si target_door es NONE o no existe punto con ese ID, el jugador
		# conserva la posición por defecto con la que se configuró la escena en Godot.
		var spawn_pos: Variant = SceneTransitionArea._find_spawn_position(tree, target_door)
		if spawn_pos != null and new_player != null:
			new_player.global_position = spawn_pos
			if new_player is CharacterBody2D:
				new_player.velocity = Vector2.ZERO
			if new_player.has_method(&"reset_physics_interpolation"):
				new_player.reset_physics_interpolation()
			if new_player.has_method(&"set_checkpoint"):
				new_player.set_checkpoint(spawn_pos)
			SceneTransitionArea._reset_cameras(new_player)

		# Esperar dos frames de física para sincronizar colisiones en negro antes de abrir la vista
		await tree.physics_frame
		await tree.physics_frame

		# Desarmar SOLAMENTE los triggers que realmente solapan con el jugador en su posición de aparición
		if new_player != null:
			var areas := tree.get_nodes_in_group(&"scene_transition_area")
			for area in areas:
				if area is SceneTransitionArea:
					area._spawn_overlapping = area.overlaps_body(new_player)

		# 3. Fade in hacia la nueva escena descubriendo desde negro (500 ms)
		var tween_in := create_tween()
		tween_in.set_trans(Tween.TRANS_SINE)
		tween_in.set_ease(Tween.EASE_IN_OUT)
		tween_in.tween_property(color_rect, "modulate:a", 0.0, duration)
		await tween_in.finished

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

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

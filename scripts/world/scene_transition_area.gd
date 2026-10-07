class_name SceneTransitionArea
extends Area2D

## Área de impacto (hitbox / trigger) para cambiar de escena con fundido a negro (fade in/out).
## Diseñado para activarse cuando el jugador entra al área, realizando una transición
## a pantalla completa totalmente por código (500 ms de fade out a negro, cambio de escena,
## y 500 ms de fade in hacia la nueva escena).

signal transition_started(target_name: String)
signal screen_faded_out
signal screen_faded_in

@export_group("Target Scene")
## Ruta de la escena destino (.tscn) a cargar.
@export_file("*.tscn") var target_scene_path: String = ""
## Alternativamente, puedes asignar directamente una PackedScene en este campo.
@export var target_scene: PackedScene

@export_group("Transition Settings")
## Duración del fade out a negro y del fade in a la nueva escena (en segundos). 0.5s = 500ms.
@export_range(0.05, 5.0, 0.05) var fade_duration: float = 0.5
## Color del fundido (por defecto negro pleno).
@export var fade_color: Color = Color.BLACK
## Bloquear la velocidad y física del jugador durante la transición para evitar caídas o movimientos en negro.
@export var lock_player: bool = true
## Capa física del jugador (Capa 1 por defecto en el proyecto).
@export_flags_2d_physics var player_collision_mask: int = 1

var _triggered: bool = false


func _ready() -> void:
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


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not _is_player(body):
		return

	if target_scene == null and target_scene_path.is_empty():
		push_warning("SceneTransitionArea: No se definió una escena destino en '%s'." % name)
		return

	_triggered = true
	var destination_name := target_scene.resource_path if target_scene != null else target_scene_path
	transition_started.emit(destination_name)

	if lock_player:
		_apply_player_lock(body)

	start_transition(get_tree(), target_scene, target_scene_path, fade_duration, fade_color)


func _is_player(body: Node2D) -> bool:
	if body is Player:
		return true
	if body.is_in_group(&"player"):
		return true
	return false


func _apply_player_lock(player: Node2D) -> void:
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)


## Inicia la transición con pantalla a negro desde cualquier lugar por código.
static func start_transition(
	tree: SceneTree,
	scene_resource: PackedScene,
	scene_path: String,
	duration: float = 0.5,
	color: Color = Color.BLACK
) -> void:
	var overlay := ScreenFadeOverlay.new(color, duration, scene_resource, scene_path)
	tree.root.add_child(overlay)
	overlay.run_transition()


## Clase interna que crea dinámicamente un CanvasLayer en /root/ para persistir
## durante la descarga y carga de escenas sin cortarse ni perder referencias.
class ScreenFadeOverlay extends CanvasLayer:
	var fade_color: Color
	var duration: float
	var target_scene: PackedScene
	var target_scene_path: String
	var color_rect: ColorRect

	func _init(
		p_color: Color,
		p_duration: float,
		p_target_scene: PackedScene,
		p_target_scene_path: String
	) -> void:
		fade_color = p_color
		duration = p_duration
		target_scene = p_target_scene
		target_scene_path = p_target_scene_path

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

		# 1. Fade out de la escena actual hacia negro (500 ms)
		var tween_out := create_tween()
		tween_out.set_trans(Tween.TRANS_SINE)
		tween_out.set_ease(Tween.EASE_IN_OUT)
		tween_out.tween_property(color_rect, "modulate:a", 1.0, duration)
		await tween_out.finished

		# 2. Cambio a la escena destino en pleno negro
		if target_scene != null:
			tree.change_scene_to_packed(target_scene)
		elif not target_scene_path.is_empty():
			tree.change_scene_to_file(target_scene_path)
		else:
			push_error("ScreenFadeOverlay: Error al cambiar de escena, no se especificó un destino válido.")
			queue_free()
			return

		# Esperar un frame a que la nueva escena se monte e inicialice en el árbol
		await tree.process_frame

		# 3. Fade in hacia la nueva escena descubriendo desde negro (500 ms)
		var tween_in := create_tween()
		tween_in.set_trans(Tween.TRANS_SINE)
		tween_in.set_ease(Tween.EASE_IN_OUT)
		tween_in.tween_property(color_rect, "modulate:a", 0.0, duration)
		await tween_in.finished

		# 4. Limpieza del overlay
		queue_free()

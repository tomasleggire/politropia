@tool
class_name ElectricCloud
extends ContactDamage
## Nube eléctrica: una plataforma sobre la que se puede parar, pero que
## descarga. Ciclo: Luz se para encima -> aviso (chispas parpadeando) ->
## DESCARGA (rayo + daño) -> la nube se recarga y es segura unos segundos.

enum Behavior { KNOCKBACK, RETURN_TO_SAFE_GROUND }
enum Phase { IDLE, WARNING, ZAPPING, RECHARGE }

const POGO_GROUP_NAME := &"pogoable"
const PLATFORM_LAYER := 2
const PLATFORM_THICKNESS := 8.0
const STAND_TOLERANCE := 4.0
const FRAME_COUNT := 3
const FRAME_CALM := 0
const FRAME_BOLT := 1
const FRAME_SPARKS := 2
const BLINK_INTERVAL := 0.08
const DEFAULT_FRAME_SIZE := Vector2(96.0, 54.0)

@export_range(0.0, 64.0, 0.5) var surface_offset_y: float = 14.0:
	set(value):
		surface_offset_y = value
		_refresh()

@export_range(0.2, 1.0, 0.01) var walkable_width_ratio: float = 0.7:
	set(value):
		walkable_width_ratio = value
		_refresh()

@export_group("Descarga")
@export var behavior: Behavior = Behavior.KNOCKBACK
@export var warning_time: float = 1.0 ## Aumentado a 1 segundo para disfrutar el hundimiento
@export var zap_flash_time: float = 0.25
@export var recharge_time: float = 2.0

@export_group("Arena Movediza")
## Cuántos píxeles se hunde la plataforma (y el jugador) visualmente.
@export var sink_depth: float = 24.0
## Qué tan rápido se hunde el jugador al pisarla (px/s).
@export var sink_speed: float = 30.0
## Velocidad máxima del jugador mientras está hundido en la nube.
@export var trapped_speed: float = 60.0
@export_group("Dimensiones")
## Tamaño manual del hitbox (ignora el espacio transparente de la imagen gigante)
@export var cloud_size := Vector2(55.0, 40.0):
	set(value):
		cloud_size = value
		_refresh()

var _sprite: Sprite2D
var _shape: CollisionShape2D
var _platform: StaticBody2D
var _platform_shape: CollisionShape2D

var _phase := Phase.IDLE
var _phase_time := 0.0
var _idle_left := 2.0
var _flash_left := 0.0

var _current_sink := 0.0
var _player_in_cloud: Player = null
var _player_original_speed := 250.0

func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _sprite != null and not _sprite.texture_changed.is_connected(_refresh):
		_sprite.texture_changed.connect(_refresh)
	if not Engine.is_editor_hint():
		_build_platform()
	_refresh()
	if Engine.is_editor_hint():
		return
	_idle_left = randf_range(1.0, 3.0)
	kind = Kind.HAZARD
	super._ready()
	remove_from_group(POGO_GROUP_NAME)
	collision_layer = 0
	monitoring = false

func _validate_property(property: Dictionary) -> void:
	if property.name == "kind":
		property.usage = PROPERTY_USAGE_NO_EDITOR

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		warnings.append("Agregá un hijo Sprite2D llamado \"Sprite2D\" con la tira de 3 frames.")
	if get_node_or_null("CollisionShape2D") == null:
		warnings.append("Agregá un hijo CollisionShape2D llamado \"CollisionShape2D\".")
	return warnings

func _try_hurt(_body: Node2D) -> void:
	pass

func get_world_rect() -> Rect2:
	var size := _frame_size()
	return Rect2(global_position - size * 0.5, size)

func _frame_size() -> Vector2:
	return cloud_size

func _surface_local_y() -> float:
	return -_frame_size().y * 0.5 + surface_offset_y

func _walkable_width() -> float:
	return _frame_size().x * walkable_width_ratio

func _build_platform() -> void:
	_platform = StaticBody2D.new()
	_platform.name = "Platform"
	_platform.collision_layer = PLATFORM_LAYER
	_platform.collision_mask = 0
	_platform_shape = CollisionShape2D.new()
	_platform_shape.one_way_collision = true
	_platform.add_child(_platform_shape)
	add_child(_platform)

func _refresh() -> void:
	if not is_node_ready() or _sprite == null:
		return
	_sprite.centered = true
	_sprite.position = Vector2.ZERO
	_sprite.hframes = FRAME_COUNT
	if Engine.is_editor_hint():
		_sprite.frame = FRAME_CALM
	if _shape != null:
		var area := RectangleShape2D.new()
		area.size = _frame_size()
		_shape.position = Vector2.ZERO
		_shape.shape = area
	if _platform_shape != null:
		var floor_rect := RectangleShape2D.new()
		floor_rect.size = Vector2(_walkable_width(), PLATFORM_THICKNESS)
		_platform_shape.shape = floor_rect
		_platform_shape.position = Vector2(0.0, _surface_local_y() + PLATFORM_THICKNESS * 0.5)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _platform == null:
		return
		
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var standing := false
	
	if player != null:
		standing = _is_standing_on_cloud(player)
		
		# --- SOLUCIÓN AL ATASCO DEBAJO DE LA NUBE ---
		if _phase == Phase.IDLE or _phase == Phase.WARNING:
			var expected_surface := global_position.y + _surface_local_y() + _current_sink
			# Si los pies del jugador están por encima o justo en la nube, la plataforma es sólida.
			# Si el jugador está caminando por debajo, la plataforma no existe y no estorba.
			if player.global_position.y < expected_surface + 15.0:
				_platform.collision_layer = PLATFORM_LAYER
			else:
				_platform.collision_layer = 0
		else:
			# En ZAPPING o RECHARGE abrimos el piso para que caiga.
			_platform.collision_layer = 0
	
	# === LÓGICA DE ARENA MOVEDIZA ===
	if standing and _phase == Phase.WARNING:
		_current_sink = move_toward(_current_sink, sink_depth, sink_speed * delta)
		
		if _player_in_cloud != player:
			_player_in_cloud = player
			_player_original_speed = player.run_max_speed
		player.run_max_speed = trapped_speed
	else:
		_current_sink = move_toward(_current_sink, 0.0, sink_speed * delta * 2.0)
		
		if is_instance_valid(_player_in_cloud):
			_player_in_cloud.run_max_speed = _player_original_speed
			_player_in_cloud = null

	_platform_shape.position.y = _surface_local_y() + PLATFORM_THICKNESS * 0.5 + _current_sink
	# =================================

	_phase_time += delta
	match _phase:
		Phase.IDLE:
			_update_idle(delta)
			if standing:
				_enter_phase(Phase.WARNING)
		Phase.WARNING:
			if not standing:
				_enter_phase(Phase.IDLE)
			else:
				var blink := int(_phase_time / BLINK_INTERVAL) % 2
				_set_frame(FRAME_SPARKS if blink == 0 else FRAME_CALM)
				if _phase_time >= warning_time:
					_zap(player)
		Phase.ZAPPING:
			if _phase_time >= zap_flash_time:
				_enter_phase(Phase.RECHARGE)
		Phase.RECHARGE:
			_set_frame(FRAME_CALM)
			if _phase_time >= recharge_time:
				_enter_phase(Phase.IDLE)

func _is_standing_on_cloud(player: Player) -> bool:
	if not player.is_on_floor() or player.is_input_locked():
		return false
	
	# Sumamos 16 píxeles extra de tolerancia para atrapar al jugador 
	# incluso si está apoyado haciendo equilibrio en el borde.
	var edge_tolerance := 16.0 
	if absf(player.global_position.x - global_position.x) > (_walkable_width() * 0.5) + edge_tolerance:
		return false
	
	var surface_y := global_position.y + _surface_local_y() + _current_sink
	return absf(player.global_position.y - surface_y) <= STAND_TOLERANCE

func _zap(player: Player) -> void:
	_enter_phase(Phase.ZAPPING)
	_set_frame(FRAME_BOLT)
	
	# Desactivamos el piso para que no frene la caída
	_platform.collision_layer = 0
	
	if behavior == Behavior.RETURN_TO_SAFE_GROUND:
		player.take_hazard_damage(damage, global_position)
	else:
		player.take_damage(damage, global_position)
		
	# --- SOLUCIÓN AL EMPUJE ---
	# Interceptamos la velocidad generada por player.gd y lo forzamos a caer verticalmente
	player.velocity = Vector2(0.0, 450.0)

func _update_idle(delta: float) -> void:
	_idle_left -= delta
	if _idle_left <= 0.0:
		_idle_left = randf_range(1.5, 3.5)
		_flash_left = 0.12
	_flash_left = maxf(_flash_left - delta, 0.0)
	_set_frame(FRAME_SPARKS if _flash_left > 0.0 else FRAME_CALM)

func _enter_phase(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_time = 0.0

func _set_frame(index: int) -> void:
	if _sprite != null and _sprite.frame != index:
		_sprite.frame = index

func _exit_tree() -> void:
	if is_instance_valid(_player_in_cloud):
		_player_in_cloud.run_max_speed = _player_original_speed

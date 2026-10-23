class_name LancetEnemy
extends Enemy

## Enemigo Lancero (Lancet Enemy).
## Guerrero tipo espartano armado con un lápiz/lanza gigante y escudo.
## Patrulla plataformas, detecta al jugador y ejecuta una embestida frontal con su lanza.
## Hereda de Enemy para integrarse en el sistema de combate, persistencia,
## hit-stop y exclusión de colisiones con el Player (igual que ShadowOwl y SnakeEnemy).

enum State {
	PATROL,    ## Patrullaje regular de izquierda a derecha.
	ATTACK,    ## Embestida rápida con la lanza activa.
	COOLDOWN,  ## Pausa de recuperación tras el ataque antes de volver a patrullar.
	DEAD       ## Estado tras ser derrotado.
}

const GROUP_PLAYER: StringName = &"player"

@export_group("Movimiento y Patrullaje")
## Velocidad de caminata estándar durante el patrullaje.
@export var walk_speed: float = 60.0
## Cooldown mínimo (en segundos) tras chocar con paredes o bordes antes de permitir otro giro.
@export var turn_cooldown_duration: float = 0.25

@export_group("Ataque y Detección")
## Velocidad horizontal durante la estocada / embestida.
@export var attack_speed: float = 180.0
## Distancia fija a recorrer en el ataque. Si es 0.0, se calcula automáticamente
## como (ancho del cuerpo * attack_distance_multiplier).
@export var attack_distance: float = 0.0
## Multiplicador respecto al ancho del cuerpo cuando attack_distance es 0.0.
@export var attack_distance_multiplier: float = 2.0
## Tiempo de recuperación tras atacar (en segundos) antes de reanudar el patrullaje.
@export var cooldown_duration: float = 1.5
## Daño infligido al jugador al ser alcanzado por la lanza/hitbox.
@export var attack_damage: int = 1

@export_group("Efectos de Lanza")
## Posición relativa de la punta del lápiz cuando mira a la derecha.
@export var pencil_tip_offset: Vector2 = Vector2(76.0, -35.0)

# Referencias a nodos hijos esperados en la escena
@onready var sprite: AnimatedSprite2D = (get_node_or_null("AnimatedSprite2D") if get_node_or_null("AnimatedSprite2D") != null else get_node_or_null("Visual/AnimatedSprite2D")) as AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D
@onready var hitbox_area: Area2D = get_node_or_null("HitboxArea") as Area2D
@onready var ledge_ray: RayCast2D = get_node_or_null("LedgeRayCast") as RayCast2D
@onready var death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D
@onready var pencil_tip_node: Node2D = get_node_or_null("PencilTip") as Node2D
@onready var pencil_gleam: Node2D = get_node_or_null("PencilTip/Gleam") as Node2D
@onready var pencil_particles: CPUParticles2D = get_node_or_null("PencilTip/Sparks") as CPUParticles2D
@onready var _sfx_chase: AudioStreamPlayer = $SfxChase

var _gleam_tween: Tween

# Variables internas de control
var current_state: State = State.PATROL
var cooldown_timer: float = 0.0
var turn_cooldown: float = 0.0

# Aliases de compatibilidad con Enemy (_facing y _health)
var facing_direction: int:
	get:
		return _facing
	set(val):
		_facing = val

var current_health: int:
	get:
		return _health
	set(val):
		_health = val

# Seguimiento del ataque
var attack_start_x: float = 0.0
var target_attack_distance: float = 0.0
var body_width: float = 32.0


func _init() -> void:
	max_health = 4
	gravity = 980.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	
	_calculate_body_width()
	_setup_ledge_ray()
	_setup_areas()
	_setup_pencil_fx()
	_update_facing_direction()
	_play_animation(&"walk")


## Gancho para cuando Enemy encuentra al Player: agrega excepción a ledge_ray
func _on_player_found(player: Node) -> void:
	super._on_player_found(player)
	if ledge_ray != null and player is CollisionObject2D:
		ledge_ray.add_exception(player as CollisionObject2D)


## El bucle de física de Enemy llama a _think() para que el arquetipo decida su velocidad horizontal.
func _think(delta: float) -> void:
	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.ATTACK:
			_process_attack(delta)
		State.COOLDOWN:
			_process_cooldown(delta)


# ==============================================================================
# COMPORTAMIENTOS POR ESTADO
# ==============================================================================

## Movimiento de patrullaje estándar. Cambia de rumbo en paredes y precipicios.
func _process_patrol(delta: float) -> void:
	if turn_cooldown > 0.0:
		turn_cooldown -= delta

	velocity.x = float(_facing) * walk_speed
	_play_animation(&"walk")

	# Si está en el suelo y no está en cooldown de giro, verifica obstáculos
	if is_on_floor() and turn_cooldown <= 0.0:
		var reached_wall: bool = false
		if is_on_wall():
			# Solo cuenta si la pared está frente a la dirección de marcha (normal opuesta a facing)
			var wall_norm: Vector2 = get_wall_normal()
			if wall_norm.x * float(_facing) < -0.1:
				reached_wall = true

		var reached_ledge: bool = false
		if ledge_ray != null:
			ledge_ray.force_raycast_update()
			if not ledge_ray.is_colliding():
				reached_ledge = true

		if reached_wall or reached_ledge:
			_flip_direction()


## Ejecución de la estocada frontal hacia adelante.
func _process_attack(_delta: float) -> void:
	velocity.x = float(_facing) * attack_speed
	_play_animation(&"attack")

	var traveled_distance: float = absf(global_position.x - attack_start_x)
	var hit_wall: bool = is_on_wall() and (get_wall_normal().x * float(_facing) < -0.1)

	# Termina el ataque si recorrió la distancia objetivo o chocó de frente contra una pared
	if traveled_distance >= target_attack_distance or hit_wall:
		_end_attack()


## Estado de descanso/recuperación tras haber atacado.
func _process_cooldown(delta: float) -> void:
	velocity.x = 0.0
	_play_animation(&"idle")

	cooldown_timer -= delta
	if cooldown_timer <= 0.0:
		current_state = State.PATROL


# ==============================================================================
# GESTIÓN DEL ATAQUE Y DETECCIÓN
# ==============================================================================

## Inicia la embestida si está en patrullaje y detecta al jugador.
func _start_attack(target_body: Node2D) -> void:
	if current_state != State.PATROL:
		return

	# Orientarse hacia el jugador antes de arremeter
	var dir_to_player: float = signf(target_body.global_position.x - global_position.x)
	if dir_to_player != 0.0 and int(dir_to_player) != _facing:
		_facing = int(dir_to_player)
		_update_facing_direction()

	current_state = State.ATTACK
	attack_start_x = global_position.x
	
	# Determina la distancia del ataque (exportada o basada en 2x ancho del cuerpo)
	if attack_distance > 0.0:
		target_attack_distance = attack_distance
	else:
		target_attack_distance = body_width * attack_distance_multiplier

	# Activa la hitbox dañina de la lanza
	_set_hitbox_active(true)
	_play_animation(&"attack")
	_trigger_pencil_gleam()


## Finaliza el ataque e ingresa en fase de recuperación.
func _end_attack() -> void:
	_set_hitbox_active(false)
	current_state = State.COOLDOWN
	cooldown_timer = cooldown_duration
	velocity.x = 0.0
	_play_animation(&"idle")


# ==============================================================================
# CONFIGURACIÓN Y ORIENTACIÓN
# ==============================================================================

## Invierte el sentido horizontal del enemigo con cooldown anti-bucle.
func _flip_direction() -> void:
	if turn_cooldown > 0.0:
		return
	_facing = -_facing
	turn_cooldown = turn_cooldown_duration # Evita bucles rápidos y oscilaciones en colisiones
	_update_facing_direction()


## Actualiza la orientación del sprite, el raycast del suelo y las áreas.
func _update_facing_direction() -> void:
	var face_scale: float = float(_facing)

	# Voltea el sprite
	if sprite != null:
		sprite.flip_h = (_facing < 0)

	# Actualiza la posición del raycast de borde (adelantado en la dirección de marcha)
	# Comienza a Y = -4.0 (ligeramente sobre el suelo) para evitar imprecisiones numéricas
	if ledge_ray != null:
		ledge_ray.position = Vector2(float(_facing) * (body_width * 0.5 + 4.0), -4.0)
		ledge_ray.target_position = Vector2(0.0, 20.0)
		ledge_ray.force_raycast_update()

	# Voltea las áreas de detección y ataque según hacia dónde mira
	if detection_area != null:
		detection_area.scale.x = face_scale
	if hitbox_area != null:
		hitbox_area.scale.x = face_scale

	_update_pencil_tip_position()


## Obtiene el ancho del cuerpo a partir de CollisionShape2D
func _calculate_body_width() -> void:
	if collision_shape != null and collision_shape.shape != null:
		var s: Shape2D = collision_shape.shape
		if s is RectangleShape2D:
			body_width = (s as RectangleShape2D).size.x
		elif s is CircleShape2D:
			body_width = (s as CircleShape2D).radius * 2.0
		elif s is CapsuleShape2D:
			body_width = (s as CapsuleShape2D).radius * 2.0
	else:
		body_width = 32.0


## Crea o conecta el raycast para detectar bordes de plataformas si no existe en la escena.
func _setup_ledge_ray() -> void:
	if ledge_ray == null:
		ledge_ray = RayCast2D.new()
		ledge_ray.name = "LedgeRayCast"
		ledge_ray.enabled = true
		ledge_ray.collision_mask = 1 | 2 # Capas de sólidos y plataformas
		add_child(ledge_ray)
	else:
		ledge_ray.enabled = true

	ledge_ray.position = Vector2(float(_facing) * (body_width * 0.5 + 4.0), -4.0)
	ledge_ray.target_position = Vector2(0.0, 20.0)


## Conecta las señales de detección y daño de las áreas.
func _setup_areas() -> void:
	# Área de Detección del Jugador
	if detection_area != null:
		if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
			detection_area.body_entered.connect(_on_detection_area_body_entered)

	# Área de Ataque / Hitbox de la lanza
	if hitbox_area != null:
		if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox_area.body_entered.connect(_on_hitbox_body_entered)
		_set_hitbox_active(false)


func _set_hitbox_active(active: bool) -> void:
	if hitbox_area != null:
		hitbox_area.monitoring = active


## Señal: Un cuerpo entra al rango de visión/detección.
func _on_detection_area_body_entered(body: Node2D) -> void:
	if _is_player(body) and current_state == State.PATROL:
		_start_attack(body)


## Señal: Un cuerpo es golpeado por la hitbox durante la embestida.
func _on_hitbox_body_entered(body: Node2D) -> void:
	if current_state == State.ATTACK and _is_player(body):
		# Aplica daño utilizando la funcion estándar del Player si existe (diferido para no alterar áreas durante flush de físicas)
		if body.has_method(&"take_damage"):
			body.call_deferred(&"take_damage", attack_damage, global_position)
		elif body.has_method(&"receive_hit"):
			body.call_deferred(&"receive_hit", attack_damage, global_position)


func _is_player(body: Node2D) -> bool:
	return body.is_in_group(GROUP_PLAYER) or body.name.to_lower().contains("player")


func _play_animation(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name or not sprite.is_playing():
			sprite.play(anim_name)


# ==============================================================================
# INTEGRACIÓN DE DAÑO Y COMBATE (SOBRESCRITURAS DE ENEMY)
# ==============================================================================

## Sobrescribe el efecto de destello de Enemy para usar el AnimatedSprite2D del lancero.
func _set_flash_visible(visible_now: bool) -> void:
	if sprite != null:
		sprite.modulate = Color(3.0, 1.5, 1.5, 1.0) if visible_now else Color.WHITE


## Recibe impacto del jugador utilizando el flujo unificado de Enemy (señales hit/died, hit_stop, flash).
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if current_state == State.DEAD:
		return false
	var success := super.receive_hit(damage, source_position, attack_name)
	if _health <= 0:
		current_state = State.DEAD
	return success


## Sobrescribe make_corpse_at de Enemy para emitir las partículas y destruir el nodo con fade/delay.
func make_corpse_at(at: Vector2, _facing_dir: int) -> void:
	current_state = State.DEAD
	_dead = true
	global_position = at
	velocity = Vector2.ZERO
	_recoil_left = 0.0
	collision_layer = 0
	_set_hitbox_active(false)

	if _gleam_tween != null and _gleam_tween.is_valid():
		_gleam_tween.kill()
	if pencil_gleam != null:
		pencil_gleam.visible = false
	if pencil_particles != null:
		pencil_particles.emitting = false

	if death_particles != null:
		death_particles.restart()
		death_particles.emitting = true
		if sprite != null:
			sprite.visible = false
		set_physics_process(false)
		var timer := get_tree().create_timer(death_particles.lifetime)
		timer.timeout.connect(queue_free)
	else:
		queue_free()


## Reinicia el estado del lancero cuando el jugador reaparece en un checkpoint o desk.
func _reset_ai() -> void:
	super._reset_ai()
	current_state = State.PATROL
	cooldown_timer = 0.0
	turn_cooldown = 0.0
	_set_hitbox_active(false)
	if sprite != null:
		sprite.visible = true
	_update_facing_direction()
	_play_animation(&"walk")


# ==============================================================================
# EFECTOS DE LANZA / LÁPIZ (DESTELLO Y CHISPAS)
# ==============================================================================

## Inicializa o busca los nodos del destello y partículas en la punta del lápiz.
func _setup_pencil_fx() -> void:
	if pencil_tip_node == null:
		pencil_tip_node = get_node_or_null("PencilTip") as Node2D
	if pencil_tip_node == null:
		pencil_tip_node = Node2D.new()
		pencil_tip_node.name = "PencilTip"
		add_child(pencil_tip_node)

	if pencil_gleam == null:
		pencil_gleam = pencil_tip_node.get_node_or_null("Gleam") as Node2D
	if pencil_gleam == null:
		pencil_gleam = Node2D.new()
		pencil_gleam.name = "Gleam"
		pencil_gleam.visible = false
		pencil_tip_node.add_child(pencil_gleam)

		var outer := Polygon2D.new()
		outer.name = "OuterStar"
		outer.color = Color(1.0, 0.82, 0.2, 0.95)
		outer.polygon = PackedVector2Array([
			Vector2(0, -14), Vector2(3, -3), Vector2(14, 0), Vector2(3, 3),
			Vector2(0, 14), Vector2(-3, 3), Vector2(-14, 0), Vector2(-3, -3)
		])
		pencil_gleam.add_child(outer)

		var inner := Polygon2D.new()
		inner.name = "InnerDiamond"
		inner.color = Color(1.0, 0.95, 0.6, 1.0)
		inner.polygon = PackedVector2Array([
			Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)
		])
		pencil_gleam.add_child(inner)

		var core := Polygon2D.new()
		core.name = "Core"
		core.color = Color.WHITE
		core.polygon = PackedVector2Array([
			Vector2(0, -2.5), Vector2(2.5, 0), Vector2(0, 2.5), Vector2(-2.5, 0)
		])
		pencil_gleam.add_child(core)

	if pencil_particles == null:
		pencil_particles = pencil_tip_node.get_node_or_null("Sparks") as CPUParticles2D
	if pencil_particles == null:
		pencil_particles = CPUParticles2D.new()
		pencil_particles.name = "Sparks"
		pencil_particles.emitting = false
		pencil_particles.amount = 16
		pencil_particles.lifetime = 0.35
		pencil_particles.one_shot = true
		pencil_particles.explosiveness = 0.9
		pencil_particles.spread = 70.0
		pencil_particles.gravity = Vector2(0, 160)
		pencil_particles.initial_velocity_min = 60.0
		pencil_particles.initial_velocity_max = 140.0
		pencil_particles.scale_amount_min = 1.8
		pencil_particles.scale_amount_max = 3.5
		pencil_particles.color = Color(1.0, 0.85, 0.3, 1.0)
		pencil_tip_node.add_child(pencil_particles)

	_update_pencil_tip_position()


## Mantiene la posición del destello y partículas en la punta según la orientación.
func _update_pencil_tip_position() -> void:
	if pencil_tip_node != null:
		var offset := pencil_tip_offset if pencil_tip_offset != null else Vector2(76.0, -35.0)
		pencil_tip_node.position = Vector2(float(_facing) * offset.x, offset.y)
	if pencil_particles != null:
		pencil_particles.direction = Vector2(float(_facing), -0.2)


## Activa el destello estelar y la ráfaga de chispas en la punta del lápiz al iniciar el ataque.
func _trigger_pencil_gleam() -> void:
	_update_pencil_tip_position()

	# Ráfaga de chispas
	if pencil_particles != null:
		pencil_particles.direction = Vector2(float(_facing), -0.2)
		pencil_particles.restart()
		pencil_particles.emitting = true

	# Animación del destello estelar (pop, rotación y desvanecimiento)
	if pencil_gleam != null:
		pencil_gleam.visible = true
		pencil_gleam.scale = Vector2(0.2, 0.2)
		pencil_gleam.modulate.a = 1.0
		pencil_gleam.rotation = 0.0

		if _gleam_tween != null and _gleam_tween.is_valid():
			_gleam_tween.kill()
		_gleam_tween = create_tween()
		_gleam_tween.set_parallel(true)
		_gleam_tween.tween_property(pencil_gleam, "scale", Vector2(1.35, 1.35), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_gleam_tween.tween_property(pencil_gleam, "rotation", deg_to_rad(45.0 * float(_facing)), 0.25)
		_gleam_tween.tween_property(pencil_gleam, "scale", Vector2(0.1, 0.1), 0.14).set_delay(0.12).set_ease(Tween.EASE_IN)
		_gleam_tween.tween_property(pencil_gleam, "modulate:a", 0.0, 0.14).set_delay(0.12)
		_gleam_tween.chain().tween_callback(func() -> void:
			if is_instance_valid(pencil_gleam):
				pencil_gleam.visible = false
		)

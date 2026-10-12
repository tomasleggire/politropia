class_name LancetEnemy
extends CharacterBody2D

## Enemigo Lancero (Lancet Enemy).
## Guerrero tipo espartano armado con un lápiz/lanza gigante y escudo.
## Patrulla plataformas, detecta al jugador y ejecuta una embestida frontal con su lanza.

enum State {
	PATROL,    ## Patrullaje regular de izquierda a derecha.
	ATTACK,    ## Embestida rápida con la lanza activa.
	COOLDOWN,  ## Pausa de recuperación tras el ataque antes de volver a patrullar.
	DEAD       ## Estado tras ser derrotado.
}

# Constantes de compatibilidad con el sistema de combate del juego
const GROUP_ENEMIES: StringName = &"enemies"
const GROUP_PLAYER: StringName = &"player"

@export_group("Movimiento y Patrullaje")
## Velocidad de caminata estándar durante el patrullaje.
@export var walk_speed: float = 60.0
## Dirección inicial al aparecer (-1 = Izquierda, 1 = Derecha).
@export_enum("Izquierda:-1", "Derecha:1") var start_facing: int = -1
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

@export_group("Salud")
@export var max_health: int = 4

@export_group("Física")
## Fuerza de gravedad aplicada cuando está en el aire.
@export var custom_gravity: float = 980.0

# Referencias a nodos hijos esperados en la escena
@onready var sprite: AnimatedSprite2D = (get_node_or_null("AnimatedSprite2D") if get_node_or_null("AnimatedSprite2D") != null else get_node_or_null("Visual/AnimatedSprite2D")) as AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D
@onready var hitbox_area: Area2D = get_node_or_null("HitboxArea") as Area2D
@onready var ledge_ray: RayCast2D = get_node_or_null("LedgeRayCast") as RayCast2D
@onready var death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D

# Variables internas de control
var current_state: State = State.PATROL
var facing_direction: int = -1
var current_health: int = 4
var cooldown_timer: float = 0.0
var turn_cooldown: float = 0.0

# Seguimiento del ataque
var attack_start_x: float = 0.0
var target_attack_distance: float = 0.0
var body_width: float = 32.0


func _ready() -> void:
	add_to_group(GROUP_ENEMIES)
	current_health = max_health
	facing_direction = 1 if start_facing >= 0 else -1
	
	_calculate_body_width()
	_setup_ledge_ray()
	_setup_areas()
	_update_facing_direction()
	_play_animation(&"walk")


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_apply_gravity(delta)

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.ATTACK:
			_process_attack(delta)
		State.COOLDOWN:
			_process_cooldown(delta)

	move_and_slide()


# ==============================================================================
# COMPORTAMIENTOS POR ESTADO
# ==============================================================================

## Movimiento de patrullaje estándar. Cambia de rumbo en paredes y precipicios.
func _process_patrol(delta: float) -> void:
	if turn_cooldown > 0.0:
		turn_cooldown -= delta

	velocity.x = facing_direction * walk_speed
	_play_animation(&"walk")

	# Si está en el suelo y no está en cooldown de giro, verifica obstáculos
	if is_on_floor() and turn_cooldown <= 0.0:
		var reached_wall: bool = false
		if is_on_wall():
			# Solo cuenta si la pared está frente a la dirección de marcha (normal opuesta a facing)
			var wall_norm: Vector2 = get_wall_normal()
			if wall_norm.x * float(facing_direction) < -0.1:
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
	velocity.x = facing_direction * attack_speed
	_play_animation(&"attack")

	var traveled_distance: float = absf(global_position.x - attack_start_x)
	var hit_wall: bool = is_on_wall() and (get_wall_normal().x * float(facing_direction) < -0.1)

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
	if dir_to_player != 0.0 and int(dir_to_player) != facing_direction:
		facing_direction = int(dir_to_player)
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
	facing_direction = -facing_direction
	turn_cooldown = turn_cooldown_duration # Evita bucles rápidos y oscilaciones en colisiones
	_update_facing_direction()


## Actualiza la orientación del sprite, el raycast del suelo y las áreas.
func _update_facing_direction() -> void:
	var face_scale: float = float(facing_direction)

	# Voltea el sprite
	if sprite != null:
		sprite.flip_h = (facing_direction < 0)

	# Actualiza la posición del raycast de borde (adelantado en la dirección de marcha)
	# Comienza a Y = -4.0 (ligeramente sobre el suelo) para evitar imprecisiones numéricas
	if ledge_ray != null:
		ledge_ray.position = Vector2(facing_direction * (body_width * 0.5 + 4.0), -4.0)
		ledge_ray.target_position = Vector2(0.0, 20.0)
		ledge_ray.force_raycast_update()

	# Voltea las áreas de detección y ataque según hacia dónde mira
	if detection_area != null:
		detection_area.scale.x = face_scale
	if hitbox_area != null:
		hitbox_area.scale.x = face_scale


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

	ledge_ray.position = Vector2(facing_direction * (body_width * 0.5 + 4.0), -4.0)
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
		# Aplica daño utilizando el método estándar del Player si existe
		if body.has_method(&"take_damage"):
			body.call(&"take_damage", attack_damage, global_position)
		elif body.has_method(&"receive_hit"):
			body.call(&"receive_hit", attack_damage, global_position)


func _is_player(body: Node2D) -> bool:
	return body.is_in_group(GROUP_PLAYER) or body.name.to_lower().contains("player")


# ==============================================================================
# FÍSICA Y ANIMACIÓN
# ==============================================================================

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		# Godot 4.3+ provee get_gravity(); en versiones previas usamos custom_gravity
		var grav_value: float = get_gravity().y if has_method(&"get_gravity") else custom_gravity
		velocity.y += grav_value * delta
	else:
		velocity.y = 0.0


func _play_animation(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name or not sprite.is_playing():
			sprite.play(anim_name)


# ==============================================================================
# INTEGRACIÓN DE DAÑO RECIBIDO (SISTEMA DE COMBATE)
# ==============================================================================

## Recibe impacto del jugador (llamado por el arma del Player en este proyecto).
func receive_hit(damage: int, _source_position: Vector2, _attack_name: StringName = &"") -> bool:
	if current_state == State.DEAD or damage <= 0:
		return false

	current_health = maxi(current_health - damage, 0)
	
	# Efecto visual de parpadeo (hurt flash)
	_flash_effect()

	if current_health <= 0:
		_die()

	return true


func _flash_effect() -> void:
	if sprite != null:
		sprite.modulate = Color(3.0, 1.5, 1.5, 1.0)
		var t := get_tree().create_timer(0.08)
		t.timeout.connect(func() -> void:
			if is_instance_valid(sprite):
				sprite.modulate = Color.WHITE
		)


func _die() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	_set_hitbox_active(false)
	set_physics_process(false)
	
	if death_particles != null:
		death_particles.restart()
		death_particles.emitting = true
		if sprite != null:
			sprite.visible = false
		collision_layer = 0
		var timer := get_tree().create_timer(death_particles.lifetime)
		timer.timeout.connect(queue_free)
	else:
		queue_free()

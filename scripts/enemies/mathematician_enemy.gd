@tool
class_name MathematicianEnemy
extends Enemy

## Enemigo Matemático (Mathematician Enemy).
## Empuja un pizarrón escolar hacia adelante como escudo y arma contundente.
## Es completamente inmune a ataques frontales (el pizarrón bloquea el daño y suelta chispas).
## Si es golpeado de frente, contraataca de inmediato arremetiendo hacia adelante.
## Solo puede ser dañado y derrotado atacándolo por la espalda.
## Al morir emite una nube de polvo de tiza blanca.

enum State {
	PATROL,    ## Patrullaje regular de izquierda a derecha.
	ATTACK,    ## Arremetida hacia adelante empujando el pizarrón.
	COOLDOWN,  ## Breve recuperación tras el empujón antes de patrullar.
	DEAD       ## Estado tras ser derrotado.
}

const GROUP_PLAYER: StringName = &"player"

@export_group("Movimiento y Patrullaje")
## Velocidad de caminata estándar durante el patrullaje.
@export var walk_speed: float = 50.0
## Cooldown mínimo (en segundos) tras chocar con paredes o bordes antes de girar.
@export var turn_cooldown_duration: float = 0.25

@export_group("Ataque y Detección")
## Velocidad horizontal durante la arremetida con el pizarrón.
@export var attack_speed: float = 150.0
## Distancia fija a recorrer en el ataque. Si es 0.0, se calcula como (ancho * multiplier).
@export var attack_distance: float = 48.0
## Multiplicador respecto al ancho del cuerpo cuando attack_distance es 0.0.
@export var attack_distance_multiplier: float = 1.5
## Cooldown corto de recuperación tras atacar (en segundos) antes de volver a patrullar.
@export var cooldown_duration: float = 0.6
## Daño infligido al jugador al ser alcanzado por el pizarrón.
@export var attack_damage: int = 1
## Rango de detección a la espalda para darse vuelta y atacar si el jugador se acerca por detrás.
@export var rear_detection_range: float = 75.0

@export_group("Efectos")
## Posición relativa del centro del pizarrón cuando mira a la derecha (para chispas y polvo).
@export var blackboard_offset: Vector2 = Vector2(28.0, -32.0)

# Referencias a nodos hijos esperados en la escena
@onready var sprite: AnimatedSprite2D = (get_node_or_null("AnimatedSprite2D") if get_node_or_null("AnimatedSprite2D") != null else get_node_or_null("Visual/AnimatedSprite2D")) as AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D
@onready var rear_detection_area: Area2D = get_node_or_null("RearDetectionArea") as Area2D
@onready var hitbox_area: Area2D = get_node_or_null("HitboxArea") as Area2D
@onready var ledge_ray: RayCast2D = get_node_or_null("LedgeRayCast") as RayCast2D
@onready var death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D
@onready var block_sparks: CPUParticles2D = get_node_or_null("BlockSparks") as CPUParticles2D
@onready var chalk_attack_particles: CPUParticles2D = get_node_or_null("ChalkAttackParticles") as CPUParticles2D

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
var _block_tween: Tween
var _sprite_base_x: float = 0.0


func _init() -> void:
	enemy_id = &"mathematician_enemy"
	max_health = 4
	gravity = 980.0


func _ready() -> void:
	super._ready()
	if sprite != null:
		_sprite_base_x = sprite.position.x
	if Engine.is_editor_hint():
		return

	_calculate_body_width()
	_setup_ledge_ray()
	_setup_areas()
	_update_facing_direction()
	_play_animation(&"walk")


## Gancho para cuando Enemy encuentra al Player: agrega excepción a ledge_ray
func _on_player_found(player: Node) -> void:
	super._on_player_found(player)
	if ledge_ray != null and player is CollisionObject2D:
		ledge_ray.add_exception(player as CollisionObject2D)


## El bucle de física de Enemy llama a _think() para decidir la velocidad horizontal.
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

	# Si el jugador se acerca por la espalda, se da vuelta y arremete
	_check_rear_detection()
	if current_state != State.PATROL:
		return

	# Si está en el suelo y no está en cooldown de giro, verifica obstáculos
	if is_on_floor() and turn_cooldown <= 0.0:
		var reached_wall: bool = false
		if is_on_wall():
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


## Arremetida frontal hacia adelante empujando el pizarrón.
func _process_attack(_delta: float) -> void:
	velocity.x = float(_facing) * attack_speed
	_play_animation(&"attack")

	var traveled_distance: float = absf(global_position.x - attack_start_x)
	var hit_wall: bool = is_on_wall() and (get_wall_normal().x * float(_facing) < -0.1)

	# Termina el ataque si recorrió la distancia objetivo o chocó de frente contra una pared
	if traveled_distance >= target_attack_distance or hit_wall:
		_end_attack()


## Estado de descanso/recuperación corto tras haber atacado.
func _process_cooldown(delta: float) -> void:
	velocity.x = 0.0
	_play_animation(&"idle")

	cooldown_timer -= delta
	if cooldown_timer <= 0.0:
		current_state = State.PATROL


# ==============================================================================
# GESTIÓN DEL ATAQUE Y DETECCIÓN
# ==============================================================================

## Inicia la embestida si está en patrullaje o cooldown y detecta al jugador.
func _start_attack(target_body: Node2D) -> void:
	if current_state != State.PATROL and current_state != State.COOLDOWN:
		return

	# Orientarse hacia el jugador antes de arremeter
	var dir_to_player: float = signf(target_body.global_position.x - global_position.x)
	if dir_to_player != 0.0 and int(dir_to_player) != _facing:
		_facing = int(dir_to_player)
		_update_facing_direction()

	_launch_attack()


## Dispara la arremetida y activa la hitbox del pizarrón.
func _launch_attack() -> void:
	current_state = State.ATTACK
	attack_start_x = global_position.x

	if attack_distance > 0.0:
		target_attack_distance = attack_distance
	else:
		target_attack_distance = body_width * attack_distance_multiplier

	_set_hitbox_active(true)
	_play_animation(&"attack")
	_trigger_chalk_attack_fx()


## Finaliza el ataque e ingresa en fase de recuperación corta.
func _end_attack() -> void:
	_set_hitbox_active(false)
	current_state = State.COOLDOWN
	cooldown_timer = cooldown_duration
	velocity.x = 0.0
	_play_animation(&"idle")


# ==============================================================================
# VULNERABILIDAD Y COMBATE (INMUNIDAD FRONTAL + DAÑO POR LA ESPALDA)
# ==============================================================================

## Recibe impacto del jugador. Solo es vulnerable si el ataque proviene por la espalda.
## Si el ataque es frontal, el pizarrón lo bloquea, suelta chispas y contraataca de inmediato.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if current_state == State.DEAD:
		return false

	# Determina si el impacto proviene de frente o por detrás.
	# _facing: 1 (mira derecha), -1 (mira izquierda).
	var dir_to_source: float = source_position.x - global_position.x
	# Margen de tolerancia para evitar ambigüedad en el mismo píxel horizontal
	var is_frontal_hit: bool = (dir_to_source * float(_facing)) >= -4.0

	if is_frontal_hit:
		# GOLPE FRONTAL: El pizarrón bloquea el ataque por completo sin sufrir daño
		_trigger_block_sparks(source_position)
		_trigger_counterattack(source_position)
		return false

	# GOLPE POR LA ESPALDA: Vulnerable, recibe el daño normal de Enemy
	var success := super.receive_hit(damage, source_position, attack_name)
	if _health <= 0:
		current_state = State.DEAD
	return success


## Contraataque inmediato al ser impactado de frente.
func _trigger_counterattack(source_position: Vector2) -> void:
	if current_state == State.DEAD:
		return

	# Asegurar orientación hacia el atacante
	var dir_to_attacker := signf(source_position.x - global_position.x)
	if dir_to_attacker != 0.0 and int(dir_to_attacker) != _facing:
		_facing = int(dir_to_attacker)
		_update_facing_direction()

	_launch_attack()


## Sobrescribe el efecto de destello de Enemy para usar el AnimatedSprite2D.
func _set_flash_visible(visible_now: bool) -> void:
	if sprite != null:
		sprite.modulate = Color(3.0, 1.5, 1.5, 1.0) if visible_now else Color.WHITE


## Sobrescribe make_corpse_at de Enemy para emitir polvo de tiza blanca y destruirse.
func make_corpse_at(at: Vector2, _facing_dir: int) -> void:
	current_state = State.DEAD
	_dead = true
	global_position = at
	velocity = Vector2.ZERO
	_recoil_left = 0.0
	collision_layer = 0
	_set_hitbox_active(false)

	if _block_tween != null and _block_tween.is_valid():
		_block_tween.kill()

	if block_sparks != null:
		block_sparks.emitting = false
	if chalk_attack_particles != null:
		chalk_attack_particles.emitting = false

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


## Reinicia el estado del matemático cuando el jugador reaparece en un checkpoint o desk.
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
# CONFIGURACIÓN, ORIENTACIÓN Y EFECTOS
# ==============================================================================

## Invierte el sentido horizontal del enemigo con cooldown anti-bucle.
func _flip_direction() -> void:
	if turn_cooldown > 0.0:
		return
	_facing = -_facing
	turn_cooldown = turn_cooldown_duration
	_update_facing_direction()


## Actualiza la orientación del sprite, el raycast del suelo, las áreas y los emisores.
func _update_facing_direction() -> void:
	var face_scale: float = float(_facing)

	if sprite != null:
		sprite.flip_h = (_facing < 0)
		if absf(_sprite_base_x) > 0.01:
			sprite.position.x = _sprite_base_x if _facing >= 0 else -_sprite_base_x

	if ledge_ray != null:
		ledge_ray.position = Vector2(float(_facing) * (body_width * 0.5 + 4.0), -4.0)
		ledge_ray.target_position = Vector2(0.0, 20.0)
		ledge_ray.force_raycast_update()

	if detection_area != null:
		detection_area.scale.x = face_scale
	if rear_detection_area != null:
		rear_detection_area.scale.x = face_scale
	if hitbox_area != null:
		hitbox_area.scale.x = face_scale

	if block_sparks != null:
		block_sparks.position = Vector2(float(_facing) * blackboard_offset.x, blackboard_offset.y)
		block_sparks.direction = Vector2(-float(_facing), -0.5)

	if chalk_attack_particles != null:
		chalk_attack_particles.position = Vector2(float(_facing) * blackboard_offset.x, blackboard_offset.y)
		chalk_attack_particles.direction = Vector2(float(_facing), -0.2)


## Calcula el ancho del cuerpo a partir de CollisionShape2D.
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


## Crea o conecta el raycast para detectar bordes de plataformas.
func _setup_ledge_ray() -> void:
	if ledge_ray == null:
		ledge_ray = RayCast2D.new()
		ledge_ray.name = "LedgeRayCast"
		ledge_ray.enabled = true
		ledge_ray.collision_mask = 1 | 2
		add_child(ledge_ray)
	else:
		ledge_ray.enabled = true

	ledge_ray.position = Vector2(float(_facing) * (body_width * 0.5 + 4.0), -4.0)
	ledge_ray.target_position = Vector2(0.0, 20.0)


## Conecta las áreas de detección y daño.
func _setup_areas() -> void:
	if detection_area != null:
		if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
			detection_area.body_entered.connect(_on_detection_area_body_entered)

	if rear_detection_area != null:
		if not rear_detection_area.body_entered.is_connected(_on_rear_detection_body_entered):
			rear_detection_area.body_entered.connect(_on_rear_detection_body_entered)

	if hitbox_area != null:
		if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
			hitbox_area.body_entered.connect(_on_hitbox_body_entered)
		_set_hitbox_active(false)


func _set_hitbox_active(active: bool) -> void:
	if hitbox_area != null:
		hitbox_area.monitoring = active


func _on_detection_area_body_entered(body: Node2D) -> void:
	if _is_player(body) and (current_state == State.PATROL or current_state == State.COOLDOWN):
		_start_attack(body)


func _on_rear_detection_body_entered(body: Node2D) -> void:
	if _is_player(body) and (current_state == State.PATROL or current_state == State.COOLDOWN):
		_on_rear_player_detected(body)


## Verifica si el jugador se encuentra a espaldas del matemático dentro del rango de percepción.
func _check_rear_detection() -> void:
	if current_state != State.PATROL and current_state != State.COOLDOWN:
		return

	# 1. Comprobación mediante área física RearDetectionArea si existe en la escena
	if rear_detection_area != null and rear_detection_area.monitoring:
		for body: Node2D in rear_detection_area.get_overlapping_bodies():
			if _is_player(body):
				_on_rear_player_detected(body)
				return

	# 2. Comprobación de proximidad y ángulo si el jugador está registrado
	if is_instance_valid(_player_ref) and _player_ref is Node2D:
		var p_pos: Vector2 = (_player_ref as Node2D).global_position
		var dx: float = p_pos.x - global_position.x
		var dy: float = absf(p_pos.y - global_position.y)
		# A una altura similar (< 55px) y viniendo desde atrás (lado opuesto a la marcha):
		if dy <= 55.0 and (dx * float(_facing)) < -4.0 and absf(dx) <= rear_detection_range:
			_on_rear_player_detected(_player_ref as Node2D)


## Reacción cuando el jugador se acerca por la espalda: gira y arremete con el pizarrón.
func _on_rear_player_detected(player: Node2D) -> void:
	if current_state != State.PATROL and current_state != State.COOLDOWN:
		return

	var dir_to_player: float = signf(player.global_position.x - global_position.x)
	if dir_to_player != 0.0 and int(dir_to_player) != _facing:
		_facing = int(dir_to_player)
		_update_facing_direction()

	_launch_attack()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if current_state == State.ATTACK and _is_player(body):
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


## Chispas al bloquear el ataque con el pizarrón.
func _trigger_block_sparks(_source_position: Vector2) -> void:
	if block_sparks != null:
		block_sparks.position = Vector2(float(_facing) * blackboard_offset.x, blackboard_offset.y)
		block_sparks.direction = Vector2(-float(_facing), -0.5)
		block_sparks.restart()
		block_sparks.emitting = true

	# Destello visual rápido de bloqueo
	if sprite != null:
		if _block_tween != null and _block_tween.is_valid():
			_block_tween.kill()
		_block_tween = create_tween()
		sprite.modulate = Color(2.5, 2.0, 1.2, 1.0)
		_block_tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)


## Efecto de polvo de tiza durante la arremetida con el pizarrón.
func _trigger_chalk_attack_fx() -> void:
	if chalk_attack_particles != null:
		chalk_attack_particles.position = Vector2(float(_facing) * blackboard_offset.x, blackboard_offset.y)
		chalk_attack_particles.direction = Vector2(float(_facing), -0.2)
		chalk_attack_particles.restart()
		chalk_attack_particles.emitting = true

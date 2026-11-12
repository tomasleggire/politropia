class_name Teacher_enemy
extends Enemy

const CD_PROJECTILE_SCENE: PackedScene = preload("res://scenes/enemies/teacher_cd_projectile.tscn")
const DEATH_KEY_SHADER: Shader = preload("res://shaders/teacher_death_key.gdshader")

enum AttackPhase { READY, TELEGRAPH, RECOVERY }

@export_group("Patrullaje")
@export var walk_speed: float = 40.0
@export var turn_cooldown_duration: float = 0.25
@export var ledge_check_distance: float = 14.0
@export var ledge_check_depth: float = 20.0

@export_group("Lanzamiento de CD")
@export var attack_range: float = 330.0
@export var fire_interval: float = 2.2
@export var telegraph_time: float = 0.65
@export var recovery_time: float = 0.35
@export var projectile_speed: float = 285.0
@export var projectile_damage: int = 1

var turn_cooldown: float = 0.0
var _attack_phase := AttackPhase.READY
var _attack_wait := 0.5
var _attack_phase_left := 0.0
var _projectiles: Array[EnemyProjectile] = []
var _death_sequence_active := false
var _death_material: ShaderMaterial
var _original_sprite_material: Material

@onready var ledge_ray: RayCast2D = get_node_or_null("LedgeRayCast")
@onready var sprite: AnimatedSprite2D = get_node_or_null(
	"AnimatedSprite2D"
)
@onready var death_particles: GPUParticles2D = get_node_or_null("DeathParticles") as GPUParticles2D


func _ready() -> void:
	_facing = 1
	start_facing = 1
	super._ready()
	
	if ledge_ray:
		ledge_ray.collision_mask = WORLD_MASK
		ledge_ray.enabled = true
		ledge_ray.target_position = Vector2(0, ledge_check_depth)
	if not Engine.is_editor_hint():
		for i: int in 2:
			_projectiles.append(_make_projectile())
	if sprite:
		_original_sprite_material = sprite.material
		_death_material = ShaderMaterial.new()
		_death_material.shader = DEATH_KEY_SHADER
		sprite.animation_finished.connect(_on_sprite_animation_finished)
	if death_particles:
		death_particles.finished.connect(_on_death_particles_finished)

	_update_direction()
	_play_walk_animation()

# Enemy.gd llama a este método desde su propio _physics_process().
func _think(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var player_in_range := (
		player != null
		and global_position.distance_to(player.global_position) <= attack_range
	)
	if player_in_range:
		if _attack_phase == AttackPhase.READY:
			_attack_wait -= delta
			if _attack_wait <= 0.0:
				_facing = 1 if player.global_position.x >= global_position.x else -1
				_update_direction()
				velocity.x = 0.0
				_attack_phase = AttackPhase.TELEGRAPH
				_attack_phase_left = telegraph_time
				if sprite:
					sprite.stop()
				return
		else:
			_facing = 1 if player.global_position.x >= global_position.x else -1
			_update_direction()
			velocity.x = 0.0
			_update_attack(delta, player)
			return

	if _attack_phase != AttackPhase.READY:
		_cancel_attack()

	if turn_cooldown > 0.0:
		turn_cooldown -= delta

	# Camina en la dirección actual.

	velocity.x = _facing * walk_speed

	if turn_cooldown > 0.0:
		return

	# Detecta si hay una pared delante.
	var wall_ahead := is_on_wall()

	# Detecta si falta suelo delante.
	var edge_ahead := false

	if ledge_ray:
		ledge_ray.force_raycast_update()
		edge_ahead = not ledge_ray.is_colliding()

	if wall_ahead or edge_ahead:
		_turn_around()


func _update_attack(delta: float, player: Player) -> void:
	match _attack_phase:
		AttackPhase.TELEGRAPH:
			_attack_phase_left -= delta
			if sprite:
				var progress := 1.0 - clampf(_attack_phase_left / maxf(telegraph_time, 0.001), 0.0, 1.0)
				var pulse := 0.5 + 0.5 * sin(progress * TAU * 2.0)
				sprite.modulate = Color(1.0, 0.86 + 0.14 * pulse, 0.58 + 0.42 * pulse, 1.0)
			if _attack_phase_left <= 0.0:
				_throw_cd(player)
				_attack_phase = AttackPhase.RECOVERY
				_attack_phase_left = recovery_time
		AttackPhase.RECOVERY:
			_attack_phase_left -= delta
			if _attack_phase_left <= 0.0:
				_attack_phase = AttackPhase.READY
				_attack_wait = fire_interval
				if sprite:
					sprite.modulate = Color.WHITE
					_play_walk_animation()


func _throw_cd(player: Player) -> void:
	var from := global_position + Vector2(18.0 * float(_facing), -62.0)
	var target := player.global_position + Vector2(0.0, -24.0)
	var direction := (target - from).normalized()
	if is_zero_approx(direction.length()):
		direction = Vector2(float(_facing), 0.0)
	var projectile := _acquire_projectile()
	projectile.damage = projectile_damage
	projectile.launch(from, direction, projectile_speed)


func _acquire_projectile() -> EnemyProjectile:
	for projectile: EnemyProjectile in _projectiles:
		if not projectile.is_active():
			return projectile
	var extra := _make_projectile()
	_projectiles.append(extra)
	return extra


func _make_projectile() -> EnemyProjectile:
	var projectile := CD_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	add_child(projectile)
	return projectile


func _cancel_attack() -> void:
	_attack_phase = AttackPhase.READY
	_attack_wait = 0.35
	_attack_phase_left = 0.0
	if sprite:
		sprite.modulate = Color.WHITE
		_play_walk_animation()


func set_ai_active(active: bool) -> void:
	super.set_ai_active(active)
	if not active:
		_clear_projectiles()


func make_corpse_at(at: Vector2, facing: int) -> void:
	_clear_projectiles()
	super.make_corpse_at(at, facing)
	_death_sequence_active = true
	if death_particles:
		death_particles.emitting = false
	if sprite and sprite.sprite_frames.has_animation(&"death"):
		sprite.visible = true
		sprite.modulate = Color.WHITE
		sprite.offset = Vector2(0.0, -24.0)
		sprite.speed_scale = 1.0
		sprite.material = _death_material
		_death_material.set_shader_parameter(&"key_background", true)
		sprite.play(&"death")
	else:
		_finish_death_animation()


func _on_sprite_animation_finished() -> void:
	if _death_sequence_active and sprite and sprite.animation == &"death":
		_finish_death_animation()


func _finish_death_animation() -> void:
	_death_sequence_active = false
	if sprite:
		sprite.visible = false
	if death_particles:
		death_particles.emitting = true
		death_particles.restart()


func _on_death_particles_finished() -> void:
	if death_particles:
		death_particles.emitting = false


func _clear_projectiles() -> void:
	for projectile: EnemyProjectile in _projectiles:
		projectile.deactivate()


func _turn_around() -> void:
	_facing *= -1
	turn_cooldown = turn_cooldown_duration

	_update_direction()

func _update_direction() -> void:
	if sprite:
		sprite.flip_h = _facing < 0

	if ledge_ray:
		ledge_ray.position.x = absf(ledge_check_distance) * _facing
		ledge_ray.target_position = Vector2(0, ledge_check_depth)



func _play_walk_animation() -> void:
	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("walk"):
			sprite.play("walk")


func _reset_ai() -> void:
	# Se ejecuta al reiniciar el enemigo desde el sistema base.
	turn_cooldown = 0.0
	velocity = Vector2.ZERO
	_clear_projectiles()
	_attack_phase = AttackPhase.READY
	_attack_wait = 0.5
	_attack_phase_left = 0.0
	_death_sequence_active = false
	if death_particles:
		death_particles.emitting = false
		death_particles.restart()
	if sprite:
		sprite.visible = true
		sprite.modulate = Color.WHITE
		sprite.offset = Vector2.ZERO
		sprite.speed_scale = 1.0
		sprite.material = _original_sprite_material

	_update_direction()
	_play_walk_animation()

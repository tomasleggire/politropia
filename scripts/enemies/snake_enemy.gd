@tool
class_name SnakeEnemy
extends Enemy

## Surface Crawler enemy (similar to Hollow Knight's Mosscreep/Tiktik).
## Crawls along surfaces including floors, walls, and ceilings.
## Never chases the player; deals contact damage.
## Upon death, it explodes into particles and disappears instead of leaving a corpse.

enum CornerMode {
	TURN_BACK,     ## Turns around at ledges (stays on its current plane / platform)
	WRAP_AROUND,   ## Climbs around convex edges (360 continuous surface following)
}

enum Direction {
	CLOCKWISE = 1,
	COUNTER_CLOCKWISE = -1,
}

const DEFAULT_VENOM_PROJECTILE := preload("res://scenes/enemies/venom_projectile.tscn")
const PLAYER_CENTER_OFFSET := Vector2(0.0, -24.0)

@export_group("Crawling")
@export var crawl_speed := 60.0
@export var crawl_direction: Direction = Direction.CLOCKWISE
@export var corner_mode: CornerMode = CornerMode.TURN_BACK
## How firmly it stays attached to surfaces (px/s towards the surface normal).
@export var adhesion_force := 180.0
## Rotation smoothing speed (radians/s).
@export var rotation_speed := 16.0

@export_group("Venom Attack")
@export var venom_scene: PackedScene = DEFAULT_VENOM_PROJECTILE
## Distance to player at which the snake triggers a shot.
@export var shoot_range := 200.0
## Minimum cooldown between shots (in seconds).
@export var shoot_cooldown := 2.5
## Flight speed of the venom projectile.
@export var projectile_speed := 190.0
## Delay from the start of the shoot animation until the venom projectile is released.
@export var shoot_delay := 0.25
## Maximum duration of the shooting stop if animation_finished does not fire.
@export var shoot_duration := 0.6
## Offset from snake center for the venom spawn point (local coordinates).
@export var mouth_offset := Vector2(16.0, -14.0)

@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
@onready var _death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D
@onready var _sfx_attack: AudioStreamPlayer = $SfxAttack

## The current surface normal this crawler is attached to (defaults to floor up: Vector2.UP).
var _surface_normal := Vector2.UP
var _forward_dir := Vector2.RIGHT
var _spawn_surface_normal := Vector2.UP

## Venom shooting state
var _is_shooting := false
var _has_fired := false
var _shoot_cooldown_left := 0.0
var _shoot_delay_left := 0.0
var _shoot_duration_left := 0.0
var _shoot_target := Vector2.ZERO
var _pool: Array[EnemyProjectile] = []
var _sight_ray: RayCast2D

## Raycasts for robust surface detection
@onready var _ray_down: RayCast2D = $RayDown
@onready var _ray_forward: RayCast2D = $RayForward
@onready var _ray_down_ahead: RayCast2D = $RayDownAhead


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_setup_sight_ray()
	if _sprite != null and not _sprite.animation_finished.is_connected(_on_animation_finished):
		_sprite.animation_finished.connect(_on_animation_finished)

	for i: int in 3:
		var initial_shot := _make_projectile()
		if initial_shot != null:
			_pool.append(initial_shot)

	if start_facing == 1:
		crawl_direction = Direction.CLOCKWISE
	elif start_facing == -1:
		crawl_direction = Direction.COUNTER_CLOCKWISE
	_facing = 1 if crawl_direction == Direction.CLOCKWISE else -1

	if rotation != 0.0:
		_surface_normal = Vector2.UP.rotated(rotation).normalized()
	else:
		_surface_normal = Vector2.UP
	_spawn_surface_normal = _surface_normal

	_update_orientation()
	_play_walk()


func _set_flash_visible(visible_now: bool) -> void:
	if _visual != null:
		# Flashes bright white/red when hit, back to normal when timer ends
		_visual.modulate = Color(3.0, 1.5, 1.5, 1.0) if visible_now else Color.WHITE


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_tick_flash(delta)
	_ensure_player_excluded()
	if _hit_stop_left > 0.0:
		_hit_stop_left -= delta
		return
	if _dead:
		return
	if not _ai_active:
		return

	# Al recibir un golpe, la serpiente se congela en seco en lugar de ser empujada fuera de la plataforma
	if _recoil_left > 0.0:
		if _is_shooting:
			_cancel_shooting()
		_recoil_left -= delta
		velocity = -_surface_normal * adhesion_force
		up_direction = _surface_normal
		move_and_slide()
		return

	if _shoot_cooldown_left > 0.0:
		_shoot_cooldown_left -= delta

	if _is_shooting:
		_update_shooting(delta)
		velocity = -_surface_normal * adhesion_force
		up_direction = _surface_normal
		move_and_slide()
		return

	if _shoot_cooldown_left <= 0.0:
		_check_shoot_trigger()
		if _is_shooting:
			velocity = -_surface_normal * adhesion_force
			up_direction = _surface_normal
			move_and_slide()
			return

	_crawl_step(delta)


var _corner_cooldown := 0.0

func _crawl_step(delta: float) -> void:
	if _corner_cooldown > 0.0:
		_corner_cooldown -= delta

	_ray_down.force_raycast_update()
	_ray_forward.force_raycast_update()
	_ray_down_ahead.force_raycast_update()

	var down_hit := _ray_down.is_colliding()
	var forward_hit := _ray_forward.is_colliding()
	var ahead_hit := _ray_down_ahead.is_colliding()
	var wall_blocked := is_on_wall() and get_wall_normal().dot(_forward_dir) < -0.2
	var is_blocked := forward_hit or wall_blocked

	# 1. Esquina interior (choca con una pared frontal)
	if is_blocked and _corner_cooldown <= 0.0:
		if corner_mode == CornerMode.TURN_BACK:
			_reverse_direction()
			return

		var wall_norm: Vector2 = _ray_forward.get_collision_normal() if forward_hit else get_wall_normal()
		if wall_norm != Vector2.ZERO and wall_norm.dot(_surface_normal) < 0.7:
			_surface_normal = wall_norm
			_update_orientation()
			_corner_cooldown = 0.25
			velocity = _forward_dir * crawl_speed
			move_and_slide()
			return

	# 2. Esquina exterior (el rayo de adelante quedó en el aire)
	if not ahead_hit and down_hit and _corner_cooldown <= 0.0:
		if corner_mode == CornerMode.WRAP_AROUND:
			var rot_step: float = PI * 0.5 if crawl_direction == Direction.CLOCKWISE else -PI * 0.5
			_surface_normal = _surface_normal.rotated(rot_step).normalized()
			_update_orientation()
			# No teletransportar hacia adentro de los bloques; avanzar naturalmente por la esquina
			global_position += _forward_dir * 8.0
			_corner_cooldown = 0.25
			velocity = (_forward_dir * crawl_speed) - (_surface_normal * adhesion_force)
			move_and_slide()
			return
		else:
			_reverse_direction()
			return

	# 3. Adhesión normal a superficie
	if down_hit or (ahead_hit and _corner_cooldown > 0.0):
		var ground_norm: Vector2 = _ray_down.get_collision_normal() if down_hit else _ray_down_ahead.get_collision_normal()
		if ground_norm != Vector2.ZERO:
			_surface_normal = ground_norm
			_update_orientation()

		velocity = (_forward_dir * crawl_speed) - (_surface_normal * adhesion_force)
		up_direction = _surface_normal
		move_and_slide()
	else:
		# Si se despegó durante un cooldown, presionar hacia la superficie para reenganchar
		if _corner_cooldown > 0.0:
			velocity = (_forward_dir * crawl_speed * 0.5) - (_surface_normal * adhesion_force * 1.5)
			move_and_slide()
		else:
			# Solo cae por gravedad normal si su orientación original era el suelo (Vector2.UP)
			# Si estaba en pared o techo, busca adherirse antes de soltarse
			if _surface_normal.dot(Vector2.UP) < 0.5:
				velocity = -_surface_normal * adhesion_force
				move_and_slide()
				if _ray_down.is_colliding():
					return
			
			# Caída libre si realmente se soltó de todo
			velocity.x = 0.0
			velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
			up_direction = Vector2.UP
			move_and_slide()
			if is_on_floor() and get_floor_normal().dot(Vector2.UP) > 0.7:
				_surface_normal = Vector2.UP
				_update_orientation()


func _update_orientation() -> void:
	if crawl_direction == Direction.CLOCKWISE:
		_forward_dir = Vector2(-_surface_normal.y, _surface_normal.x).normalized()
	else:
		_forward_dir = Vector2(_surface_normal.y, -_surface_normal.x).normalized()
	
	rotation = _surface_normal.angle() + PI * 0.5
	_aim_rays()


func _aim_rays() -> void:
	if _ray_forward == null or _ray_down_ahead == null or _ray_down == null:
		return
	var dir_sign := 1.0 if crawl_direction == Direction.CLOCKWISE else -1.0
	# Rayos locales alineados con la base del cuerpo
	_ray_down.position = Vector2(0.0, -8.0)
	_ray_down.target_position = Vector2(0.0, 16.0)
	
	_ray_forward.position = Vector2(0.0, -8.0)
	_ray_forward.target_position = Vector2(dir_sign * 20.0, 0.0)
	
	_ray_down_ahead.position = Vector2(dir_sign * 16.0, -8.0)
	_ray_down_ahead.target_position = Vector2(0.0, 20.0)
	
	if _visual != null:
		_visual.scale.x = abs(_visual.scale.x) * dir_sign


func _reverse_direction() -> void:
	crawl_direction = Direction.COUNTER_CLOCKWISE if crawl_direction == Direction.CLOCKWISE else Direction.CLOCKWISE
	_facing = 1 if crawl_direction == Direction.CLOCKWISE else -1
	_corner_cooldown = 0.25
	_update_orientation()


func _on_player_found(player: Node) -> void:
	var col_obj := player as CollisionObject2D
	if col_obj != null:
		if _ray_down != null:
			_ray_down.add_exception(col_obj)
		if _ray_forward != null:
			_ray_forward.add_exception(col_obj)
		if _ray_down_ahead != null:
			_ray_down_ahead.add_exception(col_obj)
		if _sight_ray != null:
			_sight_ray.add_exception(col_obj)


func set_ai_active(active: bool) -> void:
	super.set_ai_active(active)
	if not active:
		_cancel_shooting()
		clear_projectiles()


## Override: Overrides Enemy's corpse behavior to make the snake explode and vanish.
func make_corpse_at(at: Vector2, _facing_dir: int) -> void:
	_cancel_shooting()
	clear_projectiles()
	_dead = true
	global_position = at
	velocity = Vector2.ZERO
	_recoil_left = 0.0
	collision_layer = 0

	if _contact != null:
		_contact.monitoring = false
	if _visual != null:
		_visual.visible = false
	if _sprite != null:
		_sprite.stop()

	# Emit death particles explosion
	if _death_particles != null:
		_death_particles.restart()
		_death_particles.emitting = true

	set_physics_process(false)


func reset_to_spawn() -> void:
	_cancel_shooting()
	clear_projectiles()
	super.reset_to_spawn()
	if start_facing == 1:
		crawl_direction = Direction.CLOCKWISE
	elif start_facing == -1:
		crawl_direction = Direction.COUNTER_CLOCKWISE
	_facing = 1 if crawl_direction == Direction.CLOCKWISE else -1
	_surface_normal = _spawn_surface_normal
	_update_orientation()
	if _visual != null:
		_visual.visible = true
	_play_walk()


func _play_walk() -> void:
	if _is_shooting:
		return
	if _sprite != null and not _dead and _sprite.sprite_frames != null:
		if _sprite.sprite_frames.has_animation(&"walk"):
			_sprite.play(&"walk")
		elif _sprite.sprite_frames.has_animation(&"default"):
			_sprite.play(&"default")


## -- Venom Attack System -----------------------------------------------------

func _setup_sight_ray() -> void:
	_sight_ray = RayCast2D.new()
	_sight_ray.collision_mask = 1 # Only world geometry blocks sight
	_sight_ray.enabled = false
	_sight_ray.exclude_parent = true
	add_child(_sight_ray)


func _player_center() -> Vector2:
	if is_instance_valid(_player_ref) and _player_ref is Node2D:
		return (_player_ref as Node2D).global_position + PLAYER_CENTER_OFFSET
	return Vector2.ZERO


func _get_mouth_position() -> Vector2:
	var dir_sign := 1.0 if crawl_direction == Direction.CLOCKWISE else -1.0
	var offset: Vector2 = mouth_offset if mouth_offset != null else Vector2(16.0, -14.0)
	var local_mouth := Vector2(dir_sign * offset.x, offset.y)
	return to_global(local_mouth)


func _has_line_of_sight(from: Vector2, target: Vector2) -> bool:
	if _sight_ray == null:
		return true
	_sight_ray.global_position = from
	_sight_ray.target_position = _sight_ray.to_local(target)
	_sight_ray.force_raycast_update()
	return not _sight_ray.is_colliding()


func _check_shoot_trigger() -> void:
	if not is_instance_valid(_player_ref):
		return
	var target := _player_center()
	var mouth := _get_mouth_position()
	var dist := mouth.distance_to(target)
	var max_range: float = shoot_range if (shoot_range != null and shoot_range > 0.0) else 200.0
	if dist > max_range:
		return
	if not _has_line_of_sight(mouth, target):
		return

	# Si el jugador está detrás del sentido de avance de la serpiente, girar hacia él
	var to_player := target - global_position
	if _forward_dir.dot(to_player) < -0.1:
		_reverse_direction()

	_start_shooting(target)


func _start_shooting(target: Vector2) -> void:
	_is_shooting = true
	_has_fired = false
	_shoot_target = target
	_shoot_delay_left = shoot_delay if shoot_delay != null else 0.25
	_shoot_duration_left = shoot_duration if shoot_duration != null else 0.6

	if _sprite != null and _sprite.sprite_frames != null:
		if _sprite.sprite_frames.has_animation(&"shoot"):
			var frames := _sprite.sprite_frames.get_frame_count(&"shoot")
			var fps := _sprite.sprite_frames.get_animation_speed(&"shoot")
			if fps > 0.0 and frames > 0:
				var anim_len: float = float(frames) / fps
				_shoot_duration_left = anim_len
				_shoot_delay_left = minf(_shoot_delay_left, anim_len * 0.5)
			_sprite.play(&"shoot")


func _update_shooting(delta: float) -> void:
	_shoot_duration_left -= delta
	if not _has_fired:
		_shoot_delay_left -= delta
		if _shoot_delay_left <= 0.0:
			_has_fired = true
			_fire_venom()

	if _shoot_duration_left <= 0.0:
		_finish_shooting()


func _on_animation_finished() -> void:
	if _is_shooting and _sprite != null and _sprite.animation == &"shoot":
		if not _has_fired:
			_has_fired = true
			_fire_venom()
		_finish_shooting()


func _fire_venom() -> void:
	if _dead or not _ai_active:
		return
	var from := _get_mouth_position()
	var target := _player_center() if is_instance_valid(_player_ref) else _shoot_target
	var dir := (target - from).normalized()
	if dir == Vector2.ZERO:
		dir = _forward_dir
	var shot := _acquire_projectile()
	var speed: float = projectile_speed if (projectile_speed != null and projectile_speed > 0.0) else 190.0
	if shot != null:
		shot.launch(from, dir, speed)
		_sfx_attack.play()


func _acquire_projectile() -> EnemyProjectile:
	for shot: EnemyProjectile in _pool:
		if is_instance_valid(shot) and not shot.is_active():
			return shot
	var extra := _make_projectile()
	if extra != null:
		_pool.append(extra)
	return extra


func _make_projectile() -> EnemyProjectile:
	var scene: PackedScene = venom_scene if venom_scene != null else DEFAULT_VENOM_PROJECTILE
	if scene == null:
		return null
	var shot := scene.instantiate() as EnemyProjectile
	add_child(shot)
	return shot


func clear_projectiles() -> void:
	for shot: EnemyProjectile in _pool:
		if is_instance_valid(shot):
			shot.deactivate()


func _finish_shooting() -> void:
	_is_shooting = false
	var cd: float = shoot_cooldown if (shoot_cooldown != null and shoot_cooldown > 0.0) else 2.5
	_shoot_cooldown_left = cd
	_play_walk()


func _cancel_shooting() -> void:
	_is_shooting = false
	_has_fired = false
	var cd: float = shoot_cooldown if (shoot_cooldown != null and shoot_cooldown > 0.0) else 2.5
	_shoot_cooldown_left = cd * 0.5
	_play_walk()

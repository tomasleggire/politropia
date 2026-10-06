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

@export_group("Crawling")
@export var crawl_speed := 60.0
@export var crawl_direction: Direction = Direction.CLOCKWISE
@export var corner_mode: CornerMode = CornerMode.TURN_BACK
## How firmly it stays attached to surfaces (px/s towards the surface normal).
@export var adhesion_force := 180.0
## Rotation smoothing speed (radians/s).
@export var rotation_speed := 16.0

@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
@onready var _death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D

## The current surface normal this crawler is attached to (defaults to floor up: Vector2.UP).
var _surface_normal := Vector2.UP
var _forward_dir := Vector2.RIGHT


## Raycasts for robust surface detection
@onready var _ray_down: RayCast2D = $RayDown
@onready var _ray_forward: RayCast2D = $RayForward
@onready var _ray_down_ahead: RayCast2D = $RayDownAhead


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_surface_normal = Vector2.UP
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
		_recoil_left -= delta
		velocity = -_surface_normal * adhesion_force
		up_direction = _surface_normal
		move_and_slide()
		return

	_crawl_step(delta)


var _corner_cooldown := 0.0
var _turning_corner := false
var _last_airborne_state := false

func _crawl_step(delta: float) -> void:
	if _corner_cooldown > 0.0:
		_corner_cooldown -= delta

	_ray_down.force_raycast_update()
	_ray_forward.force_raycast_update()
	_ray_down_ahead.force_raycast_update()

	var down_hit := _ray_down.is_colliding()
	var forward_hit := _ray_forward.is_colliding()
	var ahead_hit := _ray_down_ahead.is_colliding()

	# 1. Esquina interior (choca con una pared frontal)
	if forward_hit and _corner_cooldown <= 0.0:
		var wall_norm: Vector2 = _ray_forward.get_collision_normal()
		print_rich("[color=yellow][Snake %s][/color] Esquina INTERIOR: choca al frente con normal %v | pos: %v" % [name, wall_norm, global_position])
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
			var prev_norm := _surface_normal
			_surface_normal = _surface_normal.rotated(rot_step).normalized()
			print_rich("[color=cyan][Snake %s][/color] Borde EXTERIOR detectado! Normal: %v -> %v | pos: %v | rot: %.1f deg" % [name, prev_norm, _surface_normal, global_position, rad_to_deg(rotation)])
			_update_orientation()
			# No teletransportar hacia adentro de los bloques; avanzar naturalmente por la esquina
			global_position += _forward_dir * 8.0
			_corner_cooldown = 0.25
			velocity = (_forward_dir * crawl_speed) - (_surface_normal * adhesion_force)
			move_and_slide()
			return
		else:
			print_rich("[color=orange][Snake %s][/color] Borde alcanzado en TURN_BACK -> invirtiendo" % [name])
			_reverse_direction()
			return

	# 3. Adhesión normal a superficie
	if down_hit or (ahead_hit and _corner_cooldown > 0.0):
		if _last_airborne_state:
			_last_airborne_state = false
			print_rich("[color=green][Snake %s][/color] REENGANCHADA a superficie! Normal: %v | pos: %v" % [name, _ray_down.get_collision_normal(), global_position])
		var ground_norm: Vector2 = _ray_down.get_collision_normal() if down_hit else _ray_down_ahead.get_collision_normal()
		if ground_norm != Vector2.ZERO:
			_surface_normal = ground_norm
			_update_orientation()

		velocity = (_forward_dir * crawl_speed) - (_surface_normal * adhesion_force)
		up_direction = _surface_normal
		move_and_slide()
	else:
		if not _last_airborne_state:
			_last_airborne_state = true
			print_rich("[color=red][Snake %s][/color] DESPEGADA DE SUPERFICIE! down=%s, ahead=%s, fwd=%s | normal=%v | cooldown=%.2f | pos: %v" % [name, down_hit, ahead_hit, forward_hit, _surface_normal, _corner_cooldown, global_position])

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
					print_rich("[color=green][Snake %s][/color] Reenganchada tras busqueda lateral/techo!" % [name])
					return
			
			# Caída libre si realmente se soltó de todo
			velocity.x = 0.0
			velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
			up_direction = Vector2.UP
			move_and_slide()
			if is_on_floor() and get_floor_normal().dot(Vector2.UP) > 0.7:
				print_rich("[color=magenta][Snake %s][/color] Caida al vacio: toco piso por gravedad y reinicio a UP" % [name])
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
	_ray_forward.target_position = Vector2(dir_sign * 18.0, 0.0)
	
	_ray_down_ahead.position = Vector2(dir_sign * 16.0, -8.0)
	_ray_down_ahead.target_position = Vector2(0.0, 20.0)
	
	if _visual != null:
		_visual.scale.x = abs(_visual.scale.x) * dir_sign


func _reverse_direction() -> void:
	crawl_direction = Direction.COUNTER_CLOCKWISE if crawl_direction == Direction.CLOCKWISE else Direction.CLOCKWISE
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


## Override: Overrides Enemy's corpse behavior to make the snake explode and vanish.
func make_corpse_at(at: Vector2, _facing_dir: int) -> void:
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
	super.reset_to_spawn()
	_surface_normal = Vector2.UP
	_update_orientation()
	if _visual != null:
		_visual.visible = true
	_play_walk()


func _play_walk() -> void:
	if _sprite != null and not _dead and _sprite.sprite_frames != null:
		if _sprite.sprite_frames.has_animation(&"walk"):
			_sprite.play(&"walk")
		elif _sprite.sprite_frames.has_animation(&"default"):
			_sprite.play(&"default")

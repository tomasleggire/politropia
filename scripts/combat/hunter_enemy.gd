class_name HunterEnemy
extends CharacterBody2D

## Cazador de la segunda sala: pausa, evalúa una ruta y presiona.

enum Kind { MELEE, RANGED }
enum State { SLEEP, OBSERVE, HUNT, WINDUP, COMMIT, RECOVER, DEAD }

signal defeated

const WandBolt := preload("res://scripts/combat/wand_projectile.gd")
const MeleeTexture := preload("res://assets/enemies/melee_hunter.png")
const RangedTexture := preload("res://assets/enemies/ranged_hunter.png")
const ROOM_SIZE := Vector2(720, 1280)
const SPRITE_UNIT_SCALE := 0.25 ## Los sprites se dibujaron a 4px por unidad de mundo.

var kind: Kind = Kind.MELEE
var pathfinder
var home_origin := Vector2.ZERO

var _state: State = State.SLEEP
var _hp := 4
var _max_speed := 300.0
var _accel := 2100.0
var _body_radius := 22.0
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _repath_in := 0.0
var _path: PackedVector2Array = PackedVector2Array()
var _path_i := 0
var _flank := 1.0
var _sprite: Sprite2D
var _hurt_flash := 0.0
var _contact_cd := 0.0
var _lunge_dir := Vector2.DOWN
var _wander_t := 0.0


func setup(p_kind: int, origin: Vector2, finder) -> void:
	kind = p_kind as Kind
	home_origin = origin
	pathfinder = finder
	_rng.seed = hash("%s-%s-%s" % [p_kind, origin, Time.get_ticks_usec()])
	_flank = -1.0 if _rng.randf() < 0.5 else 1.0
	if kind == Kind.MELEE:
		_hp = 5
		_max_speed = 308.0
		_accel = 2550.0
		_body_radius = 23.0
	else:
		_hp = 4
		_max_speed = 248.0
		_accel = 2050.0
		_body_radius = 18.0
	_build_visuals()


func _ready() -> void:
	add_to_group(&"enemy")
	collision_layer = 1
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	z_index = 5
	var shape := CircleShape2D.new()
	shape.radius = _body_radius
	var hit := CollisionShape2D.new()
	hit.shape = shape
	hit.position = Vector2(0, 8)
	add_child(hit)


func wake_up(delay: float = 0.35) -> void:
	if _state != State.SLEEP:
		return
	_state = State.OBSERVE
	_timer = delay + _rng.randf_range(0.22, 0.55)


func take_damage(amount: int, from_dir: Vector2) -> void:
	if _state == State.DEAD:
		return
	_hp -= amount
	_hurt_flash = 0.12
	velocity += from_dir.normalized() * 210.0
	if _hp <= 0:
		_die()
		return
	if _state == State.HUNT or _state == State.OBSERVE:
		_state = State.OBSERVE
		_timer = _rng.randf_range(0.08, 0.18)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD or _state == State.SLEEP:
		return
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	_wander_t += delta
	_update_look()
	var player := _player()
	if player == null:
		return
	match _state:
		State.OBSERVE:
			_observe(delta)
		State.HUNT:
			_hunt(delta, player)
		State.WINDUP:
			_windup(delta, player)
		State.COMMIT:
			_commit(delta, player)
		State.RECOVER:
			_recover(delta)
	_separate(delta)
	move_and_slide()
	_try_contact(player)


func _observe(delta: float) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 1.4 * delta)
	if _timer > 0.0:
		return
	_flank *= -1.0 if _rng.randf() < 0.38 else 1.0
	_state = State.HUNT
	_repath_in = 0.0


func _hunt(delta: float, player: Player) -> void:
	var goal := _goal_for(player)
	_repath_in -= delta
	if _repath_in <= 0.0 or _path_i >= _path.size():
		_rebuild_path(goal)
		_repath_in = _rng.randf_range(0.28, 0.62)
		if _should_pause(player):
			_state = State.OBSERVE
			_timer = _rng.randf_range(0.16, 0.42)
			return
	if _wants_attack(player):
		_state = State.WINDUP
		_timer = 0.18 if kind == Kind.MELEE else 0.26
		velocity = velocity.move_toward(Vector2.ZERO, _accel * 2.0 * delta)
		return
	var steer := _next_steer(goal)
	var wander := Vector2(-steer.y, steer.x) * sin(_wander_t * 2.3 + float(kind)) * 0.18
	var desired := (steer + wander).normalized() * _max_speed
	if steer == Vector2.ZERO:
		desired = Vector2.ZERO
	velocity = velocity.move_toward(desired, _accel * delta)


func _windup(delta: float, player: Player) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 2.4 * delta)
	if _timer > 0.0:
		return
	_lunge_dir = (player.global_position - global_position).normalized()
	if _lunge_dir == Vector2.ZERO:
		_lunge_dir = Vector2.DOWN
	_state = State.COMMIT
	_timer = 0.17 if kind == Kind.MELEE else 0.04


func _commit(delta: float, player: Player) -> void:
	_timer -= delta
	if kind == Kind.MELEE:
		velocity = _lunge_dir * 560.0
		if _timer <= 0.0:
			_state = State.RECOVER
			_timer = _rng.randf_range(0.38, 0.58)
		return
	if not _has_los(player):
		_state = State.HUNT
		_repath_in = 0.0
		return
	_fire_at(player)
	_state = State.RECOVER
	_timer = _rng.randf_range(0.72, 1.05)


func _recover(delta: float) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 1.6 * delta)
	if _timer <= 0.0:
		_state = State.HUNT
		_repath_in = 0.0


func _goal_for(player: Player) -> Vector2:
	if not _player_in_home(player):
		return home_origin + Vector2(70.0, ROOM_SIZE.y * 0.5)
	var predicted := player.global_position + player.velocity * 0.22
	if kind == Kind.MELEE:
		return predicted
	var to_player := predicted - global_position
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 1.0 else Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x) * _flank
	if dist < 190.0:
		return global_position - dir * 150.0 + side * 50.0
	if dist > 360.0:
		return predicted - dir * 270.0 + side * 80.0
	return predicted + side * 270.0


func _should_pause(player: Player) -> bool:
	if kind == Kind.MELEE and global_position.distance_to(player.global_position) < 130.0:
		return false
	return _rng.randf() < 0.22


func _wants_attack(player: Player) -> bool:
	if not _player_in_home(player):
		return false
	if not _has_los(player):
		return false
	var dist := global_position.distance_to(player.global_position)
	if kind == Kind.MELEE:
		return dist < 62.0
	return dist > 150.0 and dist < 430.0


func _rebuild_path(goal: Vector2) -> void:
	_path = PackedVector2Array()
	_path_i = 0
	if pathfinder == null:
		return
	var found: PackedVector2Array = pathfinder.find_path(global_position, goal)
	if found.size() >= 2:
		_path = found
		_path_i = 1


func _next_steer(goal: Vector2) -> Vector2:
	if _path_i < _path.size():
		var waypoint := _path[_path_i]
		if global_position.distance_to(waypoint) < 30.0:
			_path_i += 1
			if _path_i >= _path.size():
				return goal - global_position
			waypoint = _path[_path_i]
		return waypoint - global_position
	return goal - global_position


func _has_los(player: Player) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid(), player.get_rid()]
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


func _player_in_home(player: Player) -> bool:
	var local := player.global_position - home_origin
	return local.x >= 0.0 and local.y >= 0.0 and local.x < ROOM_SIZE.x and local.y < ROOM_SIZE.y


func _fire_at(player: Player) -> void:
	var direction := (player.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var bolt := WandBolt.new()
	bolt.team = &"enemy"
	bolt.speed = 510.0
	bolt.range_pixels = 760.0
	bolt.orb_color = Color("d9a3ff")
	bolt.glow_color = Color(0.72, 0.38, 0.95, 0.28)
	var parent := get_tree().current_scene.get_node_or_null("Projectiles")
	if parent == null:
		parent = get_parent()
	parent.add_child(bolt)
	bolt.global_position = global_position + direction * 34.0
	bolt.launch(direction)


func _try_contact(player: Player) -> void:
	if _contact_cd > 0.0 or kind != Kind.MELEE:
		return
	if global_position.distance_to(player.global_position) > 44.0:
		return
	_contact_cd = 0.55
	player.take_damage(1, (player.global_position - global_position))


func _separate(_delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"enemy"):
		if node == self or not (node is Node2D):
			continue
		var other := node as Node2D
		var away := global_position - other.global_position
		var dist := away.length()
		if dist < 1.0 or dist > 58.0:
			continue
		velocity += away.normalized() * (58.0 - dist) * 8.5


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player") as Player


func _die() -> void:
	_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	defeated.emit()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.45, 0.35), 0.18)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)


func _build_visuals() -> void:
	var shadow := Polygon2D.new()
	shadow.z_index = -1
	shadow.position = Vector2(0, 14)
	shadow.polygon = LevelGeometry.circle_points(_body_radius + 4.0, 16)
	shadow.color = Color(0.01, 0.015, 0.02, 0.34)
	add_child(shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = MeleeTexture if kind == Kind.MELEE else RangedTexture
	_sprite.scale = Vector2.ONE * SPRITE_UNIT_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)


func _update_look() -> void:
	if _sprite == null:
		return
	if _hurt_flash > 0.0:
		_sprite.modulate = Color(1.7, 1.5, 1.45, 1.0)
		return
	var pulse := 1.0
	if _state == State.WINDUP:
		pulse = 1.16
	_sprite.modulate = Color(pulse, pulse, pulse, 1.0)
	if velocity.length() > 28.0:
		_sprite.rotation = velocity.angle() + PI * 0.5
	elif _state == State.WINDUP or _state == State.COMMIT:
		_sprite.rotation = _lunge_dir.angle() + PI * 0.5

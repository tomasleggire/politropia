class_name BossEnemy
extends CharacterBody2D

## Guardián del santuario: varios patrones de ataque, todos telegrafiados con
## una animación/indicador claro antes de resolverse, para que se puedan
## aprender y esquivar. Ningún golpe llega de imprevisto: solo daña por
## contacto durante un patrón ya avisado.

signal health_changed(fraction: float)
signal defeated

enum State { SLEEP, OBSERVE, HUNT, WINDUP, COMMIT, RECOVER, DEAD }
enum Attack { SLAM, BARRAGE, CHARGE }

const WandBolt := preload("res://scripts/combat/wand_projectile.gd")
const BossTexture := preload("res://assets/enemies/sanctuary_guardian.png")
const SPRITE_UNIT_SCALE := 0.25 ## El sprite se dibujó a 4px por unidad de mundo.
const ROOM_SIZE := Vector2(720, 1280)
const MAX_HP := 30
const SLAM_RADIUS := 150.0
const CHARGE_SPEED := 900.0
const CHARGE_DISTANCE := 480.0

var pathfinder
var home_origin := Vector2.ZERO

var _hp := MAX_HP
var _max_speed := 232.0
var _accel := 1500.0
var _body_radius := 46.0
var _rng := RandomNumberGenerator.new()
var _state: State = State.SLEEP
var _timer := 0.0
var _repath_in := 0.0
var _path: PackedVector2Array = PackedVector2Array()
var _path_i := 0
var _attack: Attack = Attack.SLAM
var _attack_cd := {Attack.SLAM: 0.0, Attack.BARRAGE: 0.0, Attack.CHARGE: 0.0}
var _barrage_dirs: Array[Vector2] = []
var _charge_dir := Vector2.DOWN
var _charge_traveled := 0.0
var _contact_cd := 0.0
var _hurt_flash := 0.0
var _facing_dir := Vector2.DOWN
var _sprite: Sprite2D
var _telegraph_root: Node2D


func setup(origin: Vector2, finder) -> void:
	home_origin = origin
	pathfinder = finder
	_rng.randomize()
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
	hit.position = Vector2(0, 10)
	add_child(hit)


func wake_up(delay: float = 0.4) -> void:
	if _state != State.SLEEP:
		return
	_state = State.OBSERVE
	_timer = delay


func take_damage(amount: int, from_dir: Vector2) -> void:
	if _state == State.DEAD:
		return
	_hp = maxi(_hp - amount, 0)
	_hurt_flash = 0.12
	health_changed.emit(float(_hp) / float(MAX_HP))
	velocity += from_dir.normalized() * 70.0
	if _hp <= 0:
		_die()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD or _state == State.SLEEP:
		return
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	for key in _attack_cd.keys():
		_attack_cd[key] = maxf(_attack_cd[key] - delta, 0.0)
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
	move_and_slide()


func _observe(delta: float) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 1.2 * delta)
	if _timer <= 0.0:
		_state = State.HUNT
		_repath_in = 0.0


func _hunt(delta: float, player: Player) -> void:
	if _player_in_home(player) and _has_los(player):
		var choice := _choose_attack(global_position.distance_to(player.global_position))
		if choice != -1:
			_begin_windup(choice, player)
			return
	var goal := _goal_for(player)
	_repath_in -= delta
	if _repath_in <= 0.0 or _path_i >= _path.size():
		_rebuild_path(goal)
		_repath_in = _rng.randf_range(0.3, 0.55)
	var steer := _next_steer(goal)
	var desired := steer.normalized() * _max_speed if steer != Vector2.ZERO else Vector2.ZERO
	velocity = velocity.move_toward(desired, _accel * delta)


func _goal_for(player: Player) -> Vector2:
	if not _player_in_home(player):
		return home_origin + Vector2(ROOM_SIZE.x * 0.5, ROOM_SIZE.y * 0.62)
	var predicted := player.global_position + player.velocity * 0.18
	var to_player := predicted - global_position
	var dist := to_player.length()
	if dist < 1.0:
		return global_position
	var dir := to_player.normalized()
	if dist < 140.0:
		return global_position - dir * 70.0
	if dist > 460.0:
		return predicted - dir * 260.0
	return global_position


func _player_in_home(player: Player) -> bool:
	var local := player.global_position - home_origin
	return local.x >= 0.0 and local.y >= 0.0 and local.x < ROOM_SIZE.x and local.y < ROOM_SIZE.y


func _choose_attack(dist: float) -> int:
	var options: Array[int] = []
	if dist <= 150.0 and _attack_cd[Attack.SLAM] <= 0.0:
		options.append(Attack.SLAM)
	if dist >= 80.0 and dist <= 560.0 and _attack_cd[Attack.BARRAGE] <= 0.0:
		options.append(Attack.BARRAGE)
	if dist >= 170.0 and _attack_cd[Attack.CHARGE] <= 0.0:
		options.append(Attack.CHARGE)
	if options.is_empty():
		return -1
	return options[_rng.randi_range(0, options.size() - 1)]


func _begin_windup(attack: int, player: Player) -> void:
	_attack = attack
	_state = State.WINDUP
	match attack:
		Attack.SLAM:
			_timer = 0.55
			_facing_dir = (player.global_position - global_position).normalized()
			_show_slam_telegraph(_timer)
		Attack.BARRAGE:
			_timer = 0.6
			var aim := (player.global_position - global_position).normalized()
			if aim == Vector2.ZERO:
				aim = Vector2.DOWN
			_facing_dir = aim
			_barrage_dirs = _spread_directions(aim, 3, deg_to_rad(16.0))
			_show_barrage_telegraph(_timer)
		Attack.CHARGE:
			_timer = 0.7
			_charge_dir = (player.global_position - global_position).normalized()
			if _charge_dir == Vector2.ZERO:
				_charge_dir = Vector2.DOWN
			_facing_dir = _charge_dir
			_show_charge_telegraph(_timer)


func _windup(delta: float, player: Player) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 2.2 * delta)
	if _timer > 0.0:
		return
	_clear_telegraph()
	_state = State.COMMIT
	_attack_cd[_attack] = _attack_cooldown(_attack)
	match _attack:
		Attack.SLAM:
			_timer = 0.16
			_resolve_slam(player)
		Attack.BARRAGE:
			_timer = 0.1
			_resolve_barrage()
		Attack.CHARGE:
			_timer = 999.0
			_charge_traveled = 0.0


func _commit(delta: float, player: Player) -> void:
	if _attack == Attack.CHARGE:
		_commit_charge(delta, player)
		return
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * delta)
	if _timer <= 0.0:
		_state = State.RECOVER
		_timer = _rng.randf_range(0.45, 0.7)


func _commit_charge(delta: float, player: Player) -> void:
	velocity = _charge_dir * CHARGE_SPEED
	_charge_traveled += CHARGE_SPEED * delta
	if _contact_cd <= 0.0 and global_position.distance_to(player.global_position) < (_body_radius + 26.0):
		_contact_cd = 0.4
		player.take_damage(1, (player.global_position - global_position))
	if _charge_traveled >= CHARGE_DISTANCE:
		_state = State.RECOVER
		_timer = 0.55


func _recover(delta: float) -> void:
	_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, _accel * 1.4 * delta)
	if _timer <= 0.0:
		_state = State.HUNT
		_repath_in = 0.0


func _attack_cooldown(attack: int) -> float:
	match attack:
		Attack.SLAM:
			return 2.3
		Attack.BARRAGE:
			return 1.7
		Attack.CHARGE:
			return 2.6
	return 1.5


func _resolve_slam(player: Player) -> void:
	if global_position.distance_to(player.global_position) <= SLAM_RADIUS:
		player.take_damage(1, (player.global_position - global_position))
	_flash_ring(SLAM_RADIUS, Color(1.0, 0.55, 0.35, 0.55))


func _resolve_barrage() -> void:
	for dir in _barrage_dirs:
		_fire_bolt(dir)


func _fire_bolt(direction: Vector2) -> void:
	var bolt := WandBolt.new()
	bolt.team = &"enemy"
	bolt.speed = 560.0
	bolt.range_pixels = 900.0
	bolt.orb_color = Color("ff5a4d")
	bolt.glow_color = Color(0.95, 0.35, 0.3, 0.28)
	var parent := get_tree().current_scene.get_node_or_null("Projectiles")
	if parent == null:
		parent = get_parent()
	parent.add_child(bolt)
	bolt.global_position = global_position + direction * 46.0
	bolt.launch(direction)


func _spread_directions(base_dir: Vector2, count: int, angle_step: float) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var start := -angle_step * float(count - 1) * 0.5
	for i in count:
		dirs.append(base_dir.rotated(start + angle_step * float(i)))
	return dirs


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


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player") as Player


func _die() -> void:
	_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	_clear_telegraph()
	defeated.emit()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.7, 0.3), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)


func _build_visuals() -> void:
	var shadow := Polygon2D.new()
	shadow.z_index = -1
	shadow.position = Vector2(0, 20)
	shadow.polygon = LevelGeometry.circle_points(_body_radius + 8.0, 22)
	shadow.color = Color(0.01, 0.015, 0.02, 0.38)
	add_child(shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = BossTexture
	_sprite.scale = Vector2.ONE * SPRITE_UNIT_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)

	_telegraph_root = Node2D.new()
	_telegraph_root.z_index = 4
	add_child(_telegraph_root)


func _update_look() -> void:
	if _sprite == null:
		return
	if _hurt_flash > 0.0:
		_sprite.modulate = Color(1.8, 1.5, 1.5, 1.0)
	else:
		var pulse := 1.2 if _state == State.WINDUP else 1.0
		_sprite.modulate = Color(pulse, pulse, pulse, 1.0)
	if velocity.length() > 24.0:
		_facing_dir = velocity.normalized()
	_sprite.rotation = _facing_dir.angle() + PI * 0.5


func _clear_telegraph() -> void:
	if _telegraph_root == null:
		return
	for child in _telegraph_root.get_children():
		child.queue_free()


func _show_slam_telegraph(duration: float) -> void:
	_clear_telegraph()
	var ring := Polygon2D.new()
	ring.polygon = LevelGeometry.circle_points(1.0, 28)
	ring.color = Color(0.95, 0.35, 0.25, 0.0)
	ring.scale = Vector2(0.001, 0.001)
	_telegraph_root.add_child(ring)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector2.ONE * SLAM_RADIUS, duration)
	tween.parallel().tween_property(ring, "color:a", 0.55, duration * 0.5)


func _show_barrage_telegraph(duration: float) -> void:
	_clear_telegraph()
	var length := 620.0
	for dir in _barrage_dirs:
		var beam := Polygon2D.new()
		beam.polygon = PackedVector2Array([
			Vector2(-3, 0), Vector2(3, 0), Vector2(3, -length), Vector2(-3, -length),
		])
		beam.rotation = dir.angle() + PI * 0.5
		beam.color = Color(1.0, 0.5, 0.4, 0.0)
		_telegraph_root.add_child(beam)
		var tween := create_tween()
		tween.tween_property(beam, "color:a", 0.4, duration * 0.8)
	var core := Polygon2D.new()
	core.polygon = LevelGeometry.circle_points(6.0, 14)
	core.color = Color(1.0, 0.7, 0.4, 0.0)
	_telegraph_root.add_child(core)
	var core_tween := create_tween()
	core_tween.tween_property(core, "color:a", 0.85, duration)
	core_tween.parallel().tween_property(core, "scale", Vector2.ONE * 2.4, duration)


func _show_charge_telegraph(duration: float) -> void:
	_clear_telegraph()
	var length := CHARGE_DISTANCE + 40.0
	var width := 64.0
	var lane := Polygon2D.new()
	lane.polygon = PackedVector2Array([
		Vector2(-width * 0.5, 0), Vector2(width * 0.5, 0),
		Vector2(width * 0.5, -length), Vector2(-width * 0.5, -length),
	])
	lane.rotation = _charge_dir.angle() + PI * 0.5
	lane.color = Color(1.0, 0.65, 0.3, 0.0)
	_telegraph_root.add_child(lane)
	var tween := create_tween()
	tween.tween_property(lane, "color:a", 0.4, duration * 0.6)
	tween.tween_property(lane, "color:a", 0.62, duration * 0.4)


func _flash_ring(radius: float, color: Color) -> void:
	var ring := Polygon2D.new()
	ring.polygon = LevelGeometry.circle_points(1.0, 28)
	ring.color = color
	ring.scale = Vector2.ONE * radius
	_telegraph_root.add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "color:a", 0.0, 0.22)
	tween.tween_callback(ring.queue_free)

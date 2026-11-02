extends SceneTree
## Test suite for SnakeEnemy: validates essential properties and core enemy behaviors.
## Covers initialization/properties, surface crawling & corner navigation,
## venom attack targeting & projectiles, hit recoil adhesion, death explosion, and respawn/AI.
##
## Compatible with Rider's GDScript play button (runs directly as SceneTree)
## or CLI: godot --headless --path . --script res://tests/snake_enemy_test.gd

const SNAKE_SCENE := preload("res://scenes/enemies/snake_enemy.tscn")
const WATCHDOG_SECONDS := 30.0

const CHECKS := {
	"case_core_properties_and_defaults": 8,
	"case_crawling_and_corner_navigation": 6,
	"case_venom_attack_and_targeting": 5,
	"case_recoil_and_hit_reaction": 3,
	"case_death_explosion": 5,
	"case_reset_and_ai_control": 6,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _test_id_counter := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _tick() -> void:
	_clock += root.get_process_delta_time()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	_free_rig()
	_rig = Node2D.new()
	root.add_child(_rig)
	await call(case_name)
	_free_rig()
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.queue_free()
		_rig = null


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func _on_watchdog() -> void:
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


func finish() -> void:
	var complete := _problems.is_empty() and checks == _expected_total
	if complete and failed.is_empty():
		print("\nALL SNAKE ENEMY TESTS PASSED! (%d/%d)" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("\nFAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("\nFAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


func _create_snake(facing: int = 1, rot: float = 0.0) -> SnakeEnemy:
	_test_id_counter += 1
	var snake := SNAKE_SCENE.instantiate() as SnakeEnemy
	snake.enemy_id = StringName("test_snake_%d" % _test_id_counter)
	snake.start_facing = facing
	snake.rotation = rot
	_rig.add_child(snake)
	return snake


func _create_static_box(pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var col_shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	col_shape.shape = box
	body.add_child(col_shape)
	body.position = pos
	_rig.add_child(body)
	return body


# ==============================================================================
# Test Cases: Core Enemy Properties & Functions
# ==============================================================================

## 1. Valida propiedades clave del enemigo y valores por defecto
func case_core_properties_and_defaults() -> void:
	var snake := _create_snake(1)
	check(snake != null, "Snake instantiated")
	check(snake.max_health == 8 and snake.get_health() == 8, "Max health and current health are 8")
	check(is_equal_approx(snake.crawl_speed, 60.0), "Crawl speed is 60")
	check(is_equal_approx(snake.adhesion_force, 180.0), "Adhesion force is 180")
	check(is_equal_approx(snake.shoot_range, 200.0), "Shoot range is 200")
	check(is_equal_approx(snake.shoot_cooldown, 2.5), "Shoot cooldown is 2.5")
	check(not snake.is_dead(), "Snake starts alive")
	check(snake.is_ai_active(), "AI is active by default")


## 2. Valida navegación por superficies, orientación y comportamiento en esquinas
func case_crawling_and_corner_navigation() -> void:
	var snake := _create_snake(1, 0.0)
	check(snake._surface_normal.is_equal_approx(Vector2.UP), "Floor surface normal is UP")
	check(snake.crawl_direction == SnakeEnemy.Direction.CLOCKWISE, "Initial crawl direction is CLOCKWISE")

	snake._reverse_direction()
	check(snake.crawl_direction == SnakeEnemy.Direction.COUNTER_CLOCKWISE, "Reverses crawl direction to COUNTER_CLOCKWISE")
	check(snake.get_facing() == -1, "Facing matches reverse direction")

	# Esquina con TURN_BACK: da la vuelta en el borde
	var snake_turn := _create_snake(1)
	snake_turn.set_physics_process(false)
	snake_turn.corner_mode = SnakeEnemy.CornerMode.TURN_BACK
	snake_turn.global_position = Vector2(0.0, 0.0)
	_create_static_box(Vector2(-20.0, 8.0), Vector2(56.0, 16.0))
	await process_frame
	await process_frame
	snake_turn._crawl_step(0.016)
	check(snake_turn.crawl_direction == SnakeEnemy.Direction.COUNTER_CLOCKWISE, "TURN_BACK reverses at ledge")

	# Esquina con WRAP_AROUND: escala y rota normal de superficie
	var snake_wrap := _create_snake(1)
	snake_wrap.set_physics_process(false)
	snake_wrap.corner_mode = SnakeEnemy.CornerMode.WRAP_AROUND
	snake_wrap.global_position = Vector2(0.0, 0.0)
	snake_wrap._crawl_step(0.016)
	check(snake_wrap._surface_normal.is_equal_approx(Vector2.RIGHT), "WRAP_AROUND rotates surface normal around corner")


## 3. Valida detección de ataque de veneno, apuntado y pool de proyectiles
func case_venom_attack_and_targeting() -> void:
	var snake := _create_snake(1)
	snake.global_position = Vector2(100.0, 100.0)
	var player := CharacterBody2D.new()
	_rig.add_child(player)
	snake._player_ref = player

	# Fuera de rango: no dispara
	player.global_position = Vector2(400.0, 100.0)
	snake._check_shoot_trigger()
	check(not snake._is_shooting, "Player out of range does not trigger shoot")

	# En rango: inicia disparo
	player.global_position = Vector2(200.0, 100.0)
	snake._check_shoot_trigger()
	check(snake._is_shooting, "Player in range triggers shoot")

	# Jugador a la espalda: gira hacia él antes de disparar
	var snake_turn_player := _create_snake(1)
	snake_turn_player.global_position = Vector2(100.0, 100.0)
	snake_turn_player._player_ref = player
	player.global_position = Vector2(20.0, 100.0)
	snake_turn_player._check_shoot_trigger()
	check(snake_turn_player.get_facing() == -1, "Snake turns towards player before shooting")

	# Disparo de proyectil y pool
	snake._fire_venom()
	var active_projectiles := 0
	for shot in snake._pool:
		if shot.is_active():
			active_projectiles += 1
	check(active_projectiles >= 1, "Venom projectile is launched from pool")

	snake.clear_projectiles()
	var any_active := false
	for shot in snake._pool:
		if shot.is_active():
			any_active = true
	check(not any_active, "clear_projectiles deactivates all venom projectiles")


## 4. Valida reacción al golpe (recoil): no cae al vacío, se adhiere y cancela ataque
func case_recoil_and_hit_reaction() -> void:
	var snake := _create_snake(1)
	snake.global_position = Vector2(100.0, 100.0)
	snake._start_shooting(Vector2(200.0, 100.0))
	snake._recoil_left = 0.1
	snake._physics_process(0.05)

	check(not snake._is_shooting, "Recoil cancels active shooting")
	check(is_equal_approx(snake._recoil_left, 0.05), "Recoil duration counts down")
	check(snake.up_direction.is_equal_approx(snake._surface_normal), "Adheres firmly along surface normal during recoil")


## 5. Valida muerte del enemigo: explosión de partículas y desaparición sin cadáver persistente
func case_death_explosion() -> void:
	var snake := _create_snake(1)
	var death_pos := Vector2(80.0, 80.0)
	snake.make_corpse_at(death_pos, 1)

	check(snake.is_dead(), "Snake marked dead")
	check(snake.velocity == Vector2.ZERO, "Velocity stopped on death")
	check(snake.collision_layer == 0, "Collisions disabled on death")
	check(not snake._visual.visible, "Visual sprite hidden on death")
	check(snake._death_particles != null and snake._death_particles.emitting, "Death particles triggered")


## 6. Valida reinicio a spawn (reset_to_spawn) y control de IA (set_ai_active)
func case_reset_and_ai_control() -> void:
	var snake := _create_snake(1)
	var spawn_pos := snake.global_position
	snake.make_corpse_at(Vector2(200.0, 200.0), -1)

	snake.reset_to_spawn()
	check(not snake.is_dead(), "Snake alive after reset_to_spawn")
	check(snake.get_health() == snake.max_health, "Health restored to max_health")
	check(snake.global_position == spawn_pos, "Spawn position restored")
	check(snake._visual.visible, "Visual restored on respawn")

	var shot := snake._acquire_projectile()
	shot.launch(Vector2.ZERO, Vector2.RIGHT, 100.0)
	snake.set_ai_active(false)
	check(not snake.is_ai_active(), "AI deactivated via set_ai_active(false)")
	check(not shot.is_active(), "Active projectiles cleared when AI deactivated")

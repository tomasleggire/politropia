extends SceneTree
## Test suite for LancetEnemy: validates essential properties and core enemy behaviors.
## Covers initialization/defaults, patrol movement & ledge turns, attack charge & facing,
## attack completion & cooldown recovery, hit reaction/health loss, and death explosion/reset.
##
## Compatible with Rider's GDScript play button (runs directly as SceneTree)
## or CLI: godot --headless --path . --script res://tests/lancet_enemy_test.gd

const LANCET_SCENE := preload("res://scenes/enemies/lancet_enemy.tscn")
const WATCHDOG_SECONDS := 30.0

const CHECKS := {
	"case_core_properties_and_defaults": 8,
	"case_patrol_movement_and_turn": 6,
	"case_attack_trigger_and_facing": 6,
	"case_attack_completion_and_cooldown": 5,
	"case_hit_reaction_and_death_state": 6,
	"case_death_explosion_and_reset": 8,
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
		print("\nALL LANCET ENEMY TESTS PASSED! (%d/%d)" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("\nFAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("\nFAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


func _create_lancet(facing: int = 1) -> LancetEnemy:
	_test_id_counter += 1
	var lancet := LANCET_SCENE.instantiate() as LancetEnemy
	lancet.enemy_id = StringName("test_lancet_%d" % _test_id_counter)
	lancet.start_facing = facing
	_rig.add_child(lancet)
	return lancet


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
# Test Cases: Core LancetEnemy Properties & Behaviors
# ==============================================================================

## 1. Valida propiedades clave y valores por defecto
func case_core_properties_and_defaults() -> void:
	var lancet := _create_lancet(1)
	check(lancet != null, "Lancet instantiated")
	check(lancet.max_health == 4 and lancet.get_health() == 4, "Max health and current health are 4")
	check(is_equal_approx(lancet.walk_speed, 60.0), "Walk speed is 60.0")
	check(is_equal_approx(lancet.attack_speed, 180.0), "Attack speed is 180.0")
	check(lancet.attack_damage == 1, "Attack damage is 1")
	check(is_equal_approx(lancet.cooldown_duration, 1.5), "Cooldown duration is 1.5s")
	check(lancet.current_state == LancetEnemy.State.PATROL, "Initial state is PATROL")
	check(not lancet.is_dead() and lancet.is_ai_active(), "Lancet starts alive and AI active")


## 2. Valida movimiento de patrullaje, inversión de marcha y detección de salientes
func case_patrol_movement_and_turn() -> void:
	var lancet := _create_lancet(1)
	lancet._process_patrol(0.016)
	check(is_equal_approx(lancet.velocity.x, 60.0), "Patrol moves forward with walk_speed")

	# Inversión de dirección
	lancet._flip_direction()
	check(lancet.facing_direction == -1, "Facing inverted to -1")
	check(lancet.sprite != null and lancet.sprite.flip_h, "Sprite flipped horizontally")
	check(is_equal_approx(lancet.turn_cooldown, lancet.turn_cooldown_duration), "Turn cooldown set to prevent jitter")

	lancet._process_patrol(0.016)
	check(is_equal_approx(lancet.velocity.x, -60.0), "Patrol moves backward when facing -1")

	# Detección de borde con ledge_ray
	var lancet_ledge := _create_lancet(1)
	lancet_ledge.global_position = Vector2(20.0, 0.0)
	_create_static_box(Vector2(-20.0, 10.0), Vector2(40.0, 20.0))
	await process_frame
	await process_frame
	lancet_ledge.ledge_ray.force_raycast_update()
	check(not lancet_ledge.ledge_ray.is_colliding(), "Ledge ray detects abyss / edge of platform")


## 3. Valida activación del ataque, orientación hacia el objetivo y efectos de lanza
func case_attack_trigger_and_facing() -> void:
	var lancet := _create_lancet(1)
	lancet.global_position = Vector2(100.0, 0.0)
	var player := CharacterBody2D.new()
	player.add_to_group(LancetEnemy.GROUP_PLAYER)
	_rig.add_child(player)
	player.global_position = Vector2(160.0, 0.0)

	# Inicio de ataque hacia adelante
	lancet._start_attack(player)
	check(lancet.current_state == LancetEnemy.State.ATTACK, "State transitions to ATTACK")
	check(lancet.hitbox_area != null and lancet.hitbox_area.monitoring, "Hitbox monitoring activated on attack")
	lancet._process_attack(0.016)
	check(is_equal_approx(lancet.velocity.x, lancet.attack_speed), "Velocity set to attack_speed")
	check(lancet.pencil_gleam != null and lancet.pencil_gleam.visible, "Pencil gleam triggered on attack")

	# Inicio de ataque con el jugador a la espalda (debe girar antes de embestir)
	var lancet_behind := _create_lancet(1)
	lancet_behind.global_position = Vector2(100.0, 0.0)
	player.global_position = Vector2(20.0, 0.0)
	lancet_behind._start_attack(player)
	check(lancet_behind.facing_direction == -1, "Faces player when target is behind")
	lancet_behind._process_attack(0.016)
	check(is_equal_approx(lancet_behind.velocity.x, -lancet_behind.attack_speed), "Charges toward target direction")


## 4. Valida finalización de la embestida y recuperación en cooldown
func case_attack_completion_and_cooldown() -> void:
	var lancet := _create_lancet(1)
	lancet.global_position = Vector2(0.0, 0.0)
	var dummy_target := Node2D.new()
	_rig.add_child(dummy_target)
	dummy_target.global_position = Vector2(50.0, 0.0)
	lancet.attack_distance = 50.0
	lancet._start_attack(dummy_target)

	# Simular recorrido hasta completar la distancia objetivo
	lancet.global_position.x = 55.0
	lancet._process_attack(0.016)
	check(lancet.current_state == LancetEnemy.State.COOLDOWN, "Transitions to COOLDOWN on reaching attack distance")
	check(lancet.hitbox_area != null and not lancet.hitbox_area.monitoring, "Hitbox disabled during cooldown")
	check(lancet.velocity.x == 0.0, "Velocity halted during cooldown")
	check(is_equal_approx(lancet.cooldown_timer, lancet.cooldown_duration), "Cooldown timer set to cooldown_duration")

	# Procesar tiempo de recuperación hasta agotar cooldown
	lancet._process_cooldown(lancet.cooldown_duration + 0.1)
	check(lancet.current_state == LancetEnemy.State.PATROL, "Returns to PATROL state after cooldown expires")


## 5. Valida reacción a daño (receive_hit), descuento de vida y estado DEAD
func case_hit_reaction_and_death_state() -> void:
	var lancet := _create_lancet(1)
	check(lancet.get_health() == 4, "Starts with 4 health")

	var hit_ok := lancet.receive_hit(2, Vector2.LEFT)
	check(hit_ok, "receive_hit accepted")
	check(lancet.get_health() == 2, "Health decreased to 2 after 2 damage")
	check(not lancet.is_dead() and lancet.current_state == LancetEnemy.State.PATROL, "Still alive and patrolling")

	lancet.receive_hit(2, Vector2.LEFT)
	check(lancet.get_health() == 0, "Health drops to 0 on lethal damage")
	check(lancet.current_state == LancetEnemy.State.DEAD, "Enters State.DEAD on fatal hit")


## 6. Valida explosión de muerte y reinicio de IA
func case_death_explosion_and_reset() -> void:
	var lancet := _create_lancet(1)
	var death_pos := Vector2(75.0, 75.0)

	lancet.make_corpse_at(death_pos, 1)
	check(lancet.is_dead(), "Marked dead on make_corpse_at")
	check(lancet.velocity == Vector2.ZERO, "Velocity stopped on death")
	check(lancet.collision_layer == 0, "Collisions disabled on death")
	check(lancet.hitbox_area != null and not lancet.hitbox_area.monitoring, "Hitbox disabled on death")
	check(lancet.sprite != null and not lancet.sprite.visible, "Sprite hidden on death")
	check(lancet.death_particles != null and lancet.death_particles.emitting, "Death particles triggered")

	lancet._reset_ai()
	check(lancet.current_state == LancetEnemy.State.PATROL, "State restored to PATROL in _reset_ai")
	check(lancet.sprite != null and lancet.sprite.visible, "Sprite restored to visible in _reset_ai")

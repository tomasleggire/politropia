extends SceneTree
## Test suite for MathematicianEnemy: validates essential properties and core behaviors.
## Covers initialization/defaults, patrol & ledge turns, frontal immunity/block counterattack,
## rear vulnerability & death, attack cycle & rear detection, and chalk death explosion/reset.
##
## Compatible with Rider's GDScript play button (runs directly as SceneTree)
## or CLI: godot --headless --path . --script res://tests/mathematician_enemy_test.gd

const MATH_SCENE := preload("res://scenes/enemies/mathematician_enemy.tscn")
const WATCHDOG_SECONDS := 30.0

const CHECKS := {
	"case_core_properties_and_defaults": 8,
	"case_patrol_movement_and_turn": 7,
	"case_frontal_block_and_counterattack": 5,
	"case_rear_vulnerability_and_death": 5,
	"case_attack_cycle_and_rear_detection": 7,
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
		print("\nALL MATHEMATICIAN ENEMY TESTS PASSED! (%d/%d)" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("\nFAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("\nFAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


func _create_math(facing: int = 1) -> MathematicianEnemy:
	_test_id_counter += 1
	var math := MATH_SCENE.instantiate() as MathematicianEnemy
	math.enemy_id = StringName("test_math_%d" % _test_id_counter)
	math.start_facing = facing
	_rig.add_child(math)
	return math


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
# Test Cases: Core MathematicianEnemy Properties & Behaviors
# ==============================================================================

## 1. Valida propiedades clave y valores por defecto
func case_core_properties_and_defaults() -> void:
	var math := _create_math(1)
	check(math != null, "Mathematician instantiated")
	check(math.max_health == 4 and math.get_health() == 4, "Max health and current health are 4")
	check(is_equal_approx(math.walk_speed, 50.0), "Walk speed is 50.0")
	check(is_equal_approx(math.attack_speed, 150.0), "Attack speed is 150.0")
	check(is_equal_approx(math.attack_distance, 48.0), "Attack distance is 48.0")
	check(is_equal_approx(math.cooldown_duration, 0.6), "Cooldown duration is 0.6s")
	check(math.current_state == MathematicianEnemy.State.PATROL, "Initial state is PATROL")
	check(not math.is_dead() and math.is_ai_active(), "Starts alive and AI active")


## 2. Valida movimiento de patrullaje, inversión de rumbo y detección de salientes
func case_patrol_movement_and_turn() -> void:
	var math := _create_math(1)
	math._process_patrol(0.016)
	check(is_equal_approx(math.velocity.x, 50.0), "Patrol moves forward with walk_speed")

	# Inversión de dirección
	math._flip_direction()
	check(math.facing_direction == -1, "Facing inverted to -1")
	check(math.sprite != null and math.sprite.flip_h, "Sprite flipped horizontally")
	check(is_equal_approx(math.turn_cooldown, math.turn_cooldown_duration), "Turn cooldown set to prevent jitter")

	math._process_patrol(0.016)
	check(is_equal_approx(math.velocity.x, -50.0), "Patrol moves backward when facing -1")

	# Detección de borde con ledge_ray
	var math_ledge := _create_math(1)
	math_ledge.global_position = Vector2(20.0, 0.0)
	_create_static_box(Vector2(-20.0, 10.0), Vector2(40.0, 20.0))
	await process_frame
	await process_frame
	math_ledge.ledge_ray.force_raycast_update()
	check(not math_ledge.ledge_ray.is_colliding(), "Ledge ray detects abyss / edge of platform")
	math_ledge._flip_direction()
	check(math_ledge.facing_direction == -1, "Direction flips on edge detection")


## 3. Valida inmunidad frontal del pizarrón, chispas y contraataque inmediato
func case_frontal_block_and_counterattack() -> void:
	var math := _create_math(1)
	math.global_position = Vector2(100.0, 0.0)

	# Ataque frontal: enemigo mira derecha (1), golpe proviene desde adelante (x = 150)
	var blocked := not math.receive_hit(2, Vector2(150.0, 0.0))
	check(blocked, "Frontal hit is completely blocked by blackboard")
	check(math.get_health() == 4, "Health is unchanged after frontal block")
	check(math.block_sparks != null and math.block_sparks.emitting, "Block sparks emitted on blackboard block")
	check(math.current_state == MathematicianEnemy.State.ATTACK, "Frontal block triggers immediate counterattack")

	math._process_attack(0.016)
	check(is_equal_approx(math.velocity.x, math.attack_speed), "Counterattack charges toward attacker")


## 4. Valida vulnerabilidad a ataques por la espalda y muerte
func case_rear_vulnerability_and_death() -> void:
	var math := _create_math(1)
	math.global_position = Vector2(100.0, 0.0)

	# Ataque por la espalda: enemigo mira derecha (1), golpe proviene desde atrás (x = 50)
	var hit_ok := math.receive_hit(2, Vector2(50.0, 0.0))
	check(hit_ok, "Rear hit penetrates defense")
	check(math.get_health() == 2, "Health reduced to 2 on rear hit")
	check(not math.is_dead() and math.current_state != MathematicianEnemy.State.DEAD, "Alive and not DEAD after non-lethal hit")

	# Golpe fatal por la espalda
	math.receive_hit(2, Vector2(50.0, 0.0))
	check(math.get_health() == 0, "Health drops to 0 on fatal rear hit")
	check(math.current_state == MathematicianEnemy.State.DEAD, "Enters State.DEAD on fatal hit")


## 5. Valida ciclo de ataque, detección trasera y recuperación en cooldown
func case_attack_cycle_and_rear_detection() -> void:
	var math := _create_math(1)
	math.global_position = Vector2(100.0, 0.0)
	var player := CharacterBody2D.new()
	player.add_to_group(MathematicianEnemy.GROUP_PLAYER)
	_rig.add_child(player)
	player.global_position = Vector2(50.0, 0.0) # Jugador detrás

	# Detección por la espalda: debe girar hacia el jugador y arremeter
	math._on_rear_player_detected(player)
	check(math.facing_direction == -1, "Turns around when player is detected behind")
	check(math.current_state == MathematicianEnemy.State.ATTACK, "Launches attack after turning")
	check(math.hitbox_area != null and math.hitbox_area.monitoring, "Hitbox monitoring activated on attack")

	math._process_attack(0.016)
	check(is_equal_approx(math.velocity.x, -math.attack_speed), "Charges in new facing direction")

	# Simular recorrido hasta completar la distancia de ataque (48px)
	math.global_position.x = 40.0 # Recorrió 60px (>= 48px)
	math._process_attack(0.016)
	check(math.current_state == MathematicianEnemy.State.COOLDOWN, "Transitions to COOLDOWN after attack distance")
	check(math.velocity.x == 0.0, "Velocity halted during cooldown")

	# Recuperación tras cooldown
	math._process_cooldown(math.cooldown_duration + 0.1)
	check(math.current_state == MathematicianEnemy.State.PATROL, "Returns to PATROL state after cooldown expires")


## 6. Valida explosión de polvo de tiza en muerte y reinicio de IA
func case_death_explosion_and_reset() -> void:
	var math := _create_math(1)
	var death_pos := Vector2(80.0, 80.0)

	math.make_corpse_at(death_pos, 1)
	check(math.is_dead(), "Marked dead on make_corpse_at")
	check(math.velocity == Vector2.ZERO, "Velocity stopped on death")
	check(math.collision_layer == 0, "Collisions disabled on death")
	check(math.hitbox_area != null and not math.hitbox_area.monitoring, "Hitbox disabled on death")
	check(math.sprite != null and not math.sprite.visible, "Sprite hidden on death")
	check(math.death_particles != null and math.death_particles.emitting, "Chalk death particles triggered")

	math._reset_ai()
	check(math.current_state == MathematicianEnemy.State.PATROL, "State restored to PATROL in _reset_ai")
	check(math.sprite != null and math.sprite.visible, "Sprite restored to visible in _reset_ai")

extends SceneTree
## Focused regression suite for the book flyer and shadow owl only.
## It checks runtime behavior and animation setup, not rendered sprite crops.
## Run: godot --headless --path . --script res://tests/book_owl_enemy_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOOK_SCENE := "res://scenes/enemies/book_flyer.tscn"
const OWL_SCENE := "res://scenes/enemies/shadow_owl.tscn"
const WATCHDOG_SECONDS := 45.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const ROOM := &"book_owl_test_room"

const CHECKS := {
	"case_book_scene_and_flight_animation": 4,
	"case_book_chases_and_damages_without_projectiles": 5,
	"case_owl_idle_flaps_and_bobs": 5,
	"case_owl_attack_sequence": 3,
	"case_hit_interrupts_owl_charge": 3,
}

var checks := 0
var failed: Array[String] = []
var _problems: Array[String] = []
var _expected_total := 0
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _enemy: Enemy
var _id_counter := 0


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
	await call(case_name)
	await _free_rig()
	_registry().clear()
	_checkpoints().clear()
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])


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
		print("PASS %d/%d" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("FAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("FAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


func _registry() -> Node:
	return root.get_node("EnemyRegistry")


func _checkpoints() -> Node:
	return root.get_node("CheckpointService")


func _build_rig(with_player: bool) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM
	if with_player:
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
		_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


func _spawn(scene_path: String, at: Vector2, facing: int = 1) -> void:
	_id_counter += 1
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	enemy.enemy_id = StringName("book_owl_%d" % _id_counter)
	enemy.start_facing = facing
	enemy.position = at
	# Sound is outside this suite's scope; silence it so headless runs do not
	# leave a long MP3 playback alive when the test process exits.
	for node: Node in enemy.find_children("*", "", true, true):
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stream = null
		elif node is AudioStreamPlayer2D:
			(node as AudioStreamPlayer2D).stream = null
	_rig.add_child(enemy)
	_enemy = enemy
	await _frames(SETTLE_FRAMES)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		for node: Node in _rig.find_children("*", "", true, true):
			if node is AudioStreamPlayer:
				(node as AudioStreamPlayer).stop()
			elif node is AudioStreamPlayer2D:
				(node as AudioStreamPlayer2D).stop()
		_rig.free()
		# Let the audio server release any just-stopped MP3 playback before exit.
		for i: int in 3:
			await process_frame
	_rig = null
	_player = null
	_enemy = null


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _secs(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until:
		await process_frame


func case_book_scene_and_flight_animation() -> void:
	await _build_rig(false)
	await _spawn(BOOK_SCENE, Vector2(0.0, -150.0))
	var book := _enemy as BookFlyer
	var sprite := book.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames
	check(book is BookFlyer, "the book scene uses the book flyer behavior")
	check(frames.has_animation(&"fly"), "the book builds its fly animation")
	check(frames.get_frame_count(&"fly") == 8, "the flight loop contains eight frames")
	check(sprite.animation == &"fly" and frames.get_animation_loop(&"fly"), "the book starts in a looping flight animation")


func case_book_chases_and_damages_without_projectiles() -> void:
	await _build_rig(true)
	await _spawn(BOOK_SCENE, Vector2(160.0, -60.0), -1)
	var book := _enemy as BookFlyer
	var health_before := _player.get_health()
	var closest := INF
	var top_speed := 0.0
	for i: int in 180:
		await physics_frame
		closest = minf(closest, book.get_body_center().distance_to(_player.global_position + Vector2(0.0, -29.0)))
		top_speed = maxf(top_speed, book.velocity.length())
	check(book.is_engaged(), "the book engages the player in sight")
	check(top_speed > 100.0 and top_speed <= book.chase_max_speed + 1.0, "it accelerates without exceeding its speed limit")
	check(closest < 30.0, "it closes the distance to the player")
	check(_player.get_health() < health_before, "contact with the book damages the player (%d -> %d)" % [health_before, _player.get_health()])
	check(_rig.find_children("*", "EnemyProjectile", true, true).is_empty(), "the book attack does not create projectiles")


func case_owl_idle_flaps_and_bobs() -> void:
	await _build_rig(false)
	await _spawn(OWL_SCENE, Vector2(0.0, -150.0))
	var owl := _enemy as ShadowOwl
	var sprite := owl.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	var frames := sprite.sprite_frames
	var home := owl.get_spawn_position()
	var min_y := owl.global_position.y
	var max_y := min_y
	for i: int in 120:
		await physics_frame
		min_y = minf(min_y, owl.global_position.y)
		max_y = maxf(max_y, owl.global_position.y)
	check(not owl.is_engaged(), "without a nearby player the owl remains idle")
	check(sprite.animation == &"hover", "the idle owl plays its hover and flap animation")
	check(frames.has_animation(&"hover") and frames.get_animation_loop(&"hover"), "the hover animation loops")
	check(max_y - min_y > 2.0, "the idle owl bobs vertically")
	check(absf(owl.global_position.x - home.x) < 14.0, "idle bobbing keeps the owl near its spawn horizontally")


func case_owl_attack_sequence() -> void:
	await _build_rig(true)
	await _spawn(OWL_SCENE, Vector2(100.0, -50.0), -1)
	var owl := _enemy as ShadowOwl
	var sprite := owl.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	var seen := {&"windup": false, &"dive": false, &"charge": false, &"recover": false}
	for i: int in 210:
		await physics_frame
		if seen.has(sprite.animation):
			seen[sprite.animation] = true
	check(owl.is_engaged(), "the owl engages the nearby player")
	check(seen[&"windup"] and seen[&"dive"], "the attack includes its windup and dive animations")
	check(seen[&"charge"] and seen[&"recover"], "the attack continues through charge and recovery animations")

func case_hit_interrupts_owl_charge() -> void:
	await _build_rig(true)
	await _spawn(OWL_SCENE, Vector2(100.0, -50.0), -1)
	var owl := _enemy as ShadowOwl
	var sprite := owl.get_node("Visual/AnimatedSprite2D") as AnimatedSprite2D
	var start := owl.global_position
	var hit_during_charge := false
	for i: int in 210:
		await physics_frame
		if sprite.animation == &"charge":
			hit_during_charge = true
			owl.receive_hit(1, Vector2(owl.global_position.x - 50.0, owl.global_position.y + 29.0), &"attack_ground_1")
			break
	check(hit_during_charge, "the owl reaches its charge animation")
	check(sprite.animation == &"recover", "a hit during the charge interrupts into recovery")
	await _secs(0.2)
	check(owl.global_position.x > start.x + 15.0, "knockback remains visible during the interrupted attack")

extends SceneTree

const LANCET_SCENE := preload("res://scenes/enemies/lancet_enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _root: Node2D
var _lancet: LancetEnemy
var _player: Player

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_root = Node2D.new()
	root.add_child(_root)
	
	# Static floor body
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 40)
	floor_shape.shape = rect
	floor_body.add_child(floor_shape)
	floor_body.position = Vector2(0, 20)
	_root.add_child(floor_body)

	# Create LancetEnemy facing right
	_lancet = LANCET_SCENE.instantiate() as LancetEnemy
	_lancet.position = Vector2(0, 0)
	_lancet.start_facing = 1
	_root.add_child(_lancet)

	# Create Player initially out of detection range
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(400, 0)
	_root.add_child(_player)

	for frame in range(10):
		await process_frame

	print("Lancet initialized: pencil_tip_node is ", _lancet.pencil_tip_node != null)
	print("Pencil gleam node is ", _lancet.pencil_gleam != null)
	print("Pencil particles is ", _lancet.pencil_particles != null)

	assert(_lancet is Enemy, "LancetEnemy should inherit from Enemy")
	assert(_lancet.pencil_tip_node != null, "PencilTip node should exist")
	assert(_lancet.pencil_gleam != null, "PencilGleam node should exist")
	assert(_lancet.pencil_particles != null, "PencilParticles node should exist")
	assert(not _lancet.pencil_gleam.visible, "Gleam should be hidden while in patrol")
	assert(_lancet.get_collision_exceptions().has(_player), "Lancet should have collision exception with Player")

	# Move Player into detection range
	_player.position = Vector2(90, 0)

	var saw_attack := false
	var saw_gleam_active := false
	var saw_particles_emitting := false

	for frame in range(40):
		await process_frame
		if _lancet.current_state == LancetEnemy.State.ATTACK:
			saw_attack = true
			if _lancet.pencil_gleam.visible:
				saw_gleam_active = true
			if _lancet.pencil_particles.emitting:
				saw_particles_emitting = true

	print("Saw attack: ", saw_attack)
	print("Saw gleam active: ", saw_gleam_active)
	print("Saw particles emitting: ", saw_particles_emitting)

	assert(saw_attack, "Lancet should enter ATTACK state when player detected")
	assert(saw_gleam_active, "Pencil gleam should be visible on attack start")
	assert(saw_particles_emitting, "Pencil particles should emit on attack")

	print("ALL LANCET GLEAM TESTS PASSED!")
	quit(0)

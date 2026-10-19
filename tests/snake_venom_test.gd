extends SceneTree

const SNAKE_SCENE := preload("res://scenes/enemies/snake_enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _root: Node2D
var _snake: SnakeEnemy
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

	# Create SnakeEnemy
	_snake = SNAKE_SCENE.instantiate() as SnakeEnemy
	_snake.position = Vector2(0, 0)
	_snake.enemy_id = &"test_snake"
	_root.add_child(_snake)

	# Create Player
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(100, 0) # Close to snake (within 200px)
	_root.add_child(_player)

	for frame in range(10):
		await process_frame

	print("Initial check: Snake has sight ray: ", _snake._sight_ray != null)
	assert(_snake._sight_ray != null, "Sight ray should be initialized")

	# Wait for snake to detect player and start shooting
	var saw_shooting := false
	var saw_projectile := false
	for frame in range(60):
		await process_frame
		if _snake._is_shooting:
			saw_shooting = true
		for child in _snake.get_children():
			if child is EnemyProjectile and child.is_active():
				saw_projectile = true

	print("Saw shooting state: ", saw_shooting)
	print("Saw active projectile: ", saw_projectile)
	assert(saw_shooting, "Snake should enter shooting state when player is close")
	assert(saw_projectile, "Snake should launch a venom projectile")

	print("ALL SNAKE VENOM TESTS PASSED!")
	quit(0)

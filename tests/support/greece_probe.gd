extends RefCounted
## Physics probes for the Greece level: loads the real scene and drives the
## player through input actions. Waits run on the game clock (accumulated
## process deltas), like the Stillness Desk ritual harness.

const LEVEL := "res://scenes/levels/greece_level.tscn"
const SETTLE_FRAMES := 45
const TAP_HOLD_FRAMES := 2

var tree: SceneTree
var clock := 0.0
var level: Node
var player: CharacterBody2D


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	tree.process_frame.connect(_tick)


func _tick() -> void:
	clock += tree.root.get_process_delta_time()


func frames(n: int) -> void:
	for i: int in n:
		await tree.process_frame


func secs(t: float) -> void:
	var end := clock + t
	while clock < end:
		await tree.process_frame


## Geometry probes run on the bare level (no enemies, no spikes) so nothing
## hurts or pushes the scripted player; `populated` keeps them.
func load_level(populated := false) -> void:
	tree.root.get_node("CheckpointService").clear()
	tree.change_scene_to_file(LEVEL)
	await frames(10)
	level = tree.current_scene
	player = level.get_node("Player")
	release_all()
	if not populated:
		await _strip_dangers()


func _strip_dangers() -> void:
	var dangers: Array[Node] = []
	dangers.append_array(tree.get_nodes_in_group(&"enemies"))
	dangers.append_array(tree.get_nodes_in_group(&"greece_spikes"))
	for node: Node in dangers:
		node.queue_free()
	await frames(2)


func place(position: Vector2) -> void:
	player.global_position = position
	player.velocity = Vector2.ZERO
	await frames(SETTLE_FRAMES)


func release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


func tap(action: StringName) -> void:
	Input.action_press(action)
	await frames(TAP_HOLD_FRAMES)
	Input.action_release(action)


## Runs toward `direction` for `duration` seconds, jumping and air dashing
## repeatedly. Returns the furthest x reached in that direction.
func hop_dash_toward(direction: float, duration: float) -> float:
	var action: StringName = &"move_right" if direction > 0.0 else &"move_left"
	var best := player.global_position.x
	Input.action_press(action)
	var end := clock + duration
	while clock < end:
		await tap(&"jump")
		await secs(0.28)
		await tap(&"dash")
		await secs(0.55)
		best = maxf(best, player.global_position.x) if direction > 0.0 else minf(best, player.global_position.x)
	Input.action_release(action)
	return best


## Standing at `start`, runs toward `direction`, jumps (held to the apex),
## then double jumps `delay` seconds after the first press and holds it.
## Returns the highest point reached (smallest y) during the manoeuvre. The run
## key stays held: the caller releases it.
func run_double_jump(start: Vector2, direction: float, delay: float, hold: float) -> float:
	var action: StringName = &"move_right" if direction > 0.0 else &"move_left"
	await place(start)
	var peak := player.global_position.y
	Input.action_press(action)
	Input.action_press(&"jump")
	var end := clock + delay
	while clock < end:
		await tree.process_frame
		peak = minf(peak, player.global_position.y)
	Input.action_release(&"jump")
	await frames(TAP_HOLD_FRAMES)
	Input.action_press(&"jump")
	end = clock + hold
	while clock < end:
		await tree.process_frame
		peak = minf(peak, player.global_position.y)
	Input.action_release(&"jump")
	return peak


## Waits until the player stands on a floor at or below `min_y`; false on timeout.
func wait_for_floor(min_y: float, timeout: float) -> bool:
	var end := clock + timeout
	while clock < end:
		await tree.process_frame
		if player.is_on_floor() and player.global_position.y >= min_y:
			return true
	return false

extends SceneTree
## Regression test for ground locomotion: run speed, turn crouch, skid stop,
## tap stop without skid, and the ground dust spawned by each.
## Run: godot --headless --path . --script res://tests/locomotion_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const SETTLE_FRAMES := 30

var checks := 0
var failed: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
## Dust spawned so far per kind (the effects free themselves quickly).
var _spawned := {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(func() -> void: _clock += root.get_process_delta_time())
	await _build_rig()
	await _case_run_and_skid()
	await _case_turn()
	await _case_tap()
	_rig.free()
	print("PASS %d/%d" % [checks - failed.size(), checks] if failed.is_empty() else "FAIL %d/%d" % [failed.size(), checks])
	for message in failed:
		print("  - ", message)
	quit(0 if failed.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func _case_run_and_skid() -> void:
	Input.action_press(&"move_right")
	await _secs(0.5)
	check(is_equal_approx(_player.velocity.x, _player.run_max_speed), "runs at run_max_speed (%.0f)" % _player.velocity.x)
	check(_dust_count(GroundDust.Kind.FOOTSTEP) >= 1, "running spawns footstep dust")
	Input.action_release(&"move_right")
	await _secs(0.05)
	check(_player._state == Player.State.SKID, "releasing at speed enters the skid")
	check(_dust_count(GroundDust.Kind.STOP) == 1, "the skid spawns stop dust")
	var start_x := _player.global_position.x
	await _secs(0.3)
	check(_player._state == Player.State.IDLE and is_zero_approx(_player.velocity.x), "skid ends idle and still")
	check(_player.global_position.x - start_x < 16.0, "skid slides a short distance")


func _case_turn() -> void:
	Input.action_press(&"move_left")
	await _secs(0.02)
	check(_player._state == Player.State.TURN, "starting opposite to the facing plays the turn")
	check(is_zero_approx(_player.velocity.x), "no movement during the turn")
	await _secs(0.3)
	check(_player.velocity.x < 0.0, "runs left after the turn")
	Input.action_release(&"move_left")
	await _secs(0.5)


func _case_tap() -> void:
	Input.action_press(&"move_left")
	await _secs(0.04)
	Input.action_release(&"move_left")
	await _secs(0.05)
	check(_player._state != Player.State.SKID, "a short tap does not skid")


func _dust_count(kind: GroundDust.Kind) -> int:
	return _spawned.get(kind, 0)


func _on_child_entered(child: Node) -> void:
	if child is GroundDust:
		var kind := (child as GroundDust).kind
		_spawned[kind] = _spawned.get(kind, 0) + 1


func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	_rig.child_entered_tree.connect(_on_child_entered)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_rig.add_child(_player)
	for i in SETTLE_FRAMES:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame

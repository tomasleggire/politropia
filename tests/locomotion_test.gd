extends SceneTree
## Regression test for ground locomotion: run speed, turn crouch, skid stop,
## tap stop without skid, skid cancel/jump/ledge exits and the ground dust
## spawned by each.
## Run: godot --headless --path . --script res://tests/locomotion_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const SETTLE_FRAMES := 30
## Skid slide from the release position at run speed (spec ~10-16 px).
const SLIDE_MIN := 9.0
const SLIDE_MAX := 16.0

var checks := 0
var failed: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _floor: StaticBody2D
## Dust spawned so far per kind (the effects free themselves quickly).
var _spawned := {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(func() -> void: _clock += root.get_process_delta_time())
	await _build_rig()
	await _case_run_and_skid()
	await _case_skid_hold_after_brake()
	await _case_turn()
	await _case_tap()
	await _case_skid_cancelled_by_input()
	await _case_jump_out_of_skid_and_turn()
	await _case_ledge_during_turn_and_skid()
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
	var release_x := _player.global_position.x
	Input.action_release(&"move_right")
	await _secs(0.05)
	check(_player._state == Player.State.SKID, "releasing at speed enters the skid")
	check(_dust_count(GroundDust.Kind.STOP) == 1, "the skid spawns stop dust")
	await _secs(0.3)
	check(_player._state == Player.State.IDLE and is_zero_approx(_player.velocity.x), "skid ends idle and still")
	var slide := _player.global_position.x - release_x
	check(slide >= SLIDE_MIN and slide <= SLIDE_MAX, "skid slides %.1f px from the release (spec %.0f-%.0f)" % [slide, SLIDE_MIN, SLIDE_MAX])


func _case_skid_hold_after_brake() -> void:
	await _fresh_rig()
	Input.action_press(&"move_right")
	await _secs(0.5)
	Input.action_release(&"move_right")
	# Past the brake but inside the hold: the pose must still be held.
	await _secs(_player.skid_brake_time + _player.skid_hold_time * 0.5)
	check(_player._state == Player.State.SKID, "the skid pose is held after the brake ends")
	await _secs(_player.skid_hold_time * 0.5 + 0.1)
	check(_player._state == Player.State.IDLE, "the skid relaxes to idle after the hold")


func _case_turn() -> void:
	await _fresh_rig()
	Input.action_press(&"move_right")
	await _secs(0.4)
	Input.action_release(&"move_right")
	await _secs(0.6)
	var turns_before := _dust_count(GroundDust.Kind.TURN)
	Input.action_press(&"move_left")
	await _secs(0.02)
	check(_player._state == Player.State.TURN, "starting opposite to the facing plays the turn")
	check(is_zero_approx(_player.velocity.x), "no movement during the turn")
	check(_dust_count(GroundDust.Kind.TURN) == turns_before + 1, "the turn spawns turn dust")
	await _secs(0.3)
	check(_player.velocity.x < 0.0, "runs left after the turn")
	Input.action_release(&"move_left")
	await _secs(0.5)


func _case_tap() -> void:
	await _fresh_rig()
	# Reach the skid speed threshold but release before skid_min_run_time.
	var threshold := _player.run_max_speed * _player.skid_min_speed_ratio
	Input.action_press(&"move_right")
	var guard := 0
	while absf(_player.velocity.x) < threshold and guard < 60:
		await process_frame
		guard += 1
	Input.action_release(&"move_right")
	check(_player._run_time < _player.skid_min_run_time, "the tap releases before the min run time (%.3f)" % _player._run_time)
	await _secs(0.03)
	check(_player._state != Player.State.SKID, "reaching speed for less than the min run time does not skid")
	check(absf(_player.velocity.x) < threshold, "a filtered tap still brakes normally")
	await _secs(0.4)


func _case_skid_cancelled_by_input() -> void:
	await _fresh_rig()
	await _run_then_release(Player.State.SKID)
	Input.action_press(&"move_right")
	await _secs(0.05)
	check(_player._state != Player.State.SKID, "new input cancels the skid")
	check(_player.velocity.x > 0.0, "the player moves again after the cancelled skid")
	Input.action_release(&"move_right")
	await _secs(0.6)


func _case_jump_out_of_skid_and_turn() -> void:
	await _fresh_rig()
	await _run_then_release(Player.State.SKID)
	Input.action_press(&"jump")
	await _secs(0.05)
	check(_player._state == Player.State.JUMP and _player.velocity.y < 0.0, "jump leaves the skid")
	Input.action_release(&"jump")
	await _secs(1.0)

	await _fresh_rig()
	Input.action_press(&"move_right")
	await _secs(0.3)
	Input.action_release(&"move_right")
	await _secs(0.6)
	Input.action_press(&"move_left")
	await _secs(0.02)
	check(_player._state == Player.State.TURN, "setup: the turn is playing")
	Input.action_press(&"jump")
	await _secs(0.05)
	check(_player._state == Player.State.JUMP and _player.velocity.y < 0.0, "jump leaves the turn")
	Input.action_release(&"jump")
	Input.action_release(&"move_left")
	await _secs(1.0)


func _case_ledge_during_turn_and_skid() -> void:
	await _fresh_rig()
	await _run_then_release(Player.State.SKID)
	_floor.queue_free()
	await _secs(0.1)
	check(_player._state == Player.State.FALL, "losing the ground during the skid goes to fall")

	await _fresh_rig()
	Input.action_press(&"move_right")
	await _secs(0.3)
	Input.action_release(&"move_right")
	await _secs(0.6)
	Input.action_press(&"move_left")
	await _secs(0.02)
	check(_player._state == Player.State.TURN, "setup: the turn is playing")
	_floor.queue_free()
	await _secs(0.1)
	check(_player._state == Player.State.FALL, "losing the ground during the turn goes to fall")
	Input.action_release(&"move_left")


## Runs at full speed, releases and waits until the player is in `state`.
func _run_then_release(state: Player.State) -> void:
	Input.action_press(&"move_right")
	await _secs(0.5)
	Input.action_release(&"move_right")
	await _secs(0.05)
	check(_player._state == state, "setup: reached state %d" % state)


func _dust_count(kind: GroundDust.Kind) -> int:
	return _spawned.get(kind, 0)


func _on_child_entered(child: Node) -> void:
	if child is GroundDust:
		var kind := (child as GroundDust).kind
		_spawned[kind] = _spawned.get(kind, 0) + 1


## Replaces the rig with a clean one so cases never inherit state.
func _fresh_rig() -> void:
	_rig.free()
	await _build_rig()


func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	_rig.child_entered_tree.connect(_on_child_entered)
	_floor = LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_rig.add_child(_player)
	for i in SETTLE_FRAMES:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame

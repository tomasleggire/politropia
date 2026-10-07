extends SceneTree
## Regression test for the gated double jump: off by default, one air jump per
## airborne period once unlocked, resets, the jump buffer and the unlock signal.
## Run: godot --headless --path . --script res://tests/double_jump_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const TAP_FRAMES := 2
const APEX_DELAY := 0.36
const FULL_JUMP := 130.0
const DOUBLE_JUMP_PEAK := 260.0
const PEAK_TOLERANCE := 15.0
## Anything launched by a jump leaves the player well above this upward speed.
const LAUNCH_SPEED := -500.0
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const LEDGE_FLOOR_RECT := Rect2(-3000.0, 0.0, 3200.0, 200.0)
const WALL_RECT := Rect2(300.0, -600.0, 80.0, 600.0)

const CHECKS := {
	"case_default_off": 3,
	"case_unlocked_relaunch": 3,
	"case_air_jump_count": 4,
	"case_resets_on_landing": 2,
	"case_resets_on_wall_cling": 2,
	"case_ledge_fall_keeps_air_jump": 2,
	"case_buffered_press_is_ground_jump": 3,
	"case_dash_and_double_jump": 4,
	"case_unlock_signal": 4,
	"case_respawn_resets": 2,
	"case_input_locked": 1,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _peak := 0.0
var _unlock_emissions: Array[StringName] = []


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
	_release_all()
	_free_rig()
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


# -- Rig and input helpers --------------------------------------------------------

## Builds a flat floor (top at y=0) with Luz standing at `start_x`, plus the
## optional extra solids, and waits for her to settle.
func _build_rig(start_x: float, floor_rect: Rect2 = FLOOR_RECT, extra: Array[Rect2] = []) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	for rect: Rect2 in extra:
		LevelGeometry.add_solid(_rig, rect, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, 0.0)
	_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


## Like _secs, recording the highest point (smallest y) reached meanwhile.
func _secs_tracking_peak(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame
		_peak = minf(_peak, _player.global_position.y)


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(TAP_FRAMES)
	Input.action_release(action)


## Starts a held ground jump and tracks the peak from here on.
func _start_jump() -> void:
	_peak = _player.global_position.y
	Input.action_press(&"jump")
	await _frames(TAP_FRAMES)


## Releases the jump key (cutting nothing near the apex) and presses it again.
func _second_press(hold: float) -> void:
	Input.action_release(&"jump")
	await _frames(TAP_FRAMES)
	Input.action_press(&"jump")
	await _secs_tracking_peak(hold)
	Input.action_release(&"jump")


## Full ground jump held to the apex, then a second press held for `hold`.
func _jump_and_second_press(hold: float) -> void:
	await _start_jump()
	await _secs_tracking_peak(APEX_DELAY)
	await _second_press(hold)


## Presses jump, reads the vertical speed one frame later (before any release
## cut) and releases.
func _press_and_read_vy() -> float:
	Input.action_press(&"jump")
	await physics_frame
	await physics_frame
	var vy := _player.velocity.y
	Input.action_release(&"jump")
	await physics_frame
	return vy


func _rise() -> float:
	return -_peak


func _near(value: float, expected: float) -> bool:
	return absf(value - expected) <= PEAK_TOLERANCE


# -- Cases -----------------------------------------------------------------------

func case_default_off() -> void:
	await _build_rig(0.0)
	check(not _player.has_double_jump(), "double jump is off by default")
	await _jump_and_second_press(0.6)
	check(_rise() < FULL_JUMP + 10.0, "second press does nothing while locked (rise %.0f)" % _rise())
	await _secs(1.0)
	check(_player.is_on_floor(), "player lands after the single jump")


func case_unlocked_relaunch() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	await _start_jump()
	await _secs_tracking_peak(APEX_DELAY)
	Input.action_release(&"jump")
	await _frames(TAP_FRAMES)
	Input.action_press(&"jump")
	await physics_frame
	await physics_frame
	check(_player.velocity.y < LAUNCH_SPEED, "the press relaunches at once (vy %.0f)" % _player.velocity.y)
	await _secs_tracking_peak(0.6)
	Input.action_release(&"jump")
	check(_near(_rise(), DOUBLE_JUMP_PEAK), "peak is about jump + double_jump_height (rise %.0f)" % _rise())
	check(_player.has_double_jump(), "has_double_jump reports true")


func case_air_jump_count() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	await _jump_and_second_press(0.15)
	Input.action_release(&"jump")
	await _secs(0.5)
	var third_vy := await _press_and_read_vy()
	check(third_vy > 0.0, "a third press with one air jump does nothing (vy %.0f)" % third_vy)
	_free_rig()
	await _build_rig(0.0)
	_player.air_jumps = 2
	_player.unlock_double_jump()
	await _jump_and_second_press(0.15)
	Input.action_release(&"jump")
	await _secs(0.5)
	var vy := await _press_and_read_vy()
	check(vy < LAUNCH_SPEED, "air_jumps = 2 allows a third jump (vy %.0f)" % vy)
	await _secs(0.3)
	vy = await _press_and_read_vy()
	check(vy > LAUNCH_SPEED, "a fourth press with two air jumps does nothing (vy %.0f)" % vy)
	check(not _player.is_on_floor(), "still airborne after the extra jumps")


func case_resets_on_landing() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	await _jump_and_second_press(0.15)
	Input.action_release(&"jump")
	await _secs(1.5)
	check(_player.is_on_floor(), "landed after spending the air jump")
	await _jump_and_second_press(0.6)
	check(_near(_rise(), DOUBLE_JUMP_PEAK), "the air jump is back after landing (rise %.0f)" % _rise())


func case_resets_on_wall_cling() -> void:
	await _build_rig(240.0, FLOOR_RECT, [WALL_RECT])
	_player.unlock_double_jump()
	Input.action_press(&"move_right")
	await _jump_and_second_press(0.15)
	Input.action_release(&"jump")
	var clung := false
	var end := _clock + 2.0
	while _clock < end and not clung:
		await process_frame
		clung = _player._state == Player.State.WALL_CLING
	check(clung, "the player clings to the wall after both jumps")
	Input.action_release(&"move_right")
	await _frames(4)
	var vy := await _press_and_read_vy()
	check(vy < LAUNCH_SPEED, "clinging gave the air jump back (vy %.0f)" % vy)


func case_ledge_fall_keeps_air_jump() -> void:
	await _build_rig(100.0, LEDGE_FLOOR_RECT)
	_player.unlock_double_jump()
	Input.action_press(&"move_right")
	await _secs(1.0)
	Input.action_release(&"move_right")
	check(not _player.is_on_floor() and _player.velocity.y > 0.0, "the player walked off the ledge and is falling")
	var vy := await _press_and_read_vy()
	check(vy < LAUNCH_SPEED, "falling off a ledge keeps the air jump (vy %.0f)" % vy)


func case_buffered_press_is_ground_jump() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	_player.global_position.y = -6.0
	_player._jump_buffer_left = _player.jump_buffer_time
	await _frames(3)
	check(_player.is_on_floor() or _player.velocity.y < 0.0, "the player reached the floor or already left it")
	_peak = _player.global_position.y
	await _secs_tracking_peak(APEX_DELAY)
	check(_rise() < FULL_JUMP + 15.0, "the stale buffered press became a normal ground jump (rise %.0f)" % _rise())
	await _second_press(0.6)
	check(_rise() > DOUBLE_JUMP_PEAK - PEAK_TOLERANCE, "the landing press did not spend the air jump (rise %.0f)" % _rise())


func case_dash_and_double_jump() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	Input.action_press(&"move_right")
	await _start_jump()
	await _secs(0.15)
	var x_before := _player.global_position.x
	await _tap(&"dash")
	await _secs(0.25)
	check(_player._state == Player.State.DASH and _player.global_position.x - x_before > 60.0, "air dash happens in the same period")
	Input.action_release(&"jump")
	await _secs(0.3)
	var vy := await _press_and_read_vy()
	check(vy < LAUNCH_SPEED, "double jump still works after the air dash (vy %.0f)" % vy)
	await _tap(&"dash")
	await _frames(2)
	check(_player._state != Player.State.DASH, "a second air dash stays blocked")
	_free_rig()
	await _build_rig(0.0)
	_player.unlock_double_jump()
	Input.action_press(&"move_right")
	await _jump_and_second_press(0.1)
	x_before = _player.global_position.x
	await _tap(&"dash")
	await _secs(0.25)
	check(_player.global_position.x - x_before > 60.0, "air dash works after the double jump")


func case_unlock_signal() -> void:
	await _build_rig(0.0)
	_unlock_emissions.clear()
	_player.ability_unlocked.connect(func(ability: StringName) -> void: _unlock_emissions.append(ability))
	_player.unlock_double_jump()
	await _frames(2)
	check(_unlock_emissions.size() == 1, "ability_unlocked fires once (%d)" % _unlock_emissions.size())
	check(_unlock_emissions[0] == &"double_jump", "the signal names double_jump")
	check(_player.has_double_jump(), "the ability is on after unlocking")
	check(_player.can_double_jump, "the exported flag reflects the unlock")


func case_respawn_resets() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	await _jump_and_second_press(0.15)
	Input.action_release(&"jump")
	check(_player._air_jumps_left == 0, "the air jump is spent")
	_player.respawn()
	check(_player._air_jumps_left == _player.air_jumps, "respawn restores the air jump")


func case_input_locked() -> void:
	await _build_rig(0.0)
	_player.unlock_double_jump()
	await _start_jump()
	await _secs(APEX_DELAY)
	Input.action_release(&"jump")
	_player.set_input_locked(true)
	await _frames(TAP_FRAMES)
	await _tap(&"jump")
	await physics_frame
	await physics_frame
	check(_player.velocity.y > LAUNCH_SPEED, "no air jump fires while input is locked (vy %.0f)" % _player.velocity.y)

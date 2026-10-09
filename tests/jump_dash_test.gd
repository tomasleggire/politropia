extends SceneTree
## Regression test for the Penitent-matched jump and dash: jump height, apex
## time, tap minimum, constant air speed, the standing landing recovery and its
## jump cancel, running landings, the ground dash profile (lean-back, distance
## from rest and from a run, ledge), the air dash and the afterimages and dust.
## Numbers come from tools/art_sources/luz/reference/penitent_jump_dash_reference.md.
## Run: godot --headless --path . --script res://tests/jump_dash_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran. Time is counted in physics ticks (1/60 s).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const LEDGE_FLOOR_RECT := Rect2(-3000.0, 0.0, 3200.0, 200.0)

const CHECKS := {
	"case_full_jump": 5,
	"case_tap_jump": 4,
	"case_air_speed": 4,
	"case_standing_landing": 6,
	"case_running_landing": 3,
	"case_dash_from_rest": 7,
	"case_dash_from_run": 3,
	"case_dash_afterimages": 7,
	"case_dash_ledge": 2,
	"case_air_dash": 3,
	"case_wall_kick_height": 2,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _ticks := 0
var _rig: Node2D
var _player: Player
## Per physics tick: [t, x, y, vx, vy, state].
var _trace: Array = []
## Largest number of afterimages alive at once and their observed lives.
var _ghost_peak := 0
var _ghost_born := {}
var _ghost_lives: Array[float] = []
var _ghost_spawn_times: Array[float] = []
var _dust := {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	physics_frame.connect(_on_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _on_tick() -> void:
	_ticks += 1
	if _player == null or not is_instance_valid(_player):
		return
	_trace.append([_now(), _player.global_position.x, _player.global_position.y,
		_player.velocity.x, _player.velocity.y, _player._state])
	_watch_ghosts()


func _now() -> float:
	return float(_ticks) / float(Engine.physics_ticks_per_second)


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


# -- Rig and measuring helpers ------------------------------------------------------

func _build_rig(floor_rect: Rect2 = FLOOR_RECT, extra: Array[Rect2] = []) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	for rect: Rect2 in extra:
		LevelGeometry.add_solid(_rig, rect, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(0.0, 0.0)
	_rig.add_child(_player)
	_rig.child_entered_tree.connect(_on_rig_child)
	_ghost_peak = 0
	_ghost_born.clear()
	_ghost_lives.clear()
	_ghost_spawn_times.clear()
	_dust.clear()
	await _ticks_wait(SETTLE_FRAMES)
	_trace.clear()


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_trace.clear()


func _on_rig_child(child: Node) -> void:
	if child is GroundDust:
		var kind := (child as GroundDust).kind
		_dust[kind] = int(_dust.get(kind, 0)) + 1


## Tracks every DashAfterimage under the rig: births, lives and the peak alive.
func _watch_ghosts() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	var alive := 0
	var seen := {}
	for child: Node in _rig.get_children():
		if child is DashAfterimage:
			alive += 1
			var id := child.get_instance_id()
			seen[id] = true
			if not _ghost_born.has(id):
				_ghost_born[id] = _now()
				_ghost_spawn_times.append(_now())
	for id: int in _ghost_born.keys():
		if not seen.has(id):
			_ghost_lives.append(_now() - float(_ghost_born[id]))
			_ghost_born.erase(id)
	_ghost_peak = maxi(_ghost_peak, alive)


func _ticks_wait(n: int) -> void:
	for i: int in n:
		await physics_frame


func _secs(t: float) -> void:
	await _ticks_wait(roundi(t * float(Engine.physics_ticks_per_second)))


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


## Highest point reached so far in the trace (a positive rise above the floor y=0).
func _peak_rise() -> float:
	var best := 0.0
	for row: Array in _trace:
		best = maxf(best, -float(row[2]))
	return best


## Time of the highest point since the trace start.
func _apex_time() -> float:
	var best := 0.0
	var at := 0.0
	for row: Array in _trace:
		if -float(row[2]) > best:
			best = -float(row[2])
			at = float(row[0])
	return at


func _x_range() -> float:
	return float(_trace[_trace.size() - 1][1]) - float(_trace[0][1])


## Waits until she stands on the floor again (or the timeout), keeping the trace.
func _wait_landing(timeout: float) -> void:
	var end := _now() + timeout
	while _now() < end:
		await physics_frame
		if _player.is_on_floor() and _now() > 0.2 + float(_trace[0][0]):
			return


## A held full jump from rest: records the trace from the press.
func _full_jump() -> void:
	_trace.clear()
	Input.action_press(&"jump")
	await _secs(0.7)
	Input.action_release(&"jump")
	await _wait_landing(1.0)


# -- Cases ---------------------------------------------------------------------------

func case_full_jump() -> void:
	await _build_rig()
	var start := _now()
	await _full_jump()
	var rise := _peak_rise()
	check(absf(rise - 87.0) <= 2.5, "full jump rises 87 px (%.1f)" % rise)
	var apex := _apex_time() - start
	check(absf(apex - 0.45) <= 0.04, "time to apex 0.45 s (%.3f)" % apex)
	# Airtime: from the first tick above the floor to the landing.
	var first := 0.0
	var last := 0.0
	for row: Array in _trace:
		if float(row[2]) < -1.0:
			if first == 0.0:
				first = float(row[0])
			last = float(row[0])
	var airtime := last - first
	check(airtime >= 0.80 and airtime <= 0.90, "airtime 0.82-0.88 s (%.3f)" % airtime)
	var left_floor_after := first - start
	check(left_floor_after <= 0.06, "no takeoff anticipation: airborne %.3f s after the press" % left_floor_after)
	var fall := last - _apex_time()
	check(fall >= 0.38 and fall <= 0.45, "fall takes 0.40-0.42 s (%.3f)" % fall)


func case_tap_jump() -> void:
	await _build_rig()
	_trace.clear()
	Input.action_press(&"jump")
	await _ticks_wait(2)
	Input.action_release(&"jump")
	await _secs(1.0)
	var tap := _peak_rise()
	check(tap >= 72.0 and tap <= 77.0, "a tap reaches ~0.85 of a full jump, 74 px (%.1f)" % tap)
	check(tap / 87.0 >= 0.8 and tap / 87.0 <= 0.9, "tap is 0.8-0.9 of full (%.2f)" % (tap / 87.0))
	# Any release inside the minimum hold gives the same height.
	await _wait_landing(1.0)
	_trace.clear()
	Input.action_press(&"jump")
	await _secs(_player.jump_min_hold_time * 0.8)
	Input.action_release(&"jump")
	await _secs(1.0)
	var late_tap := _peak_rise()
	check(absf(late_tap - tap) <= 3.0, "a release at 80%% of the minimum hold equals the tap (%.1f vs %.1f)" % [late_tap, tap])
	await _wait_landing(1.0)
	_trace.clear()
	Input.action_press(&"jump")
	await _secs(_player.jump_min_hold_time + 0.1)
	Input.action_release(&"jump")
	await _secs(1.0)
	var released := _peak_rise()
	check(released > tap + 2.0 and released < 87.0, "a release after the minimum still cuts the rise (%.1f)" % released)


func case_air_speed() -> void:
	await _build_rig()
	Input.action_press(&"move_right")
	await _secs(0.4)
	_trace.clear()
	Input.action_press(&"jump")
	await _secs(0.7)
	Input.action_release(&"jump")
	await _wait_landing(1.0)
	var air_min := 9999.0
	var air_max := 0.0
	var first_air_tick := 0
	var last_air_tick := 0
	for i in _trace.size():
		if float(_trace[i][2]) < -4.0:
			if first_air_tick == 0:
				first_air_tick = i
			last_air_tick = i
			var vx := absf(float(_trace[i][3]))
			air_min = minf(air_min, vx)
			air_max = maxf(air_max, vx)
	check(air_min >= 150.0 and air_max <= 164.0, "air speed stays 157 +-7 through the jump (%.0f-%.0f)" % [air_min, air_max])
	check(is_equal_approx(_player.air_max_speed, _player.run_max_speed), "air_max_speed equals run_max_speed")
	var distance := float(_trace[last_air_tick][1]) - float(_trace[first_air_tick][1])
	check(distance >= 125.0 and distance <= 145.0, "running jump covers ~130-135 px (%.0f)" % distance)
	check(_player.velocity.x > 100.0 and _player._state == Player.State.RUN, "a running landing keeps running")


func case_standing_landing() -> void:
	await _build_rig()
	await _full_jump()
	# Landed standing: planted for the recovery.
	check(_player._landing_left > 0.0, "a standing landing starts the recovery")
	var landed_x := _player.global_position.x
	Input.action_press(&"move_right")
	await _secs(0.1)
	check(is_equal_approx(_player.global_position.x, landed_x), "movement is locked during the recovery")
	# A jump pressed at 0.1 s is held in the buffer and fires when the cancel opens (0.18 s).
	Input.action_press(&"jump")
	await _ticks_wait(2)
	Input.action_release(&"jump")
	check(_player.is_on_floor(), "a jump before the cancel time does not fire yet")
	await _secs(0.12)
	check(not _player.is_on_floor() and _player.velocity.y < 0.0, "the buffered jump fires once the cancel opens (vy %.0f)" % _player.velocity.y)
	Input.action_release(&"move_right")
	await _wait_landing(2.0)
	# Recovery length: standing, wait for the whole recovery with no input.
	await _secs(0.1)
	var locked_for := 0.0
	var t0 := _now()
	Input.action_press(&"move_right")
	while _player.global_position.x <= landed_x + 120.0 and _now() - t0 < 1.0:
		await physics_frame
		if absf(_player.velocity.x) < 1.0:
			locked_for = _now() - t0
	check(locked_for > 0.0, "she stays planted while the recovery runs (%.2f s)" % locked_for)
	await _secs(0.6)
	check(_player.velocity.x > 100.0, "she runs again once the recovery has ended")


func case_running_landing() -> void:
	await _build_rig()
	Input.action_press(&"move_right")
	await _secs(0.4)
	Input.action_press(&"jump")
	await _secs(0.7)
	Input.action_release(&"jump")
	await _wait_landing(1.0)
	check(_player._landing_left <= 0.0, "no recovery after a running landing")
	await _ticks_wait(3)
	check(_player.velocity.x > 150.0, "the speed survives the landing (%.0f)" % _player.velocity.x)
	check(_player._state == Player.State.RUN, "she is running right after landing")


func case_dash_from_rest() -> void:
	await _build_rig()
	_trace.clear()
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	var start := _now() - 2.0 / 60.0
	await _secs(0.07)
	check(absf(_player.global_position.x) < 1.0 and _player._state == Player.State.DASH, "lean-back: no forward motion for the first 0.07 s (x %.1f)" % _player.global_position.x)
	await _secs(0.5)
	var distance := _player.global_position.x
	check(distance >= 124.0 and distance <= 140.0, "dash from rest covers ~129 px, the Penitent's 120 + brake (%.1f)" % distance)
	var peak_speed := 0.0
	var plateau_ticks := 0
	for row: Array in _trace:
		peak_speed = maxf(peak_speed, absf(float(row[3])))
		if absf(float(row[3])) >= 390.0:
			plateau_ticks += 1
	check(absf(peak_speed - 395.0) <= 6.0, "plateau speed ~395 px/s (%.0f)" % peak_speed)
	var plateau := float(plateau_ticks) / 60.0
	check(plateau >= 0.15 and plateau <= 0.26, "plateau lasts ~0.2 s between the ramp and the ease-out (%.2f)" % plateau)
	var slide_end := 0.0
	for row: Array in _trace:
		if int(row[5]) == Player.State.DASH:
			slide_end = float(row[0])
	var total := slide_end - start
	check(total >= 0.46 and total <= 0.56, "lean-back + slide last ~0.5 s (%.2f)" % total)
	check(_dust.get(GroundDust.Kind.DASH_START, 0) == 1 and _dust.get(GroundDust.Kind.DASH_END, 0) == 1, "one start puff and one end fan")
	check(_player.get_node("CollisionShape2D").shape.size.y > 40.0, "the standing collider is back after the dash")


func case_dash_from_run() -> void:
	await _build_rig()
	Input.action_press(&"move_right")
	await _secs(0.5)
	var from_x := _player.global_position.x
	_trace.clear()
	# The run key is released with the dash press: the slide and its brake are measured.
	Input.action_release(&"move_right")
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	await _secs(0.12)
	check(absf(_player.velocity.x) > 150.0 and _player._state == Player.State.DASH, "from a run there is no lean-back stop (vx %.0f)" % _player.velocity.x)
	await _secs(0.7)
	var distance := _player.global_position.x - from_x
	check(distance >= 130.0 and distance <= 146.0, "dash from a run covers ~138 px (%.1f)" % distance)
	var low_scale := _player.crouch_collider_scale
	check(low_scale <= 0.55, "the slide uses the low collider (scale %.2f)" % low_scale)


func case_dash_afterimages() -> void:
	await _build_rig()
	Input.action_press(&"move_right")
	await _secs(0.4)
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	await _secs(0.9)
	check(_ghost_peak >= 3 and _ghost_peak <= 6, "4-5 afterimages alive at once (%d)" % _ghost_peak)
	var life_sum := 0.0
	for life in _ghost_lives:
		life_sum += life
	var mean_life := life_sum / maxf(float(_ghost_lives.size()), 1.0)
	check(absf(mean_life - 0.14) <= 0.03, "each ghost lives ~0.14 s (%.3f over %d)" % [mean_life, _ghost_lives.size()])
	var gaps := 0.0
	for i in range(1, _ghost_spawn_times.size()):
		gaps += _ghost_spawn_times[i] - _ghost_spawn_times[i - 1]
	var mean_gap := gaps / maxf(float(_ghost_spawn_times.size() - 1), 1.0)
	check(absf(mean_gap - 0.033) <= 0.012, "a ghost every ~2 frames (%.3f s)" % mean_gap)
	check(_ghost_born.is_empty(), "every ghost is gone after the dash")
	check(_ghost_spawn_times.size() >= 9, "the dash leaves a trail (%d ghosts)" % _ghost_spawn_times.size())
	var scene := load("res://scenes/vfx/dash_afterimage.tscn") as PackedScene
	var ghost := scene.instantiate() as DashAfterimage
	check(ghost.color.b > ghost.color.r and ghost.color.b > 0.7, "the default ghost color is a cool blue (%s)" % ghost.color)
	check(ghost.lifetime > 0.0 and ghost.start_alpha > ghost.end_alpha, "life and alpha fade are inspector values")
	ghost.free()


func case_dash_ledge() -> void:
	await _build_rig(LEDGE_FLOOR_RECT)
	_player.global_position = Vector2(150.0, 0.0)
	await _ticks_wait(10)
	Input.action_press(&"move_right")
	await _secs(0.3)
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	var fell := false
	var end := _now() + 1.0
	while _now() < end and not fell:
		await physics_frame
		fell = not _player.is_on_floor() and _player._state == Player.State.FALL
	check(fell, "a dash that reaches a ledge ends and she falls")
	Input.action_release(&"move_right")
	await _secs(0.4)
	check(_player.global_position.y > 20.0, "and keeps falling off the ledge (y %.0f)" % _player.global_position.y)


func case_air_dash() -> void:
	await _build_rig()
	Input.action_press(&"jump")
	await _secs(0.25)
	Input.action_release(&"jump")
	var from_x := _player.global_position.x
	var from_y := _player.global_position.y
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	await _secs(0.35)
	var distance := _player.global_position.x - from_x
	# 118 px of dash plus the speed bleeding off in the air with no input held.
	check(distance >= 115.0 and distance <= 150.0, "air dash covers ~118 px plus the bleed (%.0f)" % distance)
	check(absf(_player.global_position.y - from_y) <= 6.0, "gravity is suspended during the air dash (dy %.1f)" % (_player.global_position.y - from_y))
	Input.action_press(&"dash")
	await _ticks_wait(2)
	Input.action_release(&"dash")
	await _ticks_wait(2)
	check(_player._state != Player.State.DASH, "only one air dash per airborne period")


func case_wall_kick_height() -> void:
	var wall := Rect2(60.0, -600.0, 80.0, 600.0)
	await _build_rig(FLOOR_RECT, [wall])
	_player.global_position = Vector2(30.0, 0.0)
	await _ticks_wait(5)
	Input.action_press(&"move_right")
	Input.action_press(&"jump")
	var clung_y := 0.0
	var end := _now() + 1.5
	while _now() < end and _player._state != Player.State.WALL_CLING:
		await physics_frame
	clung_y = _player.global_position.y
	Input.action_release(&"jump")
	await _ticks_wait(2)
	Input.action_press(&"jump")
	await _ticks_wait(2)
	var kick_start_y := _player.global_position.y
	var highest := kick_start_y
	end = _now() + 0.9
	while _now() < end:
		await physics_frame
		highest = minf(highest, _player.global_position.y)
	var climb := kick_start_y - highest
	check(_player._wall_kick_wall_direction == 1 or clung_y < 0.0, "she clung to the wall (y %.0f)" % clung_y)
	check(climb >= 70.0 and climb <= 125.0, "a wall kick climbs ~99 px (%.0f)" % climb)

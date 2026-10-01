extends SceneTree
## Regression test for the pogo down slash that replaced the plunge: bouncing
## off an enemy and off a hazard, the restored air actions, the hazard grace
## window, a missed slash hurting as usual, the grounded down attack staying a
## crouch attack and the touch paths into the down slash.
## Run: godot --headless --path . --script res://tests/pogo_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WALKER_SCENE := "res://scenes/enemies/walker.tscn"
const CONTACT_SCENE := "res://scenes/world/contact_damage.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const HAZARD_RECT := Rect2(-48.0, -16.0, 96.0, 16.0)
const FAR_HAZARD_RECT := Rect2(500.0, -16.0, 96.0, 16.0)
## Luz waits here, far from the hazard, so a safe-ground return is detectable.
const START_X := -300.0
const ABOVE_WALKER := Vector2(0.0, -75.0)
const ABOVE_HAZARD := Vector2(0.0, -50.0)
const POGO_HEIGHT := 130.0
const PEAK_TOLERANCE := 14.0
## A bounce launches far faster upward than any fall or hop.
const BOUNCE_SPEED := -300.0
## Physics steps: long enough for the whole rise (about 26), short of the fall
## back onto the target (about 46).
const BOUNCE_STEPS := 32

const CHECKS := {
	"case_plunge_is_gone": 4,
	"case_pogo_off_walker": 8,
	"case_pogo_height_ignores_jump_release": 2,
	"case_pogo_off_hazard": 6,
	"case_missed_slash_hurts": 3,
	"case_lateral_slash_does_not_pogo": 3,
	"case_grace_window": 4,
	"case_slash_covering_a_hazard_wins": 5,
	"case_ground_down_attack_is_a_crouch_attack": 5,
	"case_touch_paths": 4,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _walker: Walker
var _max_veil := 0.0
var _was_returning := false


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
	root.get_node("EnemyRegistry").clear()
	root.get_node("CheckpointService").clear()
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


# -- Rig and helpers -----------------------------------------------------------------

## A flat floor (top at y=0) with Luz standing at `start_x`, settled.
func _build_rig(start_x := START_X) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, 0.0)
	_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


func _add_walker(at: Vector2) -> void:
	_walker = (load(WALKER_SCENE) as PackedScene).instantiate() as Walker
	_walker.enemy_id = &"w1"
	_walker.walk_speed = 0.0
	_walker.position = at
	_rig.add_child(_walker)


func _add_hazard(rect: Rect2) -> ContactDamage:
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	hazard.kind = ContactDamage.Kind.HAZARD
	_rig.add_child(hazard)
	hazard.set_area_size(rect.size)
	hazard.position = rect.get_center()
	return hazard


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_walker = null
	_max_veil = 0.0
	_was_returning = false


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash"]:
		Input.action_release(action)


## Places her in the air and lets one physics step pass, so she no longer
## counts as being on the floor.
func _drop_player_at(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	for i: int in 3:
		await physics_frame


func _veil_alpha() -> float:
	var veils := _player.find_children("*", "ScreenFade", true, false)
	return 0.0 if veils.is_empty() else (veils[0] as ScreenFade).get_alpha()


## Watches Luz for `steps` physics steps and reports the bounce: the y where she was first
## launched upward, the highest point afterwards and the darkest veil seen.
func _watch_bounce(steps: int) -> Dictionary:
	var seen := {"bounced": false, "start_y": 0.0, "peak_y": 1e9}
	for i: int in steps:
		await physics_frame
		if not seen["bounced"] and _player.velocity.y < BOUNCE_SPEED:
			seen["bounced"] = true
			seen["start_y"] = _player.global_position.y
		if seen["bounced"]:
			seen["peak_y"] = minf(seen["peak_y"], _player.global_position.y)
		_max_veil = maxf(_max_veil, _veil_alpha())
		_was_returning = _was_returning or _player.is_returning_to_safe_ground()
	return seen


# -- Cases -----------------------------------------------------------------------

func case_plunge_is_gone() -> void:
	var states: Array = Player.State.keys()
	check(not states.has("PLUNGE") and not states.has("PLUNGE_LAND"), "the plunge states no longer exist: %s" % [states])
	await _build_rig()
	await _drop_player_at(Vector2(START_X, -200.0))
	Input.action_press(&"move_down")
	_player.request_attack(0)
	await _frames(2)
	check(_player._state == Player.State.AIR_ATTACK, "down + attack in the air starts the air attack state")
	check(_player._air_attack_down, "and it is the down slash")
	await _secs(0.2)
	check(_player._state != Player.State.AIR_ATTACK or _player._air_attack_down, "it never degrades into a plunge")


func case_pogo_off_walker() -> void:
	await _build_rig()
	_add_walker(Vector2.ZERO)
	_player.can_double_jump = true
	await _frames(SETTLE_FRAMES)
	await _drop_player_at(Vector2(0.0, ABOVE_WALKER.y))
	_player._air_dash_used = true
	_player._air_jumps_left = 0
	Input.action_press(&"move_down")
	_player.request_attack(1)
	# Stops at the apex: falling back onto the walker would hurt, as it should.
	var seen := await _watch_bounce(BOUNCE_STEPS)
	check(seen["bounced"], "the down slash bounces her up")
	check(_walker.get_health() == 1, "and the walker took the hit (%d)" % _walker.get_health())
	check(not _player._air_dash_used, "the air dash is back")
	check(_player._air_jumps_left == _player.air_jumps, "and so is the double jump (%d)" % _player._air_jumps_left)
	var rise: float = seen["start_y"] - seen["peak_y"]
	check(absf(rise - POGO_HEIGHT) < PEAK_TOLERANCE, "the bounce rises about %.0f px (%.1f)" % [POGO_HEIGHT, rise])
	check(_player.get_health() == 3, "she took no damage")
	Input.action_release(&"move_down")
	_player.request_jump()
	for i: int in 3:
		await physics_frame
	check(_player._air_jumps_left == 0, "the restored double jump can be spent")
	check(Engine.time_scale == 1.0, "Engine.time_scale is untouched")


func case_pogo_height_ignores_jump_release() -> void:
	await _build_rig()
	_add_walker(Vector2.ZERO)
	await _frames(SETTLE_FRAMES)
	await _drop_player_at(Vector2(0.0, ABOVE_WALKER.y))
	Input.action_press(&"jump")
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var releasing := true
	var peak := 1e9
	var start_y := 0.0
	var end := _clock + 0.8
	while _clock < end:
		await process_frame
		if releasing and _player.velocity.y < BOUNCE_SPEED:
			start_y = _player.global_position.y
			Input.action_release(&"jump")
			releasing = false
		if not releasing:
			peak = minf(peak, _player.global_position.y)
	check(not releasing, "the bounce happened")
	check(absf((start_y - peak) - POGO_HEIGHT) < PEAK_TOLERANCE, "releasing jump during the bounce does not shorten it (%.1f)" % (start_y - peak))


func case_pogo_off_hazard() -> void:
	await _build_rig()
	var hazard := _add_hazard(HAZARD_RECT)
	check(hazard.collision_layer == ContactDamage.POGO_LAYER and hazard.is_in_group(&"pogoable"), "a hazard is on the pogoable layer and group")
	_player._air_dash_used = true
	await _drop_player_at(Vector2(0.0, ABOVE_HAZARD.y))
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var seen := await _watch_bounce(BOUNCE_STEPS)
	check(seen["bounced"], "the down slash bounces off the spike")
	check(_player.get_health() == 3, "with no hazard damage (%d)" % _player.get_health())
	check(_max_veil == 0.0 and not _was_returning, "and no safe-ground return (veil %.2f)" % _max_veil)
	check(absf(_player.global_position.x) < 20.0, "she is still above the spike, not back at the start (x %.0f)" % _player.global_position.x)
	check(not _player._air_dash_used, "the air dash is back")


func case_missed_slash_hurts() -> void:
	await _build_rig()
	_add_hazard(HAZARD_RECT)
	await _drop_player_at(Vector2(0.0, ABOVE_HAZARD.y))
	await _secs(1.0)
	check(_player.get_health() == 2, "landing on the strip without a slash costs one pip (%d)" % _player.get_health())
	check(_player.global_position.distance_to(Vector2(START_X, 0.0)) < 4.0, "and returns her to the last safe ground (%s)" % _player.global_position)
	check(not _player._pogo_bounced, "no pogo happened")


func case_lateral_slash_does_not_pogo() -> void:
	await _build_rig()
	_add_hazard(HAZARD_RECT)
	await _drop_player_at(Vector2(0.0, ABOVE_HAZARD.y))
	_player.request_attack(0)
	await _secs(1.0)
	check(not _player._air_attack_down, "a neutral air attack is the lateral slash")
	check(_player.get_health() == 2, "and the strip hurts as usual (%d)" % _player.get_health())
	check(not _player._pogo_bounced, "with no bounce")


func case_grace_window() -> void:
	await _build_rig()
	var hazard := _add_hazard(HAZARD_RECT)
	await _drop_player_at(Vector2(0.0, ABOVE_HAZARD.y))
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var seen := await _watch_bounce(6)
	check(seen["bounced"] and _player._pogo_grace_left > 0.0, "the pogo opens the grace window")
	check(not _player.take_hazard_damage(1, hazard.global_position), "hazard damage inside the window is refused")
	check(_player.get_health() == 3, "and costs nothing")
	await _secs(_player.pogo_grace_time + 0.1)
	check(_player.take_hazard_damage(1, hazard.global_position), "once the window closes the hazard hurts again")


## The player's own processing is paused so the exact order of events is
## forced: the slash is active over the spike and the body's damage arrives
## before the hitbox report.
func case_slash_covering_a_hazard_wins() -> void:
	await _build_rig()
	var hazard := _add_hazard(HAZARD_RECT)
	var far := _add_hazard(FAR_HAZARD_RECT)
	await _drop_player_at(Vector2(0.0, -30.0))
	_player.set_physics_process(false)
	_player._start_air_attack(true)
	_player._attack_phase = Player.PHASE_ACTIVE
	_player._activate_down_slash()
	check(not _player.take_hazard_damage(1, hazard.global_position), "damage from a spike under the active slash is refused")
	check(_player._pogo_bounced and _player.velocity.y < BOUNCE_SPEED, "and the pogo happens at once")
	check(_player.get_health() == 3, "with no damage")
	_player._pogo_grace_left = 0.0
	check(_player.take_hazard_damage(1, far.global_position), "a spike the slash does not cover still hurts")
	check(_player.get_health() == 2, "costing one pip")


func case_ground_down_attack_is_a_crouch_attack() -> void:
	await _build_rig(0.0)
	_add_walker(Vector2(60.0, 0.0))
	await _frames(SETTLE_FRAMES)
	Input.action_press(&"move_down")
	await _frames(4)
	check(_player._state == Player.State.CROUCH, "holding down on the ground crouches")
	_player.request_attack(1)
	await _frames(2)
	check(_player._state == Player.State.CROUCH_ATTACK, "attack from the crouch is the crouch attack")
	var lowest := 0.0
	var end := _clock + 0.4
	while _clock < end:
		await process_frame
		lowest = minf(lowest, _player.global_position.y)
	check(lowest > -1.0, "she never leaves the floor (min y %.1f)" % lowest)
	check(not _player._pogo_bounced, "there is no pogo")
	check(_walker.get_health() == 1, "the crouch attack still hits (%d)" % _walker.get_health())


func case_touch_paths() -> void:
	await _build_rig()
	await _drop_player_at(Vector2(START_X, -200.0))
	_player.request_attack(1)
	await _frames(2)
	check(_player._state == Player.State.AIR_ATTACK and _player._air_attack_down, "touch attack with the pad pushed down is the down slash")
	await _secs(0.6)
	await _drop_player_at(Vector2(START_X, -200.0))
	Input.action_press(&"move_down")
	_player.request_attack(0)
	await _frames(2)
	check(_player._air_attack_down, "a neutral touch attack with the pad held down becomes the down slash")
	Input.action_release(&"move_down")
	await _secs(0.6)
	await _drop_player_at(Vector2(START_X, -200.0))
	_player.request_attack(0)
	_player.request_attack_upgrade(1)
	check(_player._air_attack_down, "swiping down right after touching the button upgrades it")
	await _secs(0.6)
	_player.request_attack(0)
	_player.request_attack_upgrade(1)
	check(_player._state == Player.State.ATTACK, "the downward swipe does nothing on the ground")

extends RefCounted
## Scripted approaches to the Greece medal alcove, driven through the real
## player. A trial records what happened in the flags below; the test decides
## what is allowed. Waits run on the game clock through the shared probe.

const Probe := preload("res://tests/support/greece_probe.gd")
const BODY_HALF_WIDTH := 19.0
const SILL_START := 1860.0
const TRIAL_SECONDS := 1.9
const FLOOR_TOLERANCE := 4.0
const WALL_KICK_POLL := 0.05
const TRIGGER_TIMEOUT := 1.2

var probe: Probe
var reached_medal_floor := false
var reached_sill := false
## Furthest x the body centre had while at or above the alcove floor level.
var closest_x := 0.0
## Highest point (smallest y) the body reached during the trial.
var highest_y := INF


func _init(shared_probe: Probe) -> void:
	probe = shared_probe


func medal_floor_edge() -> float:
	return GreeceLayout.ALCOVE_FAR_START - BODY_HALF_WIDTH


## True while Luz stands on the medal floor, beyond the pit.
func on_medal_floor() -> bool:
	return _on_alcove_floor() and probe.player.global_position.x >= medal_floor_edge()


## True while Luz stands on the sill, the take-off of the alcove.
func on_sill() -> bool:
	var x := probe.player.global_position.x
	return _on_alcove_floor() and x > SILL_START and x < GreeceLayout.ALCOVE_SILL_END + BODY_HALF_WIDTH


## Starts at `start`, runs toward `direction`, presses jump once the body centre
## passes `trigger_x` (or after a timeout, if a wall stops it) and holds it for
## `hold` seconds. A negative `dash_delay` means no dash; otherwise Luz dashes
## that long after the jump press.
func run_jump(start: Vector2, direction: float, trigger_x: float, hold: float, dash_delay: float) -> void:
	await _begin(start)
	Input.action_press(_toward(direction))
	var give_up := probe.clock + TRIGGER_TIMEOUT
	while (probe.player.global_position.x - trigger_x) * direction < 0.0 and probe.clock < give_up:
		await probe.tree.process_frame
	Input.action_press(&"jump")
	await _fly(hold, dash_delay)
	probe.release_all()


## Runs off the edge toward `direction` without ever pressing jump.
func run_off(start: Vector2, direction: float) -> void:
	await _begin(start)
	Input.action_press(_toward(direction))
	await _watch(TRIAL_SECONDS)
	probe.release_all()


## Presses toward the wall and taps jump whenever she clings or stands: cling, kick and re-cling.
func wall_kicks(start: Vector2, direction: float, seconds: float) -> void:
	await _begin(start)
	Input.action_press(_toward(direction))
	var end := probe.clock + seconds
	while probe.clock < end:
		# Kick the moment she clings (or leaves the floor), like a player would.
		var player := probe.player
		if player.is_on_floor() or player._state == Player.State.WALL_CLING:
			await probe.tap(&"jump")
		await _watch(WALL_KICK_POLL)
	probe.release_all()


func _begin(start: Vector2) -> void:
	reached_medal_floor = false
	reached_sill = false
	closest_x = 0.0
	highest_y = INF
	await probe.place(start)


func _toward(direction: float) -> StringName:
	return &"move_right" if direction > 0.0 else &"move_left"


func _on_alcove_floor() -> bool:
	var player := probe.player
	var on_level := absf(player.global_position.y - GreeceLayout.ALCOVE_FLOOR_Y) < FLOOR_TOLERANCE
	return player.is_on_floor() and on_level


func _sample() -> void:
	highest_y = minf(highest_y, probe.player.global_position.y)
	reached_medal_floor = reached_medal_floor or on_medal_floor()
	reached_sill = reached_sill or on_sill()
	if probe.player.global_position.y <= GreeceLayout.ALCOVE_FLOOR_Y + 1.0:
		closest_x = maxf(closest_x, probe.player.global_position.x)


## Polls every frame for `seconds`.
func _watch(seconds: float) -> void:
	var end := probe.clock + seconds
	while probe.clock < end:
		await probe.tree.process_frame
		_sample()


func _fly(hold: float, dash_delay: float) -> void:
	var start := probe.clock
	var dashed := dash_delay < 0.0
	while probe.clock - start < TRIAL_SECONDS:
		await probe.tree.process_frame
		_sample()
		if probe.clock - start >= hold:
			Input.action_release(&"jump")
		if not dashed and probe.clock - start >= dash_delay:
			dashed = true
			await probe.tap(&"dash")

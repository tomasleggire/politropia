extends SceneTree
## Regression test for the combat foundation: damage, i-frames, knockback,
## the control lock, the flicker, hit-stop, death and the respawn, plus the
## ContactDamage component.
## Run: godot --headless --path . --script res://tests/combat_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CONTACT_SCENE := "res://scenes/world/contact_damage.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const SOURCE_LEFT := Vector2(-100.0, -30.0)
const SOURCE_RIGHT := Vector2(100.0, -30.0)
const CHECKPOINT := Vector2(500.0, 0.0)
## Longer than the i-frames plus the hit-stop that precedes them.
const IFRAMES_OVER := 1.2
const DEATH_BEAT := 1.0
const HAZARD_RECT := Rect2(200.0, -16.0, 96.0, 16.0)
const PLAYER_BODY := Vector2(29.0, 46.0)

const CHECKS := {
	"case_hit_signals": 5,
	"case_iframes_block": 3,
	"case_knockback_sides": 4,
	"case_control_lock": 4,
	"case_flicker_restores": 3,
	"case_air_actions_restored": 2,
	"case_no_pogo_or_ledge": 5,
	"case_hit_stop": 4,
	"case_death_signals": 4,
	"case_respawn_at_checkpoint": 6,
	"case_death_without_checkpoint": 3,
	"case_contact_rehit": 4,
	"case_untouchable_states": 3,
	"case_hazard_returns_to_safe_ground": 5,
	"case_hazard_never_leaves_her_inside": 2,
	"case_hazard_fade_restores_visibility": 2,
	"case_lethal_hazard_uses_checkpoint": 4,
	"case_safe_ground_skips_edges": 2,
	"case_safe_ground_skips_hazards": 2,
	"case_camera_shake_settles_to_zero": 3,
	"case_no_shake_during_death": 2,
	"case_fall_costs_one_pip_and_returns": 5,
	"case_lethal_fall_uses_checkpoint": 5,
	"case_fall_during_iframes_still_hurts": 4,
	"case_levels_fall_costs_a_pip": 6,
	"case_combo_rules": 11,
	"case_whiff_repeats_hit1": 4,
	"case_no_recoil_and_camera_kick": 5,
	"case_other_attack_boxes": 6,
	"case_dash_invulnerable": 5,
	"case_dash_hazards_and_grace": 4,
}
const LEVELS := {
	"level_01": "res://scenes/levels/level_01.tscn",
	"greece": "res://scenes/levels/greece_level.tscn",
}
## Far below any level's out-of-bounds line.
const VOID_Y := 6000.0


## Stands in for an enemy that regenerates at a rest.
class ResetCounter:
	extends Node
	var count := 0

	func reset_to_checkpoint_state() -> void:
		count += 1


## Stands in for an enemy: counts the slashes that strike it and records the
## freezes the player asks for.
class Dummy:
	extends CharacterBody2D
	var names: Array[StringName] = []
	var freezes: Array[float] = []

	func receive_hit(_damage: int, _source: Vector2, attack_name: StringName = &"") -> bool:
		names.append(attack_name)
		return true

	func freeze(duration: float) -> void:
		freezes.append(duration)


var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _health_events: Array[Vector2i] = []
var _damage_events: Array[Vector2i] = []
var _died_count := 0
var _respawn_count := 0
var _camera: RoomCamera
var _max_veil := 0.0


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


# -- Rig and helpers -----------------------------------------------------------------

## Builds a flat floor (top at y=0) with Luz standing at `start_x`, listening
## to her health signals, and waits for her to settle.
func _build_rig(start_x: float = 0.0, floor_rect: Rect2 = FLOOR_RECT) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, 0.0)
	_rig.add_child(_player)
	_listen()
	await _frames(SETTLE_FRAMES)


func _listen() -> void:
	_health_events.clear()
	_damage_events.clear()
	_died_count = 0
	_respawn_count = 0
	_player.health_changed.connect(func(current: int, maximum: int) -> void: _health_events.append(Vector2i(current, maximum)))
	_player.damaged.connect(func(amount: int, current: int) -> void: _damage_events.append(Vector2i(amount, current)))
	_player.died.connect(func() -> void: _died_count += 1)
	_player.respawned.connect(func() -> void: _respawn_count += 1)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_camera = null
	_max_veil = 0.0


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"dash"]:
		Input.action_release(action)


## The autoload is not a compile-time global in a --script run.
func _checkpoints() -> Node:
	return root.get_node("CheckpointService")


func _alpha() -> float:
	return _player.get_node("AnimatedSprite2D").modulate.a


func _add_resettable() -> ResetCounter:
	var counter := ResetCounter.new()
	counter.add_to_group(&"checkpoint_resettable")
	_rig.add_child(counter)
	return counter


# -- Cases -----------------------------------------------------------------------

func case_hit_signals() -> void:
	await _build_rig()
	_health_events.clear()
	var applied := _player.take_damage(1, SOURCE_LEFT)
	check(applied, "take_damage reports the hit as applied")
	check(_player.get_health() == 2 and _player.max_health == 3, "one hit leaves 2 of 3 health")
	check(_health_events == [Vector2i(2, 3)], "health_changed fires once with (2, 3): %s" % [_health_events])
	check(_damage_events == [Vector2i(1, 2)], "damaged fires once with (1, 2): %s" % [_damage_events])
	check(_died_count == 0, "a non-lethal hit does not emit died")


func case_iframes_block() -> void:
	await _build_rig()
	_player.take_damage(1, SOURCE_LEFT)
	var again := _player.take_damage(1, SOURCE_LEFT)
	check(not again, "a second hit during the i-frames is refused")
	check(_player.get_health() == 2 and _damage_events.size() == 1, "refused hit changes nothing")
	await _secs(IFRAMES_OVER)
	check(_player.take_damage(1, SOURCE_LEFT), "a hit lands again once the i-frames end")


func case_knockback_sides() -> void:
	await _build_rig()
	_player.take_damage(1, SOURCE_LEFT)
	check(_player.velocity.x > 0.0, "a source on the left pushes Luz right (vx %.0f)" % _player.velocity.x)
	check(_player.velocity.y < 0.0, "the hit kicks Luz upward (vy %.0f)" % _player.velocity.y)
	_free_rig()
	await _build_rig()
	_player.take_damage(1, SOURCE_RIGHT)
	check(_player.velocity.x < 0.0, "a source on the right pushes Luz left (vx %.0f)" % _player.velocity.x)
	check(_player.velocity.y < 0.0, "the kick is upward from this side too")


func case_control_lock() -> void:
	await _build_rig()
	Input.action_press(&"move_left")
	_player.take_damage(1, SOURCE_LEFT)
	await _secs(0.12)
	check(_player.velocity.x > 0.0, "holding left does not cancel the knockback (vx %.0f)" % _player.velocity.x)
	check(_player._state == Player.State.HURT, "the player is still in the hurt state during the lock")
	await _secs(1.0)
	check(_player._state != Player.State.HURT, "the lock releases")
	check(_player.velocity.x < 0.0, "movement input works again after the lock (vx %.0f)" % _player.velocity.x)


func case_flicker_restores() -> void:
	await _build_rig()
	var rest_alpha := _alpha()
	_player.take_damage(1, SOURCE_LEFT)
	var lowest := rest_alpha
	var end := _clock + 0.8
	while _clock < end:
		await process_frame
		lowest = minf(lowest, _alpha())
	check(lowest < rest_alpha, "the sprite blinks during the i-frames (min alpha %.2f)" % lowest)
	await _secs(IFRAMES_OVER)
	check(_alpha() == rest_alpha, "the alpha is restored exactly (%.3f)" % _alpha())
	check(_player.get_node("AnimatedSprite2D").modulate == Color.WHITE, "the tint is untouched after the blink")


func case_air_actions_restored() -> void:
	await _build_rig()
	_player._air_dash_used = true
	_player._air_jumps_left = 0
	_player.take_damage(1, SOURCE_LEFT)
	check(not _player._air_dash_used, "a hit gives the air dash back")
	check(_player._air_jumps_left == _player.air_jumps, "a hit gives the air jump back")


func case_no_pogo_or_ledge() -> void:
	await _build_rig()
	var states := Player.State.keys()
	check(not states.has("LEDGE_HANG") and not states.has("LEDGE_CLIMB"), "no ledge state exists")
	check(not ("pogo_height" in _player) and not ("ledge_climb_duration" in _player), "no pogo or ledge tunables exist")
	check(_player.get_node_or_null("LedgeCheckAbove") == null, "the ledge probe is gone")
	_player.global_position = Vector2(0.0, -150.0)
	_player.velocity = Vector2.ZERO
	await _frames(2)
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var swung := false
	var bounced := false
	for i: int in 24:
		await _frames(1)
		swung = swung or _player._state == Player.State.AIR_ATTACK
		bounced = bounced or _player.velocity.y < -50.0
	Input.action_release(&"move_down")
	check(swung, "down + attack in the air swings the horizontal air attack")
	check(not bounced, "and never bounces her upward")


func case_hit_stop() -> void:
	await _build_rig()
	var before := _player.global_position
	_player.take_damage(1, SOURCE_LEFT)
	check(Engine.time_scale == 1.0, "hit-stop does not touch Engine.time_scale")
	await _frames(2)
	check(_player.global_position == before, "Luz is frozen during the hit-stop")
	await _secs(0.4)
	check(_player.global_position.x > before.x, "Luz moves again after the hit-stop")
	check(Engine.time_scale == 1.0, "the time scale is still 1.0 afterwards")


func case_death_signals() -> void:
	await _build_rig()
	for i: int in 3:
		_player.take_damage(1, SOURCE_LEFT)
		_player._invuln_left = 0.0
	check(_player.get_health() == 0, "three hits empty the health")
	check(_died_count == 1, "died fires exactly once (%d)" % _died_count)
	check(_player.is_input_locked() and _player._state == Player.State.DEAD, "the dead player is locked in the dead state")
	check(not _player.take_damage(1, SOURCE_LEFT), "a dead player cannot be hit")


func case_respawn_at_checkpoint() -> void:
	await _build_rig()
	var enemy := _add_resettable()
	_checkpoints().activate(&"test_desk", "", CHECKPOINT)
	_player.apply_checkpoint(CHECKPOINT)
	for i: int in 3:
		_player.take_damage(1, SOURCE_LEFT)
		await _secs(IFRAMES_OVER if i < 2 else DEATH_BEAT)
	check(_died_count == 1, "died fired once across the three hits")
	check(_respawn_count == 1, "respawned fired once after the death beat (%d)" % _respawn_count)
	check(_player.global_position.distance_to(CHECKPOINT) < 4.0, "Luz wakes at the checkpoint")
	check(_player.get_health() == 3, "Luz wakes with full health")
	check(enemy.count == 1, "resettable enemies reset exactly once (%d)" % enemy.count)
	await _secs(IFRAMES_OVER)
	check(not _player.is_input_locked() and _alpha() == 1.0, "control and opacity are back")


func case_death_without_checkpoint() -> void:
	await _build_rig()
	_player.global_position.x = 200.0
	for i: int in 3:
		_player.take_damage(1, SOURCE_LEFT)
		await _secs(IFRAMES_OVER if i < 2 else DEATH_BEAT)
	check(absf(_player.global_position.x) < 4.0, "without a checkpoint Luz returns to the level start (x %.0f)" % _player.global_position.x)
	check(_player.get_health() == 3, "full health without a checkpoint too")
	check(_respawn_count == 1, "respawned fired once")


func case_contact_rehit() -> void:
	await _build_rig()
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	_rig.add_child(hazard)
	hazard.set_area_size(Vector2(1600.0, 400.0))
	hazard.position = Vector2(0.0, -100.0)
	await _secs(0.3)
	check(_player.get_health() == 2, "standing in the hazard hurts once (%d)" % _player.get_health())
	await _secs(0.4)
	check(_player.get_health() == 2, "the i-frames block repeated contact")
	await _secs(IFRAMES_OVER)
	check(_player.get_health() == 1, "contact hurts again after the i-frames (%d)" % _player.get_health())
	check(hazard.collision_mask == 1 and hazard.collision_layer == 0, "the hazard only watches the player layer")


func case_untouchable_states() -> void:
	await _build_rig()
	_player.enter_meditation()
	check(not _player.take_damage(1, SOURCE_LEFT) and _player.get_health() == 3, "a meditating player cannot be hurt")
	_player.exit_meditation()
	_player.set_input_locked(true)
	check(not _player.take_damage(1, SOURCE_LEFT), "an input-locked player cannot be hurt")
	_player.set_input_locked(false)
	check(_player.take_damage(1, SOURCE_LEFT), "she can be hurt again once control returns")


# -- Hazards, safe ground and camera shake -----------------------------------------

func _add_hazard(rect: Rect2) -> ContactDamage:
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	hazard.kind = ContactDamage.Kind.HAZARD
	_rig.add_child(hazard)
	hazard.set_area_size(rect.size)
	hazard.position = rect.get_center()
	return hazard


func _veil_alpha() -> float:
	var veils := _player.find_children("*", "ScreenFade", true, false)
	return 0.0 if veils.is_empty() else (veils[0] as ScreenFade).get_alpha()


## Runs right into the hazard, releases the key on the hit and returns the
## last safe ground at that moment. Tracks the darkest veil on the way.
func _walk_into_hazard(settle: float) -> Vector2:
	var health_before := _player.get_health()
	Input.action_press(&"move_right")
	var end := _clock + 3.0
	while _player.get_health() == health_before and _clock < end:
		await process_frame
	Input.action_release(&"move_right")
	var safe := _player.get_last_safe_ground()
	end = _clock + settle
	while _clock < end:
		await process_frame
		_max_veil = maxf(_max_veil, _veil_alpha())
	return safe


func _overlaps_hazard(hazard: ContactDamage) -> bool:
	var body := Rect2(_player.global_position - Vector2(PLAYER_BODY.x * 0.5, PLAYER_BODY.y), PLAYER_BODY)
	return hazard.get_world_rect().intersects(body)


func case_hazard_returns_to_safe_ground() -> void:
	await _build_rig()
	var hazard := _add_hazard(HAZARD_RECT)
	var safe := await _walk_into_hazard(0.8)
	check(_player.get_health() == 2, "a hazard hit costs one pip (%d)" % _player.get_health())
	check(_player.global_position.distance_to(safe) < 3.0, "Luz lands on the last safe ground (%s vs %s)" % [_player.global_position, safe])
	check(safe.x < HAZARD_RECT.position.x - _player.safe_ground_margin, "that ground is clear of the hazard (x %.0f)" % safe.x)
	check(not _player.is_input_locked(), "control is back after the return")
	check(not _overlaps_hazard(hazard), "she is not left inside the hazard")


func case_hazard_never_leaves_her_inside() -> void:
	await _build_rig()
	var hazard := _add_hazard(HAZARD_RECT)
	await _walk_into_hazard(0.5)
	var frames_inside := 0
	var end := _clock + 1.0
	while _clock < end:
		await process_frame
		frames_inside += 1 if _overlaps_hazard(hazard) else 0
	check(frames_inside == 0, "after the return she spends no frame inside the hazard (%d)" % frames_inside)
	check(_player.get_health() == 2, "and no second hit lands")


func case_hazard_fade_restores_visibility() -> void:
	await _build_rig()
	_add_hazard(HAZARD_RECT)
	await _walk_into_hazard(0.8)
	check(_max_veil > 0.95, "the screen goes fully dark during the return (%.2f)" % _max_veil)
	check(_veil_alpha() == 0.0, "the veil is gone afterwards (%.2f)" % _veil_alpha())


func case_lethal_hazard_uses_checkpoint() -> void:
	await _build_rig()
	_add_hazard(HAZARD_RECT)
	_checkpoints().activate(&"test_desk", "", CHECKPOINT)
	_player.apply_checkpoint(CHECKPOINT)
	_player._health = 1
	await _walk_into_hazard(DEATH_BEAT)
	check(_died_count == 1, "a lethal hazard hit kills her")
	check(_player.global_position.distance_to(CHECKPOINT) < 4.0, "she wakes at the checkpoint, not the safe ground")
	check(_player.get_health() == 3, "with full health")
	check(_max_veil == 0.0, "the safe-ground fade never ran")


func case_safe_ground_skips_edges() -> void:
	await _build_rig(0.0, Rect2(-100.0, 0.0, 200.0, 200.0))
	_player.global_position.x = 40.0
	await _secs(0.4)
	check(absf(_player.get_last_safe_ground().x - 40.0) < 2.0, "a spot well inside the floor is recorded")
	_player.global_position.x = 85.0
	await _secs(0.4)
	check(absf(_player.get_last_safe_ground().x - 40.0) < 2.0, "a spot near the ledge edge is not")


func case_safe_ground_skips_hazards() -> void:
	await _build_rig()
	_add_hazard(HAZARD_RECT)
	_player._invuln_left = 99.0
	_player.global_position.x = 190.0
	await _secs(0.4)
	check(_player.get_last_safe_ground().x < 100.0, "no ground is recorded next to or inside the hazard (x %.0f)" % _player.get_last_safe_ground().x)
	_player.global_position.x = 140.0
	await _secs(0.4)
	check(absf(_player.get_last_safe_ground().x - 140.0) < 2.0, "ground clear of the hazard margin is recorded")


func _add_camera() -> void:
	_camera = RoomCamera.new()
	_camera.target = _player
	_camera.world_size = Vector2(6000.0, 1000.0)
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_rig.add_child(_camera)
	await _frames(2)


func case_camera_shake_settles_to_zero() -> void:
	await _build_rig()
	await _add_camera()
	var bounds := _camera.get_room_bounds()
	_player.take_damage(1, SOURCE_LEFT)
	await _frames(3)
	check(_camera.offset != Vector2.ZERO, "a hit shakes the camera")
	await _secs(IFRAMES_OVER)
	check(_camera.offset == Vector2.ZERO, "the offset is exactly zero afterwards")
	check(_camera.get_room_bounds() == bounds, "the room bounds are untouched")


func case_no_shake_during_death() -> void:
	await _build_rig()
	await _add_camera()
	for i: int in 2:
		_player.take_damage(1, SOURCE_LEFT)
		await _secs(IFRAMES_OVER)
	_player.take_damage(1, SOURCE_LEFT)
	check(_camera.offset == Vector2.ZERO, "the lethal hit cancels any shake at once")
	var worst := 0.0
	var end := _clock + 0.5
	while _clock < end:
		await process_frame
		worst = maxf(worst, _camera.offset.length())
	check(worst == 0.0, "the camera stays still through the death fade (%.2f)" % worst)


# -- Falling out of the map ----------------------------------------------------------

## Stands on the floor long enough to record safe ground, then drops her into
## the void and runs the player's out-of-bounds fall.
func _fall_from(x: float) -> Vector2:
	_player.global_position.x = x
	await _secs(0.4)
	var safe := _player.get_last_safe_ground()
	_player.global_position.y = VOID_Y
	return safe


func case_fall_costs_one_pip_and_returns() -> void:
	await _build_rig()
	var safe := await _fall_from(40.0)
	check(_player.fall_out_of_bounds(), "a fall out of the map is accepted")
	check(not _player.fall_out_of_bounds(), "a second call while she is being returned does nothing")
	await _secs(1.0)
	check(_player.get_health() == 2 and _damage_events == [Vector2i(1, 2)], "the fall costs exactly one pip (%d)" % _player.get_health())
	check(_player.global_position.distance_to(safe) < 3.0, "she lands on the last safe ground (%s vs %s)" % [_player.global_position, safe])
	check(not _player.is_input_locked() and _died_count == 0, "control is back and she did not die")


func case_lethal_fall_uses_checkpoint() -> void:
	await _build_rig()
	var enemy := _add_resettable()
	_checkpoints().activate(&"test_desk", "", CHECKPOINT)
	_player.apply_checkpoint(CHECKPOINT)
	_player._health = 1
	await _fall_from(40.0)
	check(_player.fall_out_of_bounds(), "a lethal fall is accepted")
	await _secs(DEATH_BEAT)
	check(_died_count == 1 and _respawn_count == 1, "the death path runs once")
	check(_player.global_position.distance_to(CHECKPOINT) < 4.0, "she wakes at the checkpoint, not the safe ground")
	check(_player.get_health() == 3 and enemy.count == 1, "with full health and the enemies reset")
	check(_veil_alpha() == 0.0, "no veil is left on screen")


func case_fall_during_iframes_still_hurts() -> void:
	await _build_rig()
	_player.take_damage(1, SOURCE_LEFT)
	var safe := await _fall_from(40.0)
	check(_player.get_health() == 2, "a hit leaves her in her i-frames (%d)" % _player.get_health())
	check(_player.fall_out_of_bounds(), "a fall inside the i-frames is still accepted")
	await _secs(1.0)
	check(_player.get_health() == 1, "a pit hurts even during the i-frames (%d)" % _player.get_health())
	check(_player.global_position.distance_to(safe) < 3.0, "and she is still returned to the safe ground")


func case_levels_fall_costs_a_pip() -> void:
	for level_name: String in LEVELS:
		_checkpoints().clear()
		change_scene_to_file(LEVELS[level_name])
		await _frames(10)
		var player := current_scene.get_node("Player") as Player
		await _secs(0.6)
		var safe := player.get_last_safe_ground()
		player.global_position.y = VOID_Y
		await _secs(1.2)
		check(player.get_health() == 2, "%s: falling out of the map costs one pip (%d)" % [level_name, player.get_health()])
		check(player.global_position.distance_to(safe) < 4.0, "%s: she is back on the last safe ground" % level_name)
		check(not player.is_input_locked(), "%s: control is back" % level_name)


# -- Attacks: combo rule, timings, hitboxes, hit-stop, lunge, camera, dash i-frames ----

func _add_dummy(x: float) -> Dummy:
	var dummy := Dummy.new()
	dummy.collision_layer = 8
	dummy.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20.0, 40.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -20.0)
	dummy.add_child(shape)
	dummy.position = Vector2(x, 0.0)
	_rig.add_child(dummy)
	return dummy


func _hitbox_shape() -> CollisionShape2D:
	return _player.get_node("AttackHitbox/CollisionShape2D") as CollisionShape2D


func _box_of_hitbox() -> Dictionary:
	var shape := _hitbox_shape()
	return {"size": (shape.shape as RectangleShape2D).size, "center": shape.position}


func _box_matches(box: Dictionary, rect: Rect2, facing := 1) -> bool:
	var want_center := Vector2(rect.get_center().x * float(facing), rect.get_center().y)
	return (box["size"] as Vector2).is_equal_approx(rect.size) and (box["center"] as Vector2).distance_to(want_center) < 0.01


## Waits until the attack is in `segment` of its active phase and returns the live hitbox.
func _box_at_segment(segment: int, limit := 1.0) -> Dictionary:
	var end := _clock + limit
	while _clock < end:
		await _frames(1)
		if _player._attack_phase == Player.PHASE_ACTIVE and _player._attack_segment == segment:
			return _box_of_hitbox()
	return {"size": Vector2.ZERO, "center": Vector2(9999.0, 9999.0)}


func case_combo_rules() -> void:
	await _build_rig()
	var dummy := _add_dummy(50.0)
	var boxes := {}
	var stops := {}
	var seen := 0
	var start_x := _player.global_position.x
	var max_advance := 0.0
	var end := _clock + 3.0
	while _clock < end and not dummy.names.has(&"attack_ground_3"):
		_player.request_attack(0)
		await _frames(1)
		if _player._attack_phase == Player.PHASE_ACTIVE and _player._state == Player.State.ATTACK:
			var key := "%d_%d" % [_player._attack_combo_index, _player._attack_segment]
			if not boxes.has(key):
				boxes[key] = _box_of_hitbox()
		if _player._state == Player.State.ATTACK and _player._attack_combo_index == 2:
			max_advance = maxf(max_advance, _player.global_position.x - start_x)
		while seen < dummy.names.size():
			stops[dummy.names[seen]] = maxf(float(stops.get(dummy.names[seen], 0.0)), _player._hit_stop_left)
			seen += 1
	# Keep tracking the finisher's lunge without pressing again.
	var tail := _clock + 0.5
	while _clock < tail:
		await _frames(1)
		if _player._state == Player.State.ATTACK and _player._attack_combo_index == 2:
			max_advance = maxf(max_advance, _player.global_position.x - start_x)
	var first_of := func(attack_name: StringName) -> int: return dummy.names.find(attack_name)
	check(
		first_of.call(&"attack_ground_1") == 0 and first_of.call(&"attack_ground_2") > 0
		and first_of.call(&"attack_ground_3") > first_of.call(&"attack_ground_2"),
		"with a target the combo goes hit 1, 2, 3 in order (%s)" % [dummy.names]
	)
	check(boxes.has("0_0") and _box_matches(boxes["0_0"], _player.hitbox_hit1_a), "hit 1 phase A box")
	check(boxes.has("0_1") and _box_matches(boxes["0_1"], _player.hitbox_hit1_b), "hit 1 phase B box")
	check(boxes.has("1_0") and _box_matches(boxes["1_0"], _player.hitbox_hit2_a), "hit 2 phase A' box")
	check(boxes.has("1_1") and _box_matches(boxes["1_1"], _player.hitbox_hit2_b), "hit 2 phase B' box")
	check(boxes.has("2_0") and _box_matches(boxes["2_0"], _player.hitbox_hit3), "hit 3 finisher box")
	check(absf(float(stops.get(&"attack_ground_1", 0.0)) - 0.09) < 0.02, "hit 1 hit-stop ~0.09 s (%.3f)" % float(stops.get(&"attack_ground_1", 0.0)))
	check(absf(float(stops.get(&"attack_ground_2", 0.0)) - 0.10) < 0.02, "hit 2 hit-stop ~0.10 s (%.3f)" % float(stops.get(&"attack_ground_2", 0.0)))
	check(absf(float(stops.get(&"attack_ground_3", 0.0)) - 0.20) < 0.02, "hit 3 hit-stop ~0.20 s (%.3f)" % float(stops.get(&"attack_ground_3", 0.0)))
	check(absf(max_advance - 40.0) < 8.0, "the finisher lunges ~40 px (%.1f)" % max_advance)
	await _secs(1.0)
	check(absf(_player.global_position.x - start_x) < 6.0, "and slides back to where it started (%.1f)" % (_player.global_position.x - start_x))


func case_whiff_repeats_hit1() -> void:
	await _build_rig()
	var starts: Array[float] = []
	var max_index := 0
	var last_segment := -2
	var first_press := _clock
	var first_active := -1.0
	var end := _clock + 2.2
	while _clock < end:
		_player.request_attack(0)
		await _frames(1)
		if _player._state == Player.State.ATTACK:
			max_index = maxi(max_index, _player._attack_combo_index)
			if _player._attack_segment == 0 and last_segment != 0:
				starts.append(_clock)
				if first_active < 0.0:
					first_active = _clock - first_press
		last_segment = _player._attack_segment if _player._state == Player.State.ATTACK else -2
	var gaps: Array[float] = []
	for i in range(2, starts.size()):
		gaps.append(starts[i] - starts[i - 1])
	var mean := 0.0
	for gap in gaps:
		mean += gap
	mean = mean / maxf(float(gaps.size()), 1.0)
	check(max_index == 0, "whiffing never advances the combo (max index %d)" % max_index)
	check(starts.size() >= 5, "hit 1 repeats while mashing (%d starts)" % starts.size())
	check(absf(mean - 0.305) < 0.03, "whiff cadence ~0.305 s (%.3f)" % mean)
	check(absf(first_active - 0.117) < 0.04, "hit 1 from rest reaches its active frame after ~0.117 s (%.3f)" % first_active)


func case_no_recoil_and_camera_kick() -> void:
	await _build_rig()
	await _add_camera()
	var dummy := _add_dummy(50.0)
	_player.request_attack(0)
	var peak := 0.0
	var end := _clock + 0.5
	while _clock < end:
		await _frames(1)
		peak = maxf(peak, _camera.offset.x)
	check(dummy.names.size() >= 1, "the slash landed")
	check(absf(_player.global_position.x) < 0.5, "no recoil: Luz stays put (x %.2f)" % _player.global_position.x)
	check(peak > 3.0 and peak <= _player.attack_kick_hit1.x + 0.01, "the RoomCamera is jolted toward the hit (%.1f)" % peak)
	_camera.queue_free()
	await _frames(2)
	var player_camera := Camera2D.new()
	player_camera.set_script(load("res://scripts/camera/camara_jugador.gd"))
	_player.add_child(player_camera)
	player_camera.make_current()
	await _secs(0.5)
	_player.request_attack(0)
	var peak2 := 0.0
	end = _clock + 0.5
	while _clock < end:
		await _frames(1)
		peak2 = maxf(peak2, player_camera.offset.x)
	check(peak2 > 3.0, "the player Camera2D is jolted too (%.1f)" % peak2)
	check(player_camera.offset == Vector2.ZERO, "and settles back to zero")


func case_other_attack_boxes() -> void:
	await _build_rig()
	Input.action_press(&"move_down")
	await _secs(0.4)
	_player.request_attack(0)
	var crouch_a := await _box_at_segment(0)
	var crouch_b := await _box_at_segment(1)
	Input.action_release(&"move_down")
	await _secs(1.0)
	_player.request_attack(-1)
	var up_a := await _box_at_segment(0)
	var up_b := await _box_at_segment(1)
	await _secs(1.0)
	_player.global_position = Vector2(0.0, -200.0)
	_player.velocity = Vector2.ZERO
	await _frames(2)
	_player.request_attack(0)
	var air_a := await _box_at_segment(0)
	var air_b := await _box_at_segment(1)
	check(_box_matches(crouch_a, _player.hitbox_crouch_a), "crouch sweep 1 box")
	check(_box_matches(crouch_b, _player.hitbox_crouch_b), "crouch sweep 2 box")
	check(_box_matches(up_a, _player.hitbox_up_a), "up attack back arc box")
	check(_box_matches(up_b, _player.hitbox_up_b), "up attack front arc box")
	check(_box_matches(air_a, _player.hitbox_air_a), "air crescent box")
	check(_box_matches(air_b, _player.hitbox_air_b), "air low backhand box")


func case_dash_invulnerable() -> void:
	await _build_rig()
	_player.request_dash()
	await _secs(0.05)
	var contact := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	_rig.add_child(contact)
	contact.set_area_size(Vector2(1600.0, 400.0))
	contact.position = Vector2(0.0, -100.0)
	var shot := (load("res://scenes/enemies/enemy_projectile.tscn") as PackedScene).instantiate() as EnemyProjectile
	_rig.add_child(shot)
	shot.launch(_player.global_position + Vector2(-40.0, -20.0), Vector2.RIGHT, 250.0)
	await _secs(0.3)
	check(_player.is_dash_invulnerable(), "she is invulnerable during the dash")
	check(_player.get_health() == 3, "enemy contact and a projectile do nothing during the dash (%d)" % _player.get_health())
	check(shot.is_active(), "the projectile passes through her instead of vanishing")
	check(_player._state == Player.State.DASH, "and the dash was not interrupted")
	await _secs(0.9)
	check(_player.get_health() == 2, "the same contact hurts right after the dash (%d)" % _player.get_health())


func case_dash_hazards_and_grace() -> void:
	await _build_rig()
	_player.request_dash()
	await _secs(0.1)
	check(_player.take_hazard_damage(1, SOURCE_LEFT), "fixed hazards still hurt during the dash")
	await _free_and_rebuild()
	_player.dash_invulnerable = false
	_player.request_dash()
	await _secs(0.1)
	check(_player.take_damage(1, SOURCE_LEFT), "with dash_invulnerable off the dash does not protect")
	await _free_and_rebuild()
	_player.dash_invulnerable_grace = 0.3
	_player.request_dash()
	var end := _clock + 1.5
	while _player._state == Player.State.DASH and _clock < end:
		await _frames(1)
	check(not _player.take_damage(1, SOURCE_LEFT), "the grace after the dash still blocks hits")
	await _secs(0.4)
	check(_player.take_damage(1, SOURCE_LEFT), "and expires")


func _free_and_rebuild() -> void:
	_release_all()
	_free_rig()
	_checkpoints().clear()
	await _build_rig()

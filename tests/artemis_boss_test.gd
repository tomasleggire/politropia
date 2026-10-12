extends "res://tests/support/ritual_suite.gd"
## Artemis boss (T1 to T3): scene basics, health and defeat, the phase threshold, the
## aimed shot and its arrow, the dash i-frames, backstep, dodge, feint, kiting,
## walls and ledges, stagger, the checkpoint reset, the fan volley, the arrow
## rain, the dagger slash and the weighted attack choice, then phase two: the
## transition beat, shorter recoveries, chained strings, the moon dive, the
## spectral stag and the cornered vault, and the platform rules (T7): arrows, rain
## markers and the dive column respect one-way platforms, proximity needs the same
## height, and she never ends on a platform. Each case builds its own
## floor (top at y=0), Luz and boss, and tweaks exports so only the behaviour
## under test can happen. Timings are measured in physics steps.
##
## This suite runs inside the single runner (stillness_desk_ritual_test.gd),
## before any level scene is loaded: the boss targets the first node of group
## `player`, so no other Luz may exist.

const BOSS_SCENE := "res://scenes/enemies/bosses/artemis.tscn"
const ShakeSpy := preload("res://tests/support/shake_spy_camera.gd")
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LEDGE_FLOOR := Rect2(-300.0, 0.0, 600.0, 100.0)
const LUZ_START := Vector2(-300.0, 0.0)
const CENTER := Vector2(0.0, -29.0)
const ROOM := &"A"
const SETTLE_FRAMES := 30
const HIT_FROM := Vector2(100.0, 0.0)

const CHECKS := {
	"case_scene_basics": 4,
	"case_damage_and_defeat": 6,
	"case_phase_two_threshold": 5,
	"case_aimed_shot_telegraph_and_arrow": 9,
	"case_arrow_hurts_luz": 2,
	"case_arrow_ignored_during_dash": 2,
	"case_backstep_when_close": 3,
	"case_backstep_refused_at_walls_and_ledges": 4,
	"case_stagger": 8,
	"case_dodge": 4,
	"case_kite_and_walls": 3,
	"case_feint": 4,
	"case_checkpoint_reset": 6,
	"case_fan_volley": 7,
	"case_arrow_rain": 7,
	"case_dagger_slash": 6,
	"case_dagger_blocked_by_dash": 2,
	"case_attack_selection": 6,
	"case_reset_after_defeat_fade": 2,
	"case_phase_transition": 8,
	"case_phase_two_recoveries": 2,
	"case_chained_strings": 6,
	"case_moon_dive": 6,
	"case_moon_dive_stuck_is_a_punish_window": 5,
	"case_moon_dive_dash": 2,
	"case_spectral_stag": 8,
	"case_cornered_vault": 10,
	"case_vault_on_hit_and_priority": 5,
	"case_phase_two_selection": 2,
	"case_attack_without_luz": 3,
	"case_phase_two_reset": 5,
	"case_plain_hops_never_chain": 4,
	"case_transition_postponed_by_stagger": 4,
	"case_transition_postponed_by_vault": 4,
	"case_interrupt_aimed_shot": 9,
	"case_interrupt_dagger": 3,
	"case_interrupt_rain": 3,
	"case_interrupt_not_after_release": 4,
	"case_interrupt_vault_crouch": 4,
	"case_interrupt_phase_two_and_stagger": 4,
	"case_arrows_live_beside_the_boss": 7,
	"case_rain_respects_platforms": 5,
	"case_aimed_arrows_and_one_ways": 3,
	"case_dive_column_reaches_a_platform": 5,
	"case_proximity_needs_same_height": 8,
	"case_never_stands_on_a_platform": 3,
	"case_final_blow_restores_time_scale": 8,
	"case_corpse_stays": 9,
	"case_audio_cue_slots": 3,
	"case_cues_ranged_attacks": 4,
	"case_cues_phase_two_and_shakes": 6,
	"case_cues_reactions": 3,
}

var _rig: Node2D
var _player: Player
var _boss: ArtemisBoss


func expected_checks() -> Dictionary:
	return CHECKS


# -- Rig and helpers -----------------------------------------------------------------

func _registry() -> Node:
	return h.tree.root.get_node("EnemyRegistry")


func _build_rig(luz_at := LUZ_START, with_luz := true, floor_rect := FLOOR_RECT, walls := true) -> void:
	_free_rig()
	h.cps.clear()
	_registry().clear()
	_rig = Node2D.new()
	h.tree.root.add_child(_rig)
	LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	if walls:
		LevelGeometry.add_solid(_rig, Rect2(-482.0, -400.0, 32.0, 400.0), Color.DIM_GRAY)
		LevelGeometry.add_solid(_rig, Rect2(450.0, -400.0, 32.0, 400.0), Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM
	if with_luz:
		_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
		_rig.add_child(_player)
		_place_luz(luz_at)
	await h.frames(SETTLE_FRAMES)


func _add_boss(at: Vector2, tweaks := {}) -> ArtemisBoss:
	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as ArtemisBoss
	_boss.enemy_id = &"artemis"
	_boss.position = at
	_boss.rng_seed = 11
	# Hits cancel telegraphs by default; the older cases hit her mid-attack on purpose.
	_boss.interrupt_enabled = false
	# The killing blow's slow motion is covered by its own case; elsewhere it
	# would only stretch the waits.
	_boss.final_freeze_time = 0.0
	_boss.final_slowmo_time = 0.0
	for key: String in tweaks:
		_boss.set(key, tweaks[key])
	_rig.add_child(_boss)
	await h.frames(5)
	return _boss


func _place_luz(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null
	_boss = null


func _end_case() -> void:
	BossFeel.cancel()
	_free_rig()
	_registry().clear()
	h.cps.clear()


func _steps(n: int) -> void:
	for i: int in n:
		await h.tree.physics_frame


func _hit(n: int) -> void:
	for i: int in n:
		_boss.receive_hit(1, HIT_FROM, &"attack_1")


func _dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _distance_to_luz() -> float:
	return absf(_player.global_position.x - _boss.global_position.x)


## Runs `seconds` of physics and reports whether `state` was ever entered.
func _sees_state(state: ArtemisBoss.State, seconds: float) -> bool:
	var seen := false
	for i: int in int(seconds / _dt()):
		await h.tree.physics_frame
		seen = seen or _boss.get_state() == state
	return seen


# -- Basics, health, defeat, phases ---------------------------------------------------

func case_scene_basics() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0))
	h.check(_boss.is_in_group(Enemy.GROUP_ENEMIES), "she joins the enemies group like any other enemy")
	h.check(_boss.max_health == 30 and _boss.get_health() == 30, "accessible baseline: 30 health (%d)" % _boss.get_health())
	h.check(_boss.get_node_or_null("Visual/Body") is Polygon2D, "the placeholder body exists for the hit flash")
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE and _boss.get_phase() == 1, "she starts idle in phase one")
	_end_case()


func case_damage_and_defeat() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0})
	var events: Array[int] = []
	_boss.defeated.connect(func() -> void: events.append(1))
	_boss.receive_hit(1, HIT_FROM, &"attack_1")
	h.check(_boss.get_health() == 29, "one Luz hit takes one health (%d)" % _boss.get_health())
	_hit(28)
	_boss.receive_hit(1, HIT_FROM, &"attack_1")
	h.check(_boss.is_dead() and events.size() == 1, "the 30th hit defeats her and emits defeated once (%d)" % events.size())
	h.check(_boss.collision_layer == 0, "the defeated boss no longer collides")
	await h.secs(_boss.defeat_time + 0.4)
	h.check(_boss.visible and _boss.is_dead(), "she stays as a corpse where she fell")
	h.check(not _boss.is_physics_processing(), "once settled, her processing is switched off")
	h.check(not _boss.receive_hit(1, HIT_FROM, &"attack_1") and events.size() == 1, "further hits do nothing and defeat fires only once")
	_end_case()


func case_phase_two_threshold() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0})
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_hit(14)
	h.check(phases.is_empty(), "above half health there is no phase change")
	h.check(_boss.get_phase() == 1, "she is still in phase one at 16 health")
	_hit(1)
	h.check(phases == [2], "reaching half health emits phase_changed(2) (%s)" % [phases])
	h.check(_boss.get_phase() == 2, "and she is in phase two")
	_hit(5)
	h.check(phases == [2], "the signal fires only once")
	_end_case()


# -- Aimed shot ------------------------------------------------------------------------

func case_aimed_shot_telegraph_and_arrow() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	var t := 0.0
	var line_seen := false
	var glow_seen := false
	while _boss.is_telegraphing() and t < 2.0:
		await h.tree.physics_frame
		t += _dt()
		line_seen = line_seen or _boss.get_telegraph().is_aim_line_visible()
		glow_seen = glow_seen or _boss.get_telegraph().is_glowing()
	h.check(t >= 0.35, "the telegraph is at least 0.35 s (%.2f)" % t)
	h.check(absf(t - _boss.shot_telegraph_time) < 0.05, "and lasts the configured %.2f s (%.2f)" % [_boss.shot_telegraph_time, t])
	h.check(line_seen and glow_seen, "an aim line and a body glow show during it")
	h.check(not _boss.get_telegraph().is_aim_line_visible() and not _boss.get_telegraph().is_glowing(), "and both are gone once the arrow is released")
	h.check(_boss.active_arrow_count() == 1, "exactly one arrow is fired (%d)" % _boss.active_arrow_count())
	var arrow := _boss.get_active_arrows()[0]
	var wanted := (_player.global_position + CENTER - arrow.global_position).normalized()
	h.check(arrow.get_velocity().normalized().dot(wanted) > 0.99, "it flies toward Luz's centre (dot %.3f)" % arrow.get_velocity().normalized().dot(wanted))
	h.check(absf(arrow.get_velocity().length() - _boss.arrow_speed) < 1.0, "at the arrow speed (%.0f)" % arrow.get_velocity().length())
	while _boss.get_attack_phase() != ArtemisBoss.AttackPhase.RECOVER and t < 4.0:
		await h.tree.physics_frame
		t += _dt()
	var recover := 0.0
	while _boss.get_state() == ArtemisBoss.State.ATTACK and recover < 2.0:
		await h.tree.physics_frame
		recover += _dt()
	h.check(absf(recover - _boss.shot_recover_time) < 0.06, "the recovery window lasts %.1f s (%.2f)" % [_boss.shot_recover_time, recover])
	h.check(_boss.get_state() == ArtemisBoss.State.REPOSITION, "and she goes back to repositioning")
	_end_case()


func case_arrow_hurts_luz() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_boss._launch_arrow(Vector2(300.0, -29.0), Vector2.LEFT)
	await h.secs(1.8)
	h.check(_player.get_health() == 2, "an arrow costs Luz one pip (%d)" % _player.get_health())
	h.check(_boss.active_arrow_count() == 0, "and is spent on her")
	_end_case()


func case_arrow_ignored_during_dash() -> void:
	await _build_rig(Vector2.ZERO)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_player.request_dash()
	await h.secs(0.05)
	_boss._launch_arrow(_player.global_position + Vector2(20.0, -29.0), Vector2.LEFT)
	await h.secs(0.8)
	h.check(_player.get_health() == 3, "the dash i-frames let an arrow pass through (%d)" % _player.get_health())
	_boss._launch_arrow(_player.global_position + Vector2(80.0, -29.0), Vector2.LEFT)
	await h.secs(0.6)
	h.check(_player.get_health() == 2, "the same arrow hurts once the dash is over (%d)" % _player.get_health())
	_end_case()


# -- Movement ----------------------------------------------------------------------------

func case_backstep_when_close() -> void:
	await _build_rig(Vector2(60.0, 0.0))
	await _add_boss(Vector2.ZERO, {"opening_delay": 0.05, "dodge_chance": 0.0, "feint_chance": 0.0})
	var seen := await _sees_state(ArtemisBoss.State.BACKSTEP, 0.8)
	h.check(seen, "Luz inside the backstep distance makes her hop away")
	h.check(_boss.global_position.x < -40.0, "away from Luz (x %.0f)" % _boss.global_position.x)
	h.check(_boss.get_facing() == 1, "while still facing her")
	_end_case()


func case_backstep_refused_at_walls_and_ledges() -> void:
	var tweaks := {"opening_delay": 0.05, "dodge_chance": 0.0, "feint_chance": 0.0}
	await _build_rig(Vector2(370.0, 0.0))
	await _add_boss(Vector2(430.0, 0.0), tweaks)
	var hopped := false
	var max_x := 0.0
	for i: int in int(0.9 / _dt()):
		await h.tree.physics_frame
		hopped = hopped or _boss.get_state() == ArtemisBoss.State.BACKSTEP
		max_x = maxf(max_x, _boss.global_position.x)
	h.check(not hopped, "with a wall behind her she does not backstep")
	h.check(max_x < 438.0, "and never pushes into it (x %.1f)" % max_x)
	await _build_rig(Vector2(220.0, 0.0), true, LEDGE_FLOOR, false)
	await _add_boss(Vector2(280.0, 0.0), tweaks)
	hopped = false
	var max_y := -1000.0
	for i: int in int(0.9 / _dt()):
		await h.tree.physics_frame
		hopped = hopped or _boss.get_state() == ArtemisBoss.State.BACKSTEP
		max_y = maxf(max_y, _boss.global_position.y)
	h.check(not hopped, "with a ledge behind her she does not backstep")
	h.check(max_y < 2.0, "and never falls off it (y %.1f)" % max_y)
	_end_case()


func case_dodge() -> void:
	await _build_rig(Vector2.ZERO)
	await _add_boss(Vector2(100.0, 0.0), {
		"dodge_chance": 1.0, "feint_chance": 0.0, "opening_delay": 0.05,
		"reposition_min_time": 5.0, "reposition_max_time": 5.0,
		"backstep_trigger_distance": 0.0, "kite_speed": 0.0,
	})
	await h.secs(0.3)
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.RECOVER)
	_player.request_attack(0)
	await h.secs(0.15)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK, "she never dodges while recovering from her own attack")
	await h.secs(0.9)
	_player.request_attack(0)
	var dodged := await _sees_state(ArtemisBoss.State.DODGE, 0.3)
	h.check(dodged, "a Luz attack startup within reach is dodged")
	await h.secs(0.4)
	h.check(_boss.global_position.x > 130.0, "by hopping away from her (x %.0f)" % _boss.global_position.x)
	await h.secs(0.5)
	_player.request_attack(0)
	var again := await _sees_state(ArtemisBoss.State.DODGE, 0.3)
	h.check(not again, "the dodge has a cooldown")
	_end_case()


func case_kite_and_walls() -> void:
	var tweaks := {
		"opening_delay": 0.05, "dodge_chance": 0.0, "feint_chance": 0.0,
		"backstep_trigger_distance": 0.0, "reposition_min_time": 99.0, "reposition_max_time": 99.0,
	}
	await _build_rig(Vector2(100.0, 0.0))
	await _add_boss(Vector2.ZERO, tweaks)
	await h.secs(2.0)
	var near := _distance_to_luz()
	h.check(near > 170.0 and near < 200.0, "too close, she backs off to the preferred distance (%.0f)" % near)
	_place_luz(Vector2(400.0, 0.0))
	await h.secs(3.0)
	var far := _distance_to_luz()
	h.check(far > 240.0 and far < 270.0, "too far, she closes in to the preferred distance (%.0f)" % far)
	_boss.global_position = Vector2(400.0, 0.0)
	_place_luz(Vector2(300.0, 0.0))
	await h.secs(1.5)
	h.check(_boss.global_position.x < 438.0 and _boss.global_position.y < 2.0, "kiting into a wall stops at it (x %.1f)" % _boss.global_position.x)
	_end_case()


func case_feint() -> void:
	await _build_rig(Vector2.ZERO)
	await _add_boss(Vector2(200.0, 0.0), {
		"feint_chance": 1.0, "dodge_chance": 0.0, "opening_delay": 0.05,
		"reposition_min_time": 0.1, "reposition_max_time": 0.1, "backstep_trigger_distance": 0.0,
	})
	var seen := false
	var closest := 1.0e9
	for i: int in int(1.2 / _dt()):
		await h.tree.physics_frame
		seen = seen or _boss.get_state() == ArtemisBoss.State.FEINT
		closest = minf(closest, _distance_to_luz())
	h.check(seen, "she feints toward Luz")
	h.check(closest > _boss.feint_stop_distance - 12.0 and closest < _boss.feint_stop_distance + 2.0, "and stops just outside melee range (%.0f)" % closest)
	h.check(_player.get_health() == 3, "without touching her")
	h.check(_distance_to_luz() > closest + 15.0, "then retreats (%.0f)" % _distance_to_luz())
	_end_case()


# -- Stagger and checkpoint --------------------------------------------------------------

func case_stagger() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_hit(5)
	h.check(_boss.get_state() != ArtemisBoss.State.STAGGER, "five quick hits do not stagger her")
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.STAGGER, "the sixth inside the window does")
	await h.secs(1.3)
	h.check(_boss.get_state() == ArtemisBoss.State.STAGGER, "the stagger lasts about %.1f s" % _boss.stagger_time)
	await h.secs(0.5)
	h.check(_boss.get_state() != ArtemisBoss.State.STAGGER, "and then she recovers")
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(6)
	h.check(_boss.get_state() == ArtemisBoss.State.STAGGER, "a stagger interrupts a telegraph")
	h.check(not _boss.get_telegraph().is_aim_line_visible(), "its aim line disappears")
	await h.secs(0.9)
	h.check(_boss.active_arrow_count() == 0, "and the interrupted arrow is never fired")
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	for i: int in 6:
		_hit(1)
		await h.secs(0.6)
	h.check(_boss.get_state() != ArtemisBoss.State.STAGGER, "six hits spread over more than the window do not stagger her")
	_end_case()


func case_checkpoint_reset() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_hit(15)
	_boss._launch_arrow(Vector2(300.0, -29.0), Vector2.LEFT)
	h.cps.reset_resettable_enemies()
	h.check(_boss.get_health() == 30 and _boss.get_phase() == 1, "a checkpoint reset restores full health and phase one")
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE, "and puts her back to idle")
	h.check(_boss.active_arrow_count() == 0, "and recalls every arrow")
	h.check(not phases.is_empty() and phases[-1] == 1, "listeners are told about phase one again")
	_hit(30)
	h.check(_boss.is_dead(), "she can be defeated again")
	h.cps.reset_resettable_enemies()
	var visual := _boss.get_node("Visual") as Node2D
	var revived := not _boss.is_dead() and _boss.visible and _boss.collision_layer == Enemy.ENEMY_LAYER
	h.check(revived and is_equal_approx(visual.modulate.a, 1.0), "a reset after defeat revives her solid and fully visible")
	_end_case()


func case_reset_after_defeat_fade() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0, "opening_delay": 0.05})
	_hit(30)
	await h.secs(_boss.defeat_time + 0.4)
	h.cps.reset_resettable_enemies()
	await h.frames(3)
	h.check(_boss.is_physics_processing() and _boss.visible, "a reset after the defeat fade switches her processing back on")
	await h.secs(0.5)
	h.check(_boss.get_state() != ArtemisBoss.State.IDLE, "and she acts again instead of standing frozen (state %d)" % _boss.get_state())
	_end_case()


# -- Fan volley ------------------------------------------------------------------------

func _muzzle_position() -> Vector2:
	return (_boss.get_node("Visual/Bow/Muzzle") as Node2D).global_position


func case_fan_volley() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_boss.start_attack(ArtemisBoss.Attack.FAN)
	var t := 0.0
	var max_lines := 0
	var glow_seen := false
	while _boss.is_telegraphing() and t < 2.0:
		await h.tree.physics_frame
		t += _dt()
		max_lines = maxi(max_lines, _boss.get_telegraph().visible_aim_line_count())
		glow_seen = glow_seen or _boss.get_telegraph().is_glowing()
	h.check(t >= 0.35 and absf(t - _boss.fan_telegraph_time) < 0.05, "the fan telegraph lasts %.2f s, never under 0.35 (%.2f)" % [_boss.fan_telegraph_time, t])
	h.check(max_lines == _boss.fan_count and glow_seen, "it shows one aim line per arrow plus a glow (%d lines)" % max_lines)
	h.check(_boss.get_telegraph().visible_aim_line_count() == 0 and not _boss.get_telegraph().is_glowing(), "and both are gone once she fires")
	h.check(_boss.active_arrow_count() == _boss.fan_count, "exactly fan_count arrows fly (%d)" % _boss.active_arrow_count())
	var wanted := (_player.global_position + CENTER - _muzzle_position()).normalized()
	var angles: Array[float] = []
	for arrow: EnemyProjectile in _boss.get_active_arrows():
		angles.append(rad_to_deg(wanted.angle_to(arrow.get_velocity().normalized())))
	angles.sort()
	var spread_ok := angles.size() == 3
	if spread_ok:
		spread_ok = absf(angles[1] - angles[0] - _boss.fan_spread_degrees) < 1.0 and absf(angles[2] - angles[1] - _boss.fan_spread_degrees) < 1.0
	h.check(spread_ok, "neighbouring arrows are %.0f degrees apart (%s)" % [_boss.fan_spread_degrees, angles])
	h.check(angles.size() == 3 and absf(angles[1]) < 1.5, "and the fan is centred on Luz (%.1f degrees off)" % (angles[1] if angles.size() == 3 else 999.0))
	var recover := 0.0
	while _boss.get_state() == ArtemisBoss.State.ATTACK and recover < 2.0:
		await h.tree.physics_frame
		recover += _dt()
	h.check(absf(recover - _boss.fan_recover_time - _boss.fan_active_time) < 0.08, "the recovery window lasts %.1f s (%.2f)" % [_boss.fan_recover_time, recover])
	_end_case()


# -- Arrow rain ------------------------------------------------------------------------

const QUIET := {
	"wake_distance": 0.0, "reposition_min_time": 99.0, "reposition_max_time": 99.0,
	"kite_speed": 0.0, "backstep_trigger_distance": 0.0, "dodge_chance": 0.0,
}


## Starts a rain with Luz at `luz_x` and returns the zones once its telegraph ends.
func _rain_telegraph(luz_x: float, stats: Dictionary) -> Array[Rect2]:
	await _build_rig(Vector2(luz_x, 0.0))
	await _add_boss(Vector2(300.0, 0.0), QUIET)
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	var t := 0.0
	var marker_time := 0.0
	var max_markers := 0
	while _boss.is_telegraphing() and t < 2.0:
		await h.tree.physics_frame
		t += _dt()
		var shown := 0
		for i: int in BossTelegraph.MARKER_POOL_SIZE:
			shown += 1 if _boss.get_telegraph().is_floor_marker_visible(i) else 0
		max_markers = maxi(max_markers, shown)
		marker_time += _dt() if shown > 0 else 0.0
	stats["time"] = t
	stats["marker_time"] = marker_time
	stats["markers"] = max_markers
	return _boss.get_rain_zones()


func _gaps_are_open(zones: Array[Rect2]) -> bool:
	for i: int in range(1, zones.size()):
		if zones[i].position.x - zones[i - 1].end.x < _boss.rain_gap_width - 0.5:
			return false
	return true


func case_arrow_rain() -> void:
	var stats := {}
	var zones := await _rain_telegraph(0.0, stats)
	h.check(float(stats["time"]) >= 0.35 and absf(float(stats["time"]) - _boss.rain_telegraph_time) < 0.05, "the rain telegraph lasts %.2f s, never under 0.35 (%.2f)" % [_boss.rain_telegraph_time, stats["time"]])
	h.check(int(stats["markers"]) == _boss.rain_zone_count and float(stats["marker_time"]) >= 0.35, "a floor marker per zone shows for at least 0.35 s (%d, %.2f s)" % [stats["markers"], stats["marker_time"]])
	h.check(zones.size() == _boss.rain_zone_count and _gaps_are_open(zones), "the zones leave gaps of at least %.0f px between them" % _boss.rain_gap_width)
	h.check(_boss.active_arrow_count() == zones.size() * ceili(_boss.rain_zone_width / ArtemisBoss.RAIN_ARROW_STEP), "arrows then fall on every zone (%d)" % _boss.active_arrow_count())
	var gap_x := (zones[0].end.x + zones[1].position.x) * 0.5
	_place_luz(Vector2(gap_x, 0.0))
	await h.secs(1.2)
	h.check(_player.get_health() == 3, "Luz standing in a gap is not hit (%d)" % _player.get_health())
	_end_case()
	zones = await _rain_telegraph(0.0, stats)
	await h.secs(1.2)
	h.check(_player.get_health() == 2, "Luz standing in a zone is hit (%d)" % _player.get_health())
	_end_case()
	zones = await _rain_telegraph(440.0, stats)
	var inside := not zones.is_empty()
	for zone: Rect2 in zones:
		inside = inside and zone.position.x >= -450.0 and zone.end.x <= 450.0
	h.check(inside and _gaps_are_open(zones), "against a wall the zones stay inside the arena and keep their gaps (%d zones)" % zones.size())
	_end_case()


# -- Dagger slash ------------------------------------------------------------------------

const DAGGER_TWEAKS := {
	"opening_delay": 0.05, "backstep_trigger_distance": 0.0, "dodge_chance": 0.0, "feint_chance": 0.0,
	"reposition_min_time": 0.7, "reposition_max_time": 0.7, "kite_speed": 0.0,
}


func case_dagger_slash() -> void:
	await _build_rig(Vector2(-55.0, 0.0))
	await _add_boss(Vector2.ZERO, DAGGER_TWEAKS)
	var waited := 0.0
	while _boss.get_state() != ArtemisBoss.State.ATTACK and waited < 3.0:
		await h.tree.physics_frame
		waited += _dt()
	h.check(_boss.get_attack() == ArtemisBoss.Attack.DAGGER and waited > _boss.dagger_trigger_time, "Luz lingering close forces the dagger after %.1f s (%.2f s)" % [_boss.dagger_trigger_time, waited])
	var t := 0.0
	var armed_early := false
	var glow_seen := false
	while _boss.is_telegraphing() and t < 1.0:
		await h.tree.physics_frame
		t += _dt()
		armed_early = armed_early or (_boss.is_telegraphing() and _boss.is_dagger_active())
		glow_seen = glow_seen or _boss.get_telegraph().is_glowing()
	h.check(t >= 0.35 and glow_seen, "the dagger telegraph glows for at least 0.35 s (%.2f)" % t)
	h.check(not armed_early and _player.get_health() == 3, "the hitbox is off and Luz unhurt while it telegraphs")
	var armed := false
	var retreat_seen := false
	for i: int in int(0.5 / _dt()):
		await h.tree.physics_frame
		armed = armed or _boss.is_dagger_active()
		retreat_seen = retreat_seen or _boss.get_state() == ArtemisBoss.State.BACKSTEP
	h.check(armed and _player.get_health() == 2, "the armed hitbox hurts Luz (%d)" % _player.get_health())
	h.check(retreat_seen and not _boss.is_dagger_active(), "she backflips away right after, hitbox off, with no punish window")
	h.check(_boss.global_position.x > 80.0, "far from Luz (x %.0f)" % _boss.global_position.x)
	_end_case()


func case_dagger_blocked_by_dash() -> void:
	await _build_rig(Vector2(-55.0, 0.0))
	await _add_boss(Vector2.ZERO, QUIET)
	_boss.start_attack(ArtemisBoss.Attack.DAGGER)
	await h.secs(_boss.dagger_telegraph_time - 0.07)
	_player.request_dash()
	var covered := false
	for i: int in int(0.6 / _dt()):
		await h.tree.physics_frame
		if _boss.is_dagger_active() and (_boss.get_node("DaggerHitbox") as Area2D).overlaps_body(_player):
			covered = covered or _player.is_dash_invulnerable()
	h.check(covered, "Luz was dashing inside the armed hitbox")
	h.check(_player.get_health() == 3, "and her dash i-frames made the slash miss (%d)" % _player.get_health())
	_end_case()


# -- Attack selection ----------------------------------------------------------------------

func _draws(luz_x: float, n: int) -> Array[int]:
	_place_luz(Vector2(luz_x, 0.0))
	var out: Array[int] = []
	for i: int in n:
		out.append(_boss._choose_attack())
	return out


func _never_repeats(draws: Array[int]) -> bool:
	for i: int in range(1, draws.size()):
		if draws[i] == draws[i - 1]:
			return false
	return true


func case_attack_selection() -> void:
	await _build_rig(Vector2(0.0, 0.0))
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	var far := _draws(0.0, 120)
	var mid := _draws(80.0, 120)
	var near := _draws(200.0, 120)
	h.check(_never_repeats(far) and _never_repeats(mid) and _never_repeats(near), "she never picks the same attack twice in a row")
	var far_kinds := {}
	for a: int in far:
		far_kinds[a] = true
	h.check(not far_kinds.has(ArtemisBoss.Attack.DAGGER) and far_kinds.size() == 3, "far away she mixes shot, fan and rain and never the dagger")
	h.check(not mid.has(ArtemisBoss.Attack.DAGGER), "at mid range there is no dagger either")
	h.check(near.count(ArtemisBoss.Attack.DAGGER) > near.size() * 0.4 and not near.has(ArtemisBoss.Attack.RAIN), "up close the dagger is preferred and rain is out")
	var seeded: Array[Array] = []
	for run: int in 2:
		_boss.rng.seed = 5
		_boss._last_attack = ArtemisBoss.NO_ATTACK
		seeded.append(_draws(0.0, 20))
	h.check(seeded[0] == seeded[1], "the same seed gives the same choices")
	_boss._last_attack = ArtemisBoss.NO_ATTACK
	_boss._luz_close_time = _boss.dagger_trigger_time + 0.1
	var forced: int = _boss._choose_attack()
	var again: int = _boss._choose_attack()
	h.check(forced == ArtemisBoss.Attack.DAGGER and again != ArtemisBoss.Attack.DAGGER, "a lingering Luz forces one dagger, then the usual draw resumes")
	_end_case()


# -- Phase two: transition, recoveries, chains ------------------------------------------------

const P2 := ArtemisBoss.PHASE_TWO
const P2_QUIET := {
	"wake_distance": 0.0, "reposition_min_time": 99.0, "reposition_max_time": 99.0,
	"kite_speed": 0.0, "backstep_trigger_distance": 0.0, "dodge_chance": 0.0,
	"feint_chance": 0.0, "stagger_hits": 0, "chain_chance": 0.0,
}


## A Luz that survives every hit the tests throw at her.
func _tough_luz() -> void:
	_player.set_max_health(30)
	_player.heal(30)


func case_phase_transition() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(15)
	h.check(_boss.get_state() == ArtemisBoss.State.TRANSITION and not _boss.get_telegraph().is_aim_line_visible(), "crossing the threshold interrupts a telegraph and starts the transition")
	h.check(phases == [2], "phase_changed(2) is emitted once (%s)" % [phases])
	var landed := _boss.receive_hit(1, HIT_FROM, &"attack_1")
	h.check(landed and _boss.get_health() == 14, "she stays hittable during the transition (%d)" % _boss.get_health())
	var glow_seen := false
	var t := 0.0
	while _boss.get_state() == ArtemisBoss.State.TRANSITION and t < 0.9:
		await h.tree.physics_frame
		t += _dt()
		glow_seen = glow_seen or _boss.get_telegraph().is_glowing()
	h.check(glow_seen and _boss.active_arrow_count() == 0, "she glows silver and does not attack")
	await h.secs(0.3)
	h.check(absf(_boss.phase_two_transition_time - 1.0) < 0.001 and _boss.get_state() != ArtemisBoss.State.TRANSITION and not _boss.get_telegraph().is_glowing(), "the beat lasts about a second, then the glow is gone")
	_hit(1)
	h.check(_boss.get_state() != ArtemisBoss.State.TRANSITION and phases == [2], "it never plays twice")
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.ACTIVE)
	_hit(15)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK, "a strike that is already active is not interrupted")
	var entered := await _sees_state(ArtemisBoss.State.TRANSITION, 0.5)
	h.check(entered, "the transition starts once the strike is over")
	_end_case()


func _recover_duration() -> float:
	var t := 0.0
	while _boss.get_attack_phase() != ArtemisBoss.AttackPhase.RECOVER and t < 4.0:
		await h.tree.physics_frame
		t += _dt()
	var recover := 0.0
	while _boss.get_state() == ArtemisBoss.State.ATTACK and recover < 3.0:
		await h.tree.physics_frame
		recover += _dt()
	return recover


func case_phase_two_recoveries() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	var shot := await _recover_duration()
	h.check(absf(shot - _boss.shot_recover_time * _boss.phase_two_recover_scale) < 0.06, "the shot recovery is 15%% shorter in phase two (%.2f)" % shot)
	_boss.start_attack(ArtemisBoss.Attack.STAG)
	var stag := await _recover_duration()
	h.check(absf(stag - _boss.stag_recover_time * _boss.phase_two_recover_scale) < 0.06, "and so is the stag's, a new attack (%.2f)" % stag)
	_end_case()


## Attacks started, in order, over `seconds` of play.
func _run_string(first: ArtemisBoss.Attack, tweaks: Dictionary, luz_x: float, boss_x: float, phase: int, seconds: float) -> Array[int]:
	await _build_rig(Vector2(luz_x, 0.0))
	_tough_luz()
	await _add_boss(Vector2(boss_x, 0.0), tweaks)
	_boss._phase = phase
	_boss.start_attack(first)
	var seen: Array[int] = []
	var was_telegraphing := false
	for i: int in int(seconds / _dt()):
		await h.tree.physics_frame
		var now := _boss.is_telegraphing()
		if now and not was_telegraphing:
			seen.append(_boss.get_attack())
		was_telegraphing = now
	return seen


func _no_repeats(attacks: Array[int]) -> bool:
	for i: int in range(1, attacks.size()):
		if attacks[i] == attacks[i - 1]:
			return false
	return true


func case_chained_strings() -> void:
	var tweaks := P2_QUIET.duplicate()
	tweaks["chain_chance"] = 1.0
	var dagger := ArtemisBoss.Attack.DAGGER
	var shot := ArtemisBoss.Attack.AIMED_SHOT
	var rain := ArtemisBoss.Attack.RAIN
	var full := await _run_string(dagger, tweaks, -55.0, 0.0, P2, 6.0)
	h.check(full == [dagger, shot, rain], "dagger flip chains into a shot, then a rain: %s" % [full])
	h.check(_no_repeats(full) and _boss.get_state() == ArtemisBoss.State.REPOSITION, "never the same attack twice, and the string ends in a reposition")
	var capped := tweaks.duplicate()
	capped["chain_max_length"] = 2
	var short := await _run_string(dagger, capped, -55.0, 0.0, P2, 6.0)
	h.check(short == [dagger, shot] and _boss.get_state() == ArtemisBoss.State.REPOSITION, "chain_max_length forces the reposition after that many attacks: %s" % [short])
	var phase_one := await _run_string(dagger, tweaks, -55.0, 0.0, 1, 3.0)
	h.check(phase_one == [dagger], "phase one never chains: %s" % [phase_one])
	var seeded := P2_QUIET.duplicate()
	seeded["chain_chance"] = 0.5
	var first_run := await _run_string(shot, seeded, 0.0, 300.0, P2, 5.0)
	var second_run := await _run_string(shot, seeded, 0.0, 300.0, P2, 5.0)
	h.check(first_run == second_run and _no_repeats(first_run), "with the seeded rng the strings repeat exactly: %s" % [first_run])
	var hop_seen := false
	await _build_rig(Vector2(0.0, 0.0))
	await _add_boss(Vector2(300.0, 0.0), tweaks)
	_boss._phase = P2
	_boss.start_attack(shot)
	hop_seen = await _sees_state(ArtemisBoss.State.BACKSTEP, 2.5)
	h.check(hop_seen, "a shot string hops back before the rain")
	_end_case()


# -- Moon dive ------------------------------------------------------------------------------

func _contact_on() -> bool:
	return (_boss.get_node("ContactDamage") as Area2D).monitoring


func case_moon_dive() -> void:
	await _build_rig(Vector2(0.0, 0.0))
	_tough_luz()
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	var t := 0.0
	var stage := 0
	var locked_time := 0.0
	var marker_during_lock := true
	var off_ok := false
	var tracked_left := false
	var tracked_right := false
	while _boss.is_telegraphing() and t < 3.0:
		await h.tree.physics_frame
		t += _dt()
		if t > 0.5 and stage == 0:
			_place_luz(Vector2(-120.0, 0.0))
			stage = 1
		elif t > 0.65 and stage == 1:
			tracked_left = absf(_boss.get_dive_x() + 120.0) < 3.0
			stage = 2
		elif t > 0.8 and stage == 2:
			_place_luz(Vector2(100.0, 0.0))
			stage = 3
		elif t > 0.9 and stage == 3:
			tracked_right = absf(_boss.get_dive_x() - 100.0) < 3.0
			stage = 4
		elif _boss.is_dive_locked() and stage == 4:
			_place_luz(Vector2(-200.0, 0.0))
			stage = 5
		if _boss.is_telegraphing() and _boss.is_dive_locked():
			locked_time += _dt()
			marker_during_lock = marker_during_lock and _boss.get_telegraph().is_floor_marker_visible(0)
		if _boss.is_offscreen() and not off_ok:
			await h.frames(2)
			off_ok = not _boss.receive_hit(1, HIT_FROM, &"attack_1") and _boss.collision_layer == 0 and not _contact_on() and not (_boss.get_node("Visual") as Node2D).visible
	h.check(off_ok, "off-screen she cannot be hit and deals no contact damage")
	h.check(tracked_left and tracked_right, "the marker tracks Luz's x while she leaps and tracks")
	h.check(absf(_boss.get_dive_x() - 100.0) < 3.0, "then it locks and ignores Luz moving away (%.0f)" % _boss.get_dive_x())
	h.check(locked_time >= 0.35 and marker_during_lock, "the lock lasts at least 0.35 s with the marker shown (%.2f)" % locked_time)
	await h.frames(8)
	h.check(absf(_boss.global_position.x - 100.0) < 3.0 and _player.get_health() == 30, "she dives onto the locked x and Luz, elsewhere, is untouched (x %.0f)" % _boss.global_position.x)
	var stuck := await _recover_duration()
	h.check(stuck >= 1.2 - 0.03, "stuck in the ground for at least 1.2 s even in phase two (%.2f)" % stuck)
	_end_case()


func case_moon_dive_stuck_is_a_punish_window() -> void:
	await _build_rig(Vector2(0.0, 0.0))
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	var t := 0.0
	while _boss.get_attack_phase() != ArtemisBoss.AttackPhase.RECOVER and t < 4.0:
		await h.tree.physics_frame
		t += _dt()
	await h.frames(3)
	h.check(_player.get_health() == 2, "the impact hurts Luz standing at the locked x (%d)" % _player.get_health())
	h.check(_boss.collision_layer == Enemy.ENEMY_LAYER and _boss.visible and not _boss.is_offscreen(), "once she is stuck she is solid and visible again")
	h.check(not _contact_on(), "her body is harmless while she is stuck, so Luz can punish")
	h.check(_boss.receive_hit(1, HIT_FROM, &"attack_1"), "and she can be hit")
	await _recover_duration()
	await h.frames(3)
	h.check(_contact_on() and _boss.get_state() != ArtemisBoss.State.ATTACK, "contact damage returns when she moves again")
	_end_case()


func case_moon_dive_dash() -> void:
	var tweaks := P2_QUIET.duplicate()
	tweaks["dive_speed"] = 100000.0
	tweaks["dive_impact_time"] = 0.5
	await _build_rig(Vector2(0.0, 0.0))
	await _add_boss(Vector2(300.0, 0.0), tweaks)
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	var t := 0.0
	while not (_boss.is_telegraphing() and _boss._state_left < 0.04) and t < 3.0:
		await h.tree.physics_frame
		t += _dt()
	_player.request_dash()
	var covered := false
	for i: int in int(0.7 / _dt()):
		await h.tree.physics_frame
		if _boss.is_dive_hitbox_armed() and (_boss.get_node("DiveHitbox") as Area2D).overlaps_body(_player):
			covered = covered or _player.is_dash_invulnerable()
	h.check(covered, "Luz was dashing inside the armed impact")
	h.check(_player.get_health() == 3, "and her dash i-frames made the dive miss (%d)" % _player.get_health())
	_end_case()


# -- Spectral stag --------------------------------------------------------------------------------

func _stag_run(react: String) -> Dictionary:
	await _build_rig(LUZ_START)
	_tough_luz()
	var tweaks := P2_QUIET.duplicate()
	tweaks["arena_half_width"] = 900.0
	await _add_boss(Vector2(0.0, 0.0), tweaks)
	_boss._phase = P2
	var stag := _boss.get_stag()
	var out := {"min_x": 1.0e9, "start_x": 0.0, "clearance": 1.0e9, "covered": false, "edge": 0.0, "telegraph": 0.0, "hittable": false, "dir": 0}
	_boss.start_attack(ArtemisBoss.Attack.STAG)
	var t := 0.0
	while _boss.is_telegraphing() and t < 2.0:
		await h.tree.physics_frame
		t += _dt()
		out["edge"] += _dt() if _boss.get_telegraph().is_floor_marker_visible(0) else 0.0
		out["hittable"] = out["hittable"] or _boss.collision_layer == Enemy.ENEMY_LAYER
	out["telegraph"] = t
	var acted := false
	for i: int in int(3.5 / _dt()):
		await h.tree.physics_frame
		if stag.is_active():
			if out["start_x"] == 0.0:
				out["start_x"] = stag.global_position.x
				out["dir"] = stag.get_direction()
			out["min_x"] = minf(out["min_x"], stag.global_position.x)
			var dx := absf(stag.global_position.x - _player.global_position.x)
			if not acted and dx < (150.0 if react == "jump" else 200.0) and react != "none":
				acted = true
				if react == "jump":
					_player.request_jump()
				else:
					_player.request_dash()
			if dx < SpectralStag.WIDTH * 0.5 + 14.0:
				out["clearance"] = minf(out["clearance"], -_player.global_position.y)
				out["covered"] = out["covered"] or _player.is_dash_invulnerable()
		elif out["start_x"] != 0.0:
			break
	out["active_after"] = stag.is_active()
	out["visible_after"] = stag.visible
	out["hit"] = stag.has_hit()
	return out


func case_spectral_stag() -> void:
	var run := await _stag_run("none")
	h.check(float(run["edge"]) >= 0.35 and absf(float(run["telegraph"]) - _boss.stag_telegraph_time) < 0.05, "the edge glow lasts %.1f s, never under 0.35 (%.2f / %.2f)" % [_boss.stag_telegraph_time, run["edge"], run["telegraph"]])
	h.check(run["hittable"], "she stands casting, solid and hittable, meanwhile")
	h.check(int(run["dir"]) == -1 and float(run["start_x"]) > 400.0, "it appears at the wall farthest from Luz (x %.0f)" % run["start_x"])
	h.check(float(run["min_x"]) < -400.0, "it charges across the whole arena (to x %.0f)" % run["min_x"])
	h.check(_player.get_health() == 29 and run["hit"], "a grounded Luz is hit exactly once (%d)" % _player.get_health())
	h.check(not run["active_after"] and not run["visible_after"], "and it despawns at the far wall")
	_end_case()
	run = await _stag_run("jump")
	h.check(float(run["clearance"]) > SpectralStag.HEIGHT and _player.get_health() == 30, "a normal jump clears it (%.0f px up, health %d)" % [run["clearance"], _player.get_health()])
	_end_case()
	run = await _stag_run("dash")
	h.check(run["covered"] and _player.get_health() == 30, "a dash passes through it (health %d)" % _player.get_health())
	_end_case()


# -- Cornered vault --------------------------------------------------------------------------------

const WALL_SIDE := Vector2(430.0, 0.0)


func _vault_rig(luz_x: float, tweaks := {}) -> void:
	var all := P2_QUIET.duplicate()
	all.merge(tweaks, true)
	await _build_rig(Vector2(luz_x, 0.0))
	_tough_luz()
	await _add_boss(WALL_SIDE, all)
	_boss.engage()


func case_cornered_vault() -> void:
	await _vault_rig(340.0)
	var t := 0.0
	while _boss.get_state() != ArtemisBoss.State.VAULT and t < 1.5:
		await h.tree.physics_frame
		t += _dt()
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT and t > _boss.vault_trigger_time - 0.05, "Luz in her face with a wall at her back triggers the vault after %.1f s (%.2f)" % [_boss.vault_trigger_time, t])
	var crouch := 0.0
	var glow_seen := false
	while _boss.get_vault_phase() == ArtemisBoss.VaultPhase.CROUCH and crouch < 1.0:
		await h.tree.physics_frame
		crouch += _dt()
		glow_seen = glow_seen or _boss.get_telegraph().is_glowing()
	h.check(crouch >= 0.35 - 0.03 and glow_seen, "a crouch with a white glow warns for at least 0.35 s (%.2f)" % crouch)
	h.check(not _contact_on(), "no contact damage during the vault by default")
	var apex := 0.0
	var air := 0.0
	while _boss.get_state() == ArtemisBoss.State.VAULT and air < 3.0:
		await h.tree.physics_frame
		air += _dt()
		apex = minf(apex, _boss.global_position.y)
	h.check(apex < -100.0, "the arc clears Luz's 58 px body with room to spare (apex %.0f)" % apex)
	h.check(_boss.global_position.x < _player.global_position.x, "she lands on the other side of Luz (x %.0f)" % _boss.global_position.x)
	h.check(_boss.global_position.x > -450.0 + 13.0 and _boss.global_position.x < 450.0 - 13.0, "inside the arena")
	h.check(_player.get_health() == 30, "and Luz is not hurt")
	h.check(_boss.get_state() == ArtemisBoss.State.REPOSITION, "after the short landing recovery she repositions")
	_boss.global_position = WALL_SIDE
	_boss.velocity = Vector2.ZERO
	await h.secs(1.2)
	h.check(_boss.get_state() != ArtemisBoss.State.VAULT, "the cooldown stops a second vault right away")
	_end_case()
	await _vault_rig(340.0, {"vault_contact_damage": true})
	await h.secs(0.5)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT and _contact_on(), "contact damage during the vault is an exported option")
	_end_case()


func case_vault_on_hit_and_priority() -> void:
	await _vault_rig(200.0)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT, "a hit while cornered makes her vault even with Luz far")
	_end_case()
	await _vault_rig(200.0)
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.ACTIVE)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK, "never while an attack is active")
	_end_case()
	await _vault_rig(400.0)
	_boss._luz_close_time = _boss.dagger_trigger_time + 0.5
	_boss._pick_next_action()
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT, "cornered, the vault takes priority over the forced dagger")
	_end_case()
	await _vault_rig(400.0)
	_boss._luz_close_time = _boss.dagger_trigger_time + 0.5
	_boss._vault_left = 3.0
	_boss._pick_next_action()
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK and _boss.get_attack() == ArtemisBoss.Attack.DAGGER, "on cooldown the dagger answers instead")
	_end_case()
	await _vault_rig(0.0)
	_boss.global_position = Vector2.ZERO
	await h.secs(0.8)
	h.check(_boss.get_state() != ArtemisBoss.State.VAULT, "in the open with Luz close she does not vault")
	_end_case()


# -- Selection, guards and reset in phase two ------------------------------------------------------

func case_phase_two_selection() -> void:
	await _build_rig(Vector2(0.0, 0.0))
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	var one: Array[int] = []
	for x: float in [0.0, 80.0, 200.0]:
		one.append_array(_draws(x, 150))
	h.check(one.max() <= ArtemisBoss.Attack.DAGGER, "phase one never draws the moon dive or the stag")
	_boss._phase = P2
	_boss._last_attack = ArtemisBoss.NO_ATTACK
	var two := _draws(0.0, 200)
	h.check(two.has(ArtemisBoss.Attack.MOON_DIVE) and two.has(ArtemisBoss.Attack.STAG) and _never_repeats(two), "phase two mixes them in and still never repeats")
	_end_case()


func case_attack_without_luz() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK, "an external rain without Luz does not crash")
	_boss.start_attack(ArtemisBoss.Attack.STAG)
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	h.check(_boss._arena_bounds().x < _boss._arena_bounds().y, "nor do the dive, the stag or the arena bounds")
	h.check(_boss.get_node("WallProbe").position == Vector2(0.0, -24.0), "and the wall probe goes back where it was")
	_end_case()


func case_phase_two_reset() -> void:
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	_hit(15)
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	await h.secs(0.7)
	h.check(_boss.is_offscreen(), "mid-dive she is off-screen")
	h.cps.reset_resettable_enemies()
	await h.frames(3)
	h.check(_boss.get_phase() == 1 and _boss.get_state() == ArtemisBoss.State.IDLE, "a checkpoint reset returns to phase one and idle")
	h.check(_boss.visible and _boss.collision_layer == Enemy.ENEMY_LAYER and not _boss.is_offscreen() and _contact_on(), "and she is back, solid and harmful")
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.STAG)
	await h.secs(1.2)
	var running := _boss.get_stag().is_active()
	h.cps.reset_resettable_enemies()
	await h.frames(2)
	h.check(running and not _boss.get_stag().is_active(), "a reset also recalls the stag")
	_hit(15)
	h.check(_boss.get_state() == ArtemisBoss.State.TRANSITION, "and phase two can start again afterwards")
	_end_case()


# -- Advisories (e) and (f) -------------------------------------------------------------------

## A pending follow-up starts only at the end of the hop that belongs to its own
## string. A plain backstep or dodge in between must not fire it.
func case_plain_hops_never_chain() -> void:
	await _build_rig(Vector2(60.0, 0.0))
	await _add_boss(Vector2.ZERO, P2_QUIET)
	_boss._phase = P2
	_boss._chain_next = ArtemisBoss.Attack.RAIN
	h.check(_boss._try_backstep(), "the plain backstep starts")
	await h.secs(0.6)
	h.check(_boss.get_state() == ArtemisBoss.State.REPOSITION and _boss._chain_next == ArtemisBoss.NO_ATTACK, "its end repositions and drops the stale follow-up")
	_boss._chain_next = ArtemisBoss.Attack.RAIN
	h.check(_boss._try_chain_hop(), "the string's own hop starts")
	await h.secs(0.6)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK and _boss.get_attack() == ArtemisBoss.Attack.RAIN, "its end starts the follow-up at once")
	_end_case()


## Counts how many times the transition beat starts in `seconds` of physics.
func _transition_starts(seconds: float) -> int:
	var starts := 0
	var was := false
	for i: int in int(seconds / _dt()):
		await h.tree.physics_frame
		var now := _boss.get_state() == ArtemisBoss.State.TRANSITION
		starts += 1 if now and not was else 0
		was = now
	return starts


func case_transition_postponed_by_stagger() -> void:
	var tweaks := P2_QUIET.duplicate()
	tweaks["stagger_hits"] = 6
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), tweaks)
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_hit(15)
	h.check(_boss.get_state() == ArtemisBoss.State.STAGGER and phases == [2], "crossing the threshold inside a stagger waits for it (%s)" % [phases])
	var starts := await _transition_starts(_boss.stagger_time + 0.3)
	h.check(starts == 1, "the beat then starts exactly once (%d)" % starts)
	await h.secs(_boss.phase_two_transition_time + 0.2)
	h.check(_boss.get_state() != ArtemisBoss.State.STAGGER and _boss.get_state() != ArtemisBoss.State.TRANSITION, "the stagger and the beat are both over")
	starts = await _transition_starts(1.5)
	h.check(starts == 0 and phases == [2], "and never again")
	_end_case()


func case_transition_postponed_by_vault() -> void:
	await _vault_rig(340.0)
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT, "a hit while cornered starts the vault")
	_hit(14)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT and phases == [2], "crossing the threshold mid-vault waits for it (%s)" % [phases])
	var starts := await _transition_starts(2.5)
	h.check(starts == 1, "the beat then starts exactly once after the landing (%d)" % starts)
	await h.secs(_boss.phase_two_transition_time + 0.2)
	starts = await _transition_starts(1.5)
	h.check(starts == 0 and _boss.get_phase() == 2, "and never again")
	_end_case()


# -- Interrupt ---------------------------------------------------------------------------------------

const INTERRUPT := {"wake_distance": 0.0, "interrupt_enabled": true, "stagger_hits": 0}


func _interrupts() -> Array[int]:
	var seen: Array[int] = []
	_boss.attack_interrupted.connect(func(attack: int) -> void: seen.append(attack))
	return seen


func case_interrupt_aimed_shot() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), INTERRUPT)
	var seen := _interrupts()
	var fresh := (load(BOSS_SCENE) as PackedScene).instantiate() as ArtemisBoss
	h.check(fresh.interrupt_enabled, "interrupts are on by default")
	fresh.free()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH and seen == [ArtemisBoss.Attack.AIMED_SHOT], "a hit during the wind-up cancels it and flinches (%s)" % [seen])
	h.check(not _boss.get_telegraph().is_aim_line_visible() and not _boss.get_telegraph().is_glowing(), "the aim line and the glow are gone")
	h.check(_boss.get_health() == 29, "the hit still deals its damage")
	h.check(await _sees_state(ArtemisBoss.State.BACKSTEP, 0.45), "after the flinch she escapes with a backstep")
	await h.secs(0.4)
	h.check(_boss.active_arrow_count() == 0, "and no arrow was ever fired")
	_boss.clear_arrows()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(1)
	h.check(_boss.is_telegraphing() and seen.size() == 1, "inside the poise window a hit does not interrupt the next wind-up")
	await h.secs(0.5)
	h.check(_boss.active_arrow_count() == 1, "and the arrow is fired")
	await h.secs(_boss.interrupt_cooldown)
	_boss.clear_arrows()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH and seen.size() == 2, "once the cooldown is over a hit interrupts again")
	_end_case()


func case_interrupt_dagger() -> void:
	await _build_rig(Vector2(-55.0, 0.0))
	await _add_boss(Vector2.ZERO, INTERRUPT)
	var seen := _interrupts()
	_boss.start_attack(ArtemisBoss.Attack.DAGGER)
	await h.secs(0.15)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH and seen == [ArtemisBoss.Attack.DAGGER], "a hit cancels the dagger wind-up (%s)" % [seen])
	h.check(not _boss.is_dagger_active() and not _boss.get_telegraph().is_glowing(), "no hitbox and no glow")
	await h.secs(0.8)
	h.check(_player.get_health() == 3, "Luz is never slashed (%d)" % _player.get_health())
	_end_case()


func case_interrupt_rain() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), INTERRUPT)
	var seen := _interrupts()
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	await h.secs(0.5)
	h.check(_boss.get_telegraph().is_floor_marker_visible(0), "the rain markers show first")
	_hit(1)
	h.check(seen == [ArtemisBoss.Attack.RAIN] and not _boss.get_telegraph().is_floor_marker_visible(0) and _boss.get_rain_zones().is_empty(), "a hit clears the markers and the zones")
	await h.secs(0.9)
	h.check(_boss.active_arrow_count() == 0, "no arrow falls")
	_end_case()


func case_interrupt_not_after_release() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), INTERRUPT)
	var seen := _interrupts()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.ACTIVE)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK and _boss.active_arrow_count() == 1, "a hit while the arrow leaves does not cancel it")
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.RECOVER)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.ATTACK and _boss.get_attack_phase() == ArtemisBoss.AttackPhase.RECOVER, "nor does a hit during the recovery")
	h.check(seen.is_empty() and _boss.get_health() == 28, "no interrupt, both hits deal damage")
	_boss._set_attack_phase(ArtemisBoss.AttackPhase.TELEGRAPH)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH, "the poise was never spent: the next wind-up is interruptible")
	_end_case()


func case_interrupt_vault_crouch() -> void:
	await _vault_rig(340.0, {"interrupt_enabled": true})
	var seen := _interrupts()
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT and seen.is_empty(), "the hit that starts the vault does not interrupt anything")
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH and seen == [-1], "a hit during the crouch cancels the vault (%s)" % [seen])
	await h.secs(_boss.interrupt_flinch_time + 0.1)
	h.check(_boss.get_state() == ArtemisBoss.State.VAULT, "cornered, she escapes by vaulting once the flinch ends")
	var t := 0.0
	while _boss.get_state() == ArtemisBoss.State.VAULT and t < 3.0:
		await h.tree.physics_frame
		t += _dt()
	h.check(_boss.global_position.x < _player.global_position.x, "and lands on the other side of Luz (x %.0f)" % _boss.global_position.x)
	_end_case()


func case_interrupt_phase_two_and_stagger() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0, "interrupt_enabled": true})
	_boss._phase = ArtemisBoss.PHASE_TWO
	_boss.start_attack(ArtemisBoss.Attack.FAN)
	await h.secs(0.1)
	_hit(1)
	h.check(_boss.get_state() == ArtemisBoss.State.FLINCH and absf(_boss._interrupt_left - _boss.phase_two_interrupt_cooldown) < 0.05, "phase two interrupts with its own cooldown (%.2f)" % _boss._interrupt_left)
	h.check(_boss.phase_two_interrupt_cooldown > _boss.interrupt_cooldown, "which is longer than phase one's")
	_end_case()
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0, "interrupt_enabled": true})
	var seen := _interrupts()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(6)
	h.check(_boss.get_state() == ArtemisBoss.State.STAGGER, "the sixth hit staggers her: stagger still wins")
	h.check(seen.size() == 1 and _boss.active_arrow_count() == 0, "and no arrow is fired")
	_end_case()


# -- Arrows --------------------------------------------------------------------------------------------------

func case_arrows_live_beside_the_boss() -> void:
	await _build_rig(Vector2.ZERO)
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	var beside := true
	for arrow: EnemyProjectile in _boss._pool:
		beside = beside and arrow.get_parent() == _rig and not _boss.is_ancestor_of(arrow)
	h.check(beside and _boss._pool.size() >= ArtemisBoss.ARROW_POOL_SIZE, "the pooled arrows are siblings of the boss (%d)" % _boss._pool.size())
	var extra := _boss._make_arrow()
	await h.frames(2)
	h.check(extra.get_parent() == _rig, "an arrow grown beyond the pool is moved beside her too")
	_boss.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_boss._launch_arrow(Vector2(200.0, -100.0), Vector2.LEFT, 10.0)
	var arrow := _boss.get_active_arrows()[0]
	h.check(arrow.is_visible_in_tree() and arrow.get_parent() == _rig, "an arrow stays visible whatever her modulate")
	_boss.visible = false
	h.check(arrow.is_visible_in_tree(), "and when she is hidden")
	_boss.visible = true
	_boss.clear_arrows()
	h.check(_boss.active_arrow_count() == 0, "clear_arrows still empties the pool")
	_boss._launch_arrow(Vector2(200.0, -100.0), Vector2.LEFT, 10.0)
	_boss.make_corpse_at(_boss.global_position, 1)
	h.check(_boss.active_arrow_count() == 0, "and so does her defeat")
	_end_case()
	var points := (load("res://scenes/enemies/bosses/artemis_arrow.tscn") as PackedScene).instantiate()
	var shape := (points.get_node("Visual") as Polygon2D).polygon
	points.free()
	h.check(not Geometry2D.triangulate_polygon(shape).is_empty(), "the arrow outline triangulates: a polygon that does not is drawn as nothing")


# -- Platforms (T7) -----------------------------------------------------------------------

const PLATFORM := Rect2(-60.0, -104.0, 120.0, 20.0)
## Zones with Luz at x 0: [-148, -92], [-28, 28], [92, 148]. The platform covers the middle one.
const PLATFORM_MARKER_Y := -104.0 - ArtemisBoss.RAIN_MARKER_HEIGHT
const FLOOR_MARKER_Y := -ArtemisBoss.RAIN_MARKER_HEIGHT
const ON_PLATFORM := Vector2(0.0, -105.0)
const CLOSE_TWEAKS := {
	"wake_distance": 0.0, "kite_speed": 0.0, "reposition_min_time": 0.7, "reposition_max_time": 0.7,
	"dodge_chance": 0.0, "feint_chance": 0.0, "stagger_hits": 0, "opening_delay": 0.05,
}


func _add_platform(rect: Rect2) -> void:
	LevelGeometry.add_one_way_platform(_rig, rect, Color.STEEL_BLUE)
	await _steps(3)


## A rig with one platform, Luz placed after it exists (she settles on it) and a
## quiet boss at `boss_at`.
func _platform_rig(platform: Rect2, luz_at: Vector2, boss_at: Vector2, tweaks: Dictionary) -> void:
	await _build_rig(LUZ_START)
	await _add_platform(platform)
	_tough_luz()
	_place_luz(luz_at)
	await _add_boss(boss_at, tweaks)


## Starts a rain over `platform` with Luz at `luz_at`; returns when its telegraph ends.
func _platform_rain(platform: Rect2, luz_at: Vector2) -> void:
	await _platform_rig(platform, luz_at, Vector2(300.0, 0.0), QUIET)
	_player.set_max_health(3)
	_player.heal(3)
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	var t := 0.0
	while _boss.is_telegraphing() and t < 2.0:
		await h.tree.physics_frame
		t += _dt()


func case_rain_respects_platforms() -> void:
	await _platform_rain(PLATFORM, Vector2.ZERO)
	var markers := _boss.get_rain_markers()
	var heights_ok := markers.size() == 3
	if heights_ok:
		heights_ok = absf(markers[0].position.y - FLOOR_MARKER_Y) < 0.5 and absf(markers[1].position.y - PLATFORM_MARKER_Y) < 0.5 and absf(markers[2].position.y - FLOOR_MARKER_Y) < 0.5
	h.check(heights_ok, "the marker of a zone over a platform sits on its top, the others on the floor (%d markers)" % markers.size())
	var lowest := -1.0e9
	for i: int in int(0.7 / _dt()):
		await h.tree.physics_frame
		for arrow: EnemyProjectile in _boss.get_active_arrows():
			if absf(arrow.global_position.x) < 28.0:
				lowest = maxf(lowest, arrow.global_position.y)
	h.check(lowest <= PLATFORM.position.y, "the arrows over the platform never get below its top (%.0f)" % lowest)
	await h.secs(0.5)
	h.check(_player.get_health() == 3 and _boss.active_arrow_count() == 0, "Luz under the platform is not hit (%d)" % _player.get_health())
	_end_case()
	await _platform_rain(PLATFORM, ON_PLATFORM)
	await h.secs(1.2)
	h.check(_player.get_health() == 2, "Luz on the platform inside a zone is hit (%d)" % _player.get_health())
	_end_case()
	await _platform_rain(Rect2(0.0, -104.0, 60.0, 20.0), Vector2.ZERO)
	markers = _boss.get_rain_markers()
	var split := markers.size() == 4
	if split:
		split = absf(markers[1].end.x - 0.0) < 5.0 and absf(markers[1].position.y - FLOOR_MARKER_Y) < 0.5 and absf(markers[2].position.x - 0.0) < 5.0 and absf(markers[2].position.y - PLATFORM_MARKER_Y) < 0.5
	h.check(split, "a zone over a platform edge is split: floor marker beside platform marker (%d markers)" % markers.size())
	_end_case()


func case_aimed_arrows_and_one_ways() -> void:
	await _platform_rig(PLATFORM, LUZ_START, Vector2(300.0, 0.0), QUIET)
	_boss._launch_arrow(Vector2(-20.0, -200.0), Vector2(0.3, 1.0).normalized())
	var down := _boss.get_active_arrows()[0]
	await h.secs(1.0)
	h.check(not down.is_active() and absf(down.global_position.y - PLATFORM.position.y) < 12.0, "an arrow flying down stops on the platform top (y %.0f)" % down.global_position.y)
	_boss._launch_arrow(Vector2(0.0, -50.0), Vector2(0.2, -1.0).normalized())
	var up := _boss.get_active_arrows()[0]
	await h.secs(0.5)
	h.check(up.is_active() and up.global_position.y < PLATFORM.position.y - 20.0, "an arrow flying up passes through it (y %.0f)" % up.global_position.y)
	_boss._launch_arrow(Vector2(-200.0, -94.0), Vector2.RIGHT)
	var flat := _boss.get_active_arrows()[0]
	await h.secs(0.8)
	h.check(flat.is_active() and flat.global_position.x > PLATFORM.end.x, "a flat arrow passes through it (x %.0f)" % flat.global_position.x)
	_end_case()


func case_dive_column_reaches_a_platform() -> void:
	await _platform_rig(PLATFORM, ON_PLATFORM, Vector2(300.0, 0.0), P2_QUIET)
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	var t := 0.0
	var locked_time := 0.0
	var column := Rect2()
	var column_shown := false
	while _boss.is_telegraphing() and t < 3.0:
		await h.tree.physics_frame
		t += _dt()
		if _boss.is_dive_locked() and _boss.is_telegraphing():
			locked_time += _dt()
			column = _boss.get_dive_column()
			column_shown = _boss.get_telegraph().is_floor_marker_visible(ArtemisBoss.DIVE_COLUMN_SLOT)
	var reaches := column.has_point(ON_PLATFORM + ArtemisBoss.PLAYER_CENTER_OFFSET) and absf(column.end.y) < 0.5 and column.position.y < PLATFORM.position.y - 100.0
	h.check(reaches and column_shown, "a silver column from the drop height to the floor is shown over Luz on the platform")
	h.check(locked_time >= 0.35, "the column stays locked for at least 0.35 s (%.2f)" % locked_time)
	await h.secs(0.2)
	h.check(not _boss.get_telegraph().is_floor_marker_visible(ArtemisBoss.DIVE_COLUMN_SLOT), "the column is cleared once she drops")
	await h.secs(0.6)
	h.check(_player.get_health() < 30, "the falling hitbox hits Luz on the platform (%d)" % _player.get_health())
	h.check(absf(_boss.global_position.y) < 1.0 and _boss.is_on_floor(), "she lands on the floor, not the platform (y %.1f)" % _boss.global_position.y)
	_end_case()


## Runs `seconds` with Luz at `luz_at` and reports which close-range reactions fired.
func _close_run(platform: Rect2, luz_at: Vector2, boss_at: Vector2, tweaks: Dictionary, seconds: float) -> Dictionary:
	await _platform_rig(platform, luz_at, boss_at, tweaks)
	_boss.engage()
	var seen := {"backstep": false, "dagger": false, "vault": false}
	for i: int in int(seconds / _dt()):
		await h.tree.physics_frame
		var state := _boss.get_state()
		seen["backstep"] = seen["backstep"] or state == ArtemisBoss.State.BACKSTEP
		seen["vault"] = seen["vault"] or state == ArtemisBoss.State.VAULT
		seen["dagger"] = seen["dagger"] or _boss.is_dagger_forced() or (state == ArtemisBoss.State.ATTACK and _boss.get_attack() == ArtemisBoss.Attack.DAGGER)
	_end_case()
	return seen


func case_proximity_needs_same_height() -> void:
	var near := Vector2(30.0, 0.0)
	var backstep := (await _close_run(PLATFORM, Vector2.ZERO, near, CLOSE_TWEAKS, 1.0))["backstep"] as bool
	h.check(backstep, "control: Luz at her height in her face makes her hop back")
	backstep = (await _close_run(PLATFORM, ON_PLATFORM, near, CLOSE_TWEAKS, 1.5))["backstep"] as bool
	h.check(not backstep, "Luz on a platform right above her does not")
	var no_hop := CLOSE_TWEAKS.duplicate()
	no_hop["backstep_trigger_distance"] = 0.0
	var dagger := (await _close_run(PLATFORM, Vector2.ZERO, near, no_hop, 2.0))["dagger"] as bool
	h.check(dagger, "control: Luz at her height for a while forces the dagger")
	dagger = (await _close_run(PLATFORM, ON_PLATFORM, near, no_hop, 2.0))["dagger"] as bool
	h.check(not dagger, "Luz on a platform above her never does")
	var cornered := P2_QUIET.duplicate()
	var side_platform := Rect2(290.0, -104.0, 120.0, 20.0)
	var vault := (await _close_run(side_platform, Vector2(350.0, 0.0), WALL_SIDE, cornered, 1.5))["vault"] as bool
	h.check(vault, "control: Luz at her height with a wall at her back makes her vault")
	vault = (await _close_run(side_platform, Vector2(350.0, -105.0), WALL_SIDE, cornered, 1.5))["vault"] as bool
	h.check(not vault, "Luz on a platform above her does not")
	await _platform_rig(PLATFORM, ON_PLATFORM, near, CLOSE_TWEAKS)
	h.check(_boss._distance_band() == ArtemisBoss.Band.MID, "Luz high above counts as the middle band (ranged), never near")
	_place_luz(Vector2.ZERO)
	await _steps(4)
	h.check(_boss._distance_band() == ArtemisBoss.Band.NEAR, "and at her height the same distance is near")
	_end_case()


func case_never_stands_on_a_platform() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0), QUIET)
	h.check(not _boss.get_collision_mask_value(2) and (_boss.get_node("FloorProbe") as RayCast2D).collision_mask == 1, "her body and floor probe see solids only")
	_end_case()
	# The platform sits where her vault lands: she must fall through to the floor.
	await _platform_rig(Rect2(200.0, -100.0, 120.0, 20.0), Vector2(340.0, 0.0), WALL_SIDE, P2_QUIET)
	_boss.engage()
	var t := 0.0
	var vaulted := false
	while t < 3.0 and not (vaulted and _boss.get_state() != ArtemisBoss.State.VAULT):
		await h.tree.physics_frame
		t += _dt()
		vaulted = vaulted or _boss.get_state() == ArtemisBoss.State.VAULT
	await _steps(30)
	var landed := _boss.global_position
	h.check(vaulted and landed.x > 200.0 and landed.x < 320.0 and absf(landed.y) < 1.0, "a vault that lands over a platform ends on the floor (%.0f, %.0f)" % [landed.x, landed.y])
	_end_case()
	# A low platform in the path of her backstep, high enough to catch a hop.
	await _platform_rig(Rect2(60.0, -15.0, 120.0, 20.0), Vector2.ZERO, Vector2(30.0, 0.0), {"wake_distance": 0.0, "kite_speed": 0.0, "reposition_min_time": 99.0, "reposition_max_time": 99.0, "dodge_chance": 0.0, "feint_chance": 0.0})
	_boss.engage()
	var hopped := await _sees_state(ArtemisBoss.State.BACKSTEP, 0.5)
	await h.secs(0.6)
	h.check(hopped and _boss.global_position.x > 60.0 and absf(_boss.global_position.y) < 1.0, "a backstep across a low platform ends on the floor (%.0f, %.1f)" % [_boss.global_position.x, _boss.global_position.y])
	_end_case()


# -- Defeat feel, corpse, audio cues and shakes (T8, T9) -----------------------------------

func _add_spy() -> Node:
	var spy := ShakeSpy.new() as Camera2D
	_rig.add_child(spy)
	spy.make_current()
	return spy


## True once Engine.time_scale is back to 1.0, waiting up to `limit` REAL seconds.
func _wait_normal_speed(limit: float) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not is_equal_approx(Engine.time_scale, 1.0) and Time.get_ticks_msec() < end:
		await h.tree.process_frame
	return is_equal_approx(Engine.time_scale, 1.0)


func _record_cues() -> Array[StringName]:
	var cues: Array[StringName] = []
	_boss.sfx_cue.connect(func(cue: StringName) -> void: cues.append(cue))
	return cues


const SLOWMO := {"stagger_hits": 0, "phase_two_threshold": 0.0, "final_freeze_time": 0.05, "final_slowmo_time": 0.12, "final_slowmo_scale": 0.3}


func case_final_blow_restores_time_scale() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), SLOWMO)
	var spy := _add_spy()
	var cues := _record_cues()
	_hit(29)
	h.check(is_equal_approx(Engine.time_scale, 1.0), "before the killing blow the clock is untouched")
	_hit(1)
	var flash := _boss.get_node("FinalFlash") as ScreenFlash
	h.check(Engine.time_scale < 0.5 and flash.is_flashing(), "the killing blow freezes the world and flashes the screen white (%.2f)" % Engine.time_scale)
	h.check(spy.shakes.size() == 1 and is_equal_approx(spy.shakes[0].x, _boss.final_shake_strength), "and asks the camera for a strong shake (%s)" % [spy.shakes])
	h.check(cues == [ArtemisBoss.CUE_DEFEAT], "and plays the defeat cue (%s)" % [cues])
	h.check(await _wait_normal_speed(3.0), "the clock returns to 1.0 by itself")
	_end_case()
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), SLOWMO)
	_hit(30)
	_free_rig()
	h.check(Engine.time_scale < 0.5, "freed right after the killing blow, the world is still slowed")
	h.check(await _wait_normal_speed(3.0), "but the clock is restored even though the boss is gone")
	_end_case()
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0})
	_hit(30)
	h.check(is_equal_approx(Engine.time_scale, 1.0), "with freeze and slow motion at 0 the clock is never touched")
	_end_case()


func case_corpse_stays() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0})
	var settled: Array[int] = []
	_boss.corpse_settled.connect(func() -> void: settled.append(1))
	_hit(30)
	await h.secs(_boss.defeat_time + 0.4)
	var visual := _boss.get_node("Visual") as Node2D
	h.check(settled == [1] and not _boss.is_physics_processing(), "the collapse ends once and she rests (%s)" % [settled])
	h.check(visual.modulate.is_equal_approx(Enemy.CORPSE_TINT) and absf(visual.scale.y - ArtemisBoss.CORPSE_SQUASH_Y) < 0.01, "dimmed and squashed in a kneeling pose")
	h.check(absf(visual.rotation) > 0.3 and signf(visual.rotation) == float(_boss.get_facing()), "slumped forward, toward where she faced (%.2f)" % visual.rotation)
	var bow := _boss.get_node("Visual/Bow") as Node2D
	h.check(bow.position.is_equal_approx(ArtemisBoss.BOW_DROPPED_POSITION), "the bow lies dropped in front of her")
	h.check(_boss.collision_layer == 0, "no collision")
	await h.frames(2)
	h.check(not (_boss.get_node("ContactDamage") as Area2D).monitoring, "no contact damage")
	h.check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "not hittable")
	var here := _boss.global_position
	await h.secs(0.5)
	h.check(_boss.global_position == here and _boss.visible, "and she stays where she fell")
	_end_case()
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"stagger_hits": 0})
	_boss.global_position = Vector2(300.0, -120.0)
	_boss.velocity = Vector2.ZERO
	settled.clear()
	_boss.corpse_settled.connect(func() -> void: settled.append(1))
	_hit(30)
	await h.secs(_boss.defeat_time + 0.8)
	h.check(settled == [1] and absf(_boss.global_position.y) < 2.0, "killed in mid-air she falls first, then rests on the floor (y %.1f)" % _boss.global_position.y)
	_end_case()


func case_audio_cue_slots() -> void:
	await _build_rig(LUZ_START, false)
	await _add_boss(Vector2(300.0, 0.0))
	var names: Array[StringName] = [
		ArtemisBoss.CUE_BOW_DRAW, ArtemisBoss.CUE_BOW_RELEASE, ArtemisBoss.CUE_RAIN_WHISTLE, ArtemisBoss.CUE_RAIN_IMPACT,
		ArtemisBoss.CUE_DAGGER_SWISH, ArtemisBoss.CUE_VAULT_CROUCH, ArtemisBoss.CUE_DIVE_LEAP, ArtemisBoss.CUE_DIVE_IMPACT,
		ArtemisBoss.CUE_STAG_HORN, ArtemisBoss.CUE_STAG_CHARGE, ArtemisBoss.CUE_FLINCH, ArtemisBoss.CUE_STAGGER,
		ArtemisBoss.CUE_PHASE_TWO, ArtemisBoss.CUE_DEFEAT,
	]
	var all_slots := true
	for cue: StringName in names:
		var player := _boss.get_node_or_null("Sfx/" + String(cue)) as AudioStreamPlayer2D
		all_slots = all_slots and player != null and player.stream == null
	h.check(all_slots and _boss.get_node("Sfx").get_child_count() == names.size(), "every cue has an empty AudioStreamPlayer2D under Sfx (%d)" % names.size())
	var cues := _record_cues()
	var silent := true
	for cue: StringName in names:
		_boss.play_cue(cue)
		silent = silent and not _boss.get_cue_player(cue).playing
	h.check(silent and cues == names, "playing an empty slot is a no-op that still announces the cue")
	_boss.play_cue(&"NoSuchCue")
	h.check(cues.size() == names.size() + 1, "an unknown cue is ignored without an error")
	_end_case()


func case_cues_ranged_attacks() -> void:
	for pair: Array in [
		[ArtemisBoss.Attack.AIMED_SHOT, [ArtemisBoss.CUE_BOW_DRAW, ArtemisBoss.CUE_BOW_RELEASE]],
		[ArtemisBoss.Attack.FAN, [ArtemisBoss.CUE_BOW_DRAW, ArtemisBoss.CUE_BOW_RELEASE]],
		[ArtemisBoss.Attack.RAIN, [ArtemisBoss.CUE_RAIN_WHISTLE, ArtemisBoss.CUE_BOW_RELEASE, ArtemisBoss.CUE_RAIN_IMPACT]],
		[ArtemisBoss.Attack.DAGGER, [ArtemisBoss.CUE_DAGGER_SWISH]],
	]:
		await _build_rig()
		_tough_luz()
		await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
		var cues := _record_cues()
		_boss.start_attack(pair[0])
		await h.secs(3.0)
		h.check(cues == pair[1], "attack %d fires its cues in order (%s)" % [pair[0], cues])
		_end_case()


func case_cues_phase_two_and_shakes() -> void:
	await _build_rig(Vector2(0.0, 0.0))
	_tough_luz()
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	var spy := _add_spy()
	var cues := _record_cues()
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.MOON_DIVE)
	await h.secs(2.4)
	h.check(cues == [ArtemisBoss.CUE_DIVE_LEAP, ArtemisBoss.CUE_DIVE_IMPACT], "the dive plays its leap and its impact (%s)" % [cues])
	h.check(spy.has_shake(_boss.dive_shake_strength), "and shakes the camera on the impact (%s)" % [spy.shakes])
	_end_case()
	await _build_rig(LUZ_START)
	_tough_luz()
	await _add_boss(Vector2(0.0, 0.0), P2_QUIET.merged({"arena_half_width": 900.0}))
	spy = _add_spy()
	cues = _record_cues()
	_boss._phase = P2
	_boss.start_attack(ArtemisBoss.Attack.STAG)
	await h.secs(1.2)
	h.check(cues == [ArtemisBoss.CUE_STAG_HORN, ArtemisBoss.CUE_STAG_CHARGE], "the stag has a horn at the telegraph and a charge at the launch (%s)" % [cues])
	h.check(spy.has_shake(_boss.stag_shake_strength), "and the launch shakes the camera lightly")
	_end_case()
	await _build_rig(LUZ_START)
	await _add_boss(Vector2(300.0, 0.0), P2_QUIET)
	spy = _add_spy()
	cues = _record_cues()
	_hit(15)
	h.check(cues.has(ArtemisBoss.CUE_PHASE_TWO), "phase two announces itself")
	h.check(spy.has_shake(_boss.phase_shake_strength), "and shakes the camera when the transition starts")
	_end_case()


func case_cues_reactions() -> void:
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), INTERRUPT)
	var cues := _record_cues()
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.2)
	_hit(1)
	h.check(cues == [ArtemisBoss.CUE_BOW_DRAW, ArtemisBoss.CUE_FLINCH], "a cancelled wind-up flinches (%s)" % [cues])
	_end_case()
	await _build_rig()
	await _add_boss(Vector2(300.0, 0.0), {"wake_distance": 0.0})
	cues = _record_cues()
	_hit(6)
	h.check(cues.has(ArtemisBoss.CUE_STAGGER), "the stagger has its cue")
	_end_case()
	await _vault_rig(340.0)
	cues = _record_cues()
	var t := 0.0
	while _boss.get_state() != ArtemisBoss.State.VAULT and t < 1.5:
		await h.tree.physics_frame
		t += _dt()
	h.check(cues.has(ArtemisBoss.CUE_VAULT_CROUCH), "the vault crouch has its cue")
	_end_case()

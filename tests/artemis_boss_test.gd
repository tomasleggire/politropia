extends "res://tests/support/ritual_suite.gd"
## Artemis boss (T1): scene basics, health and defeat, the phase threshold, the
## aimed shot and its arrow, the dash i-frames, backstep, dodge, feint, kiting,
## walls and ledges, stagger and the checkpoint reset. Each case builds its own
## floor (top at y=0), Luz and boss, and tweaks exports so only the behaviour
## under test can happen. Timings are measured in physics steps.
##
## This suite runs inside the single runner (stillness_desk_ritual_test.gd),
## before any level scene is loaded: the boss targets the first node of group
## `player`, so no other Luz may exist.

const BOSS_SCENE := "res://scenes/enemies/bosses/artemis.tscn"
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
	h.check(not _boss.visible, "no corpse is left: she fades out and disappears")
	h.check(not _boss.is_physics_processing(), "and her AI is switched off")
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

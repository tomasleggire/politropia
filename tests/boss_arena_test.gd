extends "res://tests/support/ritual_suite.gd"
## BossArena (T4): the trigger, doors, camera lock, boss health bar, the reset
## when Luz dies, the defeat, the double jump reward and the permanent defeat.
## Each case builds its own floor (top at y=0), Luz and an arena with an Artemis
## child, and shortens the intro timings so every wait is a few tenths of a
## second. Luz starts outside the trigger, which spans x -200..200.
##
## Like the Artemis suite this one runs inside the single runner, before any
## level scene is loaded: the boss targets the first node of group `player`.

const ShakeSpy := preload("res://tests/support/shake_spy_camera.gd")
const ARENA_SCENE := "res://scenes/enemies/bosses/boss_arena.tscn"
const PREFAB_SCENE := "res://scenes/enemies/bosses/artemis_boss_arena.tscn"
const BOSS_SCENE := "res://scenes/enemies/bosses/artemis.tscn"
const TEST_ARENA_SCENE := "res://scenes/levels/test/artemis_arena.tscn"
const HUD_SCENE := "res://scenes/ui/health_hud.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LUZ_START := Vector2(-300.0, 0.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const BOSS_START := Vector2(300.0, 0.0)
const ARENA_RECT := Rect2(-434.0, -340.0, 868.0, 400.0)
const HIT_FROM := Vector2(100.0, 0.0)
const ROOM := &"A"
const BOSS_ID := &"artemis"
const SETTLE_FRAMES := 20
const VIEWPORT_RECT := Rect2(0.0, 0.0, 640.0, 360.0)
## The health pips and the soul meter: top-left, from the HUD margins.
const HUD_CORNER := Rect2(0.0, 0.0, 80.0, 60.0)
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.4, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const CHECKS := {
	"case_trigger_starts_fight": 11,
	"case_boss_health_bar": 11,
	"case_luz_death_resets_arena": 17,
	"case_defeat_opens_arena_and_rewards": 9,
	"case_reward_options": 3,
	"case_defeat_is_permanent": 10,
	"case_room_camera_lock": 4,
	"case_arena_limits_bound_boss": 5,
	"case_armed_boss_is_untouchable": 3,
	"case_dead_boss_while_armed_never_locks": 7,
	"case_rearm_survives_free": 4,
	"case_engaged_boss_always_hittable": 6,
	"case_test_arena_shows_luz_hud": 3,
	"case_corpse_is_inert": 8,
	"case_corpse_reloads_where_she_fell": 18,
	"case_boss_progress_round_trip": 8,
	"case_arena_cues_and_door_shake": 6,
	"case_prefab_is_one_drag": 8,
}

var _rig: Node2D
var _player: Player
var _arena: BossArena
var _boss: ArtemisBoss
var _camera: Camera2D
var _limits_before: Array[int] = []


func expected_checks() -> Dictionary:
	return CHECKS


# -- Rig and helpers -----------------------------------------------------------------

func _registry() -> Node:
	return h.tree.root.get_node("EnemyRegistry")


func _progress() -> Node:
	return h.tree.root.get_node("BossProgress")


func _reset_world() -> void:
	_free_rig()
	h.cps.clear()
	_registry().clear()
	_progress().clear()
	_rig = Node2D.new()
	h.tree.root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(-482.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(434.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM


func _add_luz() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = LUZ_START
	_rig.add_child(_player)
	_player.set_max_health(30)
	_player.heal(30)
	_player.set_checkpoint(LUZ_START)
	_place_luz(LUZ_START)


func _make_boss() -> ArtemisBoss:
	var boss := (load(BOSS_SCENE) as PackedScene).instantiate() as ArtemisBoss
	boss.enemy_id = BOSS_ID
	boss.position = BOSS_START
	boss.rng_seed = 11
	boss.stagger_hits = 0
	# The killing blow's slow motion would only stretch the waits here.
	boss.final_freeze_time = 0.0
	boss.final_slowmo_time = 0.0
	return boss


## An arena at the origin holding its boss, with fast intro timings. The boss
## must be a child before the arena enters the tree (the arena looks for it in
## `_ready`).
func _make_arena(tweaks := {}) -> BossArena:
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate() as BossArena
	arena.arena_rect = ARENA_RECT
	for key: String in ARENA_TIMINGS:
		arena.set(key, ARENA_TIMINGS[key])
	for key: String in tweaks:
		arena.set(key, tweaks[key])
	arena.add_child(_make_boss())
	_rig.add_child(arena)
	return arena


func _build(tweaks := {}) -> void:
	_reset_world()
	_add_luz()
	_arena = _make_arena(tweaks)
	_boss = _arena.get_boss() as ArtemisBoss
	await h.frames(SETTLE_FRAMES)
	_camera = _player.get_viewport().get_camera_2d()
	_limits_before = _camera_limits()


func _camera_limits() -> Array[int]:
	return [_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom]


func _arena_limits() -> Array[int]:
	return [int(ARENA_RECT.position.x), int(ARENA_RECT.position.y), int(ARENA_RECT.end.x), int(ARENA_RECT.end.y)]


func _place_luz(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null
	_arena = null
	_boss = null
	_camera = null


func _end_case() -> void:
	BossFeel.cancel()
	_free_rig()
	_registry().clear()
	_progress().clear()
	h.cps.clear()


func _enter_trigger() -> void:
	_place_luz(IN_TRIGGER)
	await h.secs(0.12)


func _hit(n: int) -> void:
	for i: int in n:
		_boss.receive_hit(1, HIT_FROM, &"attack_1")


func _kill_luz() -> void:
	_player._apply_damage(99, HIT_FROM, false, true)


## Into the trigger and past the intro delay: she is hittable only once engaged.
func _enter_fight() -> void:
	await _enter_trigger()
	await h.secs(0.3)


func _doors_blocking() -> bool:
	var blocking := true
	for door: StaticBody2D in _arena.get_doors():
		var shape := door.get_node("CollisionShape2D") as CollisionShape2D
		blocking = blocking and not shape.disabled and door.collision_layer == 1
	return blocking


func _doors_passable() -> bool:
	var passable := true
	for door: StaticBody2D in _arena.get_doors():
		passable = passable and (door.get_node("CollisionShape2D") as CollisionShape2D).disabled
	return passable


# -- Start ----------------------------------------------------------------------------

func case_trigger_starts_fight() -> void:
	await _build()
	var started: Array[int] = []
	_arena.fight_started.connect(func() -> void: started.append(1))
	await h.secs(1.0)
	h.check(not _arena.are_doors_closed() and _doors_passable() and not _arena.get_bar().is_bar_shown(), "with Luz outside the trigger the doors are open and no bar shows")
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE and _camera_limits() == _limits_before, "the boss stays idle even with Luz in her wake range, and the camera is free")
	await _enter_trigger()
	h.check(_arena.get_state() == BossArena.FightState.ACTIVE and started == [1], "Luz entering the trigger starts the fight once (%s)" % [started])
	h.check(_arena.are_doors_closed() and _doors_blocking(), "the two doors close and block (layer 1)")
	var bar := _arena.get_bar()
	h.check(bar.is_bar_shown() and bar.get_name_text() == "Artemis" and bar.get_health_ratio() == 1.0, "the boss bar shows her name at full health")
	h.check(bar.is_title_shown(), "and the title card is up")
	h.check(_camera_limits() == _arena_limits(), "the camera is locked to the arena rect (%s)" % [_camera_limits()])
	h.check(_boss._arena_bounds() == Vector2(ARENA_RECT.position.x, ARENA_RECT.end.x), "the boss clamps to the arena walls (%s)" % [_boss._arena_bounds()])
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE, "she is still idle during the intro delay")
	await h.secs(0.3)
	h.check(_boss.get_state() != ArtemisBoss.State.IDLE, "she is engaged once the delay is over")
	await h.secs(0.4)
	h.check(not bar.is_title_shown() and bar.is_bar_shown(), "the title card goes away after its time, the bar stays")
	_end_case()


# -- Health bar ------------------------------------------------------------------------

func case_boss_health_bar() -> void:
	await _build()
	await _enter_fight()
	var bar := _arena.get_bar()
	bar.set_safe_area(VIEWPORT_RECT)
	_hit(3)
	h.check(is_equal_approx(bar.get_health_ratio(), 27.0 / 30.0), "three hits drain the bar to 27/30 (%.3f)" % bar.get_health_ratio())
	h.check(is_equal_approx(bar.get_chunk_ratio(), 1.0), "and the damage chunk still shows the old health")
	await h.secs(bar.chunk_delay + bar.chunk_time + 0.15)
	h.check(is_equal_approx(bar.get_chunk_ratio(), bar.get_health_ratio()), "then the chunk catches up (%.3f)" % bar.get_chunk_ratio())
	h.check(is_equal_approx(bar.get_notch_ratio(), _boss.phase_two_threshold), "the notch marks the phase-two threshold (%.2f)" % bar.get_notch_ratio())
	h.check(not bar.is_phase_two_tint(), "the bar is in its normal colour above the notch")
	_hit(12)
	h.check(is_equal_approx(bar.get_health_ratio(), 0.5) and bar.is_phase_two_tint(), "at half health it reaches the notch and changes colour")
	var rect := bar.get_bar_rect()
	h.check(VIEWPORT_RECT.encloses(rect) and not rect.intersects(HUD_CORNER), "the bar sits inside the screen, clear of the health pips (%s)" % [rect])
	h.check(absf((rect.position.x + rect.size.x * 0.5) - 320.0) < 1.0, "centred on the screen")
	var narrow := Rect2(20.0, 10.0, 300.0, 340.0)
	bar.set_safe_area(narrow)
	rect = bar.get_bar_rect()
	h.check(narrow.encloses(rect) and rect.position.x >= narrow.position.x + bar.side_clearance - 0.01, "on a narrow safe area it shrinks instead of reaching the pips (%s)" % [rect])
	h.check(rect.position.y >= narrow.position.y, "and stays below the safe area's top edge")
	_hit(15)
	h.check(bar.get_health_ratio() == 0.0, "the killing blow empties it")
	_end_case()


# -- Luz dies --------------------------------------------------------------------------

func case_luz_death_resets_arena() -> void:
	await _build()
	var resets: Array[int] = []
	_arena.fight_reset.connect(func() -> void: resets.append(1))
	await _enter_trigger()
	await h.secs(0.6)
	_hit(16)
	_boss.start_attack(ArtemisBoss.Attack.AIMED_SHOT)
	await h.secs(0.3)
	_kill_luz()
	h.check(not _boss.is_ai_active(), "when Luz dies the boss stops")
	await h.secs(_player.death_fade_time + 0.5)
	h.check(resets == [1] and _arena.get_state() == BossArena.FightState.ARMED, "the arena resets once she has respawned (%s)" % [resets])
	h.check(_boss.get_health() == _boss.max_health and _boss.get_phase() == 1, "the boss is back at full health in phase one (%d)" % _boss.get_health())
	h.check(_boss.global_position.is_equal_approx(_boss.get_spawn_position()) and _boss.is_fresh() and _boss.is_ai_active(), "at her spawn, idle and awake")
	h.check(_arena.get_boss_reset_count() == 0, "the checkpoint contract reset her: no double reset by the arena (%d)" % _arena.get_boss_reset_count())
	h.check(not _arena.are_doors_closed() and _doors_passable(), "the doors are open")
	h.check(_camera_limits() == _limits_before, "the camera limits are restored exactly (%s)" % [_camera_limits()])
	h.check(not _arena.get_bar().is_bar_shown() and not _arena.get_bar().is_title_shown(), "the bar and the title are hidden")
	h.check(_arena.is_trigger_armed() and _boss.active_arrow_count() == 0 and not _boss.get_stag().is_active(), "the trigger is armed and the arrows and the stag are gone")
	h.check(_player.global_position.distance_to(LUZ_START) < 2.0, "Luz woke up outside the trigger")
	await _enter_trigger()
	await h.secs(0.3)
	h.check(_arena.are_doors_closed() and _arena.get_bar().is_bar_shown() and _arena.get_bar().get_health_ratio() == 1.0, "walking back in restarts the fight with a full bar")
	h.check(_boss.get_state() != ArtemisBoss.State.IDLE, "and she engages again")
	# A respawn that does not go through the checkpoint contract: the arena resets her itself.
	_hit(3)
	await h.secs(0.4)
	_kill_luz()
	_player.respawn()
	await h.frames(3)
	h.check(_arena.get_boss_reset_count() == 1 and _boss.is_fresh() and _boss.get_health() == _boss.max_health, "without a checkpoint reset the arena resets the boss once (%d)" % _arena.get_boss_reset_count())
	h.check(_boss.is_ai_active() and _arena.get_state() == BossArena.FightState.ARMED, "awake and armed again")
	_place_luz(IN_TRIGGER)
	await h.secs(0.3)
	_kill_luz()
	await h.secs(0.1)
	h.check(not _boss.is_ai_active() and _arena.get_state() == BossArena.FightState.ACTIVE, "dying in the intro window freezes the boss too")
	await h.secs(_player.death_fade_time + 0.4)
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE and _arena.is_trigger_armed(), "and everything is back to idle and armed")
	h.check(_player.get_health() == _player.max_health, "Luz is whole again")
	_end_case()


# -- Defeat and reward ----------------------------------------------------------------

func case_defeat_opens_arena_and_rewards() -> void:
	await _build()
	var cleared: Array[int] = []
	_arena.arena_cleared.connect(func() -> void: cleared.append(1))
	await _enter_trigger()
	await h.secs(0.4)
	_place_luz(Vector2(-250.0, 0.0))
	_hit(30)
	h.check(_arena.are_doors_closed() and _arena.get_reward() == null, "right after the last hit the doors hold for a beat and there is no reward yet")
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(cleared == [1] and not _arena.are_doors_closed() and _doors_passable(), "after the beat the doors open")
	h.check(not _arena.get_bar().is_bar_shown() and _camera_limits() == _limits_before, "the bar is hidden and the camera is released")
	var reward := _arena.get_reward()
	h.check(reward != null and reward.global_position.distance_to(Vector2(0.0, -28.0)) < 1.0, "the reward appears at the arena centre, on the floor (%s)" % [reward.global_position if reward != null else "none"])
	h.check(_progress().is_defeated(BOSS_ID), "the defeat is recorded")
	h.check(not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "and the boss is out of the checkpoint contract")
	h.check(not _player.has_double_jump(), "Luz has no double jump yet")
	_place_luz(reward.global_position + Vector2(0.0, 28.0))
	await h.secs(0.3)
	h.check(_player.has_double_jump(), "touching the reward unlocks the double jump")
	h.check(not is_instance_valid(reward), "and the pickup frees itself")
	_end_case()


func case_reward_options() -> void:
	await _build({"reward_enabled": false})
	await _enter_fight()
	_hit(30)
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(_arena.get_reward() == null, "reward_enabled off: no pickup appears")
	h.check(not _arena.are_doors_closed() and not _player.has_double_jump(), "but the arena still opens")
	_end_case()
	_reset_world()
	_add_luz()
	var marker := Marker2D.new()
	marker.name = "Spot"
	marker.position = Vector2(120.0, -40.0)
	_rig.add_child(marker)
	_arena = _make_arena({"reward_marker": NodePath("../Spot")})
	_boss = _arena.get_boss() as ArtemisBoss
	await h.frames(SETTLE_FRAMES)
	await _enter_fight()
	_hit(30)
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(_arena.get_reward() != null and _arena.get_reward().global_position.is_equal_approx(Vector2(120.0, -40.0)), "reward_marker places the pickup on a marker")
	_end_case()


# -- Permanence ---------------------------------------------------------------------------

func case_defeat_is_permanent() -> void:
	await _build()
	await _enter_fight()
	_hit(30)
	await h.secs(_arena.defeat_beat + _boss.defeat_time + 0.3)
	h.check(_boss.is_dead() and _boss.visible, "the boss is down and her corpse stays")
	h.cps.reset_resettable_enemies()
	await h.frames(3)
	h.check(_boss.is_dead() and _boss.visible, "a desk rest (checkpoint reset) does not bring her back")
	_registry().enter_room(ROOM)
	await h.frames(3)
	h.check(_boss.is_dead() and _boss.collision_layer == 0, "neither does re-entering the room")
	_kill_luz()
	await h.secs(_player.death_fade_time + 0.4)
	h.check(_boss.is_dead() and not _arena.are_doors_closed(), "nor does Luz dying and waking up; the arena stays open")
	var old_arena := _arena
	old_arena.free()
	_registry().clear()
	_arena = _make_arena()
	await h.frames(5)
	h.check(_arena.get_boss() != null and _arena.get_boss().is_dead(), "a re-instantiated arena finds her already beaten: her corpse")
	h.check(not _arena.are_doors_closed() and _doors_passable() and _arena.get_state() == BossArena.FightState.DEFEATED, "open doors")
	h.check(not _arena.is_trigger_armed(), "and the trigger is off")
	await _enter_fight()
	await h.secs(0.2)
	h.check(not _arena.are_doors_closed() and not _arena.get_bar().is_bar_shown(), "walking in starts nothing")
	h.check(_progress().is_defeated(BOSS_ID), "the defeat is still remembered")
	_progress().clear()
	h.check(not _progress().is_defeated(BOSS_ID), "a new game forgets it")
	_end_case()


# -- Camera and limits --------------------------------------------------------------------

func case_room_camera_lock() -> void:
	await _build()
	var camera := RoomCamera.new()
	camera.target = _player
	_rig.add_child(camera)
	await h.frames(5)
	var room := Rect2(-2000.0, -1000.0, 4000.0, 2000.0)
	camera.set_room_bounds(room, 0.0)
	await _enter_trigger()
	h.check(h.tree.root.get_viewport().get_camera_2d() == camera and camera.get_room_bounds() == _arena.get_world_rect(), "a RoomCamera is clamped to the arena rect (%s)" % [camera.get_room_bounds()])
	_kill_luz()
	_player.respawn()
	await h.secs(0.1)
	h.check(camera.get_room_bounds() == room and camera.has_room_bounds(), "and gets its room bounds back exactly (%s)" % [camera.get_room_bounds()])
	camera.clear_room_bounds(0.0)
	await _enter_trigger()
	_kill_luz()
	_player.respawn()
	await h.secs(0.1)
	h.check(not camera.has_room_bounds(), "a camera that had no room bounds is released to the whole world")
	h.check(camera.get_room_bounds() == Rect2(Vector2.ZERO, camera.world_size), "with its world rect")
	_end_case()


func case_arena_limits_bound_boss() -> void:
	_reset_world()
	_add_luz()
	_place_luz(Vector2.ZERO)
	_boss = _make_boss()
	_boss.wake_distance = 0.0
	_boss.position = Vector2(300.0, 0.0)
	_rig.add_child(_boss)
	await h.frames(SETTLE_FRAMES)
	h.check(_boss.is_fresh(), "a standalone boss with no arena starts fresh")
	_boss.set_arena_limits(-100.0, 100.0)
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	await h.secs(0.1)
	var zones := _boss.get_rain_zones()
	var inside := not zones.is_empty()
	for zone: Rect2 in zones:
		inside = inside and zone.position.x >= -100.0 and zone.end.x <= 100.0
	h.check(inside and zones.size() == 1, "the rain stays inside the arena limits (%d zone)" % zones.size())
	_boss.clear_arena_limits()
	_boss.start_attack(ArtemisBoss.Attack.RAIN)
	await h.secs(0.1)
	h.check(_boss.get_rain_zones().size() == 3, "without limits she probes the walls again and lays all three zones")
	_boss.engage()
	h.check(not _boss.is_fresh(), "an engaged boss is not fresh")
	_boss.set_manual_engage(true)
	_boss.reset_to_spawn()
	await h.secs(1.5)
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE, "with manual engage she waits for engage() even with Luz in range")
	_end_case()


# -- Softlock guards ------------------------------------------------------------------

func case_armed_boss_is_untouchable() -> void:
	await _build()
	var soul := _player.get_soul()
	_hit(5)
	h.check(_boss.get_health() == _boss.max_health, "a hit on an armed arena boss deals no damage")
	h.check(not _boss.receive_hit(1, HIT_FROM, &"attack_1") and _boss.get_state() == ArtemisBoss.State.IDLE, "it neither lands nor wakes her")
	h.check(_player.get_soul() == soul, "and Luz gains no soul")
	_end_case()


func case_dead_boss_while_armed_never_locks() -> void:
	await _build()
	_boss.reset_to_spawn()
	_boss.set_manual_engage(false)
	_boss.engage()
	_hit(30)
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(_arena.get_state() == BossArena.FightState.DEFEATED, "a boss killed while ARMED leaves the arena defeated")
	h.check(_progress().is_defeated(BOSS_ID), "the defeat is recorded")
	h.check(_arena.get_reward() != null, "the reward appears")
	h.check(not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "and the boss is out of the checkpoint contract")
	await _enter_trigger()
	h.check(not _arena.are_doors_closed() and _doors_passable(), "entering the trigger does not close the doors")
	h.check(_arena.get_state() == BossArena.FightState.DEFEATED, "and no fight starts")
	h.check(not _arena.is_trigger_armed(), "the trigger is disarmed for good")
	_end_case()


func case_rearm_survives_free() -> void:
	await _build()
	var arena := _arena
	arena._trigger.monitoring = false
	arena._rearm_trigger()
	await h.tree.physics_frame
	_rig.remove_child(arena)
	await h.frames(5)
	h.check(not arena.is_inside_tree(), "the arena left the tree between the re-arm awaits")
	h.check(not arena.is_trigger_armed() and arena.get_state() == BossArena.FightState.ARMED, "so the trigger did not re-arm and the state is unchanged")
	arena.free()
	_arena = null
	_boss = null
	_end_case()
	await _build()
	var freed := _arena
	freed._rearm_trigger()
	_free_rig()
	await h.frames(5)
	h.check(not is_instance_valid(freed), "freeing the arena during re-arm leaves it gone")
	h.check(not is_instance_valid(_arena), "with no dangling await or error")
	_end_case()


func case_engaged_boss_always_hittable() -> void:
	await _build()
	h.check(not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "before the arena engages her she is untouchable")
	_boss.engage()
	h.check(_boss.receive_hit(1, HIT_FROM, &"attack_1") and _boss.get_health() == _boss.max_health - 1, "a hit right after engage() deals damage")
	_boss._enter_state(ArtemisBoss.State.IDLE, 5.0)
	h.check(_boss.receive_hit(1, HIT_FROM, &"attack_1") and _boss.get_health() == _boss.max_health - 2, "and she stays hittable in a later IDLE")
	_boss.reset_to_spawn()
	h.check(_boss.get_state() == ArtemisBoss.State.IDLE and not _boss.receive_hit(1, HIT_FROM, &"attack_1"), "after a reset she is untouchable again until engaged")
	h.check(_boss.get_health() == _boss.max_health, "and takes no damage")
	await _enter_fight()
	_boss._enter_state(ArtemisBoss.State.IDLE, 5.0)
	h.check(_boss.receive_hit(1, HIT_FROM, &"attack_1"), "once the arena engaged her, an IDLE beat does not make her immune")
	_end_case()


# -- Test arena HUD ----------------------------------------------------------------------

func case_test_arena_shows_luz_hud() -> void:
	var state := (load(TEST_ARENA_SCENE) as PackedScene).get_state()
	var instanced: Array[String] = []
	for i: int in state.get_node_count():
		var packed := state.get_node_instance(i)
		if packed != null:
			instanced.append(packed.resource_path)
	h.check(HUD_SCENE in instanced, "the test arena instances the health HUD (%s)" % [instanced])
	_reset_world()
	_add_luz()
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as HealthHud
	_rig.add_child(hud)
	await h.frames(3)
	h.check(hud.get_pips().size() == _player.get_max_health(), "it shows one pip per health point (%d)" % hud.get_pips().size())
	h.check(hud.get_meter() != null and hud.get_meter().is_inside_tree(), "and the soul meter")
	_end_case()


# -- Corpse, reload and save hooks (T8) ------------------------------------------------

func _defeat_and_settle() -> void:
	await _enter_fight()
	_place_luz(Vector2(-250.0, 0.0))
	_hit(30)
	await h.secs(_arena.defeat_beat + _boss.defeat_time + 0.3)


func _reload_arena(forget_registry: bool) -> void:
	_arena.free()
	if forget_registry:
		_registry().clear()
	_arena = _make_arena()
	_boss = _arena.get_boss() as ArtemisBoss
	await h.frames(5)


func case_corpse_is_inert() -> void:
	await _build()
	await _defeat_and_settle()
	var soul := _player.get_soul()
	var health := _player.get_health()
	_place_luz(_boss.global_position + Vector2(0.0, 0.0))
	await h.secs(0.4)
	h.check(_boss.collision_layer == 0 and not (_boss.get_node("ContactDamage") as Area2D).monitoring, "the corpse has no collision and no contact damage")
	h.check(_player.get_health() == health and absf(_player.global_position.x - _boss.global_position.x) < 2.0, "Luz stands on it untouched and unblocked")
	h.check(not _boss.receive_hit(1, HIT_FROM, &"attack_1") and _player.get_soul() == soul, "it is not hittable and gives no soul")
	h.cps.reset_resettable_enemies()
	_registry().reset_to_checkpoint_state()
	_registry().enter_room(ROOM)
	await h.frames(3)
	h.check(_boss.is_dead() and _boss.visible and not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "a desk rest and a registry reset leave it lying")
	_kill_luz()
	await h.secs(_player.death_fade_time + 0.4)
	h.check(_boss.is_dead() and _arena.get_state() == BossArena.FightState.DEFEATED, "so does Luz dying and waking up")
	h.check(not _arena.are_doors_closed() and not _arena.is_trigger_armed(), "the arena stays open with the trigger off")
	h.check(_boss.get_state() == ArtemisBoss.State.DEFEATED and not _boss.is_physics_processing(), "she is still in her defeated state, at rest")
	h.check(_progress().is_defeated(BOSS_ID), "and the progress remembers her")
	_end_case()


func case_corpse_reloads_where_she_fell() -> void:
	await _build()
	await _defeat_and_settle()
	var fell_at := _boss.global_position
	var facing := _boss.get_facing()
	var corpse: Dictionary = _progress().get_corpse(BOSS_ID)
	h.check((corpse["position"] as Vector2).is_equal_approx(fell_at) and corpse["facing"] == facing, "the progress stores where she lies and how (%s)" % [corpse])
	h.check(_arena.get_reward() != null and not _progress().is_reward_claimed(BOSS_ID), "the reward is out and still unclaimed")
	# A room revisit after a desk rest: the registry forgot, the progress did not.
	await _reload_arena(true)
	h.check(_boss != null and _boss.is_dead() and _boss.visible, "the reloaded arena holds her corpse")
	h.check(_boss.global_position.is_equal_approx(fell_at) and _boss.get_facing() == facing, "at the stored spot, facing the stored way (%s)" % [_boss.global_position])
	h.check(_arena.get_state() == BossArena.FightState.DEFEATED and not _arena.are_doors_closed() and _doors_passable(), "the arena is open")
	h.check(not _arena.is_trigger_armed() and _boss.collision_layer == 0 and not _boss.is_in_group(Enemy.GROUP_RESETTABLE), "the trigger is off and the corpse is out of the checkpoint contract")
	var reward := _arena.get_reward()
	h.check(reward != null, "the unclaimed reward is spawned again")
	_place_luz(Vector2(-150.0, 0.0))
	await h.secs(0.4)
	h.check(not _arena.are_doors_closed() and _arena.get_state() == BossArena.FightState.DEFEATED, "walking into the old trigger starts nothing")
	_place_luz(reward.global_position + Vector2(0.0, 28.0))
	await h.secs(0.3)
	h.check(_player.has_double_jump() and _progress().is_reward_claimed(BOSS_ID), "picking it up unlocks the double jump and records the claim")
	# A scene reload: the registry still remembers the kill, so it restores her too.
	await _reload_arena(false)
	h.check(_boss.is_dead() and _boss.global_position.is_equal_approx(fell_at), "a reload that keeps the registry restores the same corpse")
	h.check(_arena.get_reward() == null, "no reward once it was claimed")
	await _reload_arena(true)
	h.check(_arena.get_reward() == null and _boss.is_dead(), "not after a forgotten registry either")
	h.check(_boss.get_state() == ArtemisBoss.State.DEFEATED and _boss.visible, "the restored boss is in the defeated state")
	# Defeated, unclaimed, but Luz already double jumps: nothing to give.
	var saved: Dictionary = _progress().to_dict()
	saved["bosses"][String(BOSS_ID)]["reward_claimed"] = false
	_progress().from_dict(saved)
	await _reload_arena(true)
	h.check(_arena.get_reward() == null, "no pickup for a Luz that can already double jump")
	_end_case()
	# And unclaimed with no double jump: back from a save.
	await _build()
	_progress().from_dict({"version": 1, "bosses": {String(BOSS_ID): {"defeated": true, "x": 120.0, "y": 0.0, "facing": 1, "reward_claimed": false}}})
	await _reload_arena(false)
	h.check(_boss.is_dead() and _boss.global_position.is_equal_approx(Vector2(120.0, 0.0)) and _boss.get_facing() == 1, "a loaded save puts the corpse at its saved spot")
	h.check(_arena.get_reward() != null and not _player.has_double_jump(), "and brings the reward back when Luz lacks the double jump")
	_end_case()
	await _build()
	h.check(_boss.get_health() == _boss.max_health and not _boss.is_dead(), "with no progress the boss is alive")
	h.check(not _progress().is_defeated(BOSS_ID) and _progress().get_corpse(BOSS_ID).is_empty(), "and no corpse is stored")
	_end_case()


func case_boss_progress_round_trip() -> void:
	var progress := _progress()
	progress.clear()
	progress.mark_defeated(&"a", Vector2(120.5, -3.0), -1)
	progress.mark_reward_claimed(&"a")
	progress.mark_defeated(&"b", Vector2(5.0, 6.0), 1)
	var data: Dictionary = progress.to_dict()
	h.check(data["version"] == 1 and (data["bosses"] as Dictionary).size() == 2, "to_dict is versioned and lists both bosses")
	var through_json: Variant = JSON.parse_string(JSON.stringify(data))
	progress.clear()
	h.check(not progress.is_defeated(&"a"), "clear forgets them")
	progress.from_dict(through_json as Dictionary)
	var a: Dictionary = progress.get_corpse(&"a")
	h.check(progress.is_defeated(&"a") and (a["position"] as Vector2).is_equal_approx(Vector2(120.5, -3.0)) and a["facing"] == -1, "from_dict restores the corpse, through JSON too")
	h.check(progress.is_reward_claimed(&"a") and not progress.is_reward_claimed(&"b"), "and the reward claims")
	progress.mark_defeated(&"a", Vector2.ZERO, 1)
	h.check(progress.is_reward_claimed(&"a"), "defeating again keeps the claim")
	progress.from_dict({"version": 99, "bosses": {"a": {"defeated": true}}})
	h.check(not progress.is_defeated(&"a"), "an unknown version leaves a clean slate")
	progress.from_dict({"version": 1, "bosses": {"x": 5, "y": {"defeated": true, "x": 1.0, "y": 2.0, "facing": 1}}})
	h.check(not progress.is_defeated(&"x") and progress.is_defeated(&"y"), "bad entries are skipped, good ones kept")
	progress.from_dict({})
	h.check(not progress.is_defeated(&"y"), "an empty dictionary is a clean slate")
	progress.clear()


func case_arena_cues_and_door_shake() -> void:
	await _build()
	var spy := ShakeSpy.new() as Camera2D
	_rig.add_child(spy)
	spy.make_current()
	var cues: Array[StringName] = []
	_arena.sfx_cue.connect(func(cue: StringName) -> void: cues.append(cue))
	var all_slots := true
	for cue: StringName in [BossArena.CUE_DOORS_CLOSE, BossArena.CUE_DOORS_OPEN, BossArena.CUE_BOSS_INTRO]:
		var player := _arena.get_node_or_null("Sfx/" + String(cue)) as AudioStreamPlayer
		all_slots = all_slots and player != null and player.stream == null
	h.check(all_slots, "the arena has three empty audio slots under Sfx")
	_arena.play_cue(BossArena.CUE_DOORS_OPEN)
	h.check(not (_arena.get_node("Sfx/DoorsOpen") as AudioStreamPlayer).playing, "an empty slot is a silent no-op")
	cues.clear()
	await _enter_trigger()
	h.check(cues == [BossArena.CUE_DOORS_CLOSE, BossArena.CUE_BOSS_INTRO], "the doors close, then the boss intro cue (%s)" % [cues])
	h.check(spy.shakes.size() == 1 and is_equal_approx(spy.shakes[0].x, _arena.door_shake_strength), "the doors closing shake the camera lightly (%s)" % [spy.shakes])
	await h.secs(0.3)
	_hit(30)
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(cues.back() == BossArena.CUE_DOORS_OPEN, "the doors opening has its cue")
	h.check(spy.has_shake(_boss.final_shake_strength), "the killing blow shook the camera too")
	_end_case()


func case_prefab_is_one_drag() -> void:
	_reset_world()
	var prefab := (load(PREFAB_SCENE) as PackedScene).instantiate() as BossArena
	_rig.add_child(prefab)
	_arena = prefab
	_add_luz()
	await h.frames(SETTLE_FRAMES)
	var boss := prefab.get_boss()
	h.check(boss is ArtemisBoss and boss.get_parent() == prefab, "the prefab holds Artemis as a child of the arena")
	h.check(boss.enemy_id == &"greece_artemis" and boss.enemy_id != &"artemis", "with its own unique default enemy_id (%s)" % boss.enemy_id)
	h.check(prefab.boss_name == "Artemis" and prefab.arena_rect.size == Vector2(936.0, 480.0), "named, and sized for the 936x480 room (%s)" % prefab.arena_rect.size)
	h.check(prefab.arena_rect.end.y == 0.0 and absf(prefab.arena_rect.get_center().x) < 0.01, "origin at the floor line, centred")
	var doors := prefab.get_doors()
	h.check(is_equal_approx(doors[0].position.x, -456.0) and is_equal_approx(doors[1].position.x, 456.0), "the doors sit just inside the walls")
	h.check(prefab.get_state() == BossArena.FightState.ARMED and prefab.is_trigger_armed(), "it starts armed")
	h.check(prefab.get_world_rect().has_point(boss.global_position + Vector2(0.0, -10.0)), "Artemis starts inside the arena")
	var state := (load(TEST_ARENA_SCENE) as PackedScene).get_state()
	var uses_prefab := false
	for i: int in state.get_node_count():
		var packed := state.get_node_instance(i)
		uses_prefab = uses_prefab or (packed != null and packed.resource_path == PREFAB_SCENE)
	h.check(uses_prefab, "and the test arena is just this prefab plus platforms and a HUD")
	_end_case()

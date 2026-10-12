extends "res://tests/support/ritual_suite.gd"
## BossArena (T4): the trigger, doors, camera lock, boss health bar, the reset
## when Luz dies, the defeat, the double jump reward and the permanent defeat.
## Each case builds its own floor (top at y=0), Luz and an arena with an Artemis
## child, and shortens the intro timings so every wait is a few tenths of a
## second. Luz starts outside the trigger, which spans x -200..200.
##
## Like the Artemis suite this one runs inside the single runner, before any
## level scene is loaded: the boss targets the first node of group `player`.

const ARENA_SCENE := "res://scenes/enemies/bosses/boss_arena.tscn"
const BOSS_SCENE := "res://scenes/enemies/bosses/artemis.tscn"
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
	await _enter_trigger()
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
	await _enter_trigger()
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
	await _enter_trigger()
	_hit(30)
	await h.secs(_arena.defeat_beat + 0.3)
	h.check(_arena.get_reward() != null and _arena.get_reward().global_position.is_equal_approx(Vector2(120.0, -40.0)), "reward_marker places the pickup on a marker")
	_end_case()


# -- Permanence ---------------------------------------------------------------------------

func case_defeat_is_permanent() -> void:
	await _build()
	await _enter_trigger()
	_hit(30)
	await h.secs(_arena.defeat_beat + _boss.defeat_time + 0.3)
	h.check(_boss.is_dead() and not _boss.visible, "the boss is down and gone")
	h.cps.reset_resettable_enemies()
	await h.frames(3)
	h.check(_boss.is_dead() and not _boss.visible, "a desk rest (checkpoint reset) does not bring her back")
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
	h.check(_arena.get_boss() == null, "a re-instantiated arena finds her already beaten: no boss")
	h.check(_arena.get_reward() == null and not _arena.are_doors_closed() and _doors_passable(), "no reward and open doors")
	h.check(not _arena.is_trigger_armed(), "and the trigger is off")
	await _enter_trigger()
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

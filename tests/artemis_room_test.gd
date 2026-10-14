extends SceneTree
## Regression test for the real Artemis room (greece/zone_artemis): the room loads
## with its arena and boss, the tiles close the arena (floor, walls, ceiling) and
## leave the doorway on the left, the door pairs with the healing room, beating
## Artemis grants the double jump once, and a reload keeps her dead and Luz's
## double jump without a second pickup.
## Run: godot --headless --path . --script res://tests/artemis_room_test.gd
## Exits 0 when every check passes, 1 otherwise.

const ZONE_PATH := "res://scenes/levels/greece/zone_artemis.tscn"
const HEALING_PATH := "res://scenes/levels/greece/zone_healing.tscn"
const BOSS_ID := &"greece_artemis"
const WATCHDOG_SECONDS := 90.0
const SOLID_MASK := 1
## Boss and arena timings shortened so the whole fight fits in a few seconds.
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.2, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

var checks := 0
var failed: Array[String] = []
var _zone: Node2D
var _arena: BossArena
var _boss: ArtemisBoss
var _player: Player


func _initialize() -> void:
	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		print("FAIL: watchdog")
		quit(1))
	await _run()
	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)


func _run() -> void:
	_forget_run()
	await _load_zone(false)
	await _case_room_contents()
	await _case_tiles_close_the_arena()
	_case_door_pairs_with_healing()
	await _case_victory_grants_double_jump_once()
	await _case_reload_keeps_defeat_and_ability()
	await _case_new_game_forgets()
	_case_ability_progress_round_trip()
	_zone.free()
	_forget_run()


# -- Rig -----------------------------------------------------------------------------

func _forget_run() -> void:
	for service: String in ["BossProgress", "AbilityProgress", "EnemyRegistry"]:
		root.get_node(service).clear()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _load_zone(fast: bool) -> void:
	if is_instance_valid(_zone):
		_zone.free()
	_zone = (load(ZONE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(_zone)
	await _frames(6)
	_arena = _zone.get_node("ArtemisBossArena") as BossArena
	_boss = _arena.get_boss() as ArtemisBoss
	_player = _zone.get_node("Player2") as Player
	if fast and _boss != null:
		for key: String in ARENA_TIMINGS:
			_arena.set(key, ARENA_TIMINGS[key])
		_boss.final_freeze_time = 0.0
		_boss.final_slowmo_time = 0.0
		_boss.stagger_hits = 0


func _solid_at(point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = SOLID_MASK
	return not root.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


## The tiles' collision is a lattice (their body is hollow), so only a ray, never a
## point deep inside a wall, tells whether a stretch of wall is closed.
func _ray_hits(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, SOLID_MASK)
	return not root.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# -- Cases ---------------------------------------------------------------------------

func _case_room_contents() -> void:
	var arenas := _zone.find_children("*", "BossArena", true, false)
	check(arenas.size() == 1, "the room holds exactly one BossArena (%d)" % arenas.size())
	check(_boss != null and _boss.enemy_id == BOSS_ID, "the arena holds Artemis with enemy_id greece_artemis")
	check(_player != null and _player.is_in_group(&"player"), "Luz is in the room")
	check(_zone.find_children("*", "ZoneAmbience", false, false).size() == 1, "one ZoneAmbience")
	check(_zone.find_children("*", "ParallaxBackdrop", false, false).size() == 1, "one ParallaxBackdrop")
	check(_zone.find_children("*", "PointLight2D", true, false).size() <= 8, "at most 8 lights")
	check(_arena.get_state() == BossArena.FightState.ARMED, "the fight starts armed")


## The arena rect must sit inside real tiles: the floor holds at its centre, both
## side walls close it, the ceiling closes it, and the doorway on the left is open
## at body height but closed above.
func _case_tiles_close_the_arena() -> void:
	var rect := _arena.arena_rect
	var origin := _arena.global_position
	var floor_y := origin.y + rect.end.y
	check(_solid_at(Vector2(origin.x, floor_y + 4.0)), "the floor is solid under the arena centre")
	check(not _solid_at(Vector2(origin.x, floor_y - 4.0)), "and the air above it is free")
	# The top row of every surface tile is a collision-free lip, so the walls and the
	# ceiling start one tile (8 px) beyond the arena rect.
	check(_solid_at(Vector2(origin.x + rect.end.x + 12.0, floor_y - 60.0)), "the right wall closes the arena")
	check(_solid_at(Vector2(origin.x + rect.position.x - 12.0, floor_y - 300.0)), "the left wall closes the arena above the doorway")
	check(_solid_at(Vector2(origin.x, origin.y + rect.position.y - 20.0)), "the ceiling closes the arena")
	check(not _solid_at(Vector2(origin.x + rect.position.x - 12.0, floor_y - 40.0)), "the doorway is open at body height")
	check(not _solid_at(Vector2(origin.x + rect.position.x - 36.0, floor_y - 80.0)), "and open along the whole passage")
	var passage_x := origin.x + rect.position.x - 36.0
	check(_ray_hits(Vector2(passage_x, floor_y - 40.0), Vector2(passage_x, floor_y - 320.0)), "with a lintel above it")
	# Luz stands on the floor at the start.
	check(absf(_player.global_position.y - floor_y) < 2.0, "Luz starts on the floor line (%.1f vs %.1f)" % [_player.global_position.y, floor_y])


func _case_door_pairs_with_healing() -> void:
	var door := _zone.get_node("SceneTransitionArea") as SceneTransitionArea
	check(door.door_id == DoorID.ID.ARTEMIS_TO_HEALING and door.target_door_id == DoorID.ID.HEALING_TO_ARTEMIS, "the door pairs ARTEMIS_TO_HEALING with HEALING_TO_ARTEMIS")
	check(door.target_scene_path == HEALING_PATH, "it leads to the healing room")
	var healing := (load(HEALING_PATH) as PackedScene).instantiate()
	var back: Variant = null
	for node: Node in healing.find_children("*", "SceneTransitionArea", true, false):
		if (node as SceneTransitionArea).door_id == DoorID.ID.HEALING_TO_ARTEMIS:
			back = node
	check(back != null and (back as SceneTransitionArea).target_scene_path == ZONE_PATH, "the healing room has the door back to this room")
	check(back != null and (back as SceneTransitionArea).target_door_id == DoorID.ID.ARTEMIS_TO_HEALING, "and it targets this room's door")
	healing.free()


func _place_luz(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO


func _kill_boss() -> void:
	var guard := 0
	while _boss.get_state() != ArtemisBoss.State.DEFEATED and guard < 300:
		_boss.receive_hit(1, _boss.global_position + Vector2(-100.0, 0.0), &"attack_1")
		guard += 1


func _case_victory_grants_double_jump_once() -> void:
	_forget_run()
	await _load_zone(true)
	check(not _player.has_double_jump(), "Luz has no double jump before the fight")
	_place_luz(_arena.global_position)
	await _wait(0.5)
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "entering the arena starts the fight")
	_place_luz(_arena.global_position + Vector2(-250.0, 0.0))
	_kill_boss()
	await _wait(_arena.defeat_beat + _boss.defeat_time + 0.5)
	check(_arena.get_state() == BossArena.FightState.DEFEATED, "beating Artemis ends the fight")
	check(root.get_node("BossProgress").is_defeated(BOSS_ID), "the defeat is remembered")
	var reward := _arena.get_reward()
	check(reward != null, "the double jump pickup appears")
	if reward == null:
		return
	_place_luz(reward.global_position + Vector2(0.0, 28.0))
	await _wait(0.4)
	check(_player.has_double_jump(), "touching it grants the double jump")
	check(root.get_node("AbilityProgress").is_unlocked(&"double_jump"), "the run remembers the ability")
	check(root.get_node("BossProgress").is_reward_claimed(BOSS_ID), "the reward is marked as claimed")
	check(_zone.find_children("*", "DoubleJumpReward", true, false).is_empty(), "and the pickup is gone")


func _case_reload_keeps_defeat_and_ability() -> void:
	await _load_zone(false)
	check(_arena.get_state() == BossArena.FightState.DEFEATED, "a reload finds Artemis still defeated")
	check(_arena.get_reward() == null and _zone.find_children("*", "DoubleJumpReward", true, false).is_empty(), "no second pickup appears")
	check(_player.has_double_jump(), "the new Luz keeps the double jump")


func _case_new_game_forgets() -> void:
	_forget_run()
	await _load_zone(false)
	check(not _player.has_double_jump(), "after a new game Luz starts without the double jump")
	check(_arena.get_state() == BossArena.FightState.ARMED, "and Artemis waits again")


func _case_ability_progress_round_trip() -> void:
	var progress := root.get_node("AbilityProgress")
	progress.clear()
	check(not progress.is_unlocked(&"double_jump"), "AbilityProgress starts empty")
	check(progress.record(&"double_jump") and not progress.record(&"double_jump"), "recording is once per ability")
	var saved: Dictionary = progress.to_dict()
	progress.clear()
	progress.from_dict(saved)
	check(progress.is_unlocked(&"double_jump"), "from_dict restores what to_dict saved")
	progress.from_dict({"version": 99, "abilities": ["dash"]})
	check(not progress.is_unlocked(&"double_jump") and not progress.is_unlocked(&"dash"), "an unknown version leaves a clean slate")
	progress.clear()

extends SceneTree
## Demo boss test hub: the new door in library zone 1, the hub and its doors, the
## three boss test rooms (arena prefab, `test_` id, return door), the arrival spots,
## the refight rule (entering the hub forgets only the `test_` bosses) and the
## unique checkpoint of the hub's Stillness Desk.
## Run: godot --headless --path . --script res://tests/boss_test_hub_test.gd
## Exits 0 when every check passes, 1 otherwise.

const ARTEMIS_ROOM := "res://scenes/levels/greece/zone_artemis.tscn"
const ZONE_1 := "res://scenes/levels/library/zone_1.tscn"
const HUB := "res://scenes/levels/test/boss_test_hub.tscn"
const LEVELS_DIR := "res://scenes/levels"
const WATCHDOG_SECONDS := 180.0
const ARTEMIS_ID := &"greece_artemis"
const FAKE_ID := &"fake_demo_boss"
const FLOOR_Y := 0.0
const FLOOR_TOLERANCE := 1.0
const BODY_SIZE := Vector2(29.0, 46.0)
## Floor-level stretch of zone_1 the tutorial path crosses: no door may sit on it.
const WALK_PATH_FROM := 60.0
const WALK_PATH_TO := 450.0

## Hub door node -> the scene it must lead to.
const HUB_DOORS := {
	"DoorToLibrary": ZONE_1,
	"DoorToTeacher": "res://scenes/levels/test/boombox_teacher_arena.tscn",
	"DoorToBlindBeast": "res://scenes/levels/test/blind_beast_arena.tscn",
	"DoorToHydra": "res://scenes/levels/test/hydra_arena.tscn",
	"DoorToArtemis": ARTEMIS_ROOM,
}
const ROOMS := [
	{
		"scene": "res://scenes/levels/test/boombox_teacher_arena.tscn",
		"arena": "BoomboxTeacherBossArena",
		"prefab": "res://scenes/enemies/bosses/boombox_teacher_boss_arena.tscn",
		"boss": "ElProfesor",
		"boss_class": "BoomboxTeacherBoss",
		"test_id": &"test_boombox_teacher",
		"real_id": &"library_boombox_teacher",
	},
	{
		"scene": "res://scenes/levels/test/blind_beast_arena.tscn",
		"arena": "BlindBeastBossArena",
		"prefab": "res://scenes/enemies/bosses/blind_beast_boss_arena.tscn",
		"boss": "BlindBeast",
		"boss_class": "BlindBeastBoss",
		"test_id": &"test_blind_beast",
		"real_id": &"library_blind_beast",
	},
	{
		"scene": "res://scenes/levels/test/hydra_arena.tscn",
		"arena": "HydraBossArena",
		"prefab": "res://scenes/enemies/bosses/hydra_boss_arena.tscn",
		"boss": "Hydra",
		"boss_class": "HydraBoss",
		"test_id": &"test_hydra",
		"real_id": &"greece_hydra",
	},
]

const CHECKS := {
	"case_zone_1_door": 7,
	"case_hub_doors": 30,
	"case_boss_rooms": 21,
	"case_arrival_spots": 32,
	"case_hub_forgets_test_bosses": 11,
	"case_desk_checkpoint": 3,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _live: Node


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	_cleanup()
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


func _cleanup() -> void:
	if _live != null and is_instance_valid(_live):
		root.remove_child(_live)
		_live.free()
	_live = null


func _instantiate(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _progress() -> Node:
	return root.get_node("BossProgress")


func _registry() -> Node:
	return root.get_node("EnemyRegistry")


## The SceneTransitionArea of `scene` whose `door_id` is `id`, or null.
func _door_with_id(scene: Node, id: int) -> SceneTransitionArea:
	for node in scene.find_children("*", "Area2D", true, false):
		if node is SceneTransitionArea and (node as SceneTransitionArea).door_id == id:
			return node as SceneTransitionArea
	return null


func _doors_of(scene: Node) -> Array[SceneTransitionArea]:
	var doors: Array[SceneTransitionArea] = []
	for node in scene.find_children("*", "Area2D", true, false):
		if node is SceneTransitionArea:
			doors.append(node as SceneTransitionArea)
	return doors


func case_zone_1_door() -> void:
	var zone := _instantiate(ZONE_1)
	check(zone.get_node_or_null("DemoShortcutToBossHub") == null, "zone_1 has no extra door for the hub")
	var door := zone.get_node_or_null("DemoShortcutToArtemis") as SceneTransitionArea
	check(door != null and door.door_id == DoorID.ID.LIBRARY_TO_ARTEMIS_DEMO and door.position == Vector2(-22, 620), "the left demo door keeps its name, id and position")
	check(door != null and door.target_scene_path == HUB, "the left demo door targets the hub")
	check(door != null and door.target_door_id == DoorID.ID.BOSS_HUB_TO_LIBRARY, "the left demo door arrives at BOSS_HUB_TO_LIBRARY")
	var doors := _doors_of(zone)
	check(doors.size() == 2, "zone_1 keeps only its two pre-existing doors (%d)" % doors.size())
	var path := Rect2(WALK_PATH_FROM, 697.0 - BODY_SIZE.y, WALK_PATH_TO - WALK_PATH_FROM, BODY_SIZE.y)
	var blocking := 0
	for each in doors:
		var shape_node := each.get_node("CollisionShape2D") as CollisionShape2D
		var size := (shape_node.shape as RectangleShape2D).size
		if Rect2(each.position + shape_node.position - size * 0.5, size).intersects(path):
			blocking += 1
	check(blocking == 0, "no zone_1 door overlaps the walking path between x %d and %d" % [WALK_PATH_FROM, WALK_PATH_TO])
	var sign_node := zone.get_node_or_null("DemoShortcutBossHubSign")
	var start_x: float = (zone.get_node("Player2") as Node2D).position.x
	check(sign_node != null and sign_node.position.x + sign_node.trigger_size.x * 0.5 < start_x - BODY_SIZE.x * 0.5, "the hub sign trigger stays clear of the spawn point")
	zone.free()


func case_hub_doors() -> void:
	var hub := _instantiate(HUB)
	for node_name: String in HUB_DOORS:
		var door := hub.get_node_or_null(node_name) as SceneTransitionArea
		check(door != null, "%s exists in the hub" % node_name)
		if door == null:
			check(false, "%s target exists" % node_name)
			check(false, "%s target has its arrival door" % node_name)
			check(false, "%s arrival door leads back to the hub" % node_name)
			check(false, "%s arrival door points back at this door" % node_name)
			continue
		var expected: String = HUB_DOORS[node_name]
		check(door.target_scene_path == expected, "%s targets %s" % [node_name, expected])
		check(ResourceLoader.exists(door.target_scene_path), "%s target exists" % node_name)
		var target := _instantiate(door.target_scene_path)
		var arrival := _door_with_id(target, door.target_door_id)
		check(arrival != null, "%s target has door %s" % [node_name, DoorID.get_id_name(door.target_door_id)])
		if node_name == "DoorToArtemis":
			# Deliberate one-way demo door: Artemis' own door continues to Greece.
			check(arrival != null and arrival.door_id == DoorID.ID.ARTEMIS_TO_ZONE_5, "%s arrives at Artemis' own door" % node_name)
			check(arrival != null and arrival.target_scene_path != HUB, "%s does not lead back to the hub (one way)" % node_name)
		else:
			check(arrival != null and arrival.target_scene_path == HUB, "%s arrival door leads back to the hub" % node_name)
			check(arrival != null and arrival.target_door_id == door.door_id, "%s arrival door points back at this door" % node_name)
		target.free()
	hub.free()


func case_boss_rooms() -> void:
	for room: Dictionary in ROOMS:
		var scene := _instantiate(room.scene)
		var arena := scene.get_node_or_null(room.arena) as BossArena
		var label: String = room.arena
		check(arena != null, "%s holds its arena prefab" % label)
		check(arena != null and arena.scene_file_path == room.prefab, "%s is the prefab %s" % [label, room.prefab])
		var boss: Node = null if arena == null else arena.get_node_or_null(room.boss)
		check(boss != null and boss.get_script() != null and boss.get_script().get_global_name() == room.boss_class, "%s holds a %s" % [label, room.boss_class])
		check(boss != null and boss.enemy_id == room.test_id, "%s overrides the boss id with %s" % [label, room.test_id])
		check(String(room.test_id).begins_with("test_"), "%s id has the test_ prefix" % label)
		var back := _door_with_id(scene, _return_door_id(room))
		check(back != null and back.target_scene_path == HUB, "%s has a return door to the hub" % label)
		# The prefab itself keeps the real id: teammates place it in real levels.
		var prefab := _instantiate(room.prefab)
		var prefab_boss := prefab.get_node_or_null(room.boss)
		check(prefab_boss != null and prefab_boss.enemy_id == room.real_id, "%s prefab keeps its real id %s" % [label, room.real_id])
		prefab.free()
		scene.free()


func _return_door_id(room: Dictionary) -> int:
	match String(room.test_id):
		"test_boombox_teacher":
			return DoorID.ID.TEACHER_ROOM_TO_BOSS_HUB
		"test_blind_beast":
			return DoorID.ID.BLIND_BEAST_ROOM_TO_BOSS_HUB
	return DoorID.ID.HYDRA_ROOM_TO_BOSS_HUB


func case_arrival_spots() -> void:
	for room: Dictionary in ROOMS:
		await _check_arrivals(room.scene, [_return_door_id(room)], room.arena)
	await _check_arrivals(HUB, [
		DoorID.ID.BOSS_HUB_TO_LIBRARY,
		DoorID.ID.BOSS_HUB_TO_TEACHER_ROOM,
		DoorID.ID.BOSS_HUB_TO_BLIND_BEAST_ROOM,
		DoorID.ID.BOSS_HUB_TO_HYDRA_ROOM,
		DoorID.ID.BOSS_HUB_TO_ARTEMIS_DEMO,
	], "hub")


## Luz arrives through each door in `ids`: on the floor, inside the room, outside
## every door trigger and outside the boss trigger.
func _check_arrivals(path: String, ids: Array, label: String) -> void:
	var scene := _instantiate(path)
	_live = scene
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var player := scene.get_node("Player") as CharacterBody2D
	var triggers: Array[Rect2] = []
	for door in _doors_of(scene):
		triggers.append(_shape_rect(door.get_node("CollisionShape2D")))
	for node in scene.find_children("Trigger", "Area2D", true, false):
		triggers.append(_shape_rect(node.get_node("CollisionShape2D")))
	for id: int in ids:
		var door := _door_with_id(scene, id)
		var tag := "%s %s" % [label, DoorID.get_id_name(id)]
		check(door != null, "%s: the arrival door exists" % tag)
		if door == null:
			for _i in 3:
				check(false, "%s: arrival checks skipped" % tag)
			continue
		var arrival := SceneTransitionArea.resolve_arrival(door, player.global_position)
		var feet := SceneTransitionArea.settle_position(player, arrival.position, arrival.slide)
		check(absf(feet.y - FLOOR_Y) <= FLOOR_TOLERANCE, "%s: Luz stands on the floor (feet %s)" % [tag, feet])
		check(absf(feet.x) < 468.0 - BODY_SIZE.x, "%s: Luz is inside the walls (feet %s)" % [tag, feet])
		var body := Rect2(feet + Vector2(-BODY_SIZE.x * 0.5, -BODY_SIZE.y), BODY_SIZE)
		var clear := true
		for rect in triggers:
			if rect.intersects(body):
				clear = false
		check(clear, "%s: the arrival spot is outside every trigger" % tag)
	_cleanup()


func _shape_rect(shape_node: CollisionShape2D) -> Rect2:
	var size := (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs()
	return Rect2(shape_node.global_position - size * 0.5, size)


func case_hub_forgets_test_bosses() -> void:
	var progress := _progress()
	var registry := _registry()
	progress.mark_defeated(ARTEMIS_ID, Vector2(5, 0), 1)
	progress.mark_defeated(FAKE_ID, Vector2(6, 0), 1)
	for boss_id in BossTestHub.TEST_BOSS_IDS:
		progress.mark_defeated(boss_id, Vector2(7, 0), 1)
		registry._kills[boss_id] = {"position": Vector2(7, 0), "facing": 1}
	registry._kills[FAKE_ID] = {"position": Vector2(6, 0), "facing": 1}
	check(BossTestHub.TEST_BOSS_IDS.size() == 3, "the hub knows the three test bosses")
	_live = _instantiate(HUB)
	root.add_child(_live)
	await process_frame
	for boss_id in BossTestHub.TEST_BOSS_IDS:
		check(not progress.is_defeated(boss_id), "entering the hub forgets %s in BossProgress" % boss_id)
		check(not registry.has_kill(boss_id), "entering the hub forgets %s in the registry" % boss_id)
	check(progress.is_defeated(ARTEMIS_ID), "Artemis keeps her defeat")
	check(progress.is_defeated(FAKE_ID), "a fake boss id keeps its defeat")
	check(registry.has_kill(FAKE_ID), "a fake boss id keeps its registry kill")
	progress.forget(&"never_seen")
	check(not progress.is_defeated(&"never_seen"), "forgetting an unknown id is harmless")
	progress.forget(ARTEMIS_ID)
	progress.forget(FAKE_ID)
	registry.forget(FAKE_ID)


func case_desk_checkpoint() -> void:
	var hub := _instantiate(HUB)
	var desk := hub.get_node_or_null("StillnessDesk")
	check(desk != null and desk.checkpoint_id != &"", "the hub desk has a checkpoint id")
	var id := String(desk.checkpoint_id) if desk != null else ""
	var uses := _count_checkpoint_id(LEVELS_DIR, id)
	check(uses == 1, "the checkpoint id '%s' is used once across the levels (%d)" % [id, uses])
	var duplicated := _count_checkpoint_id("res://scenes/world", id)
	check(duplicated == 0, "the checkpoint id is not set on a shared world scene")
	hub.free()


func _count_checkpoint_id(dir_path: String, id: String) -> int:
	var count := 0
	var needle := 'checkpoint_id = &"%s"' % id
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".tscn"):
			count += FileAccess.get_file_as_string(dir_path.path_join(file)).count(needle)
	for dir in DirAccess.get_directories_at(dir_path):
		count += _count_checkpoint_id(dir_path.path_join(dir), id)
	return count

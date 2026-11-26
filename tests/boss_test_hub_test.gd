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
const WATCHDOG_SECONDS := 420.0
const ARTEMIS_ID := &"greece_artemis"
const FAKE_ID := &"fake_demo_boss"
const FLOOR_Y := 0.0
const FLOOR_TOLERANCE := 1.0
const BODY_SIZE := Vector2(29.0, 46.0)
const PLAYER_SCENE := "res://scenes/player/player.tscn"
## Extra height kept above Luz's head in the lane checks.
const LANE_MARGIN := 8.0
const HUB_LEFT_INNER := -468.0
const HUB_RIGHT_INNER := 468.0
const ROOM_LEFT_INNER := -768.0
const MAX_WALK_FRAMES := 900
const BOSS_DOOR_NODES: Array[String] = ["DoorToTeacher", "DoorToBlindBeast", "DoorToHydra", "DoorToArtemis"]
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
	"case_hub_layout": 68,
	"case_hub_walk_and_jump": 8,
	"case_boss_rooms": 24,
	"case_room_vestibules": 25,
	"case_arrival_spots": 32,
	"case_hub_forgets_test_bosses": 16,
	"case_desk_checkpoint": 3,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _live: Node
var _recorded: Array[String] = []


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
	for action: StringName in [&"move_left", &"move_right", &"jump"]:
		Input.action_release(action)
	_kill_overlays()
	SceneTransitionArea.clear_transition_memory()
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
		var read_id := "" if boss == null else String(boss.enemy_id)
		check(read_id.begins_with("test_"), "%s boss id read from the instance has the test_ prefix (%s)" % [label, read_id])
		var back := _door_with_id(scene, _return_door_id(room))
		check(back != null and back.target_scene_path == HUB, "%s has a return door to the hub" % label)
		# The prefab itself keeps the real id: teammates place it in real levels.
		var prefab := _instantiate(room.prefab)
		var prefab_boss := prefab.get_node_or_null(room.boss)
		check(prefab_boss != null and prefab_boss.enemy_id == room.real_id, "%s prefab keeps its real id %s" % [label, room.real_id])
		# Editable children keep the override when the room is saved from the editor.
		var text := FileAccess.get_file_as_string(room.scene)
		check(text.contains('[editable path="%s"]' % room.arena), "%s keeps its arena children editable" % label)
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
		await _check_arrivals(room.scene, [_return_door_id(room)], room.arena, ROOM_LEFT_INNER)
	await _check_arrivals(HUB, [
		DoorID.ID.BOSS_HUB_TO_LIBRARY,
		DoorID.ID.BOSS_HUB_TO_TEACHER_ROOM,
		DoorID.ID.BOSS_HUB_TO_BLIND_BEAST_ROOM,
		DoorID.ID.BOSS_HUB_TO_HYDRA_ROOM,
		DoorID.ID.BOSS_HUB_TO_ARTEMIS_DEMO,
	], "hub", HUB_LEFT_INNER)


## Luz arrives through each door in `ids`: on the floor, inside the room (right of
## `min_x`), outside every door trigger and outside the boss trigger.
func _check_arrivals(path: String, ids: Array, label: String, min_x: float) -> void:
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
		check(feet.x > min_x + BODY_SIZE.x * 0.5 and feet.x < HUB_RIGHT_INNER - BODY_SIZE.x * 0.5, "%s: Luz is inside the walls (feet %s)" % [tag, feet])
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
	# The registry records a kill when an enemy emits `died`: seed it the same way.
	var holder := Node2D.new()
	root.add_child(holder)
	var seeded: Array[StringName] = []
	seeded.append_array(BossTestHub.TEST_BOSS_IDS)
	seeded.append(FAKE_ID)
	for boss_id in seeded:
		var boss := (load("res://scenes/enemies/bosses/boombox_teacher.tscn") as PackedScene).instantiate()
		boss.enemy_id = boss_id
		holder.add_child(boss)
		boss.global_position = Vector2(7, 0)
		boss.died.emit(boss)
		check(registry.has_kill(boss_id), "seeded a registry kill for %s" % boss_id)
		if boss_id != FAKE_ID:
			progress.mark_defeated(boss_id, Vector2(7, 0), 1)
	check(BossTestHub.TEST_BOSS_IDS.size() == 3, "the hub knows the three test bosses")
	check(BossTestHub.TEST_BOSS_IDS.all(func(id: StringName) -> bool: return String(id).begins_with("test_")), "every id the hub forgets has the test_ prefix")
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
	root.remove_child(holder)
	holder.free()


## Real numbers of the player: jump height and the body rect relative to the feet.
func _player_numbers() -> Dictionary:
	var player := _instantiate(PLAYER_SCENE)
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var size := (shape_node.shape as RectangleShape2D).size
	var numbers := {
		"jump": float(player.jump_height),
		"width": size.x,
		"height": size.y,
		"top": shape_node.position.y - size.y * 0.5,
	}
	player.free()
	return numbers


## Trigger of a door that is not in the tree (its parent sits at the origin).
func _trigger_rect(door: Node2D) -> Rect2:
	var shape_node := door.get_node("CollisionShape2D") as CollisionShape2D
	var size := (shape_node.shape as RectangleShape2D).size
	return Rect2(door.position + shape_node.position - size * 0.5, size)


## Body swept straight up through one full jump, from feet at (x, 0).
func _jump_envelope(x: float, n: Dictionary) -> Rect2:
	return Rect2(x - n.width * 0.5, -n.jump + n.top, n.width, n.jump - n.top)


## Floor lane Luz walks between two x positions: her standing body plus a margin.
func _lane(from_x: float, to_x: float, n: Dictionary) -> Rect2:
	return Rect2(minf(from_x, to_x) - n.width * 0.5, n.top - LANE_MARGIN, absf(to_x - from_x) + n.width, -n.top + LANE_MARGIN)


func _platform_rect(platform: StaticBody2D) -> Rect2:
	var size := ((platform.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size
	return Rect2(platform.position - size * 0.5, size)


func _hub_platforms(hub: Node) -> Array[StaticBody2D]:
	var found: Array[StaticBody2D] = []
	for child in hub.get_children():
		if child is StaticBody2D and String(child.name).begins_with("Platform"):
			found.append(child as StaticBody2D)
	return found


func _hub_triggers(hub: Node) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for door in _doors_of(hub):
		rects.append(_trigger_rect(door))
	return rects


## x of every place Luz stands in the hub: the spawn, the desk and each arrival.
func _hub_spots(hub: Node) -> Dictionary:
	var spots := {}
	spots["spawn"] = (hub.get_node("Player") as Node2D).position.x
	var desk := hub.get_node("StillnessDesk") as Node2D
	spots["desk"] = desk.position.x + (desk.get_node("SpawnAnchor") as Node2D).position.x
	var library := hub.get_node("DoorToLibrary") as Node2D
	spots["arrival from the library"] = library.position.x + _trigger_rect(library).size.x * 0.5 + SceneTransitionArea.ARRIVAL_CLEARANCE
	for door_name in BOSS_DOOR_NODES:
		var door := hub.get_node(door_name) as SceneTransitionArea
		spots["arrival from %s" % door_name] = door.position.x + door.arrival_offset.x
	return spots


func case_hub_layout() -> void:
	var n := _player_numbers()
	var hub := _instantiate(HUB)
	var triggers := _hub_triggers(hub)
	var platforms := _hub_platforms(hub)
	var whole_lane := _lane(HUB_LEFT_INNER + n.width * 0.5, HUB_RIGHT_INNER - n.width * 0.5, n)
	# Every boss door hangs on its own raised one-way platform.
	for door_name in BOSS_DOOR_NODES:
		var door := hub.get_node(door_name) as SceneTransitionArea
		var platform := hub.get_node_or_null("Platform" + door_name.trim_prefix("DoorTo")) as StaticBody2D
		var trigger := _trigger_rect(door)
		var one_way: bool = platform != null and platform.collision_layer == 2 and platform.collision_mask == 0 and (platform.get_node("CollisionShape2D") as CollisionShape2D).one_way_collision
		check(one_way, "%s hangs on a layer 2 one-way platform" % door_name)
		var top := INF if platform == null else _platform_rect(platform).position.y
		check(absf(top - trigger.end.y) < 0.5, "%s trigger bottom sits on the platform top" % door_name)
		check(-trigger.end.y >= -n.top + LANE_MARGIN, "%s trigger starts above Luz's head on the floor" % door_name)
		check(-top <= n.jump - LANE_MARGIN, "%s platform is within a single jump (%.0f of %.0f)" % [door_name, -top, n.jump])
	# Walking can never trigger a boss door; the library door is the dead end.
	for door_name in BOSS_DOOR_NODES:
		var trigger := _trigger_rect(hub.get_node(door_name))
		check(not trigger.intersects(whole_lane), "%s trigger does not touch the floor walking lane" % door_name)
	var library_trigger := _trigger_rect(hub.get_node("DoorToLibrary"))
	var spots := _hub_spots(hub)
	check(library_trigger.position.x <= HUB_LEFT_INNER, "the library door sits at the far left wall")
	check(float(spots["spawn"]) - n.width * 0.5 > library_trigger.end.x, "the spawn is to the right of the library door")
	# Lane from every standing place to the jump spot of every door.
	for spot_name: String in spots:
		for door_name in BOSS_DOOR_NODES:
			var jump_x := (hub.get_node(door_name) as Node2D).position.x
			var lane := _lane(float(spots[spot_name]), jump_x, n)
			var touched := false
			for rect in triggers:
				touched = touched or rect.intersects(lane)
			check(not touched, "walking from the %s to %s touches no trigger" % [spot_name, door_name])
	# A jump from under a door enters that door and no other.
	for door_name in BOSS_DOOR_NODES:
		var door := hub.get_node(door_name) as Node2D
		var envelope := _jump_envelope(door.position.x, n)
		var entered: Array[String] = []
		for other in _doors_of(hub):
			if _trigger_rect(other).intersects(envelope):
				entered.append(String(other.name))
		check(entered == [door_name], "a jump under %s enters only that door (%s)" % [door_name, entered])
	# No standing place is under a platform or lets a jump touch a trigger.
	for spot_name: String in spots:
		var x := float(spots[spot_name])
		var envelope := _jump_envelope(x, n)
		var touched := false
		for rect in triggers:
			touched = touched or rect.intersects(envelope)
		check(not touched, "a jump at the %s touches no trigger" % spot_name)
		var under := false
		for platform in platforms:
			var rect := _platform_rect(platform)
			under = under or (x + n.width * 0.5 > rect.position.x and x - n.width * 0.5 < rect.end.x)
		check(not under, "the %s is not under a platform" % spot_name)
	hub.free()


## Records which doors of `scene` start a transition. The transition itself is
## cancelled (its overlay is freed right away) so the test stays in the scene.
func _record_transitions(scene: Node) -> void:
	_recorded.clear()
	for door in _doors_of(scene):
		door.transition_started.connect(func(_target: String) -> void:
			_recorded.append(String(door.name))
			_kill_overlays.call_deferred())


func _kill_overlays() -> void:
	for child in root.get_children():
		if child is SceneTransitionArea.ScreenFadeOverlay:
			child.queue_free()
	SceneTransitionArea.is_transition_in_progress = false


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


## Holds `action` until `done` is true or `max_frames` pass; `tick` runs each frame.
func _hold(action: StringName, done: Callable, max_frames: int, tick := Callable()) -> bool:
	Input.action_press(action)
	var frames := 0
	while frames < max_frames and not done.call():
		if tick.is_valid():
			tick.call()
		await physics_frame
		frames += 1
	Input.action_release(action)
	return done.call()


func _start_scene(path: String) -> Player:
	_live = _instantiate(path)
	root.add_child(_live)
	await _frames(3)
	_record_transitions(_live)
	return _live.get_node("Player") as Player


## The real Player walks along the hub floor and jumps under each boss door.
func case_hub_walk_and_jump() -> void:
	for door_name in BOSS_DOOR_NODES:
		var player := await _start_scene(HUB)
		var target_x := (_live.get_node(door_name) as Node2D).position.x
		await _hold(&"move_right", func() -> bool: return player.global_position.x >= target_x - 12.0, MAX_WALK_FRAMES)
		await _frames(45)
		var near := absf(player.global_position.x - target_x) <= 40.0
		check(_recorded.is_empty() and near, "walking under %s triggers no door (x %.0f, target %.0f, doors %s)" % [door_name, player.global_position.x, target_x, _recorded])
		Input.action_press(&"jump")
		await _frames(20)
		Input.action_release(&"jump")
		await _frames(60)
		check(_recorded == [door_name], "a jump under %s enters that door only (%s)" % [door_name, _recorded])
		_cleanup()


func case_room_vestibules() -> void:
	for room: Dictionary in ROOMS:
		var label: String = room.arena
		var scene := _instantiate(room.scene)
		var arena := scene.get_node(room.arena) as BossArena
		var return_door := scene.get_node("DoorToHub") as SceneTransitionArea
		var door_width := arena.door_size.x
		var left_face := arena.left_door.x - door_width * 0.5
		check(_trigger_rect(return_door).end.x <= left_face, "%s return door is outside the arena, behind its left door" % label)
		var lintel := scene.get_node_or_null("DoorwayLintel") as StaticBody2D
		var lintel_size := Vector2.ZERO if lintel == null else ((lintel.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size
		var covers := lintel != null and lintel.position.x - lintel_size.x * 0.5 <= left_face + 0.5 and lintel.position.x + lintel_size.x * 0.5 >= left_face + arena.door_size.x - 0.5 and absf(lintel.position.y + lintel_size.y * 0.5 + arena.door_size.y) < 0.5
		check(covers, "%s has a wall over the doorway the arena door closes" % label)
		if room.arena == "HydraBossArena":
			var platforms := arena.get_node_or_null("Platforms")
			check(platforms != null and platforms.get_child_count() == 5, "the Hydra platforms stay under the arena's Platforms node")
		scene.free()
		# Fight active: Luz walks into the trigger, the left door closes and holds her.
		var player := await _start_scene(room.scene)
		var live_arena := _live.get_node(room.arena) as BossArena
		var fighting := await _hold(&"move_right", func() -> bool: return live_arena.get_state() == BossArena.FightState.ACTIVE, MAX_WALK_FRAMES)
		check(fighting, "%s: walking from the arrival spot reaches the boss trigger" % label)
		await _frames(30)
		check(live_arena.are_doors_closed(), "%s: the arena doors close when the fight starts" % label)
		var keep_alive := func() -> void: player.grant_respawn_invulnerability()
		await _hold(&"move_left", func() -> bool: return false, 240, keep_alive)
		check(player.global_position.x > left_face + door_width, "%s: Luz cannot leave through the closed left door (x %.0f)" % [label, player.global_position.x])
		check(_recorded.is_empty(), "%s: the return door stays out of reach during the fight" % label)
		_cleanup()
		# Fight not active: she walks to the doorway side and back to the return door.
		player = await _start_scene(room.scene)
		live_arena = _live.get_node(room.arena) as BossArena
		await _hold(&"move_right", func() -> bool: return player.global_position.x >= -300.0, MAX_WALK_FRAMES)
		await _frames(20)
		check(player.global_position.x >= -300.0 and live_arena.get_state() == BossArena.FightState.ARMED and not live_arena.are_doors_closed(), "%s: the doorway is open and no fight is active" % label)
		await _hold(&"move_left", func() -> bool: return not _recorded.is_empty(), MAX_WALK_FRAMES)
		await _frames(10)
		check(_recorded == ["DoorToHub"], "%s: Luz walks back to the return door (%s)" % [label, _recorded])
		_cleanup()


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

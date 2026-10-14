extends SceneTree
## Regression test for the door pairing of the library and Greece zones: every
## SceneTransitionArea must point at a door that exists in its target scene, that
## door must lead back, and Luz must arrive on the floor just inside the room,
## clear of every trigger, instead of at the scene start.
## Run: godot --headless --path . --script res://tests/door_links_test.gd
## Exits 0 when every check passes, 1 otherwise.

const LEVELS: Array[String] = ["library", "greece"]
const ZONES: Array[String] = [
	"zone_1", "zone_2", "zone_3", "zone_4", "zone_5", "zone_6", "zone_healing", "zone_lectern",
]
const WATCHDOG_SECONDS := 240.0
## The farthest from its door Luz may arrive.
const MAX_ARRIVAL_DISTANCE := 200.0
const FLOOR_PROBE := 4.0
## Doors whose arrival door does not exist yet, keyed "<level> <zone>/<node>". Library
## zone_6 has no door from zone_4 leading into it (nobody links to it yet); until zone_4
## gets a ZONE_4_TO_ZONE_6 door its exit lands at the zone_4 start and warns. Remove the
## entry as soon as that door exists.
const PENDING_ARRIVAL_DOORS: Array[String] = ["library zone_6/SceneTransitionArea"]

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	var doors: Array[Dictionary] = []
	var arrivals := {}
	for level: String in LEVELS:
		for zone: String in ZONES:
			var path := "res://scenes/levels/%s/%s.tscn" % [level, zone]
			if not ResourceLoader.exists(path):
				continue
			await _read_zone(path, doors, arrivals)
	check(doors.size() >= 20, "found the doors of the zones (%d)" % doors.size())
	for door: Dictionary in doors:
		_check_door(door, arrivals)
	await _check_real_transition()
	finish()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func finish() -> void:
	if failed.is_empty():
		print("PASS %d/%d" % [checks, checks])
		quit(0)
		return
	print("FAIL %d/%d" % [failed.size(), checks])
	for line: String in failed:
		print("  - " + line)
	quit(1)


func _on_watchdog() -> void:
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


# -- Helpers -----------------------------------------------------------------------------

func _load_zone(path: String) -> Node:
	var zone := (load(path) as PackedScene).instantiate()
	root.add_child(zone)
	await physics_frame
	await physics_frame
	return zone


func _unload(zone: Node) -> void:
	root.remove_child(zone)
	zone.free()
	await process_frame


func _scene_key(path_or_uid: String) -> String:
	return (load(path_or_uid) as PackedScene).resource_path


## Loads one zone once: lists its outgoing doors (checking the data that needs no other
## scene) and records, for each door Luz can arrive at, where she would stand.
func _read_zone(path: String, doors: Array[Dictionary], arrivals: Dictionary) -> void:
	var zone := await _load_zone(path)
	var level := path.get_base_dir().get_file()
	var player := get_first_node_in_group(&"player") as CharacterBody2D
	var key := _scene_key(path)
	arrivals[key] = {}
	var own_ids := {}
	for node in get_nodes_in_group(&"spawn_points"):
		if node is Node2D and node.get("spawn_id") != null and node.get("spawn_id") != DoorID.ID.NONE:
			arrivals[key][node.get("spawn_id")] = _arrival_report(player, node)
	for node in zone.find_children("*", "Area2D", true, false):
		if not node is SceneTransitionArea:
			continue
		var area := node as SceneTransitionArea
		var label := "%s %s/%s" % [level, path.get_file().get_basename(), area.name]
		var target := area.target_scene_path
		check(not target.is_empty() and ResourceLoader.exists(target), "%s has a loadable target scene" % label)
		check(area.target_door_id != DoorID.ID.NONE, "%s names a target door" % label)
		check(area.door_id != DoorID.ID.NONE, "%s has its own door id" % label)
		if area.door_id != DoorID.ID.NONE:
			check(not own_ids.has(area.door_id), "%s door id is unique in its scene" % label)
			own_ids[area.door_id] = true
			arrivals[key][area.door_id] = _arrival_report(player, area)
			arrivals[key][area.door_id]["leads_to"] = _scene_key(target) if ResourceLoader.exists(target) else ""
			arrivals[key][area.door_id]["points_at"] = area.target_door_id
		if target.is_empty() or not ResourceLoader.exists(target):
			continue
		doors.append({
			"label": label,
			"source": key,
			"door_id": area.door_id,
			"target": _scene_key(target),
			"target_door": area.target_door_id,
		})
	await _unload(zone)


## Where Luz would stand after arriving through `door`, and whether that spot is sound.
func _arrival_report(player: CharacterBody2D, door: Node2D) -> Dictionary:
	var arrival := SceneTransitionArea.resolve_arrival(door, player.global_position)
	var feet := SceneTransitionArea.settle_position(player, arrival.position, arrival.slide)
	var body := _body_rect(player, feet)
	var clear := true
	for node in get_nodes_in_group(&"scene_transition_area"):
		if node is SceneTransitionArea and _trigger_rect(node).intersects(body):
			clear = false
	return {
		"feet": feet,
		"door_position": door.global_position,
		"free": not _touches_solid(player, feet),
		"standing": _stands_on_floor(player, feet),
		"clear": clear,
	}


## Checks one door against the report of its target scene: the arrival door exists, it
## leads back and Luz arrives standing on the floor, clear of the triggers.
func _check_door(door: Dictionary, arrivals: Dictionary) -> void:
	var label: String = door.label
	var report: Dictionary = arrivals[door.target].get(door.target_door, {})
	if label in PENDING_ARRIVAL_DOORS:
		check(report.is_empty(), "%s: is still pending its arrival door; remove it from PENDING_ARRIVAL_DOORS" % label)
		return
	check(not report.is_empty(), "%s: the target scene has door %s" % [label, DoorID.get_id_name(door.target_door)])
	if report.is_empty():
		return
	if report.has("leads_to"):
		check(report.leads_to == door.source, "%s: the arrival door leads back to the source scene" % label)
		check(report.points_at == door.door_id, "%s: the arrival door points back at door %s" % [label, DoorID.get_id_name(door.door_id)])
	var feet: Vector2 = report.feet
	var distance := feet.distance_to(report.door_position)
	check(distance <= MAX_ARRIVAL_DISTANCE, "%s: Luz arrives at the door (%s from it)" % [label, distance])
	check(report.free, "%s: the arrival spot %s is free of solid geometry" % [label, feet])
	check(report.standing, "%s: Luz arrives standing on the floor at %s" % [label, feet])
	check(report.clear, "%s: the arrival spot %s does not touch a trigger" % [label, feet])


## Runs a real fade transition: Luz must end at the door she used (far from the scene
## start), stay there, respawn there with no checkpoint, and respawn at the checkpoint
## once one is active. A door id the target scene lacks leaves her at the scene start.
func _check_real_transition() -> void:
	var zone_1 := "res://scenes/levels/library/zone_1.tscn"
	var checkpoints := root.get_node_or_null("CheckpointService")
	if checkpoints != null:
		checkpoints.call("clear")
	change_scene_to_file("res://scenes/levels/library/zone_2.tscn")
	await _frames(10)
	SceneTransitionArea.start_transition(self, null, zone_1, 0.1, Color.BLACK, DoorID.ID.ZONE_1_TO_ZONE_2)
	await _frames(150)
	var player := get_first_node_in_group(&"player") as Player
	check(current_scene != null and current_scene.scene_file_path == zone_1, "the transition loads the target scene")
	if player == null:
		return
	var door := SceneTransitionArea.find_door(self, DoorID.ID.ZONE_1_TO_ZONE_2)
	var start := Vector2(83.0, 697.0)
	check(player.global_position.distance_to(door.global_position) < MAX_ARRIVAL_DISTANCE, "Luz arrives at the door she used")
	check(player.global_position.distance_to(start) > 500.0, "Luz does not arrive at the scene start")
	check(player.is_on_floor(), "Luz arrives on the floor")
	check(player.get_facing() == -1, "Luz faces into the room")
	var arrival := player.global_position
	await _frames(90)
	check(current_scene.scene_file_path == zone_1 and player.global_position.distance_to(arrival) < 2.0, "the door does not retrigger")
	player.global_position = start
	player.respawn()
	check(player.global_position.distance_to(arrival) < 2.0, "respawn without a checkpoint returns to the arrival door")
	if checkpoints != null:
		var desk_spot := Vector2(300.0, 697.0)
		checkpoints.call("activate", &"door_links_test", zone_1, desk_spot)
		player.global_position = start
		checkpoints.call("apply_to_player", player, zone_1)
		player.respawn()
		check(player.global_position.distance_to(desk_spot) < 2.0, "respawn with an active checkpoint uses the checkpoint, not the door")
		checkpoints.call("clear")
	SceneTransitionArea.start_transition(self, null, "res://scenes/levels/library/zone_2.tscn", 0.1, Color.BLACK, DoorID.ID.DOOR_F)
	await _frames(150)
	player = get_first_node_in_group(&"player") as Player
	check(player != null and player.global_position.distance_to(Vector2(35.0, 201.0)) < 20.0, "a missing door id leaves Luz at the scene start")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _body_rect(player: CharacterBody2D, feet: Vector2) -> Rect2:
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var size := (shape_node.shape as RectangleShape2D).size
	return Rect2(feet + shape_node.position - size * 0.5, size)


func _trigger_rect(area: SceneTransitionArea) -> Rect2:
	var half := area._half_extents()
	return Rect2(area._shape_center() - half, half * 2.0)


func _query(player: CharacterBody2D, feet: Vector2) -> PhysicsShapeQueryParameters2D:
	var shape_node := player.get_node("CollisionShape2D") as CollisionShape2D
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.collision_mask = player.collision_mask
	params.exclude = [player.get_rid()]
	params.transform = Transform2D(0.0, feet + shape_node.position)
	return params


func _touches_solid(player: CharacterBody2D, feet: Vector2) -> bool:
	return not player.get_world_2d().direct_space_state.intersect_shape(_query(player, feet), 1).is_empty()


func _stands_on_floor(player: CharacterBody2D, feet: Vector2) -> bool:
	var params := _query(player, feet)
	params.motion = Vector2(0.0, FLOOR_PROBE)
	var fractions := player.get_world_2d().direct_space_state.cast_motion(params)
	return fractions.size() == 2 and fractions[0] < 1.0

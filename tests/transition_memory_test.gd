extends SceneTree
## Regression test for the transition fallback memory: when a door's
## `target_door_id` no longer exists in the target scene, Luz must still arrive at
## the connection point she used before (the reverse door, a remembered arrival or
## the only door of the room) instead of at the scene start. Also runs the real
## Greece healing <-> Artemis links, whose `ARTEMIS_TO_HEALING` door is missing.
## Run: godot --headless --path . --script res://tests/transition_memory_test.gd
## Exits 0 when every check passes, 1 otherwise.

const HEALING_PATH := "res://scenes/levels/greece/zone_healing.tscn"
const ARTEMIS_PATH := "res://scenes/levels/greece/zone_artemis.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CONTACT_SCENE := "res://scenes/world/contact_damage.tscn"
const HEALING_START := Vector2(39.0, 385.0)
const WATCHDOG_SECONDS := 120.0

const CHECKS := {
	"case_return_door_prefers_exact_reverse": 3,
	"case_remembered_arrival_wins_over_single_door": 4,
	"case_single_door_and_no_memory_fallbacks": 3,
	"case_remembered_spot_rejected_when_unsafe": 4,
	"case_real_healing_to_artemis_uses_only_door": 8,
	"case_real_return_to_healing_uses_return_door": 8,
}


var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player


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
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])
	_free_rig()
	await process_frame


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


# -- Rig -------------------------------------------------------------------------

func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	await process_frame


func _build_player_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, Rect2(-500.0, 0.0, 1000.0, 200.0), Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(0.0, 0.0)
	_rig.add_child(_player)
	await _frames(30)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null


## Minimal door for the static helpers: only the pairing data is needed.
func _make_door(parent: Node, target_path: String, door_id: DoorID.ID, target_id: DoorID.ID, at: Vector2) -> SceneTransitionArea:
	var door := SceneTransitionArea.new()
	door.target_scene_path = target_path
	door.door_id = door_id
	door.target_door_id = target_id
	door.position = at
	parent.add_child(door)
	return door


func _wait_for_scene(path: String, limit_frames: int = 900) -> bool:
	for i: int in limit_frames:
		if current_scene != null and current_scene.scene_file_path == path and not SceneTransitionArea.is_transition_in_progress:
			return true
		await process_frame
	return current_scene != null and current_scene.scene_file_path == path and not SceneTransitionArea.is_transition_in_progress


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _start_transition(path: String, target_door: DoorID.ID, source_scene: String, source_door: DoorID.ID) -> void:
	SceneTransitionArea.start_transition(
		self,
		null,
		path,
		0.05,
		Color.BLACK,
		target_door,
		true,
		false,
		null,
		"",
		0.0,
		SceneTransitionArea.LoadingAnimationMode.NONE,
		null,
		24,
		60.0,
		1.25,
		false,
		"",
		22,
		source_scene,
		source_door
	)


# -- Cases -----------------------------------------------------------------------

## The exact reverse link must beat any other door that merely points at the
## source scene; without it, the first door back is used.
func case_return_door_prefers_exact_reverse() -> void:
	await _build_rig()
	var source := "res://tests/fake/source.tscn"
	var loose := _make_door(_rig, source, DoorID.ID.DOOR_A, DoorID.ID.DOOR_E, Vector2(10.0, 0.0))
	var exact := _make_door(_rig, source, DoorID.ID.DOOR_B, DoorID.ID.DOOR_C, Vector2(20.0, 0.0))
	# `exact` is the one whose target id matches the door she came from.
	var back := SceneTransitionArea.find_return_door(self, source, DoorID.ID.DOOR_C)
	check(back == exact, "the exact reverse link wins over another door back")
	exact.free()
	await process_frame
	back = SceneTransitionArea.find_return_door(self, source, DoorID.ID.DOOR_C)
	check(back == loose, "without the exact link the first door back is used")
	loose.free()
	await process_frame
	back = SceneTransitionArea.find_return_door(self, source, DoorID.ID.DOOR_C)
	check(back == null, "a scene with no door back resolves nothing")


## A remembered arrival is used before the only-door guess, and unknown scenes
## have no memory.
func case_remembered_arrival_wins_over_single_door() -> void:
	await _build_rig()
	SceneTransitionArea.clear_transition_memory()
	var source := "res://tests/fake/source.tscn"
	var target := "res://tests/fake/remembered.tscn"
	var spot := Vector2(123.0, 456.0)
	SceneTransitionArea.remember_arrival(target, DoorID.ID.DOOR_C, spot)
	check(SceneTransitionArea.get_remembered_arrival(target) == spot, "the arrival position is remembered per scene")
	check(SceneTransitionArea.get_remembered_arrival("res://tests/fake/unknown.tscn") == null, "an unvisited scene has no remembered arrival")
	var only := _make_door(_rig, "res://tests/fake/other.tscn", DoorID.ID.DOOR_D, DoorID.ID.NONE, Vector2(30.0, 0.0))
	var fallback := SceneTransitionArea.resolve_fallback_arrival(self, source, DoorID.ID.DOOR_A, target)
	check(fallback.get("position") == spot, "the remembered arrival wins over the only-door guess")
	SceneTransitionArea.clear_transition_memory()
	fallback = SceneTransitionArea.resolve_fallback_arrival(self, source, DoorID.ID.DOOR_A, target)
	check(fallback.get("door") == only, "after clearing the memory the only door is used")


## The only-door guess needs exactly one door; no door and no memory returns an
## empty answer so the caller keeps the scene start.
func case_single_door_and_no_memory_fallbacks() -> void:
	await _build_rig()
	SceneTransitionArea.clear_transition_memory()
	var source := "res://tests/fake/source.tscn"
	var target := "res://tests/fake/target.tscn"
	var fallback := SceneTransitionArea.resolve_fallback_arrival(self, source, DoorID.ID.DOOR_A, target)
	check(fallback.is_empty(), "no door and no memory resolves to the scene start")
	var only := _make_door(_rig, "res://tests/fake/other.tscn", DoorID.ID.DOOR_D, DoorID.ID.NONE, Vector2(30.0, 0.0))
	fallback = SceneTransitionArea.resolve_fallback_arrival(self, source, DoorID.ID.DOOR_A, target)
	check(fallback.get("door") == only, "a room with exactly one door uses it")
	_make_door(_rig, "res://tests/fake/another.tscn", DoorID.ID.DOOR_E, DoorID.ID.NONE, Vector2(40.0, 0.0))
	fallback = SceneTransitionArea.resolve_fallback_arrival(self, source, DoorID.ID.DOOR_A, target)
	check(fallback.is_empty(), "a room with several doors and no memory keeps the scene start")


## A remembered spot is only reused while it is still free, supported and clear
## of hazards; a hazard or a new wall there sends her back to the scene start.
func case_remembered_spot_rejected_when_unsafe() -> void:
	await _build_player_rig()
	check(_player != null and _player.is_on_floor(), "Luz stands on the synthetic floor")
	if _player == null:
		return
	var feet := _player.global_position
	check(SceneTransitionArea.is_arrival_safe(_player, feet), "her standing spot is a valid remembered arrival")
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	hazard.kind = ContactDamage.Kind.HAZARD
	_rig.add_child(hazard)
	hazard.set_area_size(Vector2(48.0, 32.0))
	hazard.position = feet + Vector2(0.0, -8.0)
	await _frames(2)
	check(not SceneTransitionArea.is_arrival_safe(_player, feet), "a hazard on the spot invalidates the memory")
	hazard.free()
	await _frames(2)
	LevelGeometry.add_solid(_rig, Rect2(feet.x - 40.0, feet.y - 80.0, 80.0, 80.0), Color.DIM_GRAY)
	await _frames(2)
	check(not SceneTransitionArea.is_arrival_safe(_player, feet), "a wall on the spot invalidates the memory")


## Real transition: healing door 27 targets ARTEMIS_TO_HEALING (28), which does
## not exist in the Artemis room. Artemis has a single door (30), so Luz must be
## placed at that door and the arrival remembered, not left at the scene start.
func case_real_healing_to_artemis_uses_only_door() -> void:
	SceneTransitionArea.clear_transition_memory()
	var checkpoints := root.get_node_or_null("CheckpointService")
	if checkpoints != null:
		checkpoints.call("clear")
	change_scene_to_file(HEALING_PATH)
	await _frames(12)
	var player := get_first_node_in_group(&"player") as Player
	check(player != null, "Luz starts in the healing room")
	var door := SceneTransitionArea.find_door(self, DoorID.ID.HEALING_TO_ARTEMIS) as SceneTransitionArea
	check(door != null, "the healing room keeps its door to Artemis")
	if player == null or door == null:
		return
	door.fade_duration = 0.05
	door.min_loading_screen_time = 0.0
	door.show_scene_name = false
	door._on_body_entered(player)
	var arrived := await _wait_for_scene(ARTEMIS_PATH)
	check(arrived, "the healing door loads the Artemis room")
	if not arrived:
		return
	player = get_first_node_in_group(&"player") as Player
	var fallback_door := SceneTransitionArea.find_door(self, DoorID.ID.ARTEMIS_TO_ZONE_5) as SceneTransitionArea
	check(fallback_door != null and player != null and player.global_position.distance_to(fallback_door.global_position) < 200.0, "Luz arrives at the Artemis room's only door")
	if player == null or fallback_door == null:
		return
	var raw := SceneTransitionArea.resolve_arrival(fallback_door, Vector2(2060.0, 480.0))
	var expected := SceneTransitionArea.settle_position(player, raw.position, raw.slide)
	check(player.global_position.distance_to(expected) < 3.0, "the missing door uses the only door's arrival spot (%s vs %s)" % [player.global_position, expected])
	check(SceneTransitionArea._entry_door == DoorID.ID.ARTEMIS_TO_ZONE_5, "the fallback records which door it used")
	var remembered: Variant = SceneTransitionArea.get_remembered_arrival(ARTEMIS_PATH)
	check(remembered != null and (remembered as Vector2).distance_to(player.global_position) < 2.0, "the fallback arrival is remembered for the next visit")
	var spot := player.global_position
	await _frames(90)
	check(current_scene.scene_file_path == ARTEMIS_PATH and player.global_position.distance_to(spot) < 2.0, "the fallback door does not retrigger")


## Return through a link whose healing door (28) is missing: from the Artemis
## room the healing room's door 27 must be selected as the return door, so Luz
## lands beside it instead of at the healing room's start.
func case_real_return_to_healing_uses_return_door() -> void:
	var player := get_first_node_in_group(&"player") as Player
	check(current_scene != null and current_scene.scene_file_path == ARTEMIS_PATH and player != null, "the Artemis room is the current scene")
	if current_scene == null or player == null:
		return
	_start_transition(HEALING_PATH, DoorID.ID.ARTEMIS_TO_HEALING, ARTEMIS_PATH, DoorID.ID.ARTEMIS_TO_ZONE_5)
	var arrived := await _wait_for_scene(HEALING_PATH)
	check(arrived, "the return link loads the healing room")
	if not arrived:
		return
	player = get_first_node_in_group(&"player") as Player
	var back := SceneTransitionArea.find_door(self, DoorID.ID.HEALING_TO_ARTEMIS) as SceneTransitionArea
	check(back != null and player != null, "the healing room's return door exists")
	if player == null or back == null:
		return
	var raw := SceneTransitionArea.resolve_arrival(back, HEALING_START)
	var expected := SceneTransitionArea.settle_position(player, raw.position, raw.slide)
	check(player.global_position.distance_to(expected) < 3.0, "the return link lands at door 27 (%s vs %s)" % [player.global_position, expected])
	check(player.global_position.distance_to(HEALING_START) > 500.0, "the return link does not use the healing scene start")
	check(SceneTransitionArea._entry_door == DoorID.ID.HEALING_TO_ARTEMIS, "the return link records the door it used")
	var remembered: Variant = SceneTransitionArea.get_remembered_arrival(HEALING_PATH)
	check(remembered != null and (remembered as Vector2).distance_to(player.global_position) < 2.0, "the return arrival is remembered for the next visit")
	var spot := player.global_position
	await _frames(90)
	check(current_scene.scene_file_path == HEALING_PATH and player.global_position.distance_to(spot) < 2.0, "the return door does not retrigger")

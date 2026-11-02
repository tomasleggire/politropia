extends SceneTree
## Regression coverage for level-scoped collection, depositing, death loss,
## pickup restoration, the lectern and the four-state HUD.
## Run: godot --headless --path . --script res://tests/fragment_progress_test.gd

const FRAGMENT_SCENE := preload("res://scenes/world/fragmento_libro_2.tscn")
const PEDESTAL_SCENE := "res://scenes/world/atril_libro.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)
const WATCHDOG_SECONDS := 60.0

var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player
var _events: Array[Vector3i] = []


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
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


func _progress() -> Node:
	return root.get_node("FragmentProgress")


func _run() -> void:
	_case_service()
	await _case_fragment_prefab_and_death()
	await _case_pedestal()
	await _case_hud()
	_progress().clear()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _build_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = Node2D.new()
	root.add_child(_rig)
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FLOOR_RECT.size
	shape.shape = rect
	body.position = FLOOR_RECT.get_center()
	body.add_child(shape)
	_rig.add_child(body)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(-400.0, 0.0)
	_rig.add_child(_player)
	await _frames(20)


func _case_service() -> void:
	var progress := _progress()
	progress.clear()
	_events.clear()
	progress.fragment_collected.connect(func(id: int, count: int, total: int) -> void: _events.append(Vector3i(id, count, total)))
	check(progress.count("library") == 0, "starts empty")
	check(progress.collect(2, "library"), "collect returns true once")
	check(not progress.collect(2, "library"), "duplicate collection is refused")
	check(progress.is_carried(2, "library") and progress.count("library") == 1, "collection is temporary carry state")
	check(progress.count("greece") == 0, "levels have independent progress")
	check(not progress.collect(0, "library") and not progress.collect(5, "library"), "invalid ids are refused")
	check(_events.size() == 1 and _events[0] == Vector3i(2, 1, 4), "collection signal reports id and full progress")
	var saved: Dictionary = progress.to_dict()
	progress.clear()
	progress.from_dict(saved)
	check(progress.is_carried(2, "library"), "in-memory serialization helper restores level state")
	progress.clear()
	for id in [1, 2, 3, 4]:
		progress.collect(id, "library")
	check(progress.is_complete("library"), "four carried fragments are counted")
	check(not progress.is_fully_deposited("library"), "carrying all four does not complete the book")
	progress.clear()


func _case_fragment_prefab_and_death() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	var fragment := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	check(fragment.fragment_id == 2, "fragment scene has its unique id")
	_rig.add_child(fragment)
	await _frames(3)
	check(is_instance_valid(fragment) and not progress.has_fragment(2), "fragment starts available")
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(6)
	check(progress.is_carried(2) and progress.count() == 1, "touching picks up the fragment")
	await create_timer(0.6).timeout
	check(is_instance_valid(fragment) and not fragment.visible, "collected fragment hides without losing its map position")
	var again := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	_rig.add_child(again)
	await _frames(3)
	check(is_instance_valid(again) and not again.visible, "a room reload respects the carried state")
	_player._respawn_after_death()
	await _frames(2)
	check(not progress.has_fragment(2), "player death clears carried state")
	check(fragment.visible and fragment.collectible and again.visible and again.collectible, "death restores the fragment at its original map position")
	progress.clear()
	var display := FRAGMENT_SCENE.instantiate() as FloatingBookFragment
	display.collectible = false
	display.position = Vector2.ZERO
	_rig.add_child(display)
	_player.global_position = Vector2(300.0, -10.0)
	await _frames(4)
	_player.global_position = Vector2.ZERO
	await _frames(6)
	check(progress.count() == 0 and is_instance_valid(display), "lectern display copies are never collectible")


func _case_pedestal() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	var pedestal := (load(PEDESTAL_SCENE) as PackedScene).instantiate()
	pedestal.position = Vector2(300.0, 0.0)
	_rig.add_child(pedestal)
	await _frames(3)
	pedestal.set("_player", _player)
	check(not pedestal.request_interact(), "empty inventory cannot be deposited")
	progress.collect(1)
	progress.collect(2)
	check(pedestal.request_interact(), "one fragment deposits per interaction")
	check(progress.is_deposited(1) and progress.is_carried(2), "deposit consumes only the deposited id")
	check(pedestal.request_interact(), "a second carried fragment can be deposited")
	progress.collect(3)
	progress.collect(4)
	check(progress.deposited_ids().size() == 2 and progress.carried_ids().size() == 2, "two deposited and two carried remain distinct")
	progress.lose_carried()
	check(progress.is_deposited(1) and progress.is_deposited(2), "death preserves secured fragments")
	check(not progress.has_fragment(3) and not progress.has_fragment(4), "death loses unsecured fragments")
	progress.collect(3)
	progress.collect(4)
	check(pedestal.request_interact() and pedestal.request_interact(), "lost pieces can be collected and deposited again")
	await _frames(2)
	check(progress.is_fully_deposited(), "four different deposited ids complete the set")
	check(progress.reconstruction_started(), "full deposit claims the reconstruction sequence")
	check(not progress.begin_reconstruction(), "reconstruction cannot start twice")
	progress.collect(1, "greece")
	check(progress.is_carried(1, "greece") and progress.is_deposited(1, "library"), "same id in another level has independent state")
	progress.clear()


func _case_hud() -> void:
	await _build_rig()
	var progress := _progress()
	progress.clear()
	var hud := HUD_SCENE.instantiate()
	_rig.add_child(hud)
	await _frames(2)
	var icon1 := hud.get_node("FragmentIndicator/Slot1/Icon") as TextureRect
	var mark1 := hud.get_node("FragmentIndicator/Slot1/DepositMark") as Label
	var icon3 := hud.get_node("FragmentIndicator/Slot3/Icon") as TextureRect
	var all_dim := true
	for id in range(1, 5):
		var icon := hud.get_node("FragmentIndicator/Slot%d/Icon" % id) as TextureRect
		var mark := hud.get_node("FragmentIndicator/Slot%d/DepositMark" % id) as Label
		all_dim = all_dim and icon.modulate == Color("56545c") and not mark.visible
	check(all_dim, "all four HUD icons start unlit")
	progress.collect(1)
	check(icon1.modulate == Color("ffd66e") and not mark1.visible, "carrying lights the matching icon")
	progress.collect(3)
	check(icon3.modulate == Color("ffd66e"), "second pickup lights its own icon")
	progress.collect(2)
	progress.collect(4)
	progress.deposit(1)
	check(mark1.visible, "deposit adds the secured mark")
	progress.deposit(2)
	check((hud.get_node("FragmentIndicator/Slot2/DepositMark") as Label).visible, "second deposited piece gets its own mark")
	check((hud.get_node("FragmentIndicator/Slot4/Icon") as TextureRect).modulate == Color("ffd66e"), "two carried pieces remain illuminated")
	progress.lose_carried()
	check(icon1.modulate == Color("ffd66e") and mark1.visible, "death keeps the deposited icon secured")
	check(icon3.modulate == Color("56545c"), "death dims the lost carried icon")
	check((hud.get_node("FragmentIndicator/Slot2/DepositMark") as Label).visible and (hud.get_node("FragmentIndicator/Slot4/Icon") as TextureRect).modulate == Color("56545c"), "death preserves both deposits and dims both lost pieces")
	progress.clear()

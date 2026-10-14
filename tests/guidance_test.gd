extends SceneTree
## TutorialSign (fade in/out near Luz, show-once) and PickupToast (queue, ability
## texts) on a synthetic floor.
## Run: godot --headless --path . --script res://tests/guidance_test.gd

const SIGN_SCENE := preload("res://scenes/world/tutorial_sign.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)
const WATCHDOG_SECONDS := 60.0

var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player


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


func _run() -> void:
	await _case_sign()
	await _case_show_once()
	await _case_marker_style()
	await _case_toast()


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _make_sign(show_once: bool, style := TutorialSign.MarkerStyle.FIREFLIES) -> TutorialSign:
	var sign_node := SIGN_SCENE.instantiate() as TutorialSign
	sign_node.title = "Titulo"
	sign_node.text = "Cuerpo [color=#e0b94f]uno[/color]"
	sign_node.show_once = show_once
	sign_node.marker_style = style
	sign_node.fade_time = 0.1
	sign_node.position = Vector2(0.0, 0.0)
	_rig.add_child(sign_node)
	return sign_node


func _case_sign() -> void:
	await _build_rig()
	TutorialSign.reset_seen()
	var sign_node := _make_sign(false)
	await _frames(3)
	check(not sign_node.is_panel_visible(), "panel hidden at start")
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(sign_node.is_panel_visible(), "panel visible near the sign")
	check(sign_node.get_node("PanelLayer/Root/Panel/Margin/Box/Title").text == "Titulo", "title applied")
	_player.global_position = Vector2(-400.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(not sign_node.is_panel_visible(), "panel hidden after leaving")


func _case_show_once() -> void:
	await _build_rig()
	TutorialSign.reset_seen()
	var sign_node := _make_sign(true)
	await _frames(3)
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(sign_node.is_panel_visible(), "show-once shows the first time")
	_player.global_position = Vector2(-400.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(sign_node.is_seen(), "show-once marks as read")
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(not sign_node.is_panel_visible(), "show-once stays hidden afterwards")
	TutorialSign.reset_seen()
	check(not sign_node.is_seen(), "reset_seen forgets")


func _case_marker_style() -> void:
	await _build_rig()
	TutorialSign.reset_seen()
	var fireflies := _make_sign(false)
	check(fireflies.marker_style == TutorialSign.MarkerStyle.FIREFLIES, "fireflies are the default marker")
	var signpost := _make_sign(false, TutorialSign.MarkerStyle.SIGNPOST)
	var none := _make_sign(false, TutorialSign.MarkerStyle.NONE)
	await _frames(3)
	check(fireflies.has_fireflies() and not (fireflies.get_node("Visual") as Node2D).visible, "fireflies marker hides the signpost")
	check(signpost.get_node("Visual").visible and not signpost.has_fireflies(), "signpost style keeps the signpost")
	check(not none.get_node("Visual").visible and not none.has_fireflies(), "none style draws nothing")
	_player.global_position = Vector2(0.0, -10.0)
	await _frames(4)
	await _wait(0.25)
	check(fireflies.is_panel_visible() and none.is_panel_visible(), "panel still shows with every marker style")
	var library := load("res://scenes/levels/library/zone_1.tscn") as PackedScene
	var state := library.get_state()
	var signs := 0
	for i in state.get_node_count():
		var instance := state.get_node_instance(i)
		if instance != null and instance.resource_path.ends_with("tutorial_sign.tscn"):
			signs += 1
			var overridden := false
			for j in state.get_node_property_count(i):
				overridden = overridden or state.get_node_property_name(i, j) == &"marker_style"
			check(not overridden, "library sign %s keeps the default fireflies" % state.get_node_name(i))
	check(signs == 5, "library zone_1 has five signs (%d)" % signs)


func _case_toast() -> void:
	await _build_rig()
	var toast := root.get_node_or_null("PickupToast")
	check(toast != null, "PickupToast autoload exists")
	if toast == null:
		return
	toast.hold_time = 0.1
	toast.fade_in_time = 0.05
	toast.fade_out_time = 0.05
	toast.show_toast("Uno", "sub")
	toast.show_toast("Dos")
	await _frames(3)
	check(toast.get_node("Root/Slide").visible, "toast visible")
	check(toast.get_node("Root/Slide/Panel/Margin/Box/Title").text == "Uno", "first toast plays first")
	await _wait(0.4)
	check(toast.get_node("Root/Slide/Panel/Margin/Box/Title").text == "Dos", "second toast queued after the first")
	check(not toast.get_node("Root/Slide/Panel/Margin/Box/Subtitle").visible, "empty subtitle hidden")
	await _wait(0.4)
	check(not toast.get_node("Root/Slide").visible, "toast hides when the queue is empty")
	toast.show_toast("Pre")
	_player.ability_unlocked.emit(&"double_jump")
	await _wait(0.4)
	check(toast.get_node("Root/Slide/Panel/Margin/Box/Title").text == "Doble salto", "ability unlock shows its toast")

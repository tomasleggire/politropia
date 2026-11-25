extends SceneTree
## Main menu "El Umbral": the four options, the skipped CONTINUAR row, Luz on the
## threshold, the cover-fit stage at 640x360 and 780x360 and the new game
## cinematic (input lock + Luz walking) without leaving the scene.
## Run: godot --headless --path . --script res://tests/main_menu_test.gd

# Loaded at run time: the menu script names autoloads, which are not
# registered yet while this script compiles.
const MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const WATCHDOG_SECONDS := 30.0
const EPSILON := 0.01

var checks := 0
var failed: Array[String] = []
var _changed_to := ""


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
	_check_cover_fit()
	var menu: Control = (load(MENU_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	_check_options(menu)
	_check_account_ui(menu)
	_check_navigation(menu)
	_check_luz(menu)
	await _check_new_game(menu)
	menu.queue_free()


func _check_cover_fit() -> void:
	for size in [Vector2(640, 360), Vector2(780, 360), Vector2(360, 780)]:
		var covered: Rect2 = MainMenuStage.compute_stage_transform(size) * Rect2(Vector2.ZERO, MainMenuStage.ART_SIZE)
		var label := "stage covers %dx%d" % [size.x, size.y]
		check(covered.position.x <= EPSILON and covered.position.y <= EPSILON, label + " (origin)")
		check(covered.end.x >= size.x - EPSILON and covered.end.y >= size.y - EPSILON, label + " (end)")


func _check_options(menu: Node) -> void:
	check(menu.btn_new_game.text == "NUEVA PARTIDA", "NewGame text")
	check(menu.btn_continue.text == "CONTINUAR", "Continue text")
	check(menu.btn_collectables.text == "COLECCIONABLES", "Collectables text")
	check(menu.btn_achievements.text == "LOGROS", "Achievements text")
	check(menu.btn_continue.disabled, "Continue disabled")
	check(menu.btn_continue.focus_mode == Control.FOCUS_NONE, "Continue not focusable")
	check(menu.btn_new_game.has_focus(), "NewGame focused on open")


func _check_account_ui(menu: Node) -> void:
	check(menu.account_avatar != null, "account_avatar exists")
	check(not menu.account_avatar.visible, "account_avatar hidden when disconnected")
	check(menu.btn_account.text == "CONECTAR GOOGLE", "account button shows CONECTAR GOOGLE when disconnected")
	check(menu.btn_switch_account != null, "btn_switch_account exists")
	check(not menu.btn_switch_account.visible, "btn_switch_account hidden when disconnected")

	var firebase: Node = root.get_node_or_null("/root/FirebaseService")
	if firebase == null:
		return

	var prev_logged: bool = firebase.is_logged_in
	var prev_name: String = firebase.user_name
	var prev_email: String = firebase.user_email
	var prev_photo: String = firebase.user_photo_url

	# Simulate connected Google user with full name (first name + surname)
	firebase.is_logged_in = true
	firebase.user_name = "Juan Zurita"
	firebase.user_email = "juan.zurita@example.com"
	menu._update_account_ui()

	check(menu.account_avatar.visible, "account_avatar visible when connected")
	check(menu.account_avatar.texture != null, "account_avatar has texture when connected")
	check(menu.btn_account.text == "JUAN", "account button shows only first name (excluding surname)")
	check(menu.btn_switch_account.visible, "btn_switch_account visible when connected")
	check(menu.btn_switch_account.text == "CAMBIAR USUARIO", "btn_switch_account text is CAMBIAR USUARIO")

	# Simulate connected Google user with single name
	firebase.user_name = "Lucas"
	firebase.user_email = "lucas@example.com"
	menu._update_account_ui()
	check(menu.btn_account.text == "LUCAS", "account button shows single name correctly")

	# Simulate connected Google user with only email (no display name)
	firebase.user_name = ""
	firebase.user_email = "maria@example.com"
	menu._update_account_ui()
	check(menu.btn_account.text == "MARIA", "account button shows username from email without domain or cloud icon")

	# Restore disconnected state
	firebase.is_logged_in = prev_logged
	firebase.user_name = prev_name
	firebase.user_email = prev_email
	firebase.user_photo_url = prev_photo
	menu._update_account_ui()
	check(not menu.account_avatar.visible, "account_avatar hidden after restore")
	check(not menu.btn_switch_account.visible, "btn_switch_account hidden after restore")
	check(menu.btn_account.text == "CONECTAR GOOGLE", "account button restored to CONECTAR GOOGLE")


func _check_navigation(menu: Node) -> void:
	var new_game: Button = menu.btn_new_game
	var collectables: Button = menu.btn_collectables
	var achievements: Button = menu.btn_achievements
	check(new_game.get_node(new_game.focus_neighbor_bottom) == collectables, "down skips CONTINUAR")
	check(collectables.get_node(collectables.focus_neighbor_top) == new_game, "up skips CONTINUAR")
	check(achievements.get_node(achievements.focus_neighbor_bottom) == new_game, "down wraps to top")
	check(new_game.get_node(new_game.focus_neighbor_top) == achievements, "up wraps to bottom")


func _check_luz(menu: Node) -> void:
	var luz: AnimatedSprite2D = menu.get_node("%Luz")
	check(luz != null and luz.sprite_frames != null, "Luz has frames")
	if luz == null or luz.sprite_frames == null:
		return
	var catalog := LuzAnimationCatalog.build_sprite_frames()
	check(luz.sprite_frames.has_animation(&"idle") and luz.sprite_frames.has_animation(&"walk"), "Luz idle and walk exist")
	check(luz.sprite_frames.get_frame_count(&"idle") == catalog.get_frame_count(&"idle"), "Luz uses catalog idle")
	check(luz.animation == &"idle" and luz.is_playing(), "Luz plays idle")


func _check_new_game(menu: Node) -> void:
	menu.scene_changer = func(path: String) -> void: _changed_to = path
	menu.btn_new_game.pressed.emit()
	await process_frame
	var luz: AnimatedSprite2D = menu.get_node("%Luz")
	check(menu.input_locked, "input locked after NUEVA PARTIDA")
	check(luz.animation == &"walk", "Luz walks")
	check(menu.btn_collectables.focus_mode == Control.FOCUS_NONE, "buttons lose focus during cinematic")
	check(_changed_to == "", "scene not changed before the cinematic ends")
	menu.btn_new_game.pressed.emit()
	check(_changed_to == "", "second press ignored")

extends SceneTree
## GAME OVER overlay: it takes over after the last heart and the death beat,
## pauses the game exactly once, stays visible, blocks the pause menu and
## resolves through REINTENTAR (existing respawn) or MENÚ PRINCIPAL.
## Run: godot --headless --path . --script res://tests/game_over_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MAIN_MENU_FONT := "res://assets/ui/Cinzel-Bold.ttf"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 5
const DEATH_BEAT := 0.75
const EXTRA_WAIT := 1.2
const CHECKPOINT := Vector2(48.0, 0.0)
const FLOOR_RECT := Rect2(-300.0, 0.0, 600.0, 40.0)
const OPTION_COLOR := Color(0.91, 0.85, 0.66, 1.0)
const OPTION_SELECTED_COLOR := Color(1.0, 0.96, 0.84, 1.0)
const OPTION_OUTLINE_COLOR := Color(1.0, 0.72, 0.3, 0.3)
const OPTION_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]

const CHECKS := {
	"case_nonlethal_hit_does_not_show": 4,
	"case_last_heart_starts_once": 9,
	"case_screen_stays_and_blocks_reentry": 11,
	"case_interface_contract": 12,
	"case_options_use_main_menu_language": 22,
	"case_layout_is_centered_and_touch_safe": 19,
	"case_option_feedback_is_transient": 14,
	"case_reveal_is_progressive": 6,
	"case_retry_restores_the_run": 16,
	"case_retry_without_checkpoint_uses_zone_start": 7,
	"case_main_menu_is_clean": 14,
	"case_application_focus_keeps_screen": 8,
	"case_aspect_ratios_keep_layout_inside": 21,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _game_over: CanvasLayer
var _shown_count := 0
var _died_count := 0
var _respawn_count := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_game_over = root.get_node("GameOver") as CanvasLayer
	_game_over.shown.connect(_on_shown)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _tick() -> void:
	_clock += root.get_process_delta_time()


func _on_shown() -> void:
	_shown_count += 1


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	_free_rig()
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


# -- Rig and helpers -----------------------------------------------------------------

func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2.ZERO
	_rig.add_child(_player)
	_shown_count = 0
	_died_count = 0
	_respawn_count = 0
	_player.died.connect(func() -> void: _died_count += 1)
	_player.respawned.connect(func() -> void: _respawn_count += 1)
	await _frames(SETTLE_FRAMES)

	_game_over = root.get_node("GameOver") as CanvasLayer
	_game_over.enabled = true
	# Fast by default; the progressive case restores the real timings.
	_game_over.backdrop_fade_time = 0.01
	_game_over.content_delay = 0.0
	_game_over.content_fade_time = 0.01
	# GameOver only takes over a running scene. Standalone rigs keep the old
	# automatic respawn, so these tests mark the rig as the current scene.
	current_scene = _rig


func _free_rig() -> void:
	if _game_over != null and is_instance_valid(_game_over):
		if _game_over.is_active():
			_game_over.call(&"_close_overlay")
			_game_over.call(&"_set_touch_blocked", false)
			_game_over.set(&"_player", null)
		_game_over.set(&"_reveal_tween", null)
	paused = false
	if is_instance_valid(_rig):
		if current_scene == _rig:
			current_scene = null
		_rig.free()
	_rig = null
	_player = null
	_game_over = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _wait_until(condition: Callable, limit_frames := 300) -> bool:
	for i: int in limit_frames:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _overlay() -> Control:
	return _game_over.get_node("Overlay") as Control


func _backdrop() -> ColorRect:
	return _game_over.get_node("Overlay/Backdrop") as ColorRect


func _content() -> Control:
	return _game_over.get_node("Overlay/Center/Content") as Control


func _title() -> Label:
	return _game_over.get_node("Overlay/Center/Content/Title") as Label


func _retry() -> Button:
	return _game_over.get_node("Overlay/Center/Content/Retry") as Button


func _main_menu() -> Button:
	return _game_over.get_node("Overlay/Center/Content/MainMenu") as Button


func _option_text_width(button: Button) -> float:
	var font := button.get_theme_font(&"font")
	var font_size := button.get_theme_font_size(&"font_size")
	return font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _option_gap() -> float:
	return _main_menu().global_position.y - (_retry().global_position.y + _retry().size.y)


func _option_area() -> float:
	return _retry().size.x * _retry().size.y + _main_menu().size.x * _main_menu().size.y


func _click_at(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	root.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	release.global_position = point
	root.push_input(release)


func _wait_feedback() -> void:
	await _secs(_game_over.feedback_time + 0.1)


func _lethal_hit() -> void:
	_player._health = 1
	_player._invuln_left = 0.0
	_player.take_damage(1, Vector2(-100.0, 0.0))


func _wait_for_game_over() -> bool:
	return await _wait_until(func() -> bool: return _game_over.is_active(), 180)


func _wait_for_input() -> bool:
	return await _wait_until(func() -> bool: return _game_over.is_accepting_input(), 180)


# -- Cases -----------------------------------------------------------------------

func case_nonlethal_hit_does_not_show() -> void:
	await _build_rig()
	_player.take_damage(1, Vector2(-100.0, 0.0))
	await _secs(DEATH_BEAT)
	check(not _game_over.is_active(), "one lost heart does not open GAME OVER")
	check(not _overlay().visible, "the overlay stays hidden")
	check(_player.get_health() == _player.max_health - 1, "the existing health system applied one point")
	check(not paused and _player.get_health() > 0, "the run is still live")


func case_last_heart_starts_once() -> void:
	await _build_rig()
	_player._health = 1
	_player._invuln_left = 0.4
	check(not _player.take_damage(1, Vector2(-100.0, 0.0)), "active i-frames still refuse a hit")
	check(not _game_over.is_active(), "i-frames do not open GAME OVER")
	_player._invuln_left = 0.0
	_player.take_damage(1, Vector2(-100.0, 0.0))
	check(not _game_over.is_active(), "the overlay waits for the death beat")
	await _wait_for_game_over()
	check(_game_over.is_active(), "the last heart opens GAME OVER after the death beat")
	check(paused, "the tree is paused")
	check(_overlay().visible, "the overlay is visible")
	check(_player.get_health() == 0 and _player._state == Player.State.DEAD, "Luz is dead")
	check(_died_count == 1, "died fired once")
	check(_shown_count == 1, "the screen was requested once")


func case_screen_stays_and_blocks_reentry() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()
	await _secs(EXTRA_WAIT)
	check(_game_over.is_active(), "the screen remains after the death animation")
	check(_overlay().visible, "the overlay remains visible")
	check(_shown_count == 1, "no second screen appears")
	check(not _player.take_damage(1, Vector2(-100.0, 0.0)), "a dead player takes no extra damage")
	_player._begin_death()
	check(_died_count == 1, "calling the death method again does nothing")
	check(_shown_count == 1, "the death method cannot spawn another screen")
	check(_respawn_count == 0 and _player.get_health() == 0, "no automatic respawn happened")
	check(paused, "the world stays paused")
	check(not _player.can_process(), "Luz stops processing while GAME OVER owns the tree")
	var frozen_at := _player.global_position
	_player.velocity = Vector2(120.0, 0.0)
	await _secs(0.4)
	check(_player.global_position.distance_to(frozen_at) < 0.01, "Luz cannot move while GAME OVER is visible")
	check(not _player.take_hazard_damage(1, Vector2(-100.0, 0.0)), "hazards cannot hurt the dead player")


func case_interface_contract() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	check(_game_over.is_active() and _game_over.is_accepting_input(), "the screen is active and accepting input")
	check(_title().text == "GAME OVER", "the title is exactly GAME OVER")
	var labels := 0
	for child: Node in _content().get_children():
		if child is Label:
			labels += 1
	check(labels == 1, "there is no subtitle (only the title label)")
	check(_retry().text == "REINTENTAR", "REINTENTAR is present")
	check(_main_menu().text == "MENÚ PRINCIPAL", "MENÚ PRINCIPAL is present")

	var viewport_size := root.get_visible_rect().size
	check(_overlay().size.distance_to(viewport_size) < 0.5, "the overlay fills the visible area")
	check(_backdrop().size.distance_to(viewport_size) < 0.5, "the black backdrop covers the whole screen")
	check(_game_over.layer > 100, "the overlay is above the HUD and touch controls")
	var pause_menu := root.get_node("PauseMenu")
	check(_game_over.layer > pause_menu.layer, "the overlay is above the pause menu")
	check(_game_over.process_mode == Node.PROCESS_MODE_ALWAYS and _game_over.can_process(), "the overlay processes while paused")
	check(not pause_menu.can_pause(), "the pause menu cannot open over GAME OVER")
	pause_menu.open()
	check(not pause_menu.is_open() and paused, "opening the pause menu is refused")


func case_options_use_main_menu_language() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	check(_retry().get_theme_font(&"font").resource_path == MAIN_MENU_FONT, "REINTENTAR uses the main menu font")
	check(_main_menu().get_theme_font(&"font").resource_path == MAIN_MENU_FONT, "MENÚ PRINCIPAL uses the main menu font")
	check(_title().get_theme_font(&"font").resource_path == MAIN_MENU_FONT, "the title uses the main menu font")
	check(_retry().get_theme_font_size(&"font_size") == _main_menu().get_theme_font_size(&"font_size"), "both options share one type size")
	check(_retry().get_theme_color(&"font_color") == OPTION_COLOR, "REINTENTAR is warm ivory")
	check(_main_menu().get_theme_color(&"font_color") == OPTION_COLOR, "MENÚ PRINCIPAL is warm ivory")
	check(_retry().get_theme_color(&"font_focus_color") == OPTION_SELECTED_COLOR, "REINTENTAR brightens when selected")
	check(_main_menu().get_theme_color(&"font_focus_color") == OPTION_SELECTED_COLOR, "MENÚ PRINCIPAL brightens when selected")
	check(_retry().alignment == HORIZONTAL_ALIGNMENT_CENTER, "REINTENTAR is centered")
	check(_main_menu().alignment == HORIZONTAL_ALIGNMENT_CENTER, "MENÚ PRINCIPAL is centered")
	for state: String in OPTION_STATES:
		check(_retry().get_theme_stylebox(state) is StyleBoxEmpty, "REINTENTAR has no visible %s box" % state)
	for state: String in OPTION_STATES:
		check(_main_menu().get_theme_stylebox(state) is StyleBoxEmpty, "MENÚ PRINCIPAL has no visible %s box" % state)


func case_layout_is_centered_and_touch_safe() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	var viewport_size := root.get_visible_rect().size
	check(_retry().custom_minimum_size.y >= 56.0, "REINTENTAR has a comfortable touch height")
	check(_main_menu().custom_minimum_size.y >= 56.0, "MENÚ PRINCIPAL has a comfortable touch height")
	check(is_equal_approx(_retry().custom_minimum_size.y, _main_menu().custom_minimum_size.y), "both options have the same touch height")
	check(_retry().custom_minimum_size.x >= 240.0, "REINTENTAR has a wide touch target")
	check(_retry().custom_minimum_size.x < viewport_size.x * 0.9, "the touch target leaves inert margins")
	check(_option_gap() >= 8.0, "the options are separated")
	check(absf(_retry().global_position.x + _retry().size.x * 0.5 - viewport_size.x * 0.5) < 1.0, "REINTENTAR is horizontally centered")
	check(absf(_main_menu().global_position.x + _main_menu().size.x * 0.5 - viewport_size.x * 0.5) < 1.0, "MENÚ PRINCIPAL is horizontally centered")
	check(_content().size.x <= viewport_size.x - 8.0, "the content fits the viewport width")
	check(_content().size.y <= viewport_size.y - 8.0, "the content fits the viewport height")
	check(_option_area() < viewport_size.x * viewport_size.y * 0.5, "the options do not cover the screen")
	check(_option_text_width(_retry()) + 16.0 <= _retry().size.x, "REINTENTAR text is not clipped")
	check(_option_text_width(_main_menu()) + 16.0 <= _main_menu().size.x, "MENÚ PRINCIPAL text is not clipped")
	var title_font := _title().get_theme_font(&"font")
	var title_width := title_font.get_string_size(_title().text, HORIZONTAL_ALIGNMENT_LEFT, -1, _title().get_theme_font_size(&"font_size")).x
	check(title_width <= _content().size.x, "the title is not clipped")
	check(_content().mouse_filter == Control.MOUSE_FILTER_IGNORE, "the content container is not clickable")
	check(_content().get_parent().mouse_filter == Control.MOUSE_FILTER_IGNORE, "the centering container is not clickable")
	check(_overlay().mouse_filter == Control.MOUSE_FILTER_STOP, "the overlay blocks the game behind it")

	var gap_point := Vector2(
		viewport_size.x * 0.5,
		(_retry().global_position.y + _retry().size.y + _main_menu().global_position.y) * 0.5
	)
	_click_at(gap_point)
	await _frames(2)
	check(_game_over.is_active() and not bool(_game_over.get("_resolving")), "a tap between the options does nothing")
	check(_respawn_count == 0 and _player.get_health() == 0, "the inert tap does not resolve GAME OVER")


func case_option_feedback_is_transient() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	check(_retry().has_focus(), "REINTENTAR starts selected")
	check(_retry().get_theme_constant(&"outline_size") == _game_over.selected_outline_size, "the selected option gains the gold outline")
	check(_retry().get_theme_color(&"font_outline_color") == OPTION_OUTLINE_COLOR, "the outline uses the main menu gold")
	await _wait_feedback()
	check(_retry().scale.x > 1.0, "the selected option scales up slightly")
	var touch_size := _retry().custom_minimum_size
	_main_menu().mouse_entered.emit()
	await _frames(1)
	check(_main_menu().has_focus(), "hovering an option selects it")
	check(not _retry().has_focus(), "the previous option is deselected")
	await _wait_feedback()
	check(_retry().get_theme_constant(&"outline_size") == 0, "the deselected option loses the outline")
	check(not _retry().has_theme_constant_override(&"outline_size"), "the outline override is removed, not just hidden")
	check(is_equal_approx(_retry().scale.x, 1.0), "the deselected option returns to its size")
	check(_main_menu().get_theme_constant(&"outline_size") == _game_over.selected_outline_size, "the new option gains the outline")
	check(_main_menu().scale.x > 1.0, "the new option scales up")
	check(_retry().custom_minimum_size == touch_size, "feedback does not change the touch target")
	check(_game_over.is_active() and paused and _game_over.is_accepting_input(), "the screen keeps owning the game during feedback")
	check(_respawn_count == 0, "feedback never resolves the screen")


func case_reveal_is_progressive() -> void:
	await _build_rig()
	_game_over.backdrop_fade_time = 0.45
	_game_over.content_delay = 0.08
	_game_over.content_fade_time = 0.35
	_lethal_hit()
	await _wait_for_game_over()
	check(_overlay().visible and _backdrop().color.a < 1.0, "the black veil starts transparent")
	check(_content().modulate.a < 1.0, "the content starts hidden")
	await _secs(0.2)
	check(_backdrop().color.a > 0.0 and _backdrop().color.a < 1.0, "the veil is fading in")
	await _secs(1.0)
	check(_backdrop().color.a == 1.0, "the veil finishes opaque")
	check(_content().modulate.a == 1.0, "the title and buttons finish visible")
	check(_game_over.is_accepting_input(), "the buttons accept input after the reveal")


func case_retry_restores_the_run() -> void:
	await _build_rig()
	var collectibles := root.get_node("Collectibles")
	collectibles.clear()
	var collectible_id: String = collectibles.get_all_definitions()[0].id
	check(collectibles.try_collect(collectible_id), "setup: a collectible is collected")
	_player.set_checkpoint(CHECKPOINT)
	_player.global_position = Vector2(200.0, 0.0)
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	check(root.get_node("TouchControls").get("_input_blocked") == true, "touch controls are blocked during GAME OVER")
	# Real pointer tap on the text row, not just the signal: the empty-looking
	# layout must still own a working touch target.
	_click_at(_retry().get_global_rect().get_center())
	await _frames(1)
	_retry().pressed.emit()
	await _frames(2)

	check(_respawn_count == 1, "repeated presses respawn exactly once")
	check(not _game_over.is_active(), "REINTENTAR closes the screen")
	check(not paused, "REINTENTAR resumes the tree")
	check(root.get_node("TouchControls").get("_input_blocked") == false, "touch controls work again")
	check(_player.get_health() == _player.max_health, "all hearts are restored")
	check(not _player._dead and _player._state == Player.State.IDLE, "death and movement states are reset")
	check(_player.global_position.distance_to(CHECKPOINT) < 2.0, "the run returns to its existing checkpoint")
	check(_player._invuln_left > 0.0, "the post-death i-frames are granted")
	check(collectibles.has_collected(collectible_id), "already collected items are preserved")

	await _secs(EXTRA_WAIT)
	check(not _game_over.is_active(), "GAME OVER does not reopen by itself")
	check(_player.get_health() == _player.max_health, "the player stays at full health")
	check(not paused and _respawn_count == 1, "no second respawn happens")

	var scene_before := current_scene
	_main_menu().pressed.emit()
	await _frames(2)
	check(current_scene == scene_before and not paused, "a stale MENÚ PRINCIPAL press after REINTENTAR is ignored")
	check(not bool(_game_over.get("_resolving")), "the overlay is not left resolving")
	collectibles.clear()


func case_retry_without_checkpoint_uses_zone_start() -> void:
	await _build_rig()
	var zone_start := Vector2(24.0, 0.0)
	_player.set_checkpoint(zone_start)
	_player.global_position = Vector2(220.0, 0.0)
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	_retry().pressed.emit()
	await _frames(2)

	check(_respawn_count == 1, "one respawn runs without a stored checkpoint")
	check(not _game_over.is_active() and not paused, "the screen closes and the tree resumes")
	check(_player.get_health() == _player.max_health, "all hearts are restored")
	check(not _player._dead and _player._state == Player.State.IDLE, "the player wakes up alive and idle")
	check(_player.global_position.distance_to(zone_start) < 2.0, "the run restarts from the zone start")
	check(_player._invuln_left > 0.0, "the post-death i-frames are granted")
	await _secs(EXTRA_WAIT)
	check(not _game_over.is_active() and not paused, "GAME OVER stays closed after a checkpoint-less retry")


func case_application_focus_keeps_screen() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	_game_over.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _secs(0.3)
	check(_game_over.is_active(), "GAME OVER stays active after the app loses focus")
	check(_overlay().visible, "the overlay stays visible after the app loses focus")
	check(paused, "the tree stays paused after the app loses focus")
	check(_shown_count == 1, "losing focus does not spawn another screen")

	_game_over.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _secs(0.3)
	check(_game_over.is_active(), "GAME OVER stays active when the app returns")
	check(paused, "the tree is still paused when the app returns")
	check(_game_over.is_accepting_input(), "the options still accept input after returning")
	check(_retry().has_focus(), "the selected option keeps focus across the app switch")


func case_aspect_ratios_keep_layout_inside() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	var original_size := root.size
	var sizes: Array[Vector2i] = [
		Vector2i(640, 360),
		Vector2i(390, 844),
		Vector2i(844, 390),
		Vector2i(1024, 768),
	]
	for size: Vector2i in sizes:
		root.size = size
		await _frames(2)
		var viewport_size := root.get_visible_rect().size
		var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
		var options_rect := _retry().get_global_rect().merge(_main_menu().get_global_rect())
		check(_overlay().size.distance_to(viewport_size) < 0.5, "the overlay fills %dx%d" % [size.x, size.y])
		check(viewport_rect.grow(-0.5).encloses(_content().get_global_rect()), "the content fits %dx%d" % [size.x, size.y])
		check(viewport_rect.grow(-0.5).encloses(options_rect), "both options fit %dx%d" % [size.x, size.y])
		check(
			absf(options_rect.position.x + options_rect.size.x * 0.5 - viewport_size.x * 0.5) < 1.0,
			"the options stay centered at %dx%d" % [size.x, size.y]
		)
		check(
			_option_text_width(_retry()) + 16.0 <= _retry().size.x
			and _option_text_width(_main_menu()) + 16.0 <= _main_menu().size.x,
			"the option texts are not clipped at %dx%d" % [size.x, size.y]
		)
	root.size = original_size
	await _frames(2)
	check(_overlay().size.distance_to(root.get_visible_rect().size) < 0.5, "the overlay restores its original size")


func case_main_menu_is_clean() -> void:
	await _build_rig()
	var touch := root.get_node("TouchControls")
	_game_over.main_menu_scene = MAIN_MENU_SCENE
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()
	check(_game_over.is_active() and paused, "setup: GAME OVER owns the pause")

	# Activate the second text row with a real pointer tap.
	_click_at(_main_menu().get_global_rect().get_center())
	await _frames(1)
	_main_menu().pressed.emit()
	await _frames(4)

	check(current_scene != null and current_scene.scene_file_path == MAIN_MENU_SCENE, "MENÚ PRINCIPAL loads the existing main menu")
	check(not paused, "the tree is not left paused")
	check(not _game_over.is_active() and not _overlay().visible, "the overlay is closed")
	check(touch.get("_input_blocked") == false, "touch input is not left blocked")
	check(not root.get_node("PauseMenu").is_open(), "the pause menu is not left open")
	check(_game_over.get("_player") == null, "the overlay forgets the old run")
	check(Player._transition_health == -1, "transition memory is cleared for a new run")
	check(not bool(_game_over.get("_resolving")), "the overlay is not left resolving")
	check(_game_over.get("_reveal_tween") == null, "no reveal tween is left pending")
	check(not bool(_game_over.get("_accepting_input")), "the closed overlay stops accepting input")
	var options: Array = _game_over.get("_options")
	var options_clean := true
	for option: Button in options:
		if option.scale != Vector2.ONE or option.has_meta(&"feedback_tween"):
			options_clean = false
	check(options_clean, "the option feedback is reset for the next run")
	var menu := current_scene
	var new_game: Button = null
	if menu != null:
		new_game = menu.get_node_or_null("%NewGame") as Button
	check(new_game != null and not new_game.disabled, "the main menu can start a new run")
	check(
		new_game != null and new_game.focus_mode == Control.FOCUS_ALL and not bool(menu.get("input_locked")),
		"the main menu accepts input again"
	)

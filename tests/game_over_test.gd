extends SceneTree
## GAME OVER overlay: it takes over after the last heart and the death beat,
## pauses the game exactly once, stays visible, blocks the pause menu and
## resolves through REINTENTAR (existing respawn) or MENÚ PRINCIPAL.
## Run: godot --headless --path . --script res://tests/game_over_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const WATCHDOG_SECONDS := 90.0
const SETTLE_FRAMES := 5
const DEATH_BEAT := 0.75
const EXTRA_WAIT := 1.2
const CHECKPOINT := Vector2(48.0, 0.0)
const FLOOR_RECT := Rect2(-300.0, 0.0, 600.0, 40.0)

const CHECKS := {
	"case_nonlethal_hit_does_not_show": 4,
	"case_last_heart_starts_once": 9,
	"case_screen_stays_and_blocks_reentry": 8,
	"case_interface_contract": 14,
	"case_reveal_is_progressive": 6,
	"case_retry_restores_the_run": 14,
	"case_main_menu_is_clean": 8,
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


func case_interface_contract() -> void:
	await _build_rig()
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()

	check(_title().text == "GAME OVER", "the title is exactly GAME OVER")
	var labels := 0
	for child: Node in _content().get_children():
		if child is Label:
			labels += 1
	check(labels == 1, "there is no subtitle (only the title label)")
	check(_retry().text == "REINTENTAR", "REINTENTAR is present")
	check(_main_menu().text == "MENÚ PRINCIPAL", "MENÚ PRINCIPAL is present")
	check(_retry().custom_minimum_size.y >= 48.0, "REINTENTAR has a comfortable touch height")
	check(_main_menu().custom_minimum_size.y >= 48.0, "MENÚ PRINCIPAL has a comfortable touch height")
	check(_retry().custom_minimum_size.y > _main_menu().custom_minimum_size.y, "REINTENTAR is visually dominant")

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
	_retry().pressed.emit()
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
	collectibles.clear()


func case_main_menu_is_clean() -> void:
	await _build_rig()
	var touch := root.get_node("TouchControls")
	_game_over.main_menu_scene = MAIN_MENU_SCENE
	_lethal_hit()
	await _wait_for_game_over()
	await _wait_for_input()
	check(_game_over.is_active() and paused, "setup: GAME OVER owns the pause")

	_main_menu().pressed.emit()
	_main_menu().pressed.emit()
	await _frames(4)

	check(current_scene != null and current_scene.scene_file_path == MAIN_MENU_SCENE, "MENÚ PRINCIPAL loads the existing main menu")
	check(not paused, "the tree is not left paused")
	check(not _game_over.is_active() and not _overlay().visible, "the overlay is closed")
	check(touch.get("_input_blocked") == false, "touch input is not left blocked")
	check(not root.get_node("PauseMenu").is_open(), "the pause menu is not left open")
	check(_game_over.get("_player") == null, "the overlay forgets the old run")
	check(Player._transition_health == -1, "transition memory is cleared for a new run")

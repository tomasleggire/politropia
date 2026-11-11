extends SceneTree
## Game completion: defeating Artemisa (the final boss) ends the run with the
## "CONTINUARÁ..." screen and a clean return to the main menu. The defeat is
## driven through Artemisa's real combat/arena flow (hits, death, defeat beat),
## never by showing the screen directly.
## Run: godot --headless --path . --script res://tests/game_completion_test.gd
## Exits 0 when every check passes, 1 otherwise.

const ShakeSpy := preload("res://tests/support/shake_spy_camera.gd")
const ARENA_SCENE := "res://scenes/enemies/bosses/boss_arena.tscn"
const ARTEMIS_ARENA_SCENE := "res://scenes/enemies/bosses/artemis_boss_arena.tscn"
const ARTEMIS_SCENE := "res://scenes/enemies/bosses/artemis.tscn"
const TEACHER_ARENA_SCENE := "res://scenes/enemies/bosses/teacher_boss_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ENEMY_SCENE := "res://scenes/enemies/snake_enemy.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MAIN_MENU_FONT := "res://assets/ui/Cinzel-Bold.ttf"
const WATCHDOG_SECONDS := 180.0
const SETTLE_FRAMES := 20
const FLOOR_RECT := Rect2(-500.0, 0.0, 1000.0, 100.0)
const LUZ_START := Vector2(-300.0, 0.0)
const IN_TRIGGER := Vector2(0.0, 0.0)
const ARENA_RECT := Rect2(-434.0, -340.0, 868.0, 400.0)
const HIT_FROM := Vector2(100.0, 0.0)
const ROOM := &"A"
const OPTION_COLOR := Color(0.91, 0.85, 0.66, 1.0)
const OPTION_SELECTED_COLOR := Color(1.0, 0.96, 0.84, 1.0)
const OPTION_OUTLINE_COLOR := Color(1.0, 0.72, 0.3, 0.3)
const OPTION_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
const ARENA_TIMINGS := {
	"door_time": 0.05, "title_time": 0.4, "engage_delay": 0.1,
	"camera_blend_time": 0.0, "defeat_beat": 0.2,
}

const CHECKS := {
	"case_artemis_defeat_triggers_completion_once": 11,
	"case_non_final_defeats_do_not_trigger_completion": 5,
	"case_completion_blocks_world_pause_and_game_over": 11,
	"case_interface_contract": 19,
	"case_aspect_ratios_keep_layout_inside": 17,
	"case_main_menu_return_is_clean_and_replayable": 15,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _arena: BossArena
var _boss: ArtemisBoss
var _completion: CanvasLayer
var _game_over: CanvasLayer
var _shown_count := 0
var _died_count := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _tick() -> void:
	_clock += root.get_process_delta_time()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	_cleanup_case()
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

func _registry() -> Node:
	return root.get_node("EnemyRegistry")


func _progress() -> Node:
	return root.get_node("BossProgress")


func _reset_autoloads() -> void:
	root.get_node("CheckpointService").clear()
	_registry().clear()
	_progress().clear()
	root.get_node("AbilityProgress").clear()
	_game_over = root.get_node("GameOver") as CanvasLayer
	_game_over.enabled = true
	_game_over.backdrop_fade_time = 0.01
	_game_over.content_delay = 0.0
	_game_over.content_fade_time = 0.01
	_completion = root.get_node("GameCompletion") as CanvasLayer
	_completion.enabled = true
	_completion.backdrop_fade_time = 0.01
	_completion.content_delay = 0.0
	_completion.content_fade_time = 0.01
	_shown_count = 0
	_died_count = 0
	if not _completion.shown.is_connected(_on_completion_shown):
		_completion.shown.connect(_on_completion_shown)


func _on_completion_shown() -> void:
	_shown_count += 1


func _build_base_rig() -> void:
	_cleanup_case()
	_reset_autoloads()
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(-482.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	LevelGeometry.add_solid(_rig, Rect2(434.0, -400.0, 48.0, 400.0), Color.DIM_GRAY)
	_registry().room_resolver = func(_point: Vector2) -> StringName: return ROOM
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = LUZ_START
	_rig.add_child(_player)
	_player.set_max_health(30)
	_player.heal(30)
	_player.set_checkpoint(LUZ_START)
	_place_luz(LUZ_START)
	_player.died.connect(func() -> void: _died_count += 1)
	current_scene = _rig


func _place_luz(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO


func _fast_arena(arena: BossArena) -> void:
	arena.arena_rect = ARENA_RECT
	for key: String in ARENA_TIMINGS:
		arena.set(key, ARENA_TIMINGS[key])


func _fast_boss(boss: ArtemisBoss) -> void:
	boss.stagger_hits = 0
	boss.final_freeze_time = 0.0
	boss.final_slowmo_time = 0.0
	boss.interrupt_enabled = false


func _build_artemis_rig() -> void:
	_build_base_rig()
	_arena = (load(ARTEMIS_ARENA_SCENE) as PackedScene).instantiate() as BossArena
	_fast_arena(_arena)
	_rig.add_child(_arena)
	_boss = _arena.get_boss() as ArtemisBoss
	_fast_boss(_boss)
	await _frames(SETTLE_FRAMES)


func _cleanup_case() -> void:
	BossFeel.cancel()
	Engine.time_scale = 1.0
	if _completion != null and is_instance_valid(_completion):
		if _completion.is_active():
			_completion.call(&"_close_overlay")
			_completion.call(&"_set_touch_blocked", false)
		_completion.set(&"_reveal_tween", null)
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
	_arena = null
	_boss = null
	_completion = root.get_node_or_null("GameCompletion") as CanvasLayer
	_game_over = root.get_node_or_null("GameOver") as CanvasLayer


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _wait_until(condition: Callable, limit_frames := 420) -> bool:
	for i: int in limit_frames:
		if condition.call():
			return true
		await process_frame
	return condition.call()


func _enter_trigger() -> void:
	_place_luz(IN_TRIGGER)
	await _secs(0.12)


func _enter_fight() -> void:
	await _enter_trigger()
	await _secs(0.35)


func _hit(n: int) -> void:
	for i: int in n:
		if is_instance_valid(_boss):
			_boss.receive_hit(1, HIT_FROM, &"attack_1")


func _overlay() -> Control:
	return _completion.get_node("Overlay") as Control


func _content() -> Control:
	return _completion.get_node("Overlay/Center/Content") as Control


func _title() -> Label:
	return _completion.get_node("Overlay/Center/Content/Title") as Label


func _main_menu() -> Button:
	return _completion.get_node("Overlay/Center/Content/MainMenu") as Button


func _text_width(control: Control, text: String) -> float:
	var font: Font = control.get_theme_font(&"font")
	var font_size: int = control.get_theme_font_size(&"font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


# -- Cases -----------------------------------------------------------------------

func case_artemis_defeat_triggers_completion_once() -> void:
	await _build_artemis_rig()
	await _enter_fight()
	check(not _completion.is_active(), "antes de derrotar a Artemisa la pantalla no aparece")
	check(_arena.get_state() == BossArena.FightState.ACTIVE, "la pelea con Artemisa está activa")

	# Derrota real: hits sobre Artemisa a través de su API de combate (el mismo
	# flujo que usan sus ataques recibidos) hasta matarla y dejar que la arena
	# complete su secuencia de derrota y el beat final.
	_hit(29)
	check(not _boss.is_dead() and not _completion.is_active(), "con vida restante la finalización no se activa")
	_hit(1)
	check(_boss.is_dead(), "Artemisa muere por el flujo real de daño")
	check(not _completion.is_active(), "la pantalla espera al beat de derrota de la arena")

	var appeared := await _wait_until(func() -> bool: return _completion.is_active(), 420)
	check(appeared, "la derrota confirmada de Artemisa activa la finalización")
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)
	check(_completion.is_accepting_input(), "la pantalla acepta input tras la transición")
	check(_shown_count == 1, "la pantalla aparece una sola vez")

	# Reintentos de mostrarla o señales tardías no la duplican.
	check(_completion.show_completion(), "una segunda activación se ignora sin error")
	await _frames(2)
	check(_shown_count == 1, "sigue apareciendo una sola vez")
	await _secs(0.6)
	check(_completion.is_active() and _shown_count == 1, "permanece visible sin repetirse")


func case_non_final_defeats_do_not_trigger_completion() -> void:
	# Un enemigo normal derrotado no activa la finalización.
	await _build_base_rig()
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.position = Vector2(200.0, 0.0)
	_rig.add_child(enemy)
	await _frames(SETTLE_FRAMES)
	check(enemy.receive_hit(99, HIT_FROM, &"attack_1"), "el enemigo normal recibe el golpe letal")
	await _secs(0.8)
	check(enemy.is_dead(), "el enemigo normal muere")
	check(not _completion.is_active(), "derrotar a un enemigo normal no activa la finalización")

	# Otro jefe (arena no-Artemisa) derrotado tampoco la activa.
	_cleanup_case()
	_build_base_rig()
	var teacher_arena := (load(TEACHER_ARENA_SCENE) as PackedScene).instantiate() as BossArena
	_fast_arena(teacher_arena)
	_rig.add_child(teacher_arena)
	await _frames(SETTLE_FRAMES)
	var other_boss := teacher_arena.get_boss()
	check(other_boss != null and not (other_boss is ArtemisBoss), "el otro jefe no es Artemisa")
	_place_luz(IN_TRIGGER)
	await _secs(0.5)
	if other_boss != null:
		other_boss.receive_hit(999, HIT_FROM, &"attack_1")
	await _secs(1.4)
	check(not _completion.is_active(), "derrotar a otro jefe no activa la finalización")


func case_completion_blocks_world_pause_and_game_over() -> void:
	await _build_artemis_rig()
	await _enter_fight()
	_hit(30)
	var appeared := await _wait_until(func() -> bool: return _completion.is_active(), 420)
	check(appeared, "la finalización aparece tras derrotar a Artemisa")
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)

	check(paused, "el árbol queda pausado")
	check(root.get_node("TouchControls").get("_input_blocked") == true, "los controles táctiles quedan bloqueados")
	check(not _player.can_process(), "el jugador deja de procesarse")
	var frozen_at := _player.global_position
	_player.velocity = Vector2(120.0, 0.0)
	await _secs(0.4)
	check(_player.global_position.distance_to(frozen_at) < 0.01, "el jugador no puede moverse")
	_player.take_damage(1, Vector2(-100.0, 0.0))
	_player.take_hazard_damage(1, Vector2(-100.0, 0.0))
	await _secs(0.4)
	check(not _game_over.is_active() and _completion.is_active() and paused, "ningún daño ni interacción activa GAME OVER ni cierra la finalización")

	var pause_menu := root.get_node("PauseMenu")
	check(not pause_menu.can_pause(), "el menú de pausa no puede abrirse")
	pause_menu.open()
	check(not pause_menu.is_open() and _completion.is_active(), "el menú de pausa no aparece encima")
	check(_completion.layer > pause_menu.layer, "la pantalla queda por encima del menú de pausa")

	# La muerte del jugador no debe abrir GAME OVER una vez terminada la partida.
	_game_over.enabled = true
	_player._health = 1
	_player._invuln_left = 0.0
	_player.take_damage(1, Vector2(-100.0, 0.0))
	_player._begin_death()
	await _secs(1.2)
	check(not _game_over.is_active(), "GAME OVER no aparece tras la finalización")
	check(_completion.is_active() and _shown_count == 1, "la pantalla de finalización permanece")


func case_interface_contract() -> void:
	await _build_artemis_rig()
	await _enter_fight()
	_hit(30)
	await _wait_until(func() -> bool: return _completion.is_active(), 420)
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)

	check(_title().text == "CONTINUARÁ...", "el mensaje principal es CONTINUARÁ...")
	check(_main_menu().text == "MENÚ PRINCIPAL", "la única opción es MENÚ PRINCIPAL")
	var labels := 0
	for child: Node in _content().get_children():
		if child is Label:
			labels += 1
	check(labels == 1, "no hay textos narrativos adicionales")
	var buttons := 0
	for child: Node in _content().get_children():
		if child is Button:
			buttons += 1
	check(buttons == 1, "no hay otras opciones")

	check(_main_menu().get_theme_font(&"font").resource_path == MAIN_MENU_FONT, "la opción usa la tipografía del menú")
	check(_title().get_theme_font(&"font").resource_path == MAIN_MENU_FONT, "el mensaje usa la tipografía del menú")
	check(_main_menu().get_theme_color(&"font_color") == OPTION_COLOR, "la opción usa el color del menú")
	check(_main_menu().get_theme_color(&"font_focus_color") == OPTION_SELECTED_COLOR, "la opción se ilumina al seleccionarse")
	for state: String in OPTION_STATES:
		check(_main_menu().get_theme_stylebox(state) is StyleBoxEmpty, "la opción no tiene botón gráfico (%s)" % state)
	check(_main_menu().custom_minimum_size.y >= 56.0, "la opción tiene altura táctil cómoda")
	check(_main_menu().alignment == HORIZONTAL_ALIGNMENT_CENTER, "la opción está centrada")
	check(_main_menu().get_global_rect().has_point(_main_menu().get_global_rect().get_center()), "la opción es accesible")
	check(_text_width(_main_menu(), _main_menu().text) + 16.0 <= _main_menu().size.x, "el texto de la opción no se corta")
	check(_text_width(_title(), _title().text) <= _content().size.x, "el mensaje principal no se corta")


func case_aspect_ratios_keep_layout_inside() -> void:
	await _build_artemis_rig()
	await _enter_fight()
	_hit(30)
	await _wait_until(func() -> bool: return _completion.is_active(), 420)
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)

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
		check(_overlay().size.distance_to(viewport_size) < 0.5, "el overlay llena %dx%d" % [size.x, size.y])
		check(viewport_rect.grow(-0.5).encloses(_content().get_global_rect()), "el contenido cabe en %dx%d" % [size.x, size.y])
		check(viewport_rect.grow(-0.5).encloses(_main_menu().get_global_rect()), "la opción cabe en %dx%d" % [size.x, size.y])
		check(_text_width(_main_menu(), _main_menu().text) + 16.0 <= _main_menu().size.x, "la opción no se corta en %dx%d" % [size.x, size.y])
	root.size = original_size
	await _frames(2)
	check(_overlay().size.distance_to(root.get_visible_rect().size) < 0.5, "el overlay restaura su tamaño original")


func case_main_menu_return_is_clean_and_replayable() -> void:
	await _build_artemis_rig()
	_completion.main_menu_scene = MAIN_MENU_SCENE
	await _enter_fight()
	_hit(30)
	await _wait_until(func() -> bool: return _completion.is_active(), 420)
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)

	_click_at(_main_menu().get_global_rect().get_center())
	await _frames(1)
	_main_menu().pressed.emit()
	await _frames(4)

	check(current_scene != null and current_scene.scene_file_path == MAIN_MENU_SCENE, "MENÚ PRINCIPAL carga el menú principal")
	check(not paused, "el juego queda despausado")
	check(not _completion.is_active() and not _overlay().visible, "la pantalla de finalización se cierra")
	check(root.get_node("TouchControls").get("_input_blocked") == false, "los controles táctiles se restauran")
	check(not root.get_node("PauseMenu").is_open(), "el menú de pausa no queda abierto")
	check(Player._transition_health == -1, "el estado de transición queda limpio")
	check(not bool(_completion.get("_resolving")), "la pantalla no queda resolviendo")
	check(_completion.get("_reveal_tween") == null, "no queda ningún tween pendiente")

	# Una nueva partida puede comenzar desde el menú tras la finalización.
	var menu := current_scene
	var new_game: Button = null
	if menu != null:
		new_game = menu.get_node_or_null("%NewGame") as Button
	check(new_game != null and not new_game.disabled, "el menú permite iniciar una nueva partida")
	check(new_game != null and new_game.focus_mode == Control.FOCUS_ALL and not bool(menu.get("input_locked")), "el menú acepta input")

	# Repetir la partida: una nueva derrota de Artemisa vuelve a activar la finalización.
	_cleanup_case()
	_build_artemis_rig()
	await _enter_fight()
	_hit(30)
	var appeared_again := await _wait_until(func() -> bool: return _completion.is_active(), 420)
	check(appeared_again, "en una nueva partida la derrota de Artemisa vuelve a activar la finalización")
	await _wait_until(func() -> bool: return _completion.is_accepting_input(), 240)
	check(_boss.is_dead(), "la derrota real de Artemisa vuelve a producirse")
	check(_shown_count == 1, "la nueva activación ocurre una sola vez en la nueva partida")
	check(not _game_over.is_active(), "GAME OVER no interfiere en la nueva finalización")
	check(paused and _completion.is_accepting_input(), "la pantalla queda visible y operativa en la nueva partida")


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

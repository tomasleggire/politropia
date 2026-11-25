extends Control

const GAME_SCENE := "res://scenes/levels/library/zone_1.tscn"
const INTRO_SCENE := "res://scenes/ui/new_game_intro.tscn"
const GALLERY_SCENE := "res://scenes/ui/collectibles_gallery.tscn"
const AVATAR_CACHE_PATH := "user://profile_avatar.png"

@export_group("Opening")
@export var fade_in_time := 0.8
@export var ui_stagger := 0.12

@export_group("New game cinematic")
@export var ui_fade_out_time := 0.3
@export var walk_time := 1.6
@export var walk_distance := 230.0  # Art px.
@export var flash_delay := 0.5
@export var flash_time := 1.3
@export var finish_delay := 0.2

@export_group("Selected row")
@export var selected_outline_color := Color(1.0, 0.72, 0.3, 0.3)
@export var selected_outline_size := 3

## Replaces the final scene change (tests inject their own); empty uses the tree.
var scene_changer := Callable()
var input_locked := false

var _buttons: Array[Button] = []
var _avatar_http: HTTPRequest = null
var _last_avatar_url: String = ""

@onready var btn_new_game: Button = %NewGame
@onready var btn_continue: Button = %Continue
@onready var btn_collectables: Button = %Collectables
@onready var btn_achievements: Button = %Achievements
@onready var btn_account: Button = %BtnAccount
@onready var btn_switch_account: Button = %BtnSwitchAccount
@onready var account_avatar: TextureRect = %AccountAvatar
@onready var _stage: MainMenuStage = %Stage
@onready var _ui: Control = %Ui
@onready var _logo: Control = %Logo
@onready var _logo_glow: TextureRect = %LogoGlow
@onready var _selector: MenuSelector = %Selector
@onready var _fade_black: ColorRect = %FadeBlack
@onready var _gold_flash: ColorRect = %GoldFlash
@onready var _loading_label: Label = %LoadingLabel


func _ready() -> void:
	# Disable touch controls while in the main menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		false
	)

	var has_saved_data := _has_save_data()
	btn_continue.disabled = not has_saved_data
	_buttons = [btn_new_game, btn_continue, btn_collectables, btn_achievements]
	for button in _buttons:
		_setup_button(button)
	_rebuild_focus_chain()

	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_continue.pressed.connect(_on_continue_pressed)
	btn_collectables.pressed.connect(_on_collectables_pressed)
	btn_achievements.pressed.connect(_on_achievements_pressed)

	_setup_account_button()

	if has_saved_data:
		btn_continue.grab_focus()
	else:
		btn_new_game.grab_focus()

	_place_selector.call_deferred()
	_play_opening()

	MusicManager.play_menu_music()
	# Scene loading will be handled when the player chooses New Game or Continue.
	# ResourceLoader.load_threaded_request(GAME_SCENE)


func _exit_tree() -> void:
	# Restore touch controls when leaving the menu.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		true
	)


func _process(delta: float) -> void:
	var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0015)
	_logo_glow.modulate.a = 0.05 + 0.2 * breath


func _setup_button(button: Button) -> void:
	button.focus_entered.connect(_on_button_focused.bind(button))
	button.focus_exited.connect(_on_button_unfocused.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))


## Disabled rows are skipped by navigation; the enabled ones wrap top to bottom.
func _rebuild_focus_chain() -> void:
	var enabled: Array[Button] = []
	for button in _buttons:
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		if not button.disabled:
			enabled.append(button)
	for i in enabled.size():
		var above := enabled[(i - 1 + enabled.size()) % enabled.size()]
		var below := enabled[(i + 1) % enabled.size()]
		enabled[i].focus_neighbor_top = enabled[i].get_path_to(above)
		enabled[i].focus_neighbor_bottom = enabled[i].get_path_to(below)


func _place_selector() -> void:
	_selector.set_span(_buttons[0], _buttons[_buttons.size() - 1])
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button:
		_selector.select(focused as Button, false)


func _on_button_focused(button: Button) -> void:
	button.add_theme_constant_override(&"outline_size", selected_outline_size)
	button.add_theme_color_override(&"font_outline_color", selected_outline_color)
	_selector.select(button)


func _on_button_unfocused(button: Button) -> void:
	button.remove_theme_constant_override(&"outline_size")


func _on_button_hovered(button: Button) -> void:
	if not input_locked and not button.disabled:
		button.grab_focus()


func _play_opening() -> void:
	_fade_black.color.a = 1.0
	_loading_label.visible = false
	_loading_label.modulate.a = 0.0
	_logo.modulate.a = 0.0
	_selector.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_fade_black, "color:a", 0.0, fade_in_time)
	tween.tween_property(_logo, "modulate:a", 1.0, 0.5).set_delay(ui_stagger)
	tween.tween_property(_selector, "modulate:a", 1.0, 0.5).set_delay(ui_stagger * 2.0)
	for i in _buttons.size():
		_buttons[i].modulate.a = 0.0
		var delay := ui_stagger * (2.0 + 0.6 * i)
		tween.tween_property(_buttons[i], "modulate:a", 1.0, 0.4).set_delay(delay)


func _on_new_game_pressed() -> void:
	if input_locked:
		return
	input_locked = true
	for button in _buttons:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().gui_release_focus()
	_play_new_game_cinematic()


## Fades the UI out while Luz walks into the light and the screen goes gold.
func _play_new_game_cinematic() -> void:
	var luz := _stage.luz
	luz.play(&"walk")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ui, "modulate:a", 0.0, ui_fade_out_time)
	tween.tween_property(luz, "position:x", luz.position.x + walk_distance, walk_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(luz, "modulate", Color(1.4, 1.2, 0.9), walk_time)
	tween.tween_property(_gold_flash, "color:a", 1.0, flash_time) \
		.set_delay(flash_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_interval(finish_delay)
	tween.chain().tween_callback(_finish_new_game)


func _finish_new_game() -> void:
	if SaveManager != null:
		SaveManager.clear_save()
	_reset_new_game_progress()
	SaveService.begin_new_game(GAME_SCENE)
	if SaveManager != null:
		SaveManager.set_saved_scene_path(GAME_SCENE)
		SaveManager.save_game()
	MusicManager.stop_music()
	if scene_changer.is_valid():
		scene_changer.call(INTRO_SCENE)
	else:
		get_tree().change_scene_to_file(INTRO_SCENE)


func _on_continue_pressed() -> void:
	if input_locked or btn_continue.disabled:
		return
	input_locked = true
	get_viewport().gui_release_focus()
	_loading_label.visible = true
	_loading_label.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ui, "modulate:a", 0.0, 0.3)
	tween.tween_property(_fade_black, "color:a", 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_loading_label, "modulate:a", 1.0, 0.18).set_delay(0.38)
	tween.chain().tween_callback(_continue_from_save)


func _continue_from_save() -> void:
	# Render the label before the saved PackedScene is synchronously loaded.
	await get_tree().process_frame
	if SaveManager != null and SaveManager.has_save():
		SaveManager.load_game()

	# If CheckpointService has an active checkpoint loaded, ensure SaveService is synchronized
	if CheckpointService != null and CheckpointService.has_active_checkpoint() and SaveService != null:
		SaveService.sync_from_state(CheckpointService.get_active_scene_path())

	if SaveService != null and SaveService.continue_game():
		MusicManager.play_gameplay_music()
		return

	# Fallback: load scene from CheckpointService, SaveManager, or default GAME_SCENE
	var target_scene := ""
	if CheckpointService != null and CheckpointService.has_active_checkpoint():
		target_scene = CheckpointService.get_active_scene_path()
	if (target_scene.is_empty() or not ResourceLoader.exists(target_scene)) and SaveManager != null:
		target_scene = SaveManager.get_saved_scene_path()
	if target_scene.is_empty() or not ResourceLoader.exists(target_scene):
		target_scene = GAME_SCENE

	if not target_scene.is_empty() and ResourceLoader.exists(target_scene):
		var packed: PackedScene = SaveService.load_packed_scene(target_scene) if SaveService != null else ResourceLoader.load(target_scene) as PackedScene
		if packed != null:
			if CheckpointService != null and CheckpointService.has_active_checkpoint():
				CheckpointService.queue_pending_restore()
			MusicManager.play_gameplay_music()
			var error := get_tree().change_scene_to_packed(packed)
			if error == OK:
				return

	input_locked = false
	btn_continue.disabled = true
	_ui.modulate.a = 1.0
	_fade_black.color.a = 0.0
	_loading_label.visible = false
	_loading_label.modulate.a = 0.0
	_rebuild_focus_chain()
	btn_new_game.grab_focus()
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null:
		toast.show_toast("No se pudo cargar la partida guardada.")


func _reset_new_game_progress() -> void:
	var service_paths := [
		"/root/CheckpointService",
		"/root/EnemyRegistry",
		"/root/BossProgress",
		"/root/FragmentProgress",
		"/root/MapProgress",
		"/root/SecretProgress",
		"/root/AbilityProgress",
		"/root/Collectibles",
		"/root/BlindQuestProgress"
	]

	for service_path in service_paths:
		var service := get_node_or_null(service_path)

		if service != null and service.has_method("clear"):
			service.call("clear")

	TutorialSign.reset_seen()
	Player.clear_transition_state()


func _on_collectables_pressed() -> void:
	if input_locked:
		return
	get_tree().change_scene_to_file(GALLERY_SCENE)


func _on_achievements_pressed() -> void:
	if input_locked:
		return
	_show_coming_soon_toast()


func _show_coming_soon_toast() -> void:
	var toast := get_node_or_null("/root/PickupToast")

	if toast != null:
		toast.show_toast("Coming soon")


func _setup_account_button() -> void:
	if btn_account == null:
		return

	btn_account.pressed.connect(_on_account_pressed)
	if btn_switch_account != null and not btn_switch_account.pressed.is_connected(_on_switch_account_pressed):
		btn_switch_account.pressed.connect(_on_switch_account_pressed)
	if account_avatar != null and not account_avatar.gui_input.is_connected(_on_avatar_gui_input):
		account_avatar.gui_input.connect(_on_avatar_gui_input)

	if FirebaseService != null:
		FirebaseService.auth_state_changed.connect(func(_logged: bool) -> void:
			_update_account_ui()
			_refresh_continue_button_state()
		)
		FirebaseService.sync_started.connect(func() -> void:
			_update_account_ui("SINCRONIZANDO...")
		)
		FirebaseService.sync_completed.connect(func(_ok: bool) -> void:
			_update_account_ui()
			_refresh_continue_button_state()
		)
		FirebaseService.auth_error.connect(func(msg: String) -> void:
			var toast := get_node_or_null("/root/PickupToast")
			if toast != null:
				toast.show_toast(msg)
			_update_account_ui()
		)

	_update_account_ui()


func _on_avatar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_account_pressed()


func _has_save_data() -> bool:
	return (SaveManager != null and SaveManager.has_save()) or (SaveService != null and SaveService.has_save())


func _refresh_continue_button_state() -> void:
	btn_continue.disabled = not _has_save_data()
	_rebuild_focus_chain()


func _update_account_ui(override_text: String = "") -> void:
	if btn_account == null:
		return

	if not override_text.is_empty():
		btn_account.text = override_text
		if account_avatar != null and FirebaseService != null and FirebaseService.is_logged_in:
			account_avatar.visible = true
		if btn_switch_account != null:
			btn_switch_account.visible = false
		return

	if FirebaseService != null and FirebaseService.is_logged_in:
		if account_avatar != null:
			account_avatar.visible = true
			_update_avatar_display()
		if btn_switch_account != null:
			btn_switch_account.visible = true

		var display: String = ""
		var full_name: String = FirebaseService.user_name.strip_edges()
		if not full_name.is_empty():
			var parts := full_name.split(" ", false)
			if not parts.is_empty():
				display = parts[0]
		elif not FirebaseService.user_email.is_empty():
			var local_part := FirebaseService.user_email.split("@")[0].strip_edges()
			var parts := local_part.split(".", false)
			display = parts[0] if not parts.is_empty() else local_part

		if display.is_empty():
			display = "USUARIO"
		btn_account.text = display.to_upper()
	else:
		if account_avatar != null:
			account_avatar.visible = false
			account_avatar.texture = null
		_last_avatar_url = ""
		if btn_switch_account != null:
			btn_switch_account.visible = false
		btn_account.text = "CONECTAR GOOGLE"


func _update_avatar_display() -> void:
	if account_avatar == null:
		return

	if account_avatar.texture == null:
		if FileAccess.file_exists(AVATAR_CACHE_PATH):
			var cached_img := Image.load_from_file(AVATAR_CACHE_PATH)
			if cached_img != null and not cached_img.is_empty():
				account_avatar.texture = ImageTexture.create_from_image(cached_img)
		if account_avatar.texture == null:
			account_avatar.texture = _create_default_avatar()

	var photo_url: String = FirebaseService.user_photo_url if FirebaseService != null else ""
	if not photo_url.is_empty() and photo_url != _last_avatar_url:
		_last_avatar_url = photo_url
		_fetch_avatar(photo_url)


func _fetch_avatar(url: String) -> void:
	if _avatar_http == null:
		_avatar_http = HTTPRequest.new()
		add_child(_avatar_http)
		_avatar_http.request_completed.connect(_on_avatar_request_completed)
	else:
		_avatar_http.cancel_request()

	_avatar_http.request(url)


func _on_avatar_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return

	var img := Image.new()
	var err := FAILED
	if body.size() >= 4 and body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		err = img.load_png_from_buffer(body)
	elif body.size() >= 3 and body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF:
		err = img.load_jpg_from_buffer(body)
	elif body.size() >= 4 and body[0] == 0x52 and body[1] == 0x49 and body[2] == 0x46 and body[3] == 0x46:
		err = img.load_webp_from_buffer(body)
	else:
		err = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)

	if err == OK:
		var circular := _make_circular_avatar(img, 48)
		circular.save_png(AVATAR_CACHE_PATH)
		if account_avatar != null and is_instance_valid(account_avatar):
			account_avatar.texture = ImageTexture.create_from_image(circular)


static func _make_circular_avatar(source: Image, target_size: int = 48) -> Image:
	var img := Image.create(target_size, target_size, false, Image.FORMAT_RGBA8)
	var sw := source.get_width()
	var sh := source.get_height()
	var side := mini(sw, sh)
	var src_x := (sw - side) / 2
	var src_y := (sh - side) / 2

	var cropped := source.get_region(Rect2i(src_x, src_y, side, side))
	cropped.resize(target_size, target_size, Image.INTERPOLATE_BILINEAR)

	var center := (float(target_size) - 1.0) * 0.5
	var radius := float(target_size) * 0.48
	var border_width := 1.5
	var border_col := Color(0.85, 0.75, 0.5, 0.9)

	for y in target_size:
		for x in target_size:
			var dist := Vector2(x, y).distance_to(Vector2(center, center))
			if dist <= radius:
				var c := cropped.get_pixel(x, y)
				if dist > radius - border_width:
					var blend := (dist - (radius - border_width)) / border_width
					img.set_pixel(x, y, c.lerp(border_col, blend * 0.75))
				else:
					img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


static func _create_default_avatar(target_size: int = 48) -> ImageTexture:
	var img := Image.create(target_size, target_size, false, Image.FORMAT_RGBA8)
	var center := (float(target_size) - 1.0) * 0.5
	var radius := float(target_size) * 0.48
	var head_center := Vector2(center, float(target_size) * 0.38)
	var head_radius := float(target_size) * 0.17
	var body_center := Vector2(center, float(target_size) * 0.82)
	var body_radius := float(target_size) * 0.32

	var col_bg := Color(0.13, 0.12, 0.17, 0.95)
	var col_border := Color(0.85, 0.75, 0.5, 0.9)
	var col_figure := Color(0.85, 0.8, 0.7, 0.9)

	for y in target_size:
		for x in target_size:
			var p := Vector2(x, y)
			var dist := p.distance_to(Vector2(center, center))
			if dist > radius:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif dist > radius - 1.5:
				img.set_pixel(x, y, col_border)
			else:
				var in_head := p.distance_to(head_center) <= head_radius
				var in_body := p.distance_to(body_center) <= body_radius and p.y >= head_center.y + head_radius * 0.6
				if in_head or in_body:
					img.set_pixel(x, y, col_figure)
				else:
					img.set_pixel(x, y, col_bg)
	return ImageTexture.create_from_image(img)


func _on_account_pressed() -> void:
	if input_locked:
		return

	if FirebaseService == null:
		return

	if FirebaseService.is_logged_in:
		# Already logged in: trigger manual sync
		FirebaseService.sync_with_cloud()
		var toast := get_node_or_null("/root/PickupToast")
		if toast != null:
			toast.show_toast("Sincronizando con la nube...")
	else:
		FirebaseService.prompt_google_sign_in()


func _on_switch_account_pressed() -> void:
	if input_locked:
		return
	if FirebaseService == null:
		return
	_update_account_ui("CAMBIANDO...")
	FirebaseService.switch_google_account()

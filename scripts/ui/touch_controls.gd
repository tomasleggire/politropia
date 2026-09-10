extends CanvasLayer

## Controles táctiles.
## - Mantener en cualquier parte de la pantalla = cargar salto
## - ◀ y ▶ abajo, separados (space-between)

@export var force_visible: bool = false

@onready var _jump_area: Control = $Root/JumpArea
@onready var _button_left: BaseButton = $Root/MoveBar/Left
@onready var _button_right: BaseButton = $Root/MoveBar/Right

var _jump_touch_index: int = -1
var _jump_mouse_held: bool = false


func _ready() -> void:
	layer = 100
	_apply_visibility()
	_connect_button(_button_left, &"move_left")
	_connect_button(_button_right, &"move_right")
	_jump_area.gui_input.connect(_on_jump_area_gui_input)


func _apply_visibility() -> void:
	var should_show := (
		force_visible
		or OS.has_feature("mobile")
		or DisplayServer.is_touchscreen_available()
	)
	visible = should_show


func _connect_button(button: BaseButton, action: StringName) -> void:
	button.button_down.connect(_on_action_down.bind(action))
	button.button_up.connect(_on_action_up.bind(action))


func _on_action_down(action: StringName) -> void:
	Input.action_press(action)


func _on_action_up(action: StringName) -> void:
	if Input.is_action_pressed(action):
		Input.action_release(action)


func _on_jump_area_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _jump_touch_index < 0:
			_jump_touch_index = touch.index
			Input.action_press(&"jump")
			_jump_area.accept_event()
		elif not touch.pressed and touch.index == _jump_touch_index:
			_jump_touch_index = -1
			if Input.is_action_pressed(&"jump"):
				Input.action_release(&"jump")
			_jump_area.accept_event()
		return

	# Útil para probar en editor con mouse.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and not _jump_mouse_held:
			_jump_mouse_held = true
			Input.action_press(&"jump")
			_jump_area.accept_event()
		elif not mouse.pressed and _jump_mouse_held:
			_jump_mouse_held = false
			if Input.is_action_pressed(&"jump"):
				Input.action_release(&"jump")
			_jump_area.accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _release_all() -> void:
	_jump_touch_index = -1
	_jump_mouse_held = false
	for action in [&"move_left", &"move_right", &"jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

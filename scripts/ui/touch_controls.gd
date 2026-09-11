extends CanvasLayer

## Controles:
## - Mitad izquierda de la pantalla = izquierda
## - Mitad derecha = derecha
## - Círculo SALTO (misma posición): tap = saltito, hold = cargar
## Mientras cargás, deslizá L/R sobre el salto para apuntar.

@export var force_visible: bool = false

const AIM_DEADZONE := 12.0

var _move_touch: int = -1
var _move_side: int = 0
var _jump_touch: int = -1
var _jump_origin: Vector2 = Vector2.ZERO

@onready var _root: Control = $Root
@onready var _jump: BaseButton = $Root/JumpButton


func _ready() -> void:
	layer = 100
	_apply_visibility()
	_jump.button_down.connect(_on_jump_down)
	_jump.button_up.connect(_on_jump_up)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_touch_pressed(touch)
		else:
			_on_touch_released(touch)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event as InputEventScreenDrag)


func _on_touch_pressed(touch: InputEventScreenTouch) -> void:
	# El botón de salto se maneja por su signal; solo trackeamos aim.
	if _jump.get_global_rect().has_point(touch.position):
		if _jump_touch < 0:
			_jump_touch = touch.index
			_jump_origin = touch.position
		return

	if _move_touch >= 0:
		return

	_move_touch = touch.index
	_move_side = _side_from_x(touch.position.x)
	_press_dir(_move_side)
	get_viewport().set_input_as_handled()


func _on_touch_released(touch: InputEventScreenTouch) -> void:
	if touch.index == _move_touch:
		_end_move()
		get_viewport().set_input_as_handled()
	if touch.index == _jump_touch:
		_jump_touch = -1
		_clear_aim_from_jump()


func _on_touch_drag(drag: InputEventScreenDrag) -> void:
	if drag.index == _move_touch:
		var side := _side_from_x(drag.position.x)
		if side != _move_side:
			_release_dirs()
			_move_side = side
			_press_dir(_move_side)
		get_viewport().set_input_as_handled()
		return

	if drag.index == _jump_touch and Input.is_action_pressed(&"jump"):
		var dx := drag.position.x - _jump_origin.x
		_release_dirs()
		if dx < -AIM_DEADZONE:
			Input.action_press(&"move_left")
		elif dx > AIM_DEADZONE:
			Input.action_press(&"move_right")
		get_viewport().set_input_as_handled()


func _side_from_x(x: float) -> int:
	return -1 if x < _root.size.x * 0.5 else 1


func _press_dir(side: int) -> void:
	if side < 0:
		Input.action_press(&"move_left")
	elif side > 0:
		Input.action_press(&"move_right")


func _end_move() -> void:
	_move_touch = -1
	_move_side = 0
	if _jump_touch < 0:
		_release_dirs()


func _clear_aim_from_jump() -> void:
	if _move_touch < 0:
		_release_dirs()


func _on_jump_down() -> void:
	Input.action_press(&"jump")


func _on_jump_up() -> void:
	if Input.is_action_pressed(&"jump"):
		Input.action_release(&"jump")
	_jump_touch = -1
	_clear_aim_from_jump()


func _release_dirs() -> void:
	if Input.is_action_pressed(&"move_left"):
		Input.action_release(&"move_left")
	if Input.is_action_pressed(&"move_right"):
		Input.action_release(&"move_right")


func _apply_visibility() -> void:
	visible = (
		force_visible
		or OS.has_feature("mobile")
		or DisplayServer.is_touchscreen_available()
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _release_all() -> void:
	_end_move()
	_jump_touch = -1
	for action in [&"move_left", &"move_right", &"jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

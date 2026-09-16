extends CanvasLayer

## Un único gesto puede combinar dirección horizontal y salto/descenso vertical.
## Arrastrar y sostener mueve; soltar frena conservando un poco de inercia.

@export var force_visible := false
@export var horizontal_deadzone := 22.0
@export var full_speed_distance := 105.0
@export var vertical_trigger_distance := 58.0

var _touch_id := -1
var _origin := Vector2.ZERO
var _vertical_armed := true
var _action_release_frames: Dictionary = {}

@onready var _origin_ring: Control = $Root/OriginRing
@onready var _knob: Control = $Root/Knob
@onready var _hint: Label = $Root/Hint


func _ready() -> void:
	layer = 100
	visible = force_visible or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_hide_gesture()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_id < 0:
			_begin_gesture(touch.index, touch.position)
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_id:
			_end_gesture()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_id:
			_update_gesture(drag.position)
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	for action: StringName in _action_release_frames.keys():
		var frames: int = int(_action_release_frames[action]) - 1
		if frames <= 0:
			Input.action_release(action)
			_action_release_frames.erase(action)
		else:
			_action_release_frames[action] = frames


func _begin_gesture(index: int, position: Vector2) -> void:
	_touch_id = index
	_origin = position
	_vertical_armed = true
	_origin_ring.position = position - _origin_ring.size * 0.5
	_knob.position = position - _knob.size * 0.5
	_origin_ring.visible = true
	_knob.visible = true
	_hint.text = "DESLIZÁ · ↑ SALTÁ · ↓ BAJÁ"


func _update_gesture(position: Vector2) -> void:
	var offset := position - _origin
	var horizontal := 0.0
	if absf(offset.x) > horizontal_deadzone:
		horizontal = signf(offset.x) * clampf(
			(absf(offset.x) - horizontal_deadzone) / (full_speed_distance - horizontal_deadzone),
			0.0,
			1.0
		)
	_set_horizontal(horizontal)

	if _vertical_armed and offset.y <= -vertical_trigger_distance:
		_pulse_action(&"jump")
		_vertical_armed = false
		_hint.text = "SALTO + ENVÍO"
	elif _vertical_armed and offset.y >= vertical_trigger_distance:
		_pulse_action(&"drop_down")
		_vertical_armed = false
		_hint.text = "BAJAR PLATAFORMA"
	elif not _vertical_armed and absf(offset.y) < vertical_trigger_distance * 0.35:
		_vertical_armed = true

	var visual_offset := offset.limit_length(full_speed_distance)
	_knob.position = _origin + visual_offset - _knob.size * 0.5


func _end_gesture() -> void:
	_touch_id = -1
	_release_horizontal()
	_hide_gesture()


func _set_horizontal(value: float) -> void:
	_release_horizontal()
	if value < 0.0:
		Input.action_press(&"move_left", absf(value))
	elif value > 0.0:
		Input.action_press(&"move_right", value)


func _release_horizontal() -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")


func _pulse_action(action: StringName) -> void:
	Input.action_press(action)
	_action_release_frames[action] = 2


func _hide_gesture() -> void:
	_origin_ring.visible = false
	_knob.visible = false
	_hint.text = "TOCÁ Y DESLIZÁ"


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_gesture()
		for action: StringName in _action_release_frames.keys():
			Input.action_release(action)
		_action_release_frames.clear()

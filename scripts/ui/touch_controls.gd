extends CanvasLayer

## Blasphemous-style mobile layout: a floating left-thumb joystick that drives
## the same move_* input actions as the keyboard, plus three right-side
## buttons (jump, dash, attack). The attack fires the instant the finger
## touches down (neutral, or directional if the pad already holds up/down);
## a short swipe right after that can still upgrade the same attack to
## up/plunge instead of firing a second one. Jump and dash also call the
## player directly on touch-down (in addition to Input.action_press) so a
## very quick tap can never be missed by is_action_just_pressed's same-frame
## edge (see Player.request_jump/request_dash).

@export var force_visible := false

@export_group("Joystick")
@export var joystick_capture_fraction := 0.4
@export var joystick_radius := 80.0
@export var joystick_dead_zone := 0.25
@export var joystick_vertical_ratio := 0.55
@export var joystick_vertical_angle_deg := 60.0
@export var joystick_rest_margin := Vector2(150.0, 150.0)

@export_group("Attack gesture")
@export var attack_swipe_distance := 28.0
## After touch-down, a qualifying vertical swipe within this window upgrades
## the attack that already fired to up/plunge (the player only honors the
## upgrade while its own startup phase is still active, ~attack_startup_time).
@export var attack_upgrade_window := 0.10

var _pad_touch_id := -1
var _pad_center := Vector2.ZERO
var _knob_offset := Vector2.ZERO

var _jump_touch_id := -1
var _dash_touch_id := -1

var _attack_touch_id := -1
var _attack_start := Vector2.ZERO
var _attack_timer := 0.0
var _attack_upgraded := false

var _held_actions := {
	&"move_left": false,
	&"move_right": false,
	&"move_up": false,
	&"move_down": false,
}

@onready var _pad: Control = $Root/MovePad
@onready var _jump_button: Control = $Root/JumpButton
@onready var _dash_button: Control = $Root/DashButton
@onready var _attack_button: Control = $Root/AttackButton


func _ready() -> void:
	layer = 100
	visible = force_visible or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_position_pad_at_rest()


func _process(delta: float) -> void:
	if _attack_touch_id < 0 or _attack_upgraded:
		return
	_attack_timer += delta


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _try_begin_pad(touch.index, touch.position):
			get_viewport().set_input_as_handled()
		elif _jump_touch_id < 0 and _try_begin_button(_jump_button, touch.index, touch.position):
			_begin_jump(touch.index)
			get_viewport().set_input_as_handled()
		elif _dash_touch_id < 0 and _try_begin_button(_dash_button, touch.index, touch.position):
			_begin_dash(touch.index)
			get_viewport().set_input_as_handled()
		elif _attack_touch_id < 0 and _try_begin_button(_attack_button, touch.index, touch.position):
			_begin_attack(touch.index, touch.position)
			get_viewport().set_input_as_handled()
	else:
		if touch.index == _pad_touch_id:
			_end_pad()
			get_viewport().set_input_as_handled()
		elif touch.index == _jump_touch_id:
			_end_jump()
			get_viewport().set_input_as_handled()
		elif touch.index == _dash_touch_id:
			_end_dash()
			get_viewport().set_input_as_handled()
		elif touch.index == _attack_touch_id:
			_end_attack()
			get_viewport().set_input_as_handled()


func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index == _pad_touch_id:
		_update_pad(drag.position)
		get_viewport().set_input_as_handled()
	elif drag.index == _attack_touch_id:
		_update_attack_drag(drag.position)
		get_viewport().set_input_as_handled()


func _try_begin_button(button: Control, _index: int, position: Vector2) -> bool:
	var center := button.get_global_rect().get_center()
	return position.distance_to(center) <= button.size.x * 0.5


## -- Joystick -----------------------------------------------------------

func _try_begin_pad(index: int, position: Vector2) -> bool:
	if _pad_touch_id >= 0:
		return false
	var capture_width := get_viewport().get_visible_rect().size.x * joystick_capture_fraction
	if position.x > capture_width:
		return false
	_pad_touch_id = index
	_pad_center = position
	_pad.position = position - _pad.size * 0.5
	_update_pad(position)
	return true


func _update_pad(position: Vector2) -> void:
	var raw_offset := position - _pad_center
	_knob_offset = raw_offset.limit_length(joystick_radius)
	var normalized_length := _knob_offset.length() / joystick_radius

	var horizontal_active := absf(_knob_offset.x) / joystick_radius >= joystick_dead_zone
	_set_action_held(&"move_left", horizontal_active and _knob_offset.x < 0.0)
	_set_action_held(&"move_right", horizontal_active and _knob_offset.x > 0.0)

	var vertical_active := false
	var vertical_down := false
	if normalized_length >= joystick_vertical_ratio:
		var angle_from_vertical := 90.0
		if not is_zero_approx(_knob_offset.y):
			angle_from_vertical = rad_to_deg(atan2(absf(_knob_offset.x), absf(_knob_offset.y)))
		vertical_active = angle_from_vertical <= joystick_vertical_angle_deg
		vertical_down = _knob_offset.y > 0.0
	_set_action_held(&"move_down", vertical_active and vertical_down)
	_set_action_held(&"move_up", vertical_active and not vertical_down)

	if is_instance_valid(_pad):
		_pad.call(&"set_pad_state", _knob_offset, true)


func _end_pad() -> void:
	_pad_touch_id = -1
	_set_action_held(&"move_left", false)
	_set_action_held(&"move_right", false)
	_set_action_held(&"move_up", false)
	_set_action_held(&"move_down", false)
	_knob_offset = Vector2.ZERO
	_position_pad_at_rest()
	if is_instance_valid(_pad):
		_pad.call(&"set_pad_state", Vector2.ZERO, false)


func _position_pad_at_rest() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_pad_center = Vector2(joystick_rest_margin.x, viewport_size.y - joystick_rest_margin.y)
	if is_instance_valid(_pad):
		_pad.position = _pad_center - _pad.size * 0.5


func _set_action_held(action: StringName, held: bool) -> void:
	if _held_actions.get(action, false) == held:
		return
	_held_actions[action] = held
	if held:
		Input.action_press(action)
	else:
		Input.action_release(action)


## -- Jump / dash buttons --------------------------------------------------

func _begin_jump(index: int) -> void:
	_jump_touch_id = index
	Input.action_press(&"jump")
	get_tree().call_group(&"player", &"request_jump")
	_jump_button.call(&"set_button_state", true)


func _end_jump() -> void:
	_jump_touch_id = -1
	Input.action_release(&"jump")
	if is_instance_valid(_jump_button):
		_jump_button.call(&"set_button_state", false)


func _begin_dash(index: int) -> void:
	_dash_touch_id = index
	Input.action_press(&"dash")
	get_tree().call_group(&"player", &"request_dash")
	_dash_button.call(&"set_button_state", true)


func _end_dash() -> void:
	_dash_touch_id = -1
	Input.action_release(&"dash")
	if is_instance_valid(_dash_button):
		_dash_button.call(&"set_button_state", false)


## -- Attack button (fire immediately, swipe to upgrade) ---------------------

func _begin_attack(index: int, position: Vector2) -> void:
	_attack_touch_id = index
	_attack_start = position
	_attack_timer = 0.0
	_attack_upgraded = false
	_attack_button.call(&"set_button_state", true)
	get_tree().call_group(&"player", &"request_attack", _pad_vertical_direction())


## The attack already fires as neutral above; if the pad is held up/down at
## touch-down, fire that directional attack immediately instead (zero added
## latency either way).
func _pad_vertical_direction() -> int:
	if _held_actions.get(&"move_up", false):
		return -1
	if _held_actions.get(&"move_down", false):
		return 1
	return 0


func _update_attack_drag(position: Vector2) -> void:
	if _attack_upgraded or _attack_timer > attack_upgrade_window:
		return
	var delta := position - _attack_start
	if absf(delta.y) < attack_swipe_distance or absf(delta.y) <= absf(delta.x):
		return
	_attack_upgraded = true
	get_tree().call_group(&"player", &"request_attack_upgrade", -1 if delta.y < 0.0 else 1)


func _end_attack() -> void:
	_attack_touch_id = -1
	if is_instance_valid(_attack_button):
		_attack_button.call(&"set_button_state", false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_node_ready():
			_end_pad()
			if _jump_touch_id >= 0:
				_end_jump()
			if _dash_touch_id >= 0:
				_end_dash()
			if _attack_touch_id >= 0:
				_end_attack()

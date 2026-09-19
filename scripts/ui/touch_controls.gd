extends CanvasLayer

## Left-thumb analog pad for walking and dropping through platforms.
## Any other touch can swipe to jump: up, up-left or up-right.

@export var force_visible := false
@export var pad_radius := 62.0
@export var capture_radius := 94.0
@export var horizontal_deadzone := 0.16
@export var drop_threshold := 38.0
@export var jump_min_up := 36.0
@export var jump_min_length := 42.0
@export var jump_vertical_angle := 0.38
@export var jump_max_angle := 1.22

var _pad_touch_id := -1
var _pad_center := Vector2.ZERO
var _knob_offset := Vector2.ZERO
var _drop_armed := false

var _jump_touch_id := -1
var _jump_start := Vector2.ZERO
var _jump_pos := Vector2.ZERO

@onready var _pad: Control = $Root/MovePad
@onready var _hint: Label = $Root/Hint


func _ready() -> void:
	layer = 100
	visible = force_visible or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_reset_pad()
	_reset_jump()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _try_begin_pad(touch.index, touch.position):
				get_viewport().set_input_as_handled()
			elif _try_begin_jump(touch.index, touch.position):
				get_viewport().set_input_as_handled()
		else:
			if touch.index == _pad_touch_id:
				_update_pad(touch.position)
				_commit_pad()
				get_viewport().set_input_as_handled()
			elif touch.index == _jump_touch_id:
				_jump_pos = touch.position
				_commit_jump()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _pad_touch_id:
			_update_pad(drag.position)
			get_viewport().set_input_as_handled()
		elif drag.index == _jump_touch_id:
			_jump_pos = drag.position
			_update_hint(_knob_offset.x / pad_radius)
			get_viewport().set_input_as_handled()


func _try_begin_pad(index: int, position: Vector2) -> bool:
	if _pad_touch_id >= 0:
		return false
	_pad_center = _pad.get_global_rect().get_center()
	if position.distance_to(_pad_center) > capture_radius:
		return false
	_pad_touch_id = index
	_update_pad(position)
	return true


func _try_begin_jump(index: int, position: Vector2) -> bool:
	if _jump_touch_id >= 0:
		return false
	_jump_touch_id = index
	_jump_start = position
	_jump_pos = position
	return true


func _update_pad(position: Vector2) -> void:
	var raw_offset := position - _pad_center
	_knob_offset = raw_offset.limit_length(pad_radius)
	_drop_armed = raw_offset.y >= drop_threshold

	var move_axis := clampf(_knob_offset.x / pad_radius, -1.0, 1.0)
	if absf(move_axis) < horizontal_deadzone:
		move_axis = 0.0
	get_tree().call_group(&"player", &"set_touch_move", move_axis)
	_pad.call(&"set_pad_state", _knob_offset, true, _drop_armed)
	_update_hint(move_axis)


func _commit_pad() -> void:
	if _drop_armed:
		get_tree().call_group(&"player", &"touch_drop")
	_reset_pad()


func _commit_jump() -> void:
	var swipe := _jump_pos - _jump_start
	_reset_jump()
	if swipe.length() < jump_min_length or swipe.y > -jump_min_up:
		_update_hint(_knob_offset.x / pad_radius if _pad_touch_id >= 0 else 0.0)
		return
	var angle_from_up := atan2(swipe.x, -swipe.y)
	if absf(angle_from_up) > jump_max_angle:
		_update_hint(_knob_offset.x / pad_radius if _pad_touch_id >= 0 else 0.0)
		return
	var direction := 0
	if angle_from_up <= -jump_vertical_angle:
		direction = -1
	elif angle_from_up >= jump_vertical_angle:
		direction = 1
	get_tree().call_group(&"player", &"touch_jump", direction)
	_update_hint(_knob_offset.x / pad_radius if _pad_touch_id >= 0 else 0.0)


func _jump_preview_direction() -> int:
	if _jump_touch_id < 0:
		return 0
	var swipe := _jump_pos - _jump_start
	if swipe.length() < jump_min_length or swipe.y > -jump_min_up:
		return 0
	var angle_from_up := atan2(swipe.x, -swipe.y)
	if absf(angle_from_up) > jump_max_angle:
		return 0
	if angle_from_up <= -jump_vertical_angle:
		return -1
	if angle_from_up >= jump_vertical_angle:
		return 1
	return 0


func _update_hint(move_axis: float) -> void:
	var jump_dir := _jump_preview_direction()
	if _jump_touch_id >= 0 and (_jump_pos - _jump_start).length() >= 18.0:
		if jump_dir < 0:
			_hint.text = "SALTO  ↖"
		elif jump_dir > 0:
			_hint.text = "SALTO  ↗"
		elif (_jump_pos - _jump_start).y <= -jump_min_up:
			_hint.text = "SALTO  ↑"
		else:
			_hint.text = "DESLIZÁ ARRIBA PARA SALTAR"
	elif _drop_armed:
		_hint.text = "SOLTÁ PARA ATRAVESAR  ↓"
	elif absf(move_axis) > 0.78:
		_hint.text = "CORRER  %s" % ("←" if move_axis < 0.0 else "→")
	elif not is_zero_approx(move_axis):
		_hint.text = "CAMINAR  %s" % ("←" if move_axis < 0.0 else "→")
	else:
		_hint.text = "PAD: CAMINAR · SWIPE: SALTAR"


func _reset_pad() -> void:
	_pad_touch_id = -1
	_knob_offset = Vector2.ZERO
	_drop_armed = false
	get_tree().call_group(&"player", &"set_touch_move", 0.0)
	if is_instance_valid(_pad):
		_pad.call(&"set_pad_state", Vector2.ZERO, false, false)
	if is_instance_valid(_hint) and _jump_touch_id < 0:
		_hint.text = "PAD: CAMINAR · SWIPE: SALTAR"


func _reset_jump() -> void:
	_jump_touch_id = -1
	_jump_start = Vector2.ZERO
	_jump_pos = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_node_ready():
			_reset_pad()
			_reset_jump()

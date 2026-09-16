extends CanvasLayer

## Flick controls: al soltar, el vector del swipe se convierte en un impulso.

@export var force_visible := false
@export var minimum_swipe := 16.0
@export var full_power_distance := 240.0

var _touch_id := -1
var _origin := Vector2.ZERO
var _current := Vector2.ZERO
var _started_msec := 0

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
			_commit_gesture(touch.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_id:
			_update_gesture(drag.position)
			get_viewport().set_input_as_handled()


func _begin_gesture(index: int, position: Vector2) -> void:
	_touch_id = index
	_origin = position
	_current = position
	_started_msec = Time.get_ticks_msec()
	_hint.text = "ARRASTRÁ · SOLTÁ PARA IMPULSAR"


func _update_gesture(position: Vector2) -> void:
	_current = position
	var swipe := position - _origin
	var power := roundi(clampf(swipe.length() / full_power_distance, 0.0, 1.0) * 100.0)
	_hint.text = "IMPULSO %d%%  %s" % [power, _arrow_for(swipe)]


func _commit_gesture(release_position: Vector2) -> void:
	_current = release_position
	var swipe := _current - _origin
	var duration := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	if swipe.length() >= minimum_swipe:
		get_tree().call_group(&"player", &"apply_swipe", swipe, duration)
	_touch_id = -1
	_hide_gesture()


func _arrow_for(vector: Vector2) -> String:
	if vector.length() < minimum_swipe:
		return "·"
	var angle := vector.angle()
	if angle < -2.75 or angle >= 2.75:
		return "←"
	if angle < -1.96:
		return "↖"
	if angle < -1.18:
		return "↑"
	if angle < -0.39:
		return "↗"
	if angle < 0.39:
		return "→"
	if angle < 1.18:
		return "↘"
	if angle < 1.96:
		return "↓"
	return "↙"


func _hide_gesture() -> void:
	_hint.text = "DESLIZÁ Y SOLTÁ · CADA GESTO SUMA IMPULSO"


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_touch_id = -1
		if is_instance_valid(_hint):
			_hide_gesture()

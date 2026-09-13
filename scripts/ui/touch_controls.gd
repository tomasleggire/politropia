extends CanvasLayer

## Stick fijo abajo a la izquierda. Solo se mueve tocando ese pad.

@export var force_visible: bool = false

const MAX_RADIUS := 70.0
const DEADZONE := 0.08
const PAD_SIZE := Vector2(204.0, 204.0)
const KNOB_REST := Vector2(60.0, 60.0)
const REST_ALPHA := 0.55
const ACTIVE_ALPHA := 1.0
const HOME_LEFT := 28.0
const HOME_BOTTOM := 92.0
const ATTACK_HAPTIC_MS := 32
const ATTACK_HAPTIC_AMP := 0.5

var movement_vector := Vector2.ZERO

var _touch_id := -1
var _attack_id := -1
var _attack_unlocked := false
var _attack_just_pressed := false
var _attack_tween: Tween

@onready var _root: Control = $Root
@onready var _base: Control = $Root/PadBase
@onready var _knob: Control = $Root/PadBase/PadKnob
@onready var _attack: Control = $Root/AttackButton


func _ready() -> void:
	layer = 100
	visible = force_visible or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_attack.visible = false
	_attack.modulate.a = 0.0
	_root.resized.connect(_on_root_resized)
	_knob.position = KNOB_REST
	call_deferred("_on_root_resized")


func get_movement_vector() -> Vector2:
	return movement_vector


func is_attack_held() -> bool:
	return _attack_unlocked and _attack_id >= 0


func poll_attack_just_pressed() -> bool:
	if not _attack_just_pressed:
		return false
	_attack_just_pressed = false
	return true


func unlock_attack() -> void:
	if _attack_unlocked:
		return
	_attack_unlocked = true
	_attack.visible = true
	_attack.pivot_offset = _attack.size * 0.5
	_attack.modulate.a = 0.0
	_attack.scale = Vector2(0.72, 0.72)
	if is_instance_valid(_attack_tween):
		_attack_tween.kill()
	_attack_tween = create_tween()
	_attack_tween.set_parallel(true)
	_attack_tween.tween_property(_attack, "modulate:a", 1.0, 0.2)
	_attack_tween.tween_property(_attack, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_root_resized() -> void:
	_attack.pivot_offset = _attack.size * 0.5
	_place_pad_home()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_press(touch.index, touch.position)
		else:
			_on_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_id:
			_update_stick(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			if _touch_id >= 0:
				return
			_on_press(0, mouse.position)
		else:
			_on_release(0)
	elif event is InputEventMouseMotion and _touch_id == 0:
		_update_stick((event as InputEventMouseMotion).position)


func _on_press(index: int, screen_position: Vector2) -> void:
	if _is_in_attack(screen_position):
		_begin_attack(index)
		get_viewport().set_input_as_handled()
		return
	if not _base.get_global_rect().grow(12.0).has_point(screen_position):
		return
	if _touch_id >= 0 and index != _touch_id:
		return
	_touch_id = index
	_base.modulate.a = ACTIVE_ALPHA
	_update_stick(screen_position)
	get_viewport().set_input_as_handled()


func _on_release(index: int) -> void:
	_end_attack(index)
	if index != _touch_id:
		return
	_end_move()
	get_viewport().set_input_as_handled()


func _is_in_attack(screen_position: Vector2) -> bool:
	return (
		_attack_unlocked
		and is_instance_valid(_attack)
		and _attack.visible
		and _attack.get_global_rect().has_point(screen_position)
	)


func _end_move() -> void:
	_touch_id = -1
	movement_vector = Vector2.ZERO
	if is_instance_valid(_knob):
		_knob.position = KNOB_REST
	_base.modulate.a = REST_ALPHA


func _begin_attack(index: int) -> void:
	if _attack_id >= 0:
		return
	_attack_id = index
	_attack_just_pressed = true
	Input.vibrate_handheld(ATTACK_HAPTIC_MS, ATTACK_HAPTIC_AMP)
	_pulse_attack()


func _end_attack(index: int) -> void:
	if index != _attack_id:
		return
	_attack_id = -1
	_release_attack_visual()


func _pulse_attack() -> void:
	if not is_instance_valid(_attack):
		return
	if is_instance_valid(_attack_tween):
		_attack_tween.kill()
	_attack.scale = Vector2.ONE
	_attack_tween = create_tween()
	_attack_tween.set_trans(Tween.TRANS_QUAD)
	_attack_tween.set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(_attack, "scale", Vector2(0.93, 0.94), 0.04)
	_attack_tween.tween_property(_attack, "scale", Vector2.ONE, 0.1)


func _release_attack_visual() -> void:
	if not is_instance_valid(_attack):
		return
	if is_instance_valid(_attack_tween):
		_attack_tween.kill()
	_attack.scale = Vector2.ONE


func _place_pad_home() -> void:
	_base.anchor_left = 0.0
	_base.anchor_top = 0.0
	_base.anchor_right = 0.0
	_base.anchor_bottom = 0.0
	_base.size = PAD_SIZE
	_base.position = Vector2(HOME_LEFT, _root.size.y - HOME_BOTTOM - PAD_SIZE.y)
	if _touch_id < 0:
		_base.modulate.a = REST_ALPHA


func _update_stick(screen_position: Vector2) -> void:
	var center := _base.global_position + PAD_SIZE * 0.5
	var offset := screen_position - center
	var normalized := offset / MAX_RADIUS
	if normalized.length() > 1.0:
		normalized = normalized.normalized()
	var strength := normalized.length()
	if strength <= DEADZONE:
		movement_vector = Vector2.ZERO
	else:
		var remapped := (strength - DEADZONE) / (1.0 - DEADZONE)
		movement_vector = normalized.normalized() * remapped
	_knob.position = KNOB_REST + movement_vector * MAX_RADIUS


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_attack_id = -1
		_attack_just_pressed = false
		if _touch_id >= 0:
			_end_move()
		_release_attack_visual()

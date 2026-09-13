class_name RoomDoor
extends StaticBody2D

## Barrera entre habitaciones: bloquea el paso y se materializa/desmaterializa
## con un sello arcano bien visible para que quede claro si está cerrada o no.

var _closed := false
var _collision: CollisionShape2D
var _visual: Node2D
var _panel: Polygon2D
var _glow: Polygon2D
var _pulse: Tween


func setup(gap_size: Vector2) -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 6

	var shape := RectangleShape2D.new()
	shape.size = gap_size
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	_collision.disabled = true
	add_child(_collision)

	_visual = Node2D.new()
	_visual.scale = Vector2(0.05, 0.05)
	add_child(_visual)

	_glow = _quad(gap_size * 1.5)
	_glow.color = Color(0.98, 0.8, 0.4, 0.0)
	_visual.add_child(_glow)

	_panel = _quad(gap_size)
	_panel.color = Color(0.99, 0.88, 0.55, 0.0)
	_visual.add_child(_panel)


func close_door(animated := true) -> void:
	if _closed:
		return
	_closed = true
	_collision.disabled = false
	_animate(true, animated)


func open_door(animated := true) -> void:
	if not _closed:
		return
	_closed = false
	_collision.disabled = true
	_animate(false, animated)


func _animate(closing: bool, animated: bool) -> void:
	if is_instance_valid(_pulse):
		_pulse.kill()
	var target_scale := Vector2.ONE if closing else Vector2(0.05, 0.05)
	var panel_alpha := 0.92 if closing else 0.0
	var glow_alpha := 0.4 if closing else 0.0
	if not animated:
		_visual.scale = target_scale
		_panel.color.a = panel_alpha
		_glow.color.a = glow_alpha
	else:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK if closing else Tween.TRANS_QUINT)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(_visual, "scale", target_scale, 0.32)
		tween.parallel().tween_property(_panel, "color:a", panel_alpha, 0.22)
		tween.parallel().tween_property(_glow, "color:a", glow_alpha, 0.3)
	if closing:
		_pulse = create_tween().set_loops()
		_pulse.set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_glow, "color:a", 0.24, 0.85)
		_pulse.tween_property(_glow, "color:a", 0.46, 0.85)


func _quad(size: Vector2) -> Polygon2D:
	var half := size * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	return poly

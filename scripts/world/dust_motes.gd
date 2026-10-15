class_name DustMotes
extends Node2D

## Floating dust / pollen. Drop `scenes/world/dust_motes.tscn` in a zone: with
## `fit_to_zone` it spreads over the camera area by itself. Only the motes on
## screen are drawn and nothing is allocated per frame, so it is cheap on
## device. Raise `motes_per_screen` for denser air, lower it for sparing use.

@export_group("Area")
## Fills the zone's camera area (CameraRegion limits) automatically.
@export var fit_to_zone := true
## Used when `fit_to_zone` is off or the zone has no CameraRegion.
@export var room_origin := Vector2.ZERO
@export var room_size := Vector2(720.0, 1280.0)

@export_group("Motes")
## Motes for every 640x360 of area; the total is capped by `max_motes`.
@export_range(1, 60, 1) var motes_per_screen := 10
@export_range(1, 120, 1) var max_motes := 48
## Fixed total, used instead of the density above when above 0.
@export var mote_count := 0
@export var mote_color := Color(1.0, 0.85, 0.6, 0.3)
@export_range(0.5, 4.0, 0.1) var mote_size := 1.0
@export_range(0.0, 3.0, 0.05) var rise_speed := 1.0
@export_range(0.0, 30.0, 0.5) var sway := 6.0

const SCREEN := Vector2(640.0, 360.0)
const MARGIN := 24.0

var _pos := PackedVector2Array()
var _speed := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedFloat32Array()
var _area := Rect2()


func _ready() -> void:
	_area = Rect2(room_origin, room_size)
	if fit_to_zone and not Engine.is_editor_hint():
		_area = ZoneBounds.find_rect(get_parent(), _area)
	var total := mote_count
	if total <= 0:
		total = clampi(roundi(float(motes_per_screen) * _area.get_area() / (SCREEN.x * SCREEN.y)), 4, max_motes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4177
	_pos.resize(total)
	_speed.resize(total)
	_phase.resize(total)
	_size.resize(total)
	for i in total:
		_pos[i] = _area.position + Vector2(rng.randf() * _area.size.x, rng.randf() * _area.size.y)
		_speed[i] = rng.randf_range(8.0, 20.0)
		_phase[i] = rng.randf_range(0.0, TAU)
		_size[i] = rng.randf_range(1.0, 2.6)


func _process(delta: float) -> void:
	var left := _area.position.x
	var right := _area.end.x
	for i in _pos.size():
		_phase[i] += delta
		var p := _pos[i]
		p.y -= _speed[i] * delta * 0.35 * rise_speed
		p.x += sin(_phase[i] * 0.8) * sway * delta
		if p.y < _area.position.y:
			p.y = _area.end.y
		p.x = left if p.x > right else (right if p.x < left else p.x)
		_pos[i] = p
	queue_redraw()


func _draw() -> void:
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	view = view.grow(MARGIN)
	for i in _pos.size():
		var p := _pos[i]
		if not view.has_point(to_global(p)):
			continue
		var s := _size[i] * mote_size
		var a := mote_color.a * (0.55 + 0.45 * sin(_phase[i]))
		draw_circle(p, s * 2.2, Color(mote_color.r, mote_color.g, mote_color.b, a * 0.18))
		draw_circle(p, s, Color(mote_color.r, mote_color.g, mote_color.b, a))

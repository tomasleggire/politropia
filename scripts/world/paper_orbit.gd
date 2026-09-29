class_name PaperOrbit
extends Node

## The desk papers lift off at the celebration peak, circle Luz slowly and
## glide back to their exact resting spots when she leaves. Sheets on higher
## orbits always stay behind her, so they never cross her face.

const FRONT_Z := 4
const LIFT_TIME := 1.1
const RETURN_TIME := 0.9

@export_group("Orbit")
@export var center := Vector2(0.0, -47.0)
@export var centers_y := PackedFloat32Array([-40.0, -44.0, -58.0, -66.0])
@export var radii := PackedVector2Array([Vector2(38.0, 7.0), Vector2(54.0, 6.0), Vector2(46.0, 5.0), Vector2(62.0, 6.0)])
## Starting angle per sheet: on the same side of Luz as its resting spot.
@export var start_angles := PackedFloat32Array([2.98, 2.26, 0.88, 0.16])
@export var speeds := PackedFloat32Array([0.5, 0.38, 0.55, 0.33])
@export_range(0.1, 1.0, 0.05) var resting_speed_scale := 0.45
@export_range(0.0, 0.6, 0.01) var wobble := 0.35

var lift := 0.0
var resting_level := 0.0

var _sheets: Array[Node2D] = []
var _rest: Array[Transform2D] = []
var _angles := PackedFloat32Array()
var _tweens: Dictionary = {}
var _settled := true
var _returning := false


func setup(sheets: Array[Node2D]) -> void:
	_sheets = sheets
	_rest.clear()
	for sheet in sheets:
		_rest.append(sheet.transform)
	_angles = start_angles.duplicate()


func get_rest_position(index: int) -> Vector2:
	return _rest[index].origin


func lift_off() -> void:
	_settled = false
	_returning = false
	AltarFxKit.ease_property(self, _tweens, self, &"lift", 1.0, LIFT_TIME, Tween.EASE_OUT)


func settle_into_rest() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"resting_level", 1.0, 1.5)


func glide_home() -> void:
	_returning = true
	AltarFxKit.ease_property(self, _tweens, self, &"resting_level", 0.0, RETURN_TIME)
	AltarFxKit.ease_property(self, _tweens, self, &"lift", 0.0, RETURN_TIME, Tween.EASE_IN_OUT)


func step(delta: float, time: float) -> void:
	if _settled:
		return
	if _returning and lift <= 0.0:
		_snap_home()
		return
	var speed := lerpf(1.0, resting_speed_scale, resting_level)
	for i in _sheets.size():
		_angles[i] = fposmod(_angles[i] + speeds[i] * speed * delta, TAU)
		_place(i, time)


func _place(i: int, time: float) -> void:
	var sheet := _sheets[i]
	var rest := _rest[i]
	var orbit := LuzOrbit.point(Vector2(center.x, centers_y[i]), radii[i], _angles[i])
	orbit.y += sin(time * 1.6 + float(i) * 1.9) * 2.5
	sheet.position = rest.origin.lerp(orbit, lift)
	sheet.rotation = rest.get_rotation() + lift * sin(time * 1.1 + float(i) * 1.7) * wobble
	sheet.z_index = FRONT_Z if not _returning and lift > 0.5 and LuzOrbit.is_front(orbit, _angles[i]) else 0


func _snap_home() -> void:
	for i in _sheets.size():
		_sheets[i].transform = _rest[i]
		_sheets[i].z_index = 0
	_settled = true


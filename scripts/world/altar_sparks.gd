class_name AltarSparks
extends Node2D

## Release-beat sparks: a burst rises from the altar's roots, on both sides,
## and winds up into the orbit the fireflies take over. Positions are in desk
## space. Sparks passing in front of Luz stay below her face line (LuzOrbit).

const MAX_SPARKS := 24
const ROOT_HALF_SPAN := Vector2(14.0, 40.0)

@export_group("Flight")
@export var origin_y := -4.0
@export var orbit_center := Vector2(0.0, -41.0)
@export var orbit_radius_x := Vector2(30.0, 50.0)
@export var orbit_radius_y := Vector2(8.0, 16.0)
@export var life_range := Vector2(1.2, 1.8)
@export var spin_range := Vector2(2.4, 4.2)
@export_range(0.0, 0.8, 0.02) var launch_stagger := 0.4
## Extra height the spiral climbs above the orbit before settling into it.
@export var arc_height := Vector2(26.0, 52.0)

@export_group("Look")
@export var color := Color(1.0, 0.84, 0.48)
@export_range(0.05, 0.4, 0.01) var spark_scale := 0.21

var _rng := RandomNumberGenerator.new()
var _sprites: Array[Sprite2D] = []
var _age := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _life := PackedFloat32Array()
var _start_x := PackedFloat32Array()
var _start_angle := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _end_rx := PackedFloat32Array()
var _end_ry := PackedFloat32Array()
var _end_y := PackedFloat32Array()
var _arc := PackedFloat32Array()
var _active := 0


func _ready() -> void:
	for i: int in MAX_SPARKS:
		var sprite := AltarFxKit.make_sprite(self, AltarFxKit.glow_texture(), true)
		sprite.scale = Vector2.ONE * spark_scale
		sprite.visible = false
		_sprites.append(sprite)
	for array: PackedFloat32Array in [_age, _delay, _life, _start_x, _start_angle, _spin, _end_rx, _end_ry, _end_y, _arc]:
		array.resize(MAX_SPARKS)
	setup(0)


func setup(seed_value: int) -> void:
	_rng.seed = seed_value + 3


## Launches `count` (capped at MAX_SPARKS) sparks, alternating left and right root.
func burst(count: int) -> void:
	_active = mini(count, MAX_SPARKS)
	for i: int in MAX_SPARKS:
		_sprites[i].visible = false
	for i: int in _active:
		var side := -1.0 if i % 2 == 0 else 1.0
		_start_x[i] = side * _rng.randf_range(ROOT_HALF_SPAN.x, ROOT_HALF_SPAN.y)
		_start_angle[i] = 0.0 if side > 0.0 else PI
		_spin[i] = side * _rng.randf_range(spin_range.x, spin_range.y)
		_end_rx[i] = _rng.randf_range(orbit_radius_x.x, orbit_radius_x.y)
		_end_ry[i] = _rng.randf_range(orbit_radius_y.x, orbit_radius_y.y)
		_end_y[i] = orbit_center.y + _rng.randf_range(-6.0, 6.0)
		_arc[i] = _rng.randf_range(arc_height.x, arc_height.y)
		_life[i] = _rng.randf_range(life_range.x, life_range.y)
		_delay[i] = float(i) / maxf(float(_active), 1.0) * launch_stagger
		_age[i] = 0.0
		_place(i)


## Stops and hides every spark; also the abort path.
func clear() -> void:
	_active = 0
	for sprite: Sprite2D in _sprites:
		sprite.visible = false


func get_live_count() -> int:
	var live := 0
	for sprite: Sprite2D in _sprites:
		if sprite.visible:
			live += 1
	return live


func step(delta: float) -> void:
	for i: int in _active:
		if _age[i] < _life[i] + _delay[i]:
			_age[i] += delta
			_place(i)


func _place(i: int) -> void:
	var sprite := _sprites[i]
	var t := clampf((_age[i] - _delay[i]) / _life[i], 0.0, 1.0)
	if _age[i] < _delay[i] or t >= 1.0:
		sprite.visible = false
		return
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var angle := _start_angle[i] + _spin[i] * (_age[i] - _delay[i])
	var rx := lerpf(absf(_start_x[i]), _end_rx[i], eased)
	var ry := lerpf(2.0, _end_ry[i], eased)
	var y := lerpf(origin_y, _end_y[i], eased) - sin(PI * t) * _arc[i]
	var pos := Vector2(orbit_center.x + cos(angle) * rx, y + sin(angle) * ry)
	sprite.position = pos
	sprite.z_index = 2 if LuzOrbit.is_front(pos, angle) else 0
	var envelope := minf(t * 8.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, t))
	sprite.modulate = Color(color, envelope)
	sprite.scale = Vector2.ONE * spark_scale * (1.4 - 0.5 * t)
	sprite.visible = true

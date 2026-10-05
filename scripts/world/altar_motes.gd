class_name AltarMotes
extends Node2D

## A few round warm specks drifting slowly through the light above the desk.
## Faint while it waits, a little brighter while Luz rests. A negative `rise`
## makes them fall instead, which is how the light shaft's dust moves.

@export_group("Cone")
@export_range(1, 40) var count := 9
@export var base := Vector2(0.0, -30.0)
@export_range(4.0, 60.0, 1.0) var half_width := 30.0
@export_range(-300.0, 300.0, 1.0) var rise := 78.0
## Sideways shift per unit of vertical travel (leans the drift with a slanted beam).
@export_range(-0.5, 0.5, 0.01) var lean := 0.0

@export_group("Look")
@export var color := Color(1.0, 0.86, 0.55)
@export_range(0.0, 1.0, 0.01) var idle_alpha := 0.22
@export_range(0.0, 1.0, 0.01) var resting_alpha := 0.42
@export_range(0.01, 0.1, 0.005) var mote_scale := 0.05

var resting_level := 0.0

var _rng := RandomNumberGenerator.new()
var _sprites: Array[Sprite2D] = []
var _life := PackedFloat32Array()
var _rate := PackedFloat32Array()
var _x0 := PackedFloat32Array()
var _sway := PackedFloat32Array()
var _sway_phase := PackedFloat32Array()


func _ready() -> void:
	for i: int in count:
		var sprite := AltarFxKit.make_sprite(self, AltarFxKit.glow_texture(), true)
		sprite.scale = Vector2.ONE * mote_scale
		_sprites.append(sprite)
	setup(0)


func setup(seed_value: int) -> void:
	_rng.seed = seed_value + 1
	_life.resize(count)
	_rate.resize(count)
	_x0.resize(count)
	_sway.resize(count)
	_sway_phase.resize(count)
	for i: int in count:
		_life[i] = float(i) / count
		_respawn(i)


func step(delta: float) -> void:
	var alpha := lerpf(idle_alpha, resting_alpha, resting_level)
	for i: int in count:
		_life[i] += _rate[i] * delta
		if _life[i] >= 1.0:
			_life[i] -= 1.0
			_respawn(i)
		var life := _life[i]
		var sway := sin(life * TAU * 1.5 + _sway_phase[i]) * _sway[i]
		_sprites[i].position = base + Vector2(_x0[i] + sway + lean * -rise * life, -rise * life)
		_sprites[i].modulate = Color(color, alpha * sin(PI * life))


func _respawn(i: int) -> void:
	_rate[i] = 1.0 / _rng.randf_range(14.0, 24.0)
	_x0[i] = _rng.randf_range(-half_width, half_width)
	_sway[i] = _rng.randf_range(2.0, 6.0)
	_sway_phase[i] = _rng.randf_range(0.0, TAU)

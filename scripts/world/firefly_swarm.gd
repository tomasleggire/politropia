class_name FireflySwarm
extends Node2D

## Warm fireflies around the altar: they drift as a beacon while the desk
## waits, gather in orbit around the seated Luz on activation and disperse when
## she leaves. The three extra fireflies only join a first celebration.

const BASE_COUNT := 7
const EXTRA_COUNT := 3
const WANDER_MIN_Y := -120.0
const WANDER_MAX_Y := -8.0
const NOISE_GAIN := 1.5
const DISPERSE_TIME := 1.2

@export_group("Wander")
@export var wander_center := Vector2(0.0, -64.0)
@export var wander_radii := Vector2(58.0, 44.0)
@export_range(0.05, 1.0, 0.01) var wander_speed := 0.28
## Extra outward reach of the one firefly acting as a beacon.
@export_range(0.0, 1.5, 0.05) var beacon_reach := 0.6
@export_range(2.0, 30.0, 0.5) var beacon_period := 9.0

@export_group("Orbit")
@export var orbit_center := Vector2(0.0, -41.0)
@export var orbit_radius_x := Vector2(32.0, 46.0)
@export var orbit_radius_y := Vector2(9.0, 15.0)
@export var orbit_speed := Vector2(0.55, 1.2)
@export_range(0.1, 1.0, 0.05) var resting_speed_scale := 0.45
@export_range(0.2, 3.0, 0.05) var gather_time := 1.1

@export_group("Look")
@export var core_color := Color("ffd27a")
@export var glow_color := Color(1.0, 0.72, 0.3, 0.6)
@export_range(0.1, 1.0, 0.05) var glow_scale := 0.32
@export_range(0.0, 0.5, 0.01) var breath_swell := 0.18

## Overall brightness 0..1, higher when this desk is the active checkpoint.
var brightness := 0.6
var gather_level := 0.0
var resting_level := 0.0
var extras_level := 0.0

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _cores: Array[Sprite2D] = []
var _glows: Array[Sprite2D] = []
var _tweens: Dictionary = {}
var _beacon_offset := 0
var _noise_y := PackedFloat32Array()
var _blink_phase := PackedFloat32Array()
var _blink_speed := PackedFloat32Array()
var _gather_delay := PackedFloat32Array()
var _orbit_cy := PackedFloat32Array()
var _orbit_rx := PackedFloat32Array()
var _orbit_ry := PackedFloat32Array()
var _orbit_omega := PackedFloat32Array()
var _angle := PackedFloat32Array()


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	for i in BASE_COUNT + EXTRA_COUNT:
		_glows.append(AltarFxKit.make_sprite(self, AltarFxKit.glow_texture(), true))
		_cores.append(AltarFxKit.make_sprite(self, AltarFxKit.dot_texture(), false))
	setup(0)


## Rebuilds every per-firefly parameter from `seed_value`; same seed, same swarm.
func setup(seed_value: int) -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value & 0x7fffffff
	_beacon_offset = _rng.randi_range(0, BASE_COUNT - 1)
	var count := BASE_COUNT + EXTRA_COUNT
	_noise_y.resize(count)
	_blink_phase.resize(count)
	_blink_speed.resize(count)
	_gather_delay.resize(count)
	_orbit_cy.resize(count)
	_orbit_rx.resize(count)
	_orbit_ry.resize(count)
	_orbit_omega.resize(count)
	_angle.resize(count)
	for i in count:
		_noise_y[i] = _rng.randf_range(0.0, 200.0)
		_blink_phase[i] = _rng.randf_range(0.0, TAU)
		_blink_speed[i] = _rng.randf_range(1.1, 2.3)
		_gather_delay[i] = _rng.randf()
		_orbit_cy[i] = orbit_center.y + _rng.randf_range(-5.0, 5.0)
		_orbit_rx[i] = _rng.randf_range(orbit_radius_x.x, orbit_radius_x.y)
		_orbit_ry[i] = _rng.randf_range(orbit_radius_y.x, orbit_radius_y.y)
		var direction := 1.0 if _rng.randf() < 0.7 else -1.0
		_orbit_omega[i] = direction * _rng.randf_range(orbit_speed.x, orbit_speed.y)
		_angle[i] = _rng.randf_range(0.0, TAU)
	for i in _cores.size():
		_place(i, 0.0, 0.0)
	_apply_visibility()


func get_firefly_count() -> int:
	return BASE_COUNT + EXTRA_COUNT


func get_firefly_position(index: int) -> Vector2:
	return _glows[index].position


func get_visible_count() -> int:
	var visible_count := 0
	for glow in _glows:
		if glow.visible and glow.modulate.a > 0.02:
			visible_count += 1
	return visible_count


func gather(first: bool) -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"gather_level", 1.0, gather_time, Tween.EASE_IN_OUT)
	if first:
		AltarFxKit.ease_property(self, _tweens, self, &"extras_level", 1.0, gather_time)


func settle_into_rest() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"resting_level", 1.0, 1.2)


func disperse() -> void:
	AltarFxKit.ease_property(self, _tweens, self, &"gather_level", 0.0, DISPERSE_TIME)
	AltarFxKit.ease_property(self, _tweens, self, &"resting_level", 0.0, DISPERSE_TIME)
	AltarFxKit.ease_property(self, _tweens, self, &"extras_level", 0.0, DISPERSE_TIME)


func step(delta: float, time: float, breath: float) -> void:
	var speed := lerpf(1.0, resting_speed_scale, resting_level)
	for i in _cores.size():
		_angle[i] = fposmod(_angle[i] + _orbit_omega[i] * speed * delta, TAU)
		_place(i, time, breath)
	_apply_visibility()


func _place(i: int, time: float, breath: float) -> void:
	var wander := _wander_point(i, time)
	var gather_i := smoothstep(0.0, 1.0, clampf((gather_level - _gather_delay[i] * 0.4) / 0.6, 0.0, 1.0))
	var swell := 1.0 + (breath - 0.5) * breath_swell * resting_level
	var orbit := LuzOrbit.point(
		Vector2(orbit_center.x, _orbit_cy[i]), Vector2(_orbit_rx[i], _orbit_ry[i]) * swell, _angle[i]
	)
	var pos := wander.lerp(orbit, gather_i)
	_glows[i].position = pos
	# The 2x2 core snaps to whole pixels so the motion stays pixel-art.
	_cores[i].position = pos.round()
	var z := 2 if gather_i > 0.5 and LuzOrbit.is_front(pos, _angle[i]) else 0
	_glows[i].z_index = z
	_cores[i].z_index = z
	var blink := 0.35 + 0.65 * (0.5 + 0.5 * sin(time * _blink_speed[i] + _blink_phase[i]))
	blink *= 1.0 + (breath - 0.5) * 0.3 * resting_level
	var presence := 1.0 if i < BASE_COUNT else extras_level
	var level := blink * brightness * presence
	_cores[i].modulate = Color(core_color, clampf(level, 0.0, 1.0))
	_glows[i].modulate = Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * clampf(level, 0.0, 1.0))
	_glows[i].scale = Vector2.ONE * glow_scale * (0.8 + 0.3 * blink)


func _wander_point(i: int, time: float) -> Vector2:
	var t := time * wander_speed
	var reach := 1.0 + beacon_reach * _beacon_weight(i, time)
	var drift := Vector2(
		_noise.get_noise_2d(t, _noise_y[i]) * wander_radii.x * NOISE_GAIN * reach,
		_noise.get_noise_2d(t, _noise_y[i] + 57.0) * wander_radii.y * NOISE_GAIN,
	)
	var point := wander_center + drift
	point.y = clampf(point.y, WANDER_MIN_Y, WANDER_MAX_Y)
	return point


## One base firefly at a time drifts farther out; the rest of the time is zero.
func _beacon_weight(i: int, time: float) -> float:
	if i >= BASE_COUNT:
		return 0.0
	var slot := int(floorf(time / beacon_period))
	if (slot * 3 + _beacon_offset) % BASE_COUNT != i:
		return 0.0
	var envelope := sin(PI * (time / beacon_period - float(slot)))
	return envelope * envelope


func _apply_visibility() -> void:
	for i in range(BASE_COUNT, BASE_COUNT + EXTRA_COUNT):
		_glows[i].visible = extras_level > 0.01
		_cores[i].visible = extras_level > 0.01

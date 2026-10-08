class_name HitSpark
extends Node2D

## Penitent-style hit feedback on the struck target: a yellow-white streak, an
## orange starburst with a red crescent, and red blood droplets. Procedural and
## reusable: drop the scene anywhere, set `direction` and `intensity`, add it to
## the world and it frees itself. Presentation only.
##
## Phases (measured on the reference, seconds): streak 0..0.17, orange burst
## 0.12..0.25, blood 0.1..0.4. `freeze()` holds everything for the hit-stop.

@export_group("Colours")
@export var streak_color := Color("FFF2A0")
@export var core_color := Color("FFFFFF")
@export var burst_color := Color("FF9020")
@export var blood_color := Color("C01010")

@export_group("Streak")
## Length of the diagonal streak in pixels (reference: ~128 across the whole effect).
@export var streak_length := 80.0
@export var streak_width := 5.0
## Upward tilt of the streak in degrees.
@export var streak_angle := 20.0
@export var streak_time := 0.17

@export_group("Burst")
@export var burst_radius := 24.0
@export var burst_start := 0.12
@export var burst_time := 0.13
@export var burst_spikes := 8

@export_group("Blood")
@export var blood_start := 0.1
@export var blood_time := 0.3
## Droplets per intensity level (1 = hit 1, 3 = finisher).
@export var blood_per_intensity := 7
@export var blood_speed := Vector2(40.0, 130.0)
@export var blood_gravity := 420.0
@export var blood_size := 2.0

@export_group("Lifetime")
@export var total_time := 0.42

## 1 or -1: the side the attack came from faces this way.
var direction := 1
## 1 = hit 1, 2 = hit 2, 3 = finisher (bigger burst, more blood).
var intensity := 1

var _age := 0.0
var _freeze_left := 0.0
var _drops: Array[Dictionary] = []
var _seeded := false


func _ready() -> void:
	z_index = 2
	_seed_drops()


func freeze(duration: float) -> void:
	_freeze_left = maxf(_freeze_left, duration)


func get_age() -> float:
	return _age


func _process(delta: float) -> void:
	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		return
	_age += delta
	if _age >= total_time:
		queue_free()
		return
	queue_redraw()


func _seed_drops() -> void:
	if _seeded:
		return
	_seeded = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (intensity + 1)
	for i in blood_per_intensity * intensity:
		var angle := rng.randf_range(-PI * 0.85, -PI * 0.1)
		var speed := rng.randf_range(blood_speed.x, blood_speed.y) * (1.0 + 0.15 * float(intensity))
		_drops.append({
			"velocity": Vector2(cos(angle) * float(direction), sin(angle)) * speed,
			"size": blood_size * rng.randf_range(0.7, 1.3),
		})


func _draw() -> void:
	_draw_streak()
	_draw_burst()
	_draw_blood()


func _draw_streak() -> void:
	if _age >= streak_time:
		return
	var progress := _age / streak_time
	var angle := deg_to_rad(streak_angle)
	var dir := Vector2(cos(angle) * float(direction), -sin(angle))
	var length := streak_length * (0.6 + 0.4 * float(intensity) / 3.0) * minf(progress * 4.0, 1.0)
	var width := streak_width * (1.0 - progress * 0.6)
	var normal := Vector2(-dir.y, dir.x)
	var tip := dir * length * 0.6
	var tail := -dir * length * 0.4
	draw_polygon(PackedVector2Array([tail, normal * width * 0.5, tip, -normal * width * 0.5]),
		PackedColorArray([streak_color, streak_color, streak_color, streak_color]))
	draw_polygon(PackedVector2Array([tail * 0.6, normal * width * 0.2, tip * 0.8, -normal * width * 0.2]),
		PackedColorArray([core_color, core_color, core_color, core_color]))


func _draw_burst() -> void:
	var local := _age - burst_start
	if local < 0.0 or local >= burst_time:
		return
	var progress := local / burst_time
	# Grows fast, then shrinks away: no alpha fade, like the reference.
	var scale_now := sin(progress * PI) * (0.8 + 0.2 * float(intensity))
	var radius := burst_radius * scale_now
	var spikes := burst_spikes + 2 * (intensity - 1)
	for i in spikes:
		var angle := TAU * float(i) / float(spikes) + 0.3
		var length := radius * (1.0 if i % 2 == 0 else 0.6)
		var normal := Vector2(-sin(angle), cos(angle))
		var base := Vector2(cos(angle), sin(angle))
		draw_polygon(PackedVector2Array([base * 3.0 + normal * 2.0, base * length, base * 3.0 - normal * 2.0]),
			PackedColorArray([burst_color, burst_color, burst_color]))
	if radius > 4.0:
		draw_circle(Vector2.ZERO, radius * 0.3, core_color)
		var arc_points := PackedVector2Array()
		for i in 9:
			var a := lerpf(PI * 0.55, PI * 1.15, float(i) / 8.0)
			arc_points.append(Vector2(cos(a) * float(direction) * -1.0, sin(a)) * radius * 1.3)
		draw_polyline(arc_points, blood_color, 2.0)


func _draw_blood() -> void:
	var local := _age - blood_start
	if local < 0.0 or local >= blood_time:
		return
	for drop in _drops:
		var velocity: Vector2 = drop["velocity"]
		var p := velocity * local + Vector2(0.0, blood_gravity * local * local * 0.5)
		var s := float(drop["size"]) * (1.0 - local / blood_time * 0.5)
		draw_rect(Rect2(p.round() - Vector2(s, s) * 0.5, Vector2(s, s)), blood_color)

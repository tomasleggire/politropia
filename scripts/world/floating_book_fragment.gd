class_name FloatingBookFragment
extends Node2D

const FLOAT_DISTANCE := 4.0
const FLOAT_HALF_CYCLE := 1.0
const GLOW_LOW_ALPHA := 0.35
const GLOW_HIGH_ALPHA := 0.62
const GLOW_HALF_CYCLE := 1.5
const PARTICLE_COLORS := [Color("ffe9a6"), Color("ffd070"), Color("fff7df")]

var _float_tween: Tween
var _glow_tween: Tween
var _particle_timer: Timer
var _particle_rng := RandomNumberGenerator.new()
@onready var _glow: Sprite2D = $Glow
@onready var _particle_container: Node2D = $Particles


func _ready() -> void:
	_particle_rng.randomize()
	_start_float_animation()
	_start_glow_pulse()
	_start_particle_loop()


func _start_float_animation() -> void:
	var anchor_y := position.y
	var highest := anchor_y - FLOAT_DISTANCE
	var lowest := anchor_y + FLOAT_DISTANCE
	position.y = highest
	_float_tween = create_tween().set_loops()
	_float_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_float_tween.tween_property(self, "position:y", lowest, FLOAT_HALF_CYCLE).from(highest)
	_float_tween.tween_property(self, "position:y", highest, FLOAT_HALF_CYCLE).from(lowest)


func _start_glow_pulse() -> void:
	_glow.modulate.a = GLOW_LOW_ALPHA
	_glow_tween = create_tween().set_loops()
	_glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(_glow, "modulate:a", GLOW_HIGH_ALPHA, GLOW_HALF_CYCLE).from(GLOW_LOW_ALPHA)
	_glow_tween.tween_property(_glow, "modulate:a", GLOW_LOW_ALPHA, GLOW_HALF_CYCLE).from(GLOW_HIGH_ALPHA)


func _start_particle_loop() -> void:
	_particle_timer = Timer.new()
	_particle_timer.one_shot = true
	_particle_timer.timeout.connect(_emit_magic_particle)
	add_child(_particle_timer)
	_schedule_next_particle()


func _schedule_next_particle() -> void:
	_particle_timer.start(_particle_rng.randf_range(0.26, 0.5))


func _emit_magic_particle() -> void:
	var sparkle := Polygon2D.new()
	var is_spark := _particle_rng.randf() < 0.65
	sparkle.polygon = _spark_shape() if is_spark else _light_dot_shape()
	sparkle.color = PARTICLE_COLORS[_particle_rng.randi_range(0, PARTICLE_COLORS.size() - 1)]
	sparkle.modulate.a = _particle_rng.randf_range(0.82, 1.0)
	sparkle.scale = Vector2.ONE * _particle_rng.randf_range(0.95, 1.4)
	sparkle.position = Vector2(_particle_rng.randf_range(-25.0, 25.0), _particle_rng.randf_range(-60.0, -8.0))
	_particle_container.add_child(sparkle)

	var lifetime := _particle_rng.randf_range(1.1, 1.5)
	var destination := sparkle.position + Vector2(_particle_rng.randf_range(-2.0, 2.0), -_particle_rng.randf_range(10.0, 18.0))
	var fade := create_tween().set_parallel()
	fade.tween_property(sparkle, "position", destination, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(sparkle, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade.chain().tween_callback(sparkle.queue_free)
	_schedule_next_particle()


func _spark_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -4), Vector2(0.8, -1), Vector2(3, 0), Vector2(0.8, 1),
		Vector2(0, 4), Vector2(-0.8, 1), Vector2(-3, 0), Vector2(-0.8, -1),
	])


func _light_dot_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -1.8), Vector2(1.8, 0), Vector2(0, 1.8), Vector2(-1.8, 0),
	])

## Stop independent bobbing and glow changes so the pedestal can animate this fragment.
func stop_idle_motion() -> void:
	if _float_tween != null:
		_float_tween.kill()
	if _glow_tween != null:
		_glow_tween.kill()
	if _particle_timer != null:
		_particle_timer.stop()

class_name FloatingBookFragment
extends Node2D

## A floating book page. Drop `scenes/world/fragmento_libro*.tscn` into a zone.
## Luz collects it by touching it: the fragment is recorded in `FragmentProgress`
## (so it stays gone when she re-enters the room) and fades out. Each scene
## carries its own `fragment_id` (1-4); place each id once per level. The
## lectern builds its own copies with `collectible = false`.

signal collected(id: int)

const FLOAT_DISTANCE := 4.0
const FLOAT_HALF_CYCLE := 1.0
const GLOW_LOW_ALPHA := 0.35
const GLOW_HIGH_ALPHA := 0.62
const GLOW_HALF_CYCLE := 1.5
const PARTICLE_COLORS := [Color("ffe9a6"), Color("ffd070"), Color("fff7df")]

@export_group("Collection")
## Which of the book's four fragments this is (1-4).
@export_range(1, 4) var fragment_id := 1
## Off for display copies (the pedestal's), which must never be picked up.
@export var collectible := true
## Radius of the pickup area around the fragment, in pixels.
@export var pickup_radius := 22.0
## Seconds the fragment takes to fade away after being collected.
@export_range(0.05, 1.5, 0.05) var collect_fade_time := 0.35

var _float_tween: Tween
var _glow_tween: Tween
var _particle_timer: Timer
var _particle_rng := RandomNumberGenerator.new()
var _level_key := ""
var _pickup_area: Area2D
var _origin_position := Vector2.ZERO
var _origin_scale := Vector2.ONE
var _collecting_animation := false
@onready var _glow: Sprite2D = $Glow
@onready var _particle_container: Node2D = $Particles


func _ready() -> void:
	_origin_position = position
	_origin_scale = scale
	var progress := get_node_or_null("/root/FragmentProgress")
	if progress != null:
		_level_key = progress.current_level_key()
		if collectible:
			_pickup_area = _build_pickup_area()
			progress.progress_changed.connect(_on_progress_changed)
			if progress.fragment_state(fragment_id, _level_key) != 0:
				_set_unavailable()
				return
	_particle_rng.randomize()
	_start_float_animation()
	_start_glow_pulse()
	_start_particle_loop()


func _build_pickup_area() -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.position = Vector2(0, -12.5)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = pickup_radius
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(_on_pickup_body_entered)
	add_child(area)
	return area


func _on_pickup_body_entered(body: Node2D) -> void:
	if not collectible or not body.is_in_group(&"player"):
		return
	var progress := get_node_or_null("/root/FragmentProgress")
	if progress == null:
		return
	_collecting_animation = true
	collectible = false
	if not progress.collect(fragment_id, _level_key):
		collectible = true
		_collecting_animation = false
		return
	if is_instance_valid(_pickup_area):
		_pickup_area.set_deferred("monitoring", false)
	collected.emit(fragment_id)
	stop_idle_motion()
	var fade := create_tween().set_parallel(true)
	fade.tween_property(self, "modulate:a", 0.0, collect_fade_time).set_trans(Tween.TRANS_SINE)
	fade.tween_property(self, "scale", Vector2(1.4, 1.4), collect_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.chain().tween_callback(_finish_pickup_animation)


func _finish_pickup_animation() -> void:
	_collecting_animation = false
	visible = false


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
	if is_instance_valid(_particle_timer):
		_particle_timer.start(_particle_rng.randf_range(0.26, 0.5))


func _emit_magic_particle() -> void:
	if not collectible or not visible:
		return
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


func _on_progress_changed(changed_level_key: String) -> void:
	if changed_level_key != _level_key:
		return
	var progress := get_node_or_null("/root/FragmentProgress")
	if progress == null:
		return
	var state: int = progress.fragment_state(fragment_id, _level_key)
	if state == 0:
		if not _collecting_animation:
			_restore_pickup()
	else:
		collectible = false
		if is_instance_valid(_pickup_area):
			_pickup_area.set_deferred("monitoring", false)
		if not _collecting_animation:
			visible = false
			stop_idle_motion()


func _set_unavailable() -> void:
	collectible = false
	visible = false
	if is_instance_valid(_pickup_area):
		_pickup_area.set_deferred("monitoring", false)


func _restore_pickup() -> void:
	collectible = true
	_collecting_animation = false
	position = _origin_position
	scale = _origin_scale
	modulate = Color.WHITE
	visible = true
	if is_instance_valid(_pickup_area):
		_pickup_area.set_deferred("monitoring", true)
	if _float_tween == null or not _float_tween.is_running():
		_start_float_animation()
	if _glow_tween == null or not _glow_tween.is_running():
		_start_glow_pulse()
	if not is_instance_valid(_particle_timer):
		_start_particle_loop()
	else:
		_schedule_next_particle()

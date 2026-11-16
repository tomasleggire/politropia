class_name HydraVenom
extends Area2D

## One venom spit of the Hydra's spitter, pooled by the boss. Its life is
## PLANNED (an amber marker on the spot, from the start of the telegraph) ->
## FLIGHT (a glob on an arc, harmless) -> POOL (a puddle that hurts on contact
## until it dries) -> IDLE (parked, invisible, harmless). It lives in the world,
## beside the boss, so nothing about the boss moves or hides it.

signal landed(point: Vector2)

enum State { IDLE, PLANNED, FLIGHT, POOL }

const PLAYER_LAYER := 1
const MARKER_COLOR := Color(1.0, 0.72, 0.25)
const GLOB_COLOR := Color(0.35, 0.9, 0.35)
const POOL_COLOR := Color(0.25, 0.75, 0.3)
const POOL_EDGE_COLOR := Color(0.7, 1.0, 0.55)
const MARKER_THICKNESS := 8.0
const POOL_HEIGHT := 14.0
const GLOB_RADIUS := 9.0
## Marker pulse (radians per second) and the faster one once the glob is flying.
const PULSE_RATE := 8.0
const FLIGHT_PULSE_RATE := 18.0
## The puddle blinks during its last seconds.
const DRY_WARNING_TIME := 0.7
const ELLIPSE_POINTS := 20

var damage := 1
## Seconds between two hits while Luz keeps standing in the puddle.
var rehit_interval := 0.5

var _state := State.IDLE
var _width := 96.0
var _flight_time := 0.7
var _arc_height := 90.0
var _pool_time := 3.5
var _start := Vector2.ZERO
var _flight_left := 0.0
var _pool_left := 0.0
var _rehit_left := 0.0
var _clock := 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	top_level = true
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	z_index = 1
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	_shape.disabled = true
	add_child(_shape)
	release()


func _physics_process(delta: float) -> void:
	_clock += delta
	match _state:
		State.PLANNED:
			queue_redraw()
		State.FLIGHT:
			_update_flight(delta)
		State.POOL:
			_update_pool(delta)


func _draw() -> void:
	match _state:
		State.PLANNED:
			_draw_marker(PULSE_RATE)
		State.FLIGHT:
			_draw_marker(FLIGHT_PULSE_RATE)
			_draw_glob()
		State.POOL:
			_draw_pool()


func get_state() -> State:
	return _state


func is_active() -> bool:
	return _state != State.IDLE


func is_flying() -> bool:
	return _state == State.FLIGHT


func is_pool() -> bool:
	return _state == State.POOL


func is_marker_visible() -> bool:
	return _state == State.PLANNED or _state == State.FLIGHT


## Seconds the puddle still hurts.
func get_pool_time_left() -> float:
	return _pool_left if _state == State.POOL else 0.0


## The landing point (the surface under the marker), world space.
func get_spot() -> Vector2:
	return global_position


## Marks `spot` (a point on a surface) with a marker; nothing flies yet.
func plan(spot: Vector2, width: float, flight_time: float, arc_height: float, pool_time: float) -> void:
	global_position = spot
	_width = width
	_flight_time = maxf(flight_time, 0.05)
	_arc_height = arc_height
	_pool_time = pool_time
	_state = State.PLANNED
	_set_pool_active(false)
	visible = true
	queue_redraw()


## Throws the glob from `from`; it lands on the planned spot after the flight time.
func launch(from: Vector2) -> void:
	if _state != State.PLANNED:
		return
	_start = from
	_flight_left = _flight_time
	_state = State.FLIGHT
	queue_redraw()


## Parks it: no marker, no glob, no puddle, no damage.
func release() -> void:
	_state = State.IDLE
	_set_pool_active(false)
	visible = false
	queue_redraw()


func _update_flight(delta: float) -> void:
	_flight_left -= delta
	if _flight_left <= 0.0:
		_land()
		return
	queue_redraw()


func _land() -> void:
	_state = State.POOL
	_pool_left = _pool_time
	_rehit_left = 0.0
	var shape := _shape.shape as RectangleShape2D
	shape.size = Vector2(_width, POOL_HEIGHT)
	_shape.position = Vector2(0.0, -POOL_HEIGHT * 0.5)
	_set_pool_active(true)
	landed.emit(global_position)
	queue_redraw()


func _update_pool(delta: float) -> void:
	_pool_left -= delta
	if _pool_left <= 0.0:
		release()
		return
	_rehit_left = maxf(_rehit_left - delta, 0.0)
	if _rehit_left <= 0.0:
		_hurt_overlapping()
	queue_redraw()


func _hurt_overlapping() -> void:
	for body: Node2D in get_overlapping_bodies():
		var player := body as Player
		if player != null and player.take_damage(damage, global_position):
			_rehit_left = rehit_interval
			return


## Deferred: a severing hit can release the pool from inside a physics callback,
## where changing a shape or an area is forbidden.
func _set_pool_active(on: bool) -> void:
	if _shape != null:
		_shape.set_deferred(&"disabled", not on)
	set_deferred(&"monitoring", on)


func _draw_marker(rate: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_clock * rate)
	var rect := Rect2(-_width * 0.5, -MARKER_THICKNESS, _width, MARKER_THICKNESS)
	draw_rect(rect, Color(MARKER_COLOR, 0.3 + 0.3 * pulse))
	draw_rect(Rect2(rect.position, Vector2(4.0, rect.size.y)), Color(MARKER_COLOR, 0.9))
	draw_rect(Rect2(rect.end.x - 4.0, rect.position.y, 4.0, rect.size.y), Color(MARKER_COLOR, 0.9))


## The glob rides a parabola: a straight line from the mouth to the spot plus a
## bump that peaks halfway (4 u (1 - u) reaches 1 at u = 0.5).
func _draw_glob() -> void:
	var u := 1.0 - _flight_left / _flight_time
	var point := _start.lerp(global_position, u) - Vector2(0.0, _arc_height * 4.0 * u * (1.0 - u))
	var local := to_local(point)
	draw_circle(local, GLOB_RADIUS, GLOB_COLOR)
	draw_circle(local + Vector2(-2.5, -3.0), GLOB_RADIUS * 0.35, Color(0.85, 1.0, 0.8, 0.9))


func _draw_pool() -> void:
	var fade := 1.0
	if _pool_left < DRY_WARNING_TIME:
		fade = 0.55 + 0.45 * sin(_clock * FLIGHT_PULSE_RATE)
	var points := PackedVector2Array()
	for i: int in ELLIPSE_POINTS:
		var angle := TAU * float(i) / float(ELLIPSE_POINTS)
		points.append(Vector2(cos(angle) * _width * 0.5, -POOL_HEIGHT * 0.5 + sin(angle) * POOL_HEIGHT * 0.5))
	draw_colored_polygon(points, Color(POOL_COLOR, 0.85 * fade))
	points.append(points[0])
	draw_polyline(points, Color(POOL_EDGE_COLOR, fade), 2.0)

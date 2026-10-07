class_name GroundDust
extends Node2D

## Reusable pixel-art ground dust: opaque off-white shapes that shrink in
## stepped increments (no alpha fade) and free themselves when done. Drop the
## scene anywhere in world space; it stays where it was placed. Pick the kind,
## size, color and timing in the inspector. Origin = the ground contact point.

enum Kind { FOOTSTEP, TURN, STOP }

@export var kind := Kind.FOOTSTEP
@export var color := Color(0.93, 0.91, 0.86)
## Horizontal side the effect points to: the puff is centered, the STOP skid
## lines trail BEHIND this direction (-1 left, 1 right). Luz sets it to her facing.
@export_enum("Left:-1", "Right:1") var direction := 1
## Size multiplier applied to the active step: each step multiplies the last.
@export_range(0.1, 1.0) var step_shrink := 0.5

@export_group("Footstep")
@export var footstep_size := Vector2(7.0, 3.0)
@export var footstep_lifetime := 0.11
@export var footstep_steps := 1

@export_group("Turn")
@export var turn_size := Vector2(10.0, 4.0)
@export var turn_lifetime := 0.133
@export var turn_steps := 2

@export_group("Stop")
@export var stop_size := Vector2(14.0, 6.0)
@export var stop_lifetime := 0.3
@export var stop_steps := 3

var _elapsed := 0.0
var _step := -1
var _size := Vector2.ZERO
var _lifetime := 0.1
var _steps := 1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Spawned between physics ticks and never moved again: no interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = global_position.round()
	_load_kind_settings()
	_show_step(0)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	_show_step(mini(int(_elapsed / (_lifetime / float(_steps))), _steps - 1))


func _load_kind_settings() -> void:
	match kind:
		Kind.TURN:
			_size = turn_size
			_lifetime = turn_lifetime
			_steps = turn_steps
		Kind.STOP:
			_size = stop_size
			_lifetime = stop_lifetime
			_steps = stop_steps
		_:
			_size = footstep_size
			_lifetime = footstep_lifetime
			_steps = footstep_steps
	_steps = maxi(_steps, 1)
	_lifetime = maxf(_lifetime, 0.001)


func _show_step(step: int) -> void:
	if step == _step:
		return
	_step = step
	queue_redraw()


func _draw() -> void:
	var step_scale := pow(step_shrink, float(_step))
	var width := maxi(roundi(_size.x * step_scale), 1)
	var height := maxi(roundi(_size.y * step_scale), 1)
	if kind == Kind.STOP:
		_draw_skid_lines(width, height)
	else:
		_draw_puff(width, height)


## Flat dome resting on the ground, built from 1 px rows so edges stay crisp.
func _draw_puff(width: int, height: int) -> void:
	for row in height:
		var fill := sqrt(1.0 - pow(float(row) / float(height), 2.0))
		var row_width := maxi(roundi(float(width) * fill), 1)
		draw_rect(Rect2(-float(row_width) * 0.5, -row - 1, row_width, 1), color)


## Scratch lines along the ground, trailing behind the facing direction and
## getting shorter the higher they sit.
func _draw_skid_lines(width: int, height: int) -> void:
	var line_count := maxi(mini(height, 3), 1)
	for line in line_count:
		var length := maxi(roundi(float(width) * (1.0 - 0.3 * float(line))), 1)
		var x := 0 if direction < 0 else -length
		draw_rect(Rect2(x, -1 - 2 * line, length, 1), color)

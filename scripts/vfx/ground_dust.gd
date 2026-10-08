class_name GroundDust
extends Node2D

## Reusable pixel-art ground dust: opaque off-white shapes that shrink in
## stepped increments (no alpha fade) and free themselves when done. Drop the
## scene anywhere in world space; it stays where it was placed. Pick the kind,
## size, color and timing in the inspector. Origin = the ground contact point.
##
## Every shape is built from square dust pixels of `pixel_size` world units.
## Luz is drawn at about 6.9 texels per world unit, so the old 1-unit dust
## pixels looked chunky next to her; 0.5 keeps the hard NEAREST look but with
## twice the detail. Sizes are in world units, so changing the pixel size
## changes the detail and never the footprint.

enum Kind { FOOTSTEP, TURN, STOP, TAKEOFF, LANDING }

@export var kind := Kind.FOOTSTEP
@export var color := Color(0.93, 0.91, 0.86)
## Horizontal side the effect points to: puffs are centered, the STOP skid
## lines trail BEHIND this direction (-1 left, 1 right). Luz sets it to her facing.
@export_enum("Left:-1", "Right:1") var direction := 1
## Edge of one dust pixel in world units (smaller = finer detail).
@export_range(0.25, 1.0, 0.05) var pixel_size := 0.5
## Size multiplier applied to the active step: each step multiplies the last.
@export_range(0.1, 1.0) var step_shrink := 0.6
## Highest a loose speck may sit above the ground, in world units.
@export var speck_height := 7.0

@export_group("Footstep")
## Dome width and height in world units.
@export var footstep_size := Vector2(12.0, 5.0)
@export var footstep_lifetime := 0.2
@export var footstep_steps := 3
## Loose specks around the puff.
@export var footstep_specks := 3
## How far the specks scatter from the center, in world units.
@export var footstep_speck_spread := 9.0

@export_group("Turn")
@export var turn_size := Vector2(14.0, 5.0)
@export var turn_lifetime := 0.25
@export var turn_steps := 3
@export var turn_specks := 4
@export var turn_speck_spread := 12.0

@export_group("Stop")
## Width and height of the skid: the width is the length of the longest line,
## the height sets how many lines trail behind the feet.
@export var stop_size := Vector2(30.0, 7.0)
@export var stop_lifetime := 0.42
@export var stop_steps := 4
@export var stop_specks := 6
@export var stop_speck_spread := 20.0

@export_group("Takeoff")
## Tiny puff under the feet when she leaves the ground.
@export var takeoff_size := Vector2(9.0, 3.0)
@export var takeoff_lifetime := 0.2
@export var takeoff_steps := 3
@export var takeoff_specks := 4
@export var takeoff_speck_spread := 10.0

@export_group("Landing")
## Wide thin arcs skimming the ground; the width spans both arcs.
@export var landing_size := Vector2(40.0, 5.0)
@export var landing_lifetime := 0.27
@export var landing_steps := 4
@export var landing_specks := 8
@export var landing_speck_spread := 22.0

var _elapsed := 0.0
var _step := -1
var _size := Vector2.ZERO
var _lifetime := 0.1
var _steps := 1
## Loose specks, in dust pixels from the origin (x) and above the ground (y).
var _specks: Array[Vector2i] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Spawned between physics ticks and never moved again: no interpolation.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = (global_position / pixel_size).round() * pixel_size
	_load_kind_settings()
	_show_step(0)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	_show_step(mini(int(_elapsed / (_lifetime / float(_steps))), _steps - 1))


func _load_kind_settings() -> void:
	var speck_count := 0
	var spread := 0.0
	match kind:
		Kind.TURN:
			_size = turn_size
			_lifetime = turn_lifetime
			_steps = turn_steps
			speck_count = turn_specks
			spread = turn_speck_spread
		Kind.STOP:
			_size = stop_size
			_lifetime = stop_lifetime
			_steps = stop_steps
			speck_count = stop_specks
			spread = stop_speck_spread
		Kind.TAKEOFF:
			_size = takeoff_size
			_lifetime = takeoff_lifetime
			_steps = takeoff_steps
			speck_count = takeoff_specks
			spread = takeoff_speck_spread
		Kind.LANDING:
			_size = landing_size
			_lifetime = landing_lifetime
			_steps = landing_steps
			speck_count = landing_specks
			spread = landing_speck_spread
		_:
			_size = footstep_size
			_lifetime = footstep_lifetime
			_steps = footstep_steps
			speck_count = footstep_specks
			spread = footstep_speck_spread
	_steps = maxi(_steps, 1)
	_lifetime = maxf(_lifetime, 0.001)
	_scatter_specks(speck_count, spread)


## Same spot, same specks: the pattern is seeded from the (grid-snapped) position.
func _scatter_specks(count: int, spread: float) -> void:
	_specks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(global_position.x), roundi(global_position.y), int(kind)))
	var reach := maxi(roundi(spread / pixel_size), 1)
	var height := maxi(roundi(speck_height / pixel_size), 1)
	for i in maxi(count, 0):
		var side := -1 if rng.randf() < 0.5 else 1
		_specks.append(Vector2i(side * rng.randi_range(maxi(int(reach / 3.0), 1), reach), rng.randi_range(1, height)))


func _show_step(step: int) -> void:
	if step == _step:
		return
	_step = step
	queue_redraw()


func _draw() -> void:
	var step_scale := pow(step_shrink, float(_step))
	var width := maxi(roundi(_size.x / pixel_size * step_scale), 1)
	var height := maxi(roundi(_size.y / pixel_size * step_scale), 1)
	match kind:
		Kind.STOP:
			_draw_skid_lines(width, height)
		Kind.LANDING:
			_draw_landing_arcs(width, height)
		_:
			_draw_puff(width, height)
	_draw_specks(step_scale)


## One dust pixel run: x, y from the origin (y up) and size, all in dust pixels.
func _pixels(x: int, y: int, w: int, h: int) -> void:
	draw_rect(Rect2(float(x) * pixel_size, float(-y - h) * pixel_size, float(w) * pixel_size, float(h) * pixel_size), color)


## Flat dome resting on the ground, built from one-pixel rows so edges stay crisp.
func _draw_puff(width: int, height: int) -> void:
	for row in height:
		var fill := sqrt(1.0 - pow(float(row) / float(height), 2.0))
		var row_width := maxi(roundi(float(width) * fill), 1)
		_pixels(-int(row_width * 0.5), row, row_width, 1)


## Scratch lines along the ground, trailing behind the facing direction and
## getting shorter the higher they sit; one line per two dust-pixel rows of height.
func _draw_skid_lines(width: int, height: int) -> void:
	var line_count := maxi(mini(int(height * 0.5), 6), 1)
	for line in line_count:
		var length := maxi(roundi(float(width) * (1.0 - 0.18 * float(line))), 1)
		var x := 0 if direction < 0 else -length
		_pixels(x, 1 + 2 * line, length, 1)


## Two thin flat arcs, one to each side of the feet: each is a one-pixel curve
## that rises from the ground to `height` and comes back to it.
func _draw_landing_arcs(width: int, height: int) -> void:
	var half := maxi(int(width * 0.5), 2)
	var inner := maxi(int(half * 0.2), 1)
	for side in [-1, 1]:
		var length := half - inner
		var previous := 0
		for i in length:
			var rise := roundi(float(height) * sin(float(i) / float(length) * PI))
			var x: int = inner + i if side > 0 else -inner - i - 1
			# Fill the vertical gap to the previous column so the curve stays connected.
			_pixels(x, mini(rise, previous), 1, absi(rise - previous) + 1)
			previous = rise


## Loose specks: the later ones drop out first as the effect shrinks.
func _draw_specks(step_scale: float) -> void:
	var visible_count := roundi(float(_specks.size()) * step_scale)
	for i in mini(visible_count, _specks.size()):
		_pixels(_specks[i].x, _specks[i].y, 1, 1)

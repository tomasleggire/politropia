class_name PlayerSlashVfx
extends Node2D

## Procedural Penitent-style slash strokes for Luz's attacks. Every stroke is a
## tapered curve fitted to the rectangle of the hitbox that is active with it,
## so the visual reach equals the hitbox reach by construction. Presentation
## only: this node never touches collision, damage or gameplay state.
##
## Colours follow the measured reference (cream tip, mint-grey tail); the
## stroke erodes from its tail instead of fading its alpha. A stroke stays in
## the world where it was cast (the finisher's lunge does not drag it).

## Seconds a stroke keeps eroding after its active phase ends (measured: 3
## faint frames after the 4-5 bright ones).
const TAIL_TIME := 0.05
## Points along each stroke's centre line.
const SEGMENTS := 18
## Gap kept between the curve's extremes and the hitbox edge, in pixels.
const FIT_INSET := 1.0

## Normalised control points (x right, y down, 0..1 across the hitbox) of a
## quadratic curve, the stroke's maximum width in pixels and where along the
## curve (0..1) the stroke is at its widest.
const SHAPES := {
	&"slash_a": {"pts": [Vector2(0.0, 0.85), Vector2(0.65, 1.0), Vector2(1.0, 0.0)], "width": 9.0, "peak": 0.9},
	&"slash_b_high": {"pts": [Vector2(0.0, 0.75), Vector2(0.45, 0.1), Vector2(1.0, 0.6)], "width": 6.0, "peak": 0.3},
	&"slash_b_low": {"pts": [Vector2(0.0, 0.1), Vector2(0.35, 1.25), Vector2(1.0, 0.85)], "width": 6.0, "peak": 0.4},
	&"slash_finisher": {"pts": [Vector2(0.1, 0.0), Vector2(1.9, 0.5), Vector2(0.1, 1.0)], "width": 10.0, "peak": 0.5},
	&"slash_crouch_a": {"pts": [Vector2(0.0, 0.0), Vector2(0.75, 0.1), Vector2(1.0, 1.0)], "width": 9.0, "peak": 0.8},
	&"slash_crouch_b": {"pts": [Vector2(0.0, 0.2), Vector2(0.35, 1.0), Vector2(1.0, 0.8)], "width": 6.0, "peak": 0.35},
	&"slash_up_rise": {"pts": [Vector2(0.0, 1.0), Vector2(0.05, 0.0), Vector2(1.0, 0.0)], "width": 8.0, "peak": 0.8},
	&"slash_up_fall": {"pts": [Vector2(0.0, 0.0), Vector2(0.95, 0.0), Vector2(1.0, 1.0)], "width": 8.0, "peak": 0.3},
	&"slash_air_a": {"pts": [Vector2(0.0, 0.0), Vector2(0.7, 0.05), Vector2(1.0, 0.85)], "width": 9.0, "peak": 0.8},
	&"slash_air_b": {"pts": [Vector2(0.0, 0.75), Vector2(0.5, 0.65), Vector2(1.0, 0.2)], "width": 6.0, "peak": 0.3},
}

@export_group("Colours")
@export var head_color := Color("F5F0D0")
@export var tail_color := Color("A9C4B8")
## Width multiplier on every stroke (inspector tuning of the whole look).
@export var width_scale := 1.0

var _strokes: Array[Dictionary] = []
var _freeze_left := 0.0


func _ready() -> void:
	visible = false
	set_process(false)


## `rect` is the active hitbox in right-facing local pixels (x forward, y down
## from the feet); `duration` is how long that phase is active.
func play_stroke(shape: StringName, facing: int, rect: Rect2, duration: float) -> void:
	if not SHAPES.has(shape):
		return
	var points := stroke_points(shape, facing, rect)
	_strokes.append({
		"shape": shape,
		"points": points,
		"width": float(SHAPES[shape]["width"]) * width_scale,
		"peak": float(SHAPES[shape]["peak"]),
		"age": 0.0,
		"life": duration + TAIL_TIME,
		"active": duration,
		"origin": global_position,
	})
	visible = true
	set_process(true)
	queue_redraw()


func stop_slash() -> void:
	_strokes.clear()
	_freeze_left = 0.0
	visible = false
	set_process(false)
	queue_redraw()


## Holds every stroke for `duration` seconds (hit-stop).
func freeze(duration: float) -> void:
	_freeze_left = maxf(_freeze_left, duration)


func is_playing() -> bool:
	return not _strokes.is_empty()


func stroke_count() -> int:
	return _strokes.size()


## Centre line of a stroke after fitting it into `rect` (mirrored by facing).
static func stroke_points(shape: StringName, facing: int, rect: Rect2) -> PackedVector2Array:
	var pts: Array = SHAPES[shape]["pts"]
	var raw := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var a: Vector2 = (pts[0] as Vector2).lerp(pts[1], t)
		var b: Vector2 = (pts[1] as Vector2).lerp(pts[2], t)
		raw.append(a.lerp(b, t))
	var low := raw[0]
	var high := raw[0]
	for p in raw:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	var span := (high - low).max(Vector2(0.0001, 0.0001))
	var inner := rect.grow(-FIT_INSET)
	var sign_x := 1.0 if facing >= 0 else -1.0
	var out := PackedVector2Array()
	for p in raw:
		var n := (p - low) / span
		var local := inner.position + n * inner.size
		out.append(Vector2(local.x * sign_x, local.y))
	return out


## Bounding rectangle of the drawn polygon of a stroke (for tests and tuning).
static func stroke_bounds(shape: StringName, facing: int, rect: Rect2) -> Rect2:
	var points := stroke_points(shape, facing, rect)
	var half := float(SHAPES[shape]["width"]) * 0.5
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	return bounds.grow(half)


func _process(delta: float) -> void:
	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		return
	for stroke in _strokes:
		stroke["age"] = float(stroke["age"]) + delta
	_strokes = _strokes.filter(func(s: Dictionary) -> bool: return float(s["age"]) < float(s["life"]))
	if _strokes.is_empty():
		stop_slash()
		return
	queue_redraw()


func _draw() -> void:
	for stroke in _strokes:
		_draw_stroke(stroke)


func _draw_stroke(stroke: Dictionary) -> void:
	var points: PackedVector2Array = stroke["points"]
	var age := float(stroke["age"])
	var active := float(stroke["active"])
	# Erosion starts once the active phase is over: the tail disappears first.
	var erode := clampf((age - active) / TAIL_TIME, 0.0, 1.0)
	var shift: Vector2 = (stroke["origin"] as Vector2) - global_position
	var first := int(round(erode * float(points.size() - 2)))
	var width_now := float(stroke["width"]) * (1.0 - 0.5 * erode)
	var peak := float(stroke["peak"])
	for i in range(first, points.size() - 1):
		var u0 := float(i) / float(points.size() - 1)
		var u1 := float(i + 1) / float(points.size() - 1)
		var w0 := width_now * _profile(u0, peak)
		var w1 := width_now * _profile(u1, peak)
		var p0 := points[i] + shift
		var p1 := points[i + 1] + shift
		var dir := (p1 - p0).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var quad := PackedVector2Array([
			p0 - normal * w0 * 0.5, p0 + normal * w0 * 0.5,
			p1 + normal * w1 * 0.5, p1 - normal * w1 * 0.5,
		])
		var c0 := tail_color.lerp(head_color, _profile(u0, peak))
		var c1 := tail_color.lerp(head_color, _profile(u1, peak))
		draw_polygon(quad, PackedColorArray([c0, c0, c1, c1]))


## 0.12 at the start, 1.0 at `peak`, 0.12 again at the end.
static func _profile(u: float, peak: float) -> float:
	var rising := u / maxf(peak, 0.001)
	var falling := (1.0 - u) / maxf(1.0 - peak, 0.001)
	return clampf(minf(rising, falling), 0.0, 1.0) * 0.88 + 0.12

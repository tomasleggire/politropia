class_name PlayerSlashVfx
extends Node2D

## Procedural Penitent-style slash for Luz's attacks: ONE tapered crescent (an
## arc for the up attack) per attack, anchored to her body, drawn over the
## animation's active window and then eroded from its tail. Presentation only: this node never touches collision, damage or
## gameplay state.
##
## Colours follow the measured reference (cream tip, mint-grey tail); the
## stroke erodes from its tail instead of fading its alpha. A stroke stays in
## the world where it was cast (the finisher's lunge does not drag it).

## Seconds a stroke keeps eroding after its active phase ends (measured: 3
## faint frames after the 4-5 bright ones).
const TAIL_TIME := 0.05
## Share of the slash time the crescent takes to reach its full length: it is
## cast at the first active frame, while the ruler is still out in front.
const GROW_SHARE := 0.35
## Share of the slash time it stays whole before it erodes from its tail (the
## ruler is back by then).
const HOLD_SHARE := 0.65
## Points along each stroke's centre line.
const SEGMENTS := 28

## One slash per attack: a cubic curve in right-facing local pixels (x forward,
## y down, feet at the origin), shaped after the Penitent's slash A. Ground,
## crouch and air attacks are a "boomerang" crescent that sweeps from beside her
## body to the front and hooks up at its end; the up attack is an arc over her
## head. `active_frames` is how many animation frames the attack's active window
## spans and `frames` how many of them the slash is drawn for. `width` is the
## stroke's maximum width and `peak` where along it (0 start .. 1 end) it is widest.
const SLASHES := {
	&"attack_1": {"pts": [Vector2(12, -18), Vector2(86, -18), Vector2(88, -40), Vector2(48, -44)], "active_frames": 3, "frames": 2, "width": 12.0, "peak": 0.70},
	&"attack_2": {"pts": [Vector2(12, -22), Vector2(86, -22), Vector2(88, -44), Vector2(48, -50)], "active_frames": 4, "frames": 2, "width": 12.0, "peak": 0.70},
	&"attack_3": {"pts": [Vector2(14, -14), Vector2(116, -12), Vector2(118, -50), Vector2(68, -58)], "active_frames": 2, "frames": 2, "width": 14.0, "peak": 0.70},
	&"crouch_attack": {"pts": [Vector2(10, -4), Vector2(78, -4), Vector2(78, -22), Vector2(42, -26)], "active_frames": 2, "frames": 2, "width": 12.0, "peak": 0.70},
	&"up_attack": {"pts": [Vector2(-40, -34), Vector2(-46, -100), Vector2(25, -142), Vector2(28, -56)], "active_frames": 3, "frames": 3, "width": 10.0, "peak": 0.30},
	&"air_attack": {"pts": [Vector2(12, -22), Vector2(86, -22), Vector2(88, -44), Vector2(50, -50)], "active_frames": 3, "frames": 2, "width": 12.0, "peak": 0.70},
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


## Casts the slash of `attack` (a SLASHES key); `duration` is the animation's
## active window, over which the crescent is drawn from tail to head.
func play_slash(attack: StringName, facing: int, duration: float) -> void:
	if not SLASHES.has(attack):
		return
	# One slash per attack: a new one replaces whatever is left of the last.
	_strokes.clear()
	_strokes.append({
		"attack": attack,
		"points": slash_points(attack, facing),
		"width": float(SLASHES[attack]["width"]) * width_scale,
		"peak": float(SLASHES[attack]["peak"]),
		"age": 0.0,
		"life": duration * HOLD_SHARE + TAIL_TIME,
		"active": maxf(duration * HOLD_SHARE, 0.001),
		"grow": maxf(duration * GROW_SHARE, 0.001),
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


## Seconds the slash is drawn for an active window of `active_time`.
static func slash_time(attack: StringName, active_time: float) -> float:
	var config: Dictionary = SLASHES[attack]
	var share := float(config["frames"]) / float(config["active_frames"])
	return maxf(active_time * minf(share, 1.0), 0.06)


## Centre line of a slash (mirrored by facing).
static func slash_points(attack: StringName, facing: int) -> PackedVector2Array:
	var control: Array = SLASHES[attack]["pts"]
	var sign_x := 1.0 if facing >= 0 else -1.0
	var out := PackedVector2Array()
	for i in SEGMENTS + 1:
		var u := float(i) / float(SEGMENTS)
		var layer: Array = control.duplicate()
		while layer.size() > 1:
			var next: Array = []
			for j in layer.size() - 1:
				next.append((layer[j] as Vector2).lerp(layer[j + 1], u))
			layer = next
		var point: Vector2 = layer[0]
		out.append(Vector2(point.x * sign_x, point.y))
	return out


## Rectangle (right-facing local pixels) that holds the drawn slash.
static func slash_bounds(attack: StringName, facing: int = 1) -> Rect2:
	var points := slash_points(attack, facing)
	var half := float(SLASHES[attack]["width"]) * 0.5
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
	# The crescent is drawn from its tail to its head over the first part of its time.
	var grown := clampf(age / float(stroke["grow"]), 0.0, 1.0)
	var last := maxi(int(ceil(grown * float(points.size() - 1))), 2)
	var width_now := float(stroke["width"]) * (1.0 - 0.5 * erode)
	var peak := float(stroke["peak"])
	# Both edges use smoothed normals, so a tight hook has no gaps or fans.
	var top := mini(last, points.size() - 1)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors := PackedColorArray()
	for i in range(first, top + 1):
		var u := float(i) / float(points.size() - 1)
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var dir := (after - before).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var half := width_now * _profile(u, peak) * 0.5
		var centre := points[i] + shift
		left.append(centre - normal * half)
		right.append(centre + normal * half)
		colors.append(tail_color.lerp(head_color, _profile(u, peak)))
	for i in range(left.size() - 1):
		# Triangles, not a quad: the inner edge of a tight hook can twist.
		draw_primitive(PackedVector2Array([left[i], right[i], right[i + 1]]), PackedColorArray([colors[i], colors[i], colors[i + 1]]), PackedVector2Array())
		draw_primitive(PackedVector2Array([left[i], right[i + 1], left[i + 1]]), PackedColorArray([colors[i], colors[i + 1], colors[i + 1]]), PackedVector2Array())


## 0.12 at the start, 1.0 at `peak`, 0.12 again at the end.
static func _profile(u: float, peak: float) -> float:
	var rising := u / maxf(peak, 0.001)
	var falling := (1.0 - u) / maxf(1.0 - peak, 0.001)
	return clampf(minf(rising, falling), 0.0, 1.0) * 0.88 + 0.12

class_name PlayerSlashVfx
extends Node2D

## Procedural Penitent-style slash for Luz's attacks: ONE tapered crescent per
## attack that follows the ruler's own sweep (grip and tip measured on the
## attack frames), grows with the animation's active window and then erodes from
## its tail. Presentation only: this node never touches collision, damage or
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
const SEGMENTS := 18

## Measured grip and tip of Luz's ruler on every attack frame, in right-facing
## local pixels (tools/luz_ruler_tip_track.py): clip -> frame -> [gx, gy, tx, ty].
const TIPS_PATH := "res://assets/player/luz/luz_ruler_tips.json"

## One slash per attack, shaped by the ruler itself. The path starts at `start`
## (0 grip .. 1 tip) of the ruler on the first listed frame, passes through the
## tip of every listed frame and ends `extend` pixels past the last tip along
## the sweep; `bow` bulges the middle of a path that has no other curvature.
## `active_frames` is how many animation frames the attack's active window spans:
## the slash is drawn only over the share of the window the listed frames take.
## `width` is the stroke's maximum width and `peak` where along it it is widest.
const SLASHES := {
	&"attack_1": {"clip": "ground_attack_1", "active_frames": 3, "frames": [4, 5], "start": 0.1, "extend": 14.0, "bow": -4.0, "width": 9.0, "peak": 0.85},
	&"attack_2": {"clip": "ground_attack_2", "active_frames": 4, "frames": [2, 3], "start": 0.1, "extend": 14.0, "bow": -4.0, "width": 9.0, "peak": 0.85},
	&"attack_3": {"clip": "ground_attack_3", "active_frames": 2, "frames": [5], "start": 0.0, "extend": 22.0, "bow": -9.0, "width": 11.0, "peak": 0.8},
	&"crouch_attack": {"clip": "crouch_attack", "active_frames": 2, "frames": [4], "start": 0.0, "extend": 22.0, "bow": -8.0, "width": 9.0, "peak": 0.8},
	&"up_attack": {"clip": "up_attack", "active_frames": 3, "frames": [3, 4, 5], "start": 0.2, "extend": 32.0, "bow": 0.0, "width": 9.0, "peak": 0.8},
	&"air_attack": {"clip": "air_horizontal_attack", "active_frames": 3, "frames": [3], "start": 0.0, "extend": 22.0, "bow": -8.0, "width": 9.0, "peak": 0.8},
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
	var share := float((config["frames"] as Array).size()) / float(config["active_frames"])
	return maxf(active_time * minf(share, 1.0), 0.06)


## Centre line of a slash (mirrored by facing), from the ruler track.
static func slash_points(attack: StringName, facing: int) -> PackedVector2Array:
	var config: Dictionary = SLASHES[attack]
	var track: Array = _tips()[config["clip"]]
	var frames: Array = config["frames"]
	var first: Array = track[int(frames[0])]
	var grip := Vector2(first[0], first[1])
	var tip := Vector2(first[2], first[3])
	var waypoints: Array[Vector2] = [grip.lerp(tip, float(config["start"]))]
	for frame in frames:
		var row: Array = track[int(frame)]
		waypoints.append(Vector2(row[2], row[3]))
	var last := waypoints[waypoints.size() - 1]
	var previous := waypoints[waypoints.size() - 2]
	var last_row: Array = track[int(frames[frames.size() - 1])]
	var axis := (Vector2(last_row[2], last_row[3]) - Vector2(last_row[0], last_row[1])).normalized()
	var end := last + axis * float(config["extend"])
	var begin := waypoints[0]
	@warning_ignore("integer_division")
	var middle := waypoints[waypoints.size() / 2]
	if waypoints.size() == 2:
		middle = begin.lerp(end, 0.5) + Vector2(axis.y, -axis.x) * float(config["bow"])
	# Quadratic curve that passes through `middle` halfway along.
	var control := 2.0 * middle - 0.5 * (begin + end)
	var sign_x := 1.0 if facing >= 0 else -1.0
	var out := PackedVector2Array()
	for i in SEGMENTS + 1:
		var u := float(i) / float(SEGMENTS)
		var point := begin.lerp(control, u).lerp(control.lerp(end, u), u)
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


static var _tips_cache: Dictionary = {}


static func _tips() -> Dictionary:
	if _tips_cache.is_empty():
		var file := FileAccess.open(TIPS_PATH, FileAccess.READ)
		assert(file != null, "Cannot read Luz ruler tip track")
		_tips_cache = JSON.parse_string(file.get_as_text())
	return _tips_cache


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
	for i in range(first, mini(last, points.size() - 1)):
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

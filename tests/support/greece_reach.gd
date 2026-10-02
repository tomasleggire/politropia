extends RefCounted
## Data-level reachability for the Greece layout. Standing surfaces are the
## walkable tops of solids and one-ways with player headroom; an edge exists
## when a jump (+ air dash) envelope connects two surfaces with a clear line.
## Spikes are not standable: the stretch of a floor they cover is cut out.

const PLAYER_HEIGHT := 58.0
const BODY_MID := 29.0
const MIN_SURFACE_WIDTH := 24.0
const LINE_SAMPLES := 24
const LINE_SHRINK := 2.0
const RUN_SPEED := 250.0
const JUMP_HEIGHT := 130.0
const FALL_GRAVITY := 2407.0

var solids: Array[Rect2] = []
var hazards: Array[Rect2] = []
var surfaces: Array[Dictionary] = []   # {x0, x1, y}


func _init(solid_rects: Array[Rect2], one_way_rects: Array[Rect2], hazard_rects: Array[Rect2] = []) -> void:
	solids = solid_rects
	hazards = hazard_rects
	var tops: Array[Rect2] = []
	tops.append_array(solid_rects)
	tops.append_array(one_way_rects)
	for rect: Rect2 in tops:
		_add_free_segments(rect)


func surface_at(point: Vector2) -> int:
	for i: int in surfaces.size():
		var s := surfaces[i]
		if absf(point.y - float(s.y)) < 1.5 and point.x >= float(s.x0) and point.x <= float(s.x1):
			return i
	return -1


## Extra horizontal reach of a running jump that lands `drop` px below its
## take-off, against a flat one: the fall after the apex lasts longer.
static func fall_reach_bonus(drop: float) -> float:
	var flat_fall := sqrt(2.0 * JUMP_HEIGHT / FALL_GRAVITY)
	var long_fall := sqrt(2.0 * (JUMP_HEIGHT + drop) / FALL_GRAVITY)
	return RUN_SPEED * (long_fall - flat_fall)


## Indices of every surface reachable from `start`. With `fall_reach`, a jump to
## a lower surface gets the longer reach of its longer fall.
func reachable(start: int, max_rise: float, max_gap: float, fall_reach := false) -> Dictionary:
	var seen := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var from_index: int = queue.pop_back()
		for to_index: int in surfaces.size():
			if not seen.has(to_index) and can_reach(from_index, to_index, max_rise, max_gap, fall_reach):
				seen[to_index] = true
				queue.append(to_index)
	return seen


func can_reach(a: int, b: int, max_rise: float, max_gap: float, fall_reach := false) -> bool:
	var from_surface := surfaces[a]
	var to_surface := surfaces[b]
	var rise := float(from_surface.y) - float(to_surface.y)
	var reach := max_gap
	if fall_reach and rise < 0.0:
		reach += fall_reach_bonus(-rise)
	if rise > max_rise or _gap(from_surface, to_surface) > reach:
		return false
	return _line_is_clear(from_surface, to_surface)


func _gap(a: Dictionary, b: Dictionary) -> float:
	return maxf(0.0, maxf(float(b.x0) - float(a.x1), float(a.x0) - float(b.x1)))


func _line_is_clear(a: Dictionary, b: Dictionary) -> bool:
	var start := Vector2(_anchor_x(a, b), float(a.y) - BODY_MID)
	var end := Vector2(_anchor_x(b, a), float(b.y) - BODY_MID)
	for i: int in LINE_SAMPLES + 1:
		var point := start.lerp(end, float(i) / float(LINE_SAMPLES))
		if _inside_any_solid(point):
			return false
	return true


## X on `surface` closest to `other` (the middle of the overlap when they overlap).
func _anchor_x(surface: Dictionary, other: Dictionary) -> float:
	if float(surface.x1) <= float(other.x0):
		return float(surface.x1)
	if float(other.x1) <= float(surface.x0):
		return float(surface.x0)
	return (maxf(float(surface.x0), float(other.x0)) + minf(float(surface.x1), float(other.x1))) * 0.5


func _inside_any_solid(point: Vector2) -> bool:
	for rect: Rect2 in solids:
		if rect.grow(-LINE_SHRINK).has_point(point):
			return true
	return false


func _add_free_segments(rect: Rect2) -> void:
	var free: Array[Vector2] = [Vector2(rect.position.x, rect.end.x)]
	for blocker: Rect2 in solids:
		if blocker.position.y < rect.position.y and blocker.end.y > rect.position.y - PLAYER_HEIGHT:
			free = _subtract(free, blocker.position.x, blocker.end.x)
	for hazard: Rect2 in hazards:
		if absf(hazard.end.y - rect.position.y) < 1.5:
			free = _subtract(free, hazard.position.x, hazard.end.x)
	for span: Vector2 in free:
		if span.y - span.x >= MIN_SURFACE_WIDTH:
			surfaces.append({"x0": span.x, "x1": span.y, "y": rect.position.y})


func _subtract(spans: Array[Vector2], cut_x0: float, cut_x1: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span: Vector2 in spans:
		if cut_x1 <= span.x or cut_x0 >= span.y:
			result.append(span)
			continue
		if cut_x0 > span.x:
			result.append(Vector2(span.x, cut_x0))
		if cut_x1 < span.y:
			result.append(Vector2(cut_x1, span.y))
	return result

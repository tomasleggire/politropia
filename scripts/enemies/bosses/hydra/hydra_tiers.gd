class_name HydraTiers
extends RefCounted

## The vertical map of the Hydra fight, read from the one-way platforms of the
## arena (group `hydra_platform`) instead of hardcoded heights, so a teammate can
## move the platforms and the heads, the sweep bands and the venom spots follow.
##
## A level is the y of a standing surface: the floor plus every distinct platform
## top, ordered from the floor upwards. The three heads sit at the lowest level,
## the middle one and the highest one (the head tiers).

const GROUP := &"hydra_platform"
## Two surfaces closer than this share a level.
const SAME_LEVEL := 1.0
## A platform top this far above the feet still counts as the surface under them.
const FEET_TOLERANCE := 6.0
const TIER_COUNT := 3
## Head tiers when the arena has too few platform levels to derive them.
const DEFAULT_TIER_STEP := 112.0

var floor_y := 0.0

var _tops: Array[Rect2] = []
var _levels: Array[float] = []


## Re-reads the platforms in the scene tree. `new_floor_y` is the floor surface.
func rebuild(tree: SceneTree, new_floor_y: float) -> void:
	floor_y = new_floor_y
	_tops.clear()
	_levels.clear()
	_levels.append(floor_y)
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		var top := _top_rect(node)
		if top.size.x <= 0.0:
			continue
		_tops.append(top)
		if top.position.y < floor_y - SAME_LEVEL and not _has_level(top.position.y):
			_levels.append(top.position.y)
	# Floor first: the largest y is the lowest surface.
	_levels.sort_custom(func(a: float, b: float) -> bool: return a > b)


## Standing surfaces from the floor up.
func levels() -> Array[float]:
	return _levels


func level_count() -> int:
	return _levels.size()


## World rectangles of the platform tops (x, surface y, width, thickness).
func platform_tops() -> Array[Rect2]:
	return _tops


## The y of the surface a head of `tier` (0 low, 1 mid, 2 high) reaches along.
func tier_y(tier: int) -> float:
	if _levels.size() >= TIER_COUNT:
		match tier:
			0:
				return _levels[0]
			1:
				return _levels[_levels.size() / 2]
			_:
				return _levels[_levels.size() - 1]
	return floor_y - DEFAULT_TIER_STEP * float(clampi(tier, 0, TIER_COUNT - 1))


## The head tier closest to Luz's feet (ties go to the lower one).
func tier_of(feet_y: float) -> int:
	var best := 0
	var best_gap := INF
	for tier: int in TIER_COUNT:
		var gap := absf(feet_y - tier_y(tier))
		if gap < best_gap - 0.001:
			best_gap = gap
			best = tier
	return best


## The y of the highest surface at `x` that is at or below `feet_y`; the floor
## when none is (a spot past a platform edge drops to the floor).
func surface_below(x: float, feet_y: float) -> float:
	var best := floor_y
	for top: Rect2 in _tops:
		if x < top.position.x or x > top.end.x:
			continue
		if top.position.y < feet_y - FEET_TOLERANCE:
			continue
		if top.position.y < best:
			best = top.position.y
	return best


func _has_level(y: float) -> bool:
	for level: float in _levels:
		if absf(level - y) <= SAME_LEVEL:
			return true
	return false


## The top of a platform body: its first rectangle shape, in world space.
func _top_rect(node: Node) -> Rect2:
	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return Rect2()
	var size := (shape_node.shape as RectangleShape2D).size
	var center := shape_node.global_position
	return Rect2(center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y)

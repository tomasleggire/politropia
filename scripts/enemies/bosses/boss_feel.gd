class_name BossFeel
extends RefCounted

## Static helpers for boss game feel: camera shakes and the final-blow slow
## motion. Static on purpose: the slow motion must be undone even when the boss
## and the arena that started it are already freed (a scene change, a free).

## Engine.time_scale during the freeze (a hit-stop for the whole world).
const FREEZE_SCALE := 0.05

static var _token := 0


## Shakes the current camera when it has the shake API (RoomCamera). A plain
## Camera2D or no camera is a no-op.
static func shake_camera(viewport: Viewport, strength: float, duration: float) -> void:
	if viewport == null or strength <= 0.0 or duration <= 0.0:
		return
	var camera := viewport.get_camera_2d()
	if camera != null and camera.has_method(&"shake"):
		camera.call(&"shake", strength, duration)


## A freeze of `freeze_time` then a slow motion of `slow_time` at `slow_scale`,
## both in REAL seconds, then back to 1.0. The timers belong to the SceneTree and
## ignore the time scale, so no node has to outlive the effect. A newer call
## replaces the one in progress.
static func slow_motion(tree: SceneTree, freeze_time: float, slow_time: float, slow_scale: float) -> void:
	_token += 1
	if freeze_time <= 0.0 and slow_time <= 0.0:
		Engine.time_scale = 1.0
		return
	if freeze_time > 0.0:
		Engine.time_scale = FREEZE_SCALE
		_real_timer(tree, freeze_time).timeout.connect(_begin_slow.bind(tree, _token, slow_time, slow_scale))
		return
	_begin_slow(tree, _token, slow_time, slow_scale)


## Puts the clock back at once and drops any pending restore (tests, new game).
static func cancel() -> void:
	_token += 1
	Engine.time_scale = 1.0


static func is_active() -> bool:
	return not is_equal_approx(Engine.time_scale, 1.0)


static func _begin_slow(tree: SceneTree, token: int, slow_time: float, slow_scale: float) -> void:
	if token != _token:
		return
	if slow_time <= 0.0:
		Engine.time_scale = 1.0
		return
	Engine.time_scale = clampf(slow_scale, FREEZE_SCALE, 1.0)
	_real_timer(tree, slow_time).timeout.connect(_restore.bind(token))


static func _restore(token: int) -> void:
	if token == _token:
		Engine.time_scale = 1.0


## Always processes, real time (ignores Engine.time_scale).
static func _real_timer(tree: SceneTree, seconds: float) -> SceneTreeTimer:
	return tree.create_timer(seconds, true, false, true)

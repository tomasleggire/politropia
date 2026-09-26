class_name RulerWeapon
extends Node2D

## Procedural wooden-ruler weapon layer. Luz's attack body frames no longer
## draw their own ruler (see tools/erase_luz_ruler.py) -- this node renders
## and animates the single ruler prop every attack now shows, positioned and
## rotated every frame from assets/player/luz/luz_attack_swings.json (the
## same swing model tools/generate_luz_slash_smears.py reads), so the ruler
## always visually reaches exactly as far as its crescent smear and hitbox,
## in every combo hit and in the up/crouch/air attacks. Presentation only:
## no collision, damage, or gameplay authority -- player.gd owns AttackHitbox
## independently and just tells this node which kind/facing to swing.
##
## Base anchoring (T3b-fix): the ruler's BASE is always the
## measured hand/grip pixel of whichever body frame the AnimatedSprite2D is
## currently showing (assets/player/luz/luz_ruler_anchors.json, folded into
## the swing model as measured_frame_grips/tips_native_px) -- never a
## parametric point on the swing arc, which is what let the ruler float
## detached from the hand. The TIP blends between that same frame's
## measured (original-art) tip and the swing model's arc/thrust tip: fully
## the measured art pose at the very start of windup and the very end of
## recovery, fully the swing model during the active window, eased across
## the rest of windup/recovery -- so the ruler always starts and ends in
## the hand's actual drawn pose and only leaves it to trace the swing while
## the hitbox is live.

const SWING_MODEL_PATH := "res://assets/player/luz/luz_attack_swings.json"

## Same numeric texture_filter as the character AnimatedSprite2D and
## PlayerSlashVfx (scripts/player/player_slash_vfx.gd), so the weapon reads
## consistently with the rest of Luz's art at the same display scale.
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Reference ruler texture, drawn once in world units (1 texture px = 1
## world unit at scale 1.0) so Sprite2D.scale.x = current_length / this
## stretches the ruler to any swing's current reach without re-rendering.
## THICKNESS is an absolute world-unit constant (never scaled); ~4 world/
## game px, matching the playtest-requested "about 4 game px wide" (the
## reference art in tools/art_sources/luz/source/ draws its ruler roughly
## 1/9-1/10 as thick as long, closer than the previous 9px/56px attempt).
const REF_LENGTH := 56
const REF_THICKNESS := 4
const TICK_SPACING := 5

const WOOD_FILL := Color(0.82, 0.66, 0.42)
const WOOD_TICK := Color(0.62, 0.46, 0.27)
const WOOD_OUTLINE := Color(0.28, 0.18, 0.10)

## Native sprite-sheet pixel anchor every clip's frames were repacked
## against (assets/player/luz/animation_manifest.json's "frame_anchor") and
## the same display_scale used everywhere else in Luz's art pipeline --
## converts luz_ruler_anchors.json's measured native px into the world
## units this node (and hitboxes/swing geometry) work in.
const FRAME_ANCHOR_NATIVE_PX := Vector2(256.0, 413.0)
const DISPLAY_SCALE := 0.175

var _swings: Dictionary
var _sprite: Sprite2D
var _body_sprite: AnimatedSprite2D

var _config: Dictionary
var _frame_grips: Array = []  # Array[Vector2], world units, per body frame index
var _frame_tips: Array = []  # Array[Vector2], world units, per body frame index
var _elapsed := 0.0
var _startup_time := 0.0
var _active_time := 0.0
var _window_end := 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	_swings = _read_swing_model()
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = TEXTURE_FILTER
	_sprite.texture = _build_ruler_texture()
	add_child(_sprite)


## Must be called once (e.g. from player.gd's _ready) before the first
## start_swing, so this node can read which of the 4 body frames is
## currently displayed and anchor the ruler's base to that exact frame's
## measured hand position.
func set_body_sprite(body_sprite: AnimatedSprite2D) -> void:
	_body_sprite = body_sprite


## Starts (or restarts) the procedural swing for one attack. startup_time /
## active_time / window_end mirror the caller's own attack-phase timings
## (player.gd's attack_startup_time/attack_active_time/attack window) so the
## ruler's windup -> active -> follow-through motion always lines up with
## the real hitbox activation regardless of tunable changes.
func start_swing(
	kind: StringName, facing: int, startup_time: float, active_time: float, window_end: float
) -> void:
	if not _swings.has(String(kind)):
		return
	_config = _swings[String(kind)]
	_frame_grips = _config["_frame_grips_world"]
	_frame_tips = _config["_frame_tips_world"]
	_startup_time = maxf(startup_time, 0.001)
	_active_time = maxf(active_time, 0.001)
	_window_end = maxf(window_end, _startup_time + _active_time + 0.001)
	_elapsed = 0.0
	scale = Vector2(1 if facing >= 0 else -1, 1)
	visible = true
	set_process(true)
	_update_pose(0.0)


func stop_swing() -> void:
	visible = false
	set_process(false)
	_elapsed = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _window_end:
		stop_swing()
		return
	_update_pose(_elapsed)


func _update_pose(t: float) -> void:
	var body_frame_index := 0
	if _body_sprite != null:
		body_frame_index = clampi(_body_sprite.frame, 0, _frame_grips.size() - 1)
	var art_grip: Vector2 = _frame_grips[body_frame_index]
	var art_tip: Vector2 = _frame_tips[body_frame_index]

	var phase_t := _phase_fraction(t)
	var weight := _art_blend_weight(phase_t)
	var swing_tip := _swing_tip_thrust(phase_t) if String(_config.get("type", "")) == "thrust" else _swing_tip_ellipse(phase_t)
	var blended_tip: Vector2 = art_tip.lerp(swing_tip, weight)

	_place_sprite(art_grip, blended_tip)


## Returns {phase, f} where phase is 0 (windup), 1 (active) or 2 (recovery)
## and f is that phase's 0..1 progress, used to interpolate both angle/
## length and reach fraction across the whole attack, not just the active
## window -- so the ruler is already rising into position during startup
## and settles smoothly afterward instead of popping.
func _phase_fraction(t: float) -> Dictionary:
	if t < _startup_time:
		return {"phase": 0, "f": clampf(t / _startup_time, 0.0, 1.0)}
	elif t < _startup_time + _active_time:
		return {"phase": 1, "f": clampf((t - _startup_time) / _active_time, 0.0, 1.0)}
	else:
		var recovery_time := maxf(_window_end - _startup_time - _active_time, 0.001)
		return {"phase": 2, "f": clampf((t - _startup_time - _active_time) / recovery_time, 0.0, 1.0)}


## 0 = fully the measured art pose (hand-drawn tip for the current body
## frame), 1 = fully the swing model. 1.0 for the whole active window (the
## hitbox is live -- the ruler must trace the real swing exactly), eased
## in across windup and back out across recovery so it never pops.
func _art_blend_weight(phase_t: Dictionary) -> float:
	var phase: int = phase_t["phase"]
	var f: float = phase_t["f"]
	match phase:
		0:
			return smoothstep(0.0, 1.0, f)
		1:
			return 1.0
		_:
			return smoothstep(0.0, 1.0, 1.0 - f)


func _swing_tip_ellipse(phase_t: Dictionary) -> Vector2:
	var size: Array = _config["hitbox_size"]
	var flare: float = _config["flare"]
	var rx: float = (float(size[0]) * 0.5) * flare
	var ry: float = (float(size[1]) * 0.5) * flare
	var tilt := deg_to_rad(float(_config["tilt_deg"]))
	var pivot := Vector2(_config["hitbox_offset"][0], _config["hitbox_offset"][1])

	var theta_deg := _interpolate(
		phase_t,
		float(_config["theta_windup"]), float(_config["theta_start"]),
		float(_config["theta_end"]), float(_config["theta_follow"]),
	)
	var reach := _reach_fraction(phase_t)
	var theta := deg_to_rad(theta_deg)
	var local := Vector2(rx * cos(theta), ry * sin(theta)) * reach
	return pivot + local.rotated(tilt)


func _swing_tip_thrust(phase_t: Dictionary) -> Vector2:
	var base := Vector2(_config["base"][0], _config["base"][1])
	var angle := deg_to_rad(float(_config["angle_deg"]))
	var direction := Vector2(cos(angle), sin(angle))
	var length := _interpolate(
		phase_t,
		float(_config["windup_length"]) * 0.4, float(_config["windup_length"]),
		float(_config["extend_length"]), float(_config["follow_length"]),
	)
	return base + direction * length


## Piecewise value across windup -> start -> end -> follow, keyed by the
## same three-phase timeline as _phase_fraction: windup->start during
## startup, start->end during the active window, end->follow during
## recovery.
func _interpolate(phase_t: Dictionary, windup: float, start: float, end: float, follow: float) -> float:
	var phase: int = phase_t["phase"]
	var f: float = phase_t["f"]
	match phase:
		0:
			return lerpf(windup, start, f)
		1:
			return lerpf(start, end, f)
		_:
			return lerpf(end, follow, f)


## Visual "stretch" of the swing-model tip along its arc/thrust: short
## during windup, reaching full extension partway through the active window
## (so the tip is at its farthest exactly when the hitbox is live), then a
## slight recoil through recovery. Only meaningful while _art_blend_weight
## is > 0; irrelevant once the pose is fully back at the measured art tip.
func _reach_fraction(phase_t: Dictionary) -> float:
	var phase: int = phase_t["phase"]
	var f: float = phase_t["f"]
	match phase:
		0:
			return lerpf(0.30, 0.55, f)
		1:
			return lerpf(0.55, 1.0, minf(f / 0.6, 1.0)) if f < 0.6 else lerpf(1.0, 0.92, (f - 0.6) / 0.4)
		_:
			return lerpf(0.92, 0.45, f)


func _place_sprite(base: Vector2, tip: Vector2) -> void:
	var delta := tip - base
	var length := maxf(delta.length(), 1.0)
	_sprite.position = base
	_sprite.rotation = delta.angle()
	_sprite.scale = Vector2(length / float(REF_LENGTH), 1.0)


func _build_ruler_texture() -> ImageTexture:
	var image := Image.create(REF_LENGTH, REF_THICKNESS, false, Image.FORMAT_RGBA8)
	for x in REF_LENGTH:
		for y in REF_THICKNESS:
			var color: Color
			var is_edge := y == 0 or y == REF_THICKNESS - 1 or x == 0 or x == REF_LENGTH - 1
			if is_edge:
				color = WOOD_OUTLINE
			elif (x % TICK_SPACING) == 0:
				color = WOOD_TICK
			else:
				color = WOOD_FILL
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## Converts assets/player/luz/luz_attack_swings.json's measured_frame_
## grips/tips_native_px (raw sprite-sheet pixels) into world-unit Vector2
## arrays once at load time, cached on each kind's config under
## "_frame_grips_world"/"_frame_tips_world".
static func _read_swing_model() -> Dictionary:
	var file := FileAccess.open(SWING_MODEL_PATH, FileAccess.READ)
	assert(file != null, "Cannot read Luz attack swing model")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid Luz attack swing model JSON")
	var kinds: Dictionary = parsed.get("kinds", {})
	for kind_name in kinds:
		var config: Dictionary = kinds[kind_name]
		config["_frame_grips_world"] = _native_px_to_world(config["measured_frame_grips_native_px"])
		config["_frame_tips_world"] = _native_px_to_world(config["measured_frame_tips_native_px"])
	return kinds


static func _native_px_to_world(points_native_px: Array) -> Array:
	var result: Array = []
	for point in points_native_px:
		var native := Vector2(point[0], point[1])
		result.append((native - FRAME_ANCHOR_NATIVE_PX) * DISPLAY_SCALE)
	return result

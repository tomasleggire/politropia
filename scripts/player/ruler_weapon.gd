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

const SWING_MODEL_PATH := "res://assets/player/luz/luz_attack_swings.json"

## Same numeric texture_filter as the character AnimatedSprite2D and
## PlayerSlashVfx (scripts/player/player_slash_vfx.gd), so the weapon reads
## consistently with the rest of Luz's art at the same display scale.
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Reference ruler texture, drawn once in world units (1 texture px = 1
## world unit at scale 1.0) so Sprite2D.scale.x = current_length / this
## stretches the ruler to any swing's current reach without re-rendering.
const REF_LENGTH := 56
const REF_THICKNESS := 9
const TICK_SPACING := 4

const WOOD_FILL := Color(0.82, 0.66, 0.42)
const WOOD_HIGHLIGHT := Color(0.90, 0.76, 0.53)
const WOOD_OUTLINE := Color(0.32, 0.21, 0.11)
const TICK_COLOR := Color(0.40, 0.27, 0.15)

var _swings: Dictionary
var _sprite: Sprite2D

var _active := false
var _elapsed := 0.0
var _config: Dictionary
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
	var phase_t := _phase_fraction(t)
	if String(_config.get("type", "")) == "thrust":
		_update_thrust(phase_t)
	else:
		_update_ellipse_arc(phase_t)


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


func _update_ellipse_arc(phase_t: Dictionary) -> void:
	var size: Array = _config["hitbox_size"]
	var flare: float = _config["flare"]
	var rx: float = (float(size[0]) * 0.5) * flare
	var ry: float = (float(size[1]) * 0.5) * flare
	var tilt := deg_to_rad(float(_config["tilt_deg"]))
	var pivot := Vector2(_config["hitbox_offset"][0], _config["hitbox_offset"][1])
	# Fraction of the ellipse radius the grip end sits at, vs. the tip at
	# radius 1.0 -- keeps the ruler's body-side end close to the swing pivot
	# (roughly the hand/shoulder) while the tip rides the full swing arc.
	var base_fraction: float = _config.get("base_radius_fraction", 0.22)

	var theta_deg := _interpolate(
		phase_t,
		float(_config["theta_windup"]), float(_config["theta_start"]),
		float(_config["theta_end"]), float(_config["theta_follow"]),
	)
	var reach := _reach_fraction(phase_t)
	var theta := deg_to_rad(theta_deg)
	var local := Vector2(rx * cos(theta), ry * sin(theta)) * reach
	var rotated := local.rotated(tilt)

	var tip := pivot + rotated
	var base := pivot + rotated * base_fraction
	_place_sprite(base, tip)


func _update_thrust(phase_t: Dictionary) -> void:
	var base := Vector2(_config["base"][0], _config["base"][1])
	var angle := deg_to_rad(float(_config["angle_deg"]))
	var direction := Vector2(cos(angle), sin(angle))
	var length := _interpolate(
		phase_t,
		float(_config["windup_length"]) * 0.4, float(_config["windup_length"]),
		float(_config["extend_length"]), float(_config["follow_length"]),
	)
	var tip := base + direction * length
	var grip := base + direction * (length * 0.12)
	_place_sprite(grip, tip)


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


## Visual "stretch" of the ruler along its swing radius/length: short during
## windup, reaching full extension partway through the active window (so
## the tip is at its farthest exactly when the hitbox is live), then a
## slight recoil through recovery.
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
			var color := Color(0, 0, 0, 0)
			var is_edge := y == 0 or y == REF_THICKNESS - 1 or x == 0 or x == REF_LENGTH - 1
			if is_edge:
				color = WOOD_OUTLINE
			elif (x % TICK_SPACING) == 0:
				color = TICK_COLOR
			elif y == 1:
				color = WOOD_HIGHLIGHT
			else:
				color = WOOD_FILL
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _read_swing_model() -> Dictionary:
	var file := FileAccess.open(SWING_MODEL_PATH, FileAccess.READ)
	assert(file != null, "Cannot read Luz attack swing model")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid Luz attack swing model JSON")
	return parsed.get("kinds", {})

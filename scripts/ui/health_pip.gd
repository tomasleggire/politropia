class_name HealthPip
extends Control

## One health point of the HUD. The placeholder look is neutral and drawn in
## code: a soft round gem when full, a dim hollow ring when empty. Final art
## replaces it by setting `full_texture` / `empty_texture`. Losing and
## refilling play short tweens; both kill the previous tween first and end by
## snapping to the target look, so rapid hits can never leave it mid-way.

const GEM := Color("efe6d4")
const GEM_RIM := Color("b9ad94")
const RING_EMPTY := Color(0.92, 0.89, 0.82, 0.32)
const RING_WIDTH := 2.0
const EDGE_INSET := 3.0

@export_group("Art")
## Optional art; when set it replaces the drawn placeholder.
@export var full_texture: Texture2D
@export var empty_texture: Texture2D

@export_group("Feedback")
@export var lose_time := 0.35
@export var shake_pixels := 4.0
@export var refill_time := 0.2
@export var pop_scale := 1.25
## Scale a pip shrinks to while it fades out on a loss.
@export var lose_shrink := 0.8

## 0 is empty, 1 is full; fractions fade the gem while it is changing.
var fill := 1.0:
	set(value):
		fill = value
		queue_redraw()
var flash := 0.0:
	set(value):
		flash = value
		queue_redraw()
var shake := 0.0:
	set(value):
		shake = value
		queue_redraw()

var _full := true
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5


func is_full() -> bool:
	return _full


## True while a lose or refill tween is still running.
func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Shows the final look at once, cancelling any tween.
func set_full(value: bool) -> void:
	_full = value
	_kill_tween()
	_snap()


func play_lose() -> void:
	_full = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_apply_loss, 0.0, 1.0, lose_time)
	_tween.tween_callback(_snap)


## Refills after `delay` seconds with a small pop.
func play_refill(delay: float) -> void:
	_full = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_interval(maxf(delay, 0.0))
	_tween.tween_method(_apply_refill, 0.0, 1.0, refill_time)
	_tween.tween_callback(_snap)


func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _snap() -> void:
	fill = 1.0 if _full else 0.0
	flash = 0.0
	shake = 0.0
	scale = Vector2.ONE


func _apply_loss(t: float) -> void:
	shake = sin(t * 60.0) * shake_pixels * (1.0 - t)
	flash = clampf(1.0 - t * 2.5, 0.0, 1.0)
	fill = clampf(1.0 - (t - 0.3) / 0.7, 0.0, 1.0)
	scale = Vector2.ONE * lerpf(1.0, lose_shrink, t)


func _apply_refill(t: float) -> void:
	fill = t
	scale = Vector2.ONE * lerpf(pop_scale, 1.0, t)


func _draw() -> void:
	draw_set_transform(Vector2(shake, 0.0))
	_draw_empty()
	if fill > 0.0:
		_draw_full()


func _draw_empty() -> void:
	if empty_texture != null:
		draw_texture_rect(empty_texture, Rect2(Vector2.ZERO, size), false)
		return
	draw_arc(size * 0.5, _radius(), 0.0, TAU, 32, RING_EMPTY, RING_WIDTH, true)


func _draw_full() -> void:
	var tint := Color.WHITE.lerp(Color(2.0, 2.0, 2.0), flash)
	tint.a = fill
	if full_texture != null:
		draw_texture_rect(full_texture, Rect2(Vector2.ZERO, size), false, tint)
		return
	var center := size * 0.5
	var rim := GEM_RIM * tint
	var body := GEM.lerp(Color.WHITE, flash)
	body.a = fill
	draw_circle(center, _radius(), rim)
	draw_circle(center, _radius() - 2.0, body)
	var shine := Color(1.0, 1.0, 1.0, 0.7 * fill)
	draw_circle(center + Vector2(-_radius() * 0.3, -_radius() * 0.3), _radius() * 0.25, shine)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - EDGE_INSET

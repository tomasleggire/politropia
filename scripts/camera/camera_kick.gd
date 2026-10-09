class_name CameraKick
extends RefCounted

## Short view jolt used by both cameras (RoomCamera and the player Camera2D).
## The offset jumps to `amplitude`, holds for `hold` seconds and then snaps
## back linearly over `decay` seconds (measured on the Penitent: ~2 frames at
## full amplitude, then ~3 frames back). Presentation only: the owner adds
## `offset()` to its own Camera2D.offset and calls `update` every tick.

var _amplitude := Vector2.ZERO
var _hold := 0.0
var _decay := 0.0
var _elapsed := 0.0
var _active := false


## A stronger kick replaces a weaker one in progress.
func start(amplitude: Vector2, hold: float, decay: float) -> void:
	if _active and amplitude.length() < offset().length():
		return
	_amplitude = amplitude
	_hold = maxf(hold, 0.0)
	_decay = maxf(decay, 0.001)
	_elapsed = 0.0
	_active = true


func update(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed >= _hold + _decay:
		cancel()


func cancel() -> void:
	_active = false
	_amplitude = Vector2.ZERO
	_elapsed = 0.0


func is_active() -> bool:
	return _active


func offset() -> Vector2:
	if not _active:
		return Vector2.ZERO
	if _elapsed <= _hold:
		return _amplitude
	return _amplitude * (1.0 - (_elapsed - _hold) / _decay)

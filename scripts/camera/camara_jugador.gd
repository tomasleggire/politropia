extends Camera2D

## Combat jolt (see CameraKick); the player calls kick() on a landed hit.
var _kick := CameraKick.new()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_to_group(&"player_camera")
	pass # Replace with function body.


func cambiar_region(
	izquierda: int,
	arriba: int,
	derecha: int,
	abajo: int
) -> void:
	limit_left=izquierda
	limit_right=derecha
	limit_bottom=abajo
	limit_top=arriba
	
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _kick.is_active():
		_kick.update(delta)
		offset = _kick.offset()


## Jolts the view by `amplitude` pixels (hold, then snap back over `decay`).
func kick(amplitude: Vector2, hold: float, decay: float) -> void:
	_kick.start(amplitude, hold, decay)
	offset = _kick.offset()


func cancel_kick() -> void:
	_kick.cancel()
	offset = Vector2.ZERO

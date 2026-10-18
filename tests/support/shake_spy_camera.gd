extends Camera2D
## Test double for the camera shake API (RoomCamera.shake): records every call as
## Vector2(strength, duration) so a suite can see which shakes were requested.

var shakes: Array[Vector2] = []


func shake(strength: float, duration: float) -> void:
	shakes.append(Vector2(strength, duration))


func has_shake(strength: float) -> bool:
	for entry: Vector2 in shakes:
		if is_equal_approx(entry.x, strength):
			return true
	return false

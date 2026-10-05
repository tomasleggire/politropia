class_name LuzOrbit
extends RefCounted

## Orbit maths shared by the FX that circle the seated Luz. Positions are in
## desk space (origin at the floor under the desk, y up is negative).

## Front passes must stay below the face line (seat is at y -26, face near -58).
const FACE_FLOOR_Y := -44.0
const SILHOUETTE_HALF_WIDTH := 20.0


static func point(center: Vector2, radii: Vector2, angle: float) -> Vector2:
	return center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)


## True when the orbiter may be drawn in front of Luz without crossing her
## face; otherwise it must stay behind her.
static func is_front(position: Vector2, angle: float) -> bool:
	if sin(angle) <= 0.0:
		return false
	return position.y >= FACE_FLOOR_Y or absf(position.x) > SILHOUETTE_HALF_WIDTH

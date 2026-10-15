class_name WallHurtbox
extends Area2D

## Hit area of a `BreakableWall`. Luz's attack hitbox only reports areas and
## bodies on the enemies' physics layer, and it never sees a plain static body,
## so the wall carries this area and passes every hit up to itself.


## Same signature enemies use; the wall decides whether the hit counts.
func receive_hit(damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	var wall := get_parent() as BreakableWall
	return wall != null and wall.receive_hit(damage, source_position, attack_name)

@tool
class_name Walker
extends Enemy

## Patrols its platform edge to edge (the Crawlid): turns at a ledge, found
## with a floor ray ahead of its front edge, and at a wall. It never chases.
## Placeholder visuals only; the Greek look comes later.

@export_group("Patrol")
@export var walk_speed := 60.0
## How far ahead of the front edge the floor ray looks.
@export var ledge_probe_ahead := 4.0
## A drop deeper than this counts as a ledge.
@export var ledge_probe_depth := 12.0

@onready var _floor_probe: RayCast2D = $FloorProbe

var _half_width := 20.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var body := $CollisionShape2D as CollisionShape2D
	if body.shape is RectangleShape2D:
		_half_width = (body.shape as RectangleShape2D).size.x * 0.5
	_aim_probe()


func _think(_delta: float) -> void:
	if is_on_floor() and (is_on_wall() or not _has_floor_ahead()):
		_turn_around()
	velocity.x = float(_facing) * walk_speed


func _reset_ai() -> void:
	if is_node_ready():
		_aim_probe()


func _on_player_found(player: Node) -> void:
	_floor_probe.add_exception(player as CollisionObject2D)


func _has_floor_ahead() -> bool:
	_floor_probe.force_raycast_update()
	return _floor_probe.is_colliding()


func _turn_around() -> void:
	_facing = -_facing
	_apply_visual()
	_aim_probe()


## The ray starts a little above the feet, ahead of the front edge, and looks
## down past the floor surface by `ledge_probe_depth`.
func _aim_probe() -> void:
	_floor_probe.position = Vector2(float(_facing) * (_half_width + ledge_probe_ahead), -4.0)
	_floor_probe.target_position = Vector2(0.0, 4.0 + ledge_probe_depth)

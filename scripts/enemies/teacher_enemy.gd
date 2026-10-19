class_name Teacher_enemy
extends Enemy


@export_group("Patrullaje")
@export var walk_speed: float = 40.0
@export var turn_cooldown_duration: float = 0.25
@export var ledge_check_distance: float = 14.0
@export var ledge_check_depth: float = 20.0

var turn_cooldown: float = 0.0

@onready var ledge_ray: RayCast2D = get_node_or_null("LedgeRayCast")
@onready var sprite: AnimatedSprite2D = get_node_or_null(
	"AnimatedSprite2D"
)


func _ready() -> void:
	_facing = 1
	start_facing = 1
	super._ready()
	
	if ledge_ray:
		ledge_ray.collision_mask = WORLD_MASK
		ledge_ray.enabled = true
		ledge_ray.target_position = Vector2(0, ledge_check_depth)

	_update_direction()
	_play_walk_animation()

# Enemy.gd llama a este método desde su propio _physics_process().
func _think(delta: float) -> void:
	if turn_cooldown > 0.0:
		turn_cooldown -= delta

	# Camina en la dirección actual.

	velocity.x = _facing * walk_speed

	if turn_cooldown > 0.0:
		return

	# Detecta si hay una pared delante.
	var wall_ahead := is_on_wall()

	# Detecta si falta suelo delante.
	var edge_ahead := false

	if ledge_ray:
		ledge_ray.force_raycast_update()
		edge_ahead = not ledge_ray.is_colliding()

	if wall_ahead or edge_ahead:
		_turn_around()


func _turn_around() -> void:
	_facing *= -1
	turn_cooldown = turn_cooldown_duration

	_update_direction()

func _update_direction() -> void:
	if sprite:
		sprite.flip_h = _facing < 0

	if ledge_ray:
		ledge_ray.position.x = absf(ledge_check_distance) * _facing
		ledge_ray.target_position = Vector2(0, ledge_check_depth)



func _play_walk_animation() -> void:
	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("walk"):
			sprite.play("walk")


func _reset_ai() -> void:
	# Se ejecuta al reiniciar el enemigo desde el sistema base.
	turn_cooldown = 0.0
	velocity = Vector2.ZERO

	_update_direction()
	_play_walk_animation()

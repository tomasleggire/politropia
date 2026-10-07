@tool
class_name SpikeStrip
extends ContactDamage

const MODULE_WIDTH := 16
const MODULE_HEIGHT := 44
const CATCH_FLOOR_THICKNESS := 4
const CATCH_FLOOR_LAYER := 1

@export_range(1, 32) var count: int = 1:
	set(value):
		count = value
		_refresh()

## Encoge la caja de daño en los extremos (izq/der) para permitir saltar desde el borde.
@export_range(0.0, 16.0, 0.5) var edge_tolerance: float = 4.0:
	set(value):
		edge_tolerance = value
		_refresh()

## Empuja la caja de daño hacia abajo para que la punta visual no lastime al rozarla saltando.
@export_range(0.0, 24.0, 0.5) var hitbox_top_offset: float = 10.0:
	set(value):
		hitbox_top_offset = value
		_refresh()

## Si el jugador sube más rápido que esto (px/s), los pinchos no le hacen daño.
## Cubre el salto con coyote time justo en el borde.
@export var rising_grace_speed: float = 60.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D
var _catch_floor_shape: CollisionShape2D


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_catch_floor()
	_refresh()
	if Engine.is_editor_hint():
		return
	kind = Kind.HAZARD
	super._ready()


func _validate_property(property: Dictionary) -> void:
	if property.name == "kind":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if has_overlapping_bodies():
		for body in get_overlapping_bodies():
			_try_hurt(body)


## No hay daño mientras el jugador sube (salto desde el borde con coyote time).
func _try_hurt(body: Node2D) -> void:
	var player := body as Player
	if player != null and player.velocity.y < -rising_grace_speed:
		return
	super._try_hurt(body)


func get_world_rect() -> Rect2:
	var rect_shape := _shape.shape as RectangleShape2D if _shape != null else null
	if rect_shape == null:
		return super.get_world_rect()
	return Rect2(
		global_position + _shape.position - rect_shape.size * 0.5,
		rect_shape.size
	)


func _build_catch_floor() -> void:
	var body := StaticBody2D.new()
	body.name = "CatchFloor"
	body.collision_layer = CATCH_FLOOR_LAYER
	body.collision_mask = 0
	_catch_floor_shape = CollisionShape2D.new()
	_catch_floor_shape.one_way_collision = true
	body.add_child(_catch_floor_shape)
	add_child(body)


func _refresh() -> void:
	if not is_node_ready():
		return
	var width := MODULE_WIDTH * count
	var half_height := MODULE_HEIGHT * 0.5

	_sprite.centered = true
	_sprite.position = Vector2.ZERO
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, width, MODULE_HEIGHT)

	# Hitbox de daño: rectángulo normal, achicado por los dos parámetros.
	var hit_width := maxf(width - (edge_tolerance * 2.0), 1.0)
	var hit_height := maxf(MODULE_HEIGHT - hitbox_top_offset, 1.0)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(hit_width, hit_height)
	_shape.shape = rect
	_shape.position = Vector2(0.0, hitbox_top_offset * 0.5)

	# Piso de rescate al fondo: queda dentro de la zona de daño,
	# así que nunca se puede caminar sobre los pinchos.
	if _catch_floor_shape != null:
		var floor_rect := RectangleShape2D.new()
		floor_rect.size = Vector2(width, CATCH_FLOOR_THICKNESS)
		_catch_floor_shape.shape = floor_rect
		_catch_floor_shape.position = Vector2(0.0, half_height - CATCH_FLOOR_THICKNESS * 0.5)
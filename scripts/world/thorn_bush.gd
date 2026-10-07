@tool
class_name ThornBush
extends ContactDamage


enum Behavior { KNOCKBACK, RETURN_TO_SAFE_GROUND }

## Cantidad de arbustos apilados en vertical a lo largo de la pared. El
## conjunto queda centrado en el origen y el hitbox cubre toda la pila.
@export_range(1, 32) var count: int = 1:
	set(value):
		count = value
		_refresh()

## Alto de UN arbusto en pantalla (px). El ancho se calcula con la proporción del
## PNG. Luz mide ~58 px de alto.
@export_range(8.0, 800.0, 1.0) var display_height: float = 96.0:
	set(value):
		display_height = value
		_refresh()

## Espeja el arbusto: las espinas apuntan hacia la izquierda (pared a la derecha).
@export var flip_h: bool = false:
	set(value):
		flip_h = value
		_refresh()

@export var behavior: Behavior = Behavior.KNOCKBACK

## Tamaño del hitbox como fracción del arte. Más chico que el arte a propósito:
## las puntas sueltas del borde no deberían doler. Anclado del lado de la pared.
@export_range(0.05, 1.0, 0.01) var hitbox_width_ratio: float = 0.6:
	set(value):
		hitbox_width_ratio = value
		_refresh()

@export_range(0.05, 1.0, 0.01) var hitbox_height_ratio: float = 0.65:
	set(value):
		hitbox_height_ratio = value
		_refresh()

## Desplaza el hitbox en px. X: positivo = hacia las espinas (se invierte solo
## con Flip H). Y: positivo = hacia abajo.
@export var hitbox_offset: Vector2 = Vector2.ZERO:
	set(value):
		hitbox_offset = value
		_refresh()

## Si es true, el tajo hacia abajo de Luz rebota en el arbusto (pogo).
## Solo tiene efecto en KNOCKBACK; en RETURN_TO_SAFE_GROUND siempre rebota.
@export var pogoable: bool = false

var _sprite: Sprite2D
var _shape: CollisionShape2D


func _ready() -> void:
	_ensure_children()
	_refresh()
	if Engine.is_editor_hint():
		return
	kind = Kind.HAZARD if behavior == Behavior.RETURN_TO_SAFE_GROUND else Kind.ENEMY
	super._ready()
	if pogoable and kind == Kind.ENEMY:
		add_to_group(POGO_GROUP)
		collision_layer = POGO_LAYER


## Oculta "kind" del Inspector: lo decide "behavior".
func _validate_property(property: Dictionary) -> void:
	if property.name == "kind":
		property.usage = PROPERTY_USAGE_NO_EDITOR


## El hitbox está desplazado del origen, así que el rect del mundo (que usa el
## jugador para el pogo y la zona segura) se calcula con el offset real.
func get_world_rect() -> Rect2:
	var rect_shape := _shape.shape as RectangleShape2D if _shape != null else null
	if rect_shape == null:
		return super.get_world_rect()
	return Rect2(
		global_position + _shape.position - rect_shape.size * 0.5,
		rect_shape.size
	)


## Reutiliza "Sprite2D" / "CollisionShape2D" si la escena ya los tiene (los
## nombres importan: ContactDamage busca "CollisionShape2D"); si no, los crea.
## Sin "owner", no se guardan en el .tscn.
func _ensure_children() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	if not _sprite.texture_changed.is_connected(_refresh):
		_sprite.texture_changed.connect(_refresh)
	_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		add_child(_shape)


func _get_configuration_warnings() -> PackedStringArray:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return PackedStringArray(["Agregá un hijo Sprite2D llamado \"Sprite2D\" con la textura del arbusto."])
	return PackedStringArray()


func _refresh() -> void:
	if not is_node_ready() or _sprite == null or _shape == null:
		return

	# "unit" = tamaño en pantalla de UN arbusto.
	var unit := Vector2(display_height, display_height)
	var texture := _sprite.texture
	_sprite.centered = false
	_sprite.flip_h = flip_h
	# El arte se reduce mucho: mipmaps evitan el centelleo/dientes de sierra.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if texture != null:
		var tex_size := texture.get_size()
		var factor := display_height / maxf(tex_size.y, 1.0)
		_sprite.scale = Vector2(factor, factor)
		# Una sola región que repite el PNG "count" veces en vertical.
		_sprite.region_enabled = true
		_sprite.region_rect = Rect2(Vector2.ZERO, Vector2(tex_size.x, tex_size.y * count))
		unit = tex_size * factor
	else:
		_sprite.scale = Vector2.ONE
		_sprite.region_enabled = false

	# Origen = centro del borde de la pared, centrado en toda la pila.
	# Sin flip el arte crece hacia +x.
	var total_height := unit.y * count
	var side := -1.0 if flip_h else 1.0
	_sprite.position = Vector2(-unit.x if flip_h else 0.0, -total_height * 0.5)

	# Hitbox: ancho de un arbusto; alto de la pila con el mismo margen en los
	# extremos que tendría un solo arbusto (hitbox_height_ratio).
	var rect := RectangleShape2D.new()
	rect.size = Vector2(
		unit.x * hitbox_width_ratio,
		unit.y * (float(count) - 1.0 + hitbox_height_ratio)
	)
	_shape.position = Vector2(
		side * (rect.size.x * 0.5 + hitbox_offset.x), hitbox_offset.y
	)
	_shape.shape = rect
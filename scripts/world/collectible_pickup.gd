class_name CollectiblePickup
extends Area2D

## A collectible object in the world. Drop `scenes/world/collectible_pickup.tscn`
## into a level and assign a `CollectibleDefinition` in the Inspector.
##
## It only reacts to bodies in the project's `player` group. The session state
## lives in the `Collectibles` autoload, so the object never talks to the
## gallery or to other UI. If the ID was already collected, the object removes
## itself as soon as the level loads.

signal collected(id: String)

const PLAYER_GROUP := &"player"
const PICKUP_GROUP := &"collectible_pickups"
const ICON_PIXELS := 26.0

@export_group("Collectible")
## Definition of this object. Its `id` must exist in the collectibles catalog.
@export var definition: CollectibleDefinition
## Seconds of the small pickup animation before freeing the node. Set it to 0
## to remove the object at once. Collection is registered before it starts.
@export_range(0.0, 1.5, 0.05) var collect_animation_time := 0.28
## Small vertical movement while the object waits in the level.
@export var bob_amplitude := 4.0
@export var bob_speed := 1.6
## Color of the provisional diamond shown when the definition has no image.
@export var placeholder_color := Color(0.36, 0.85, 0.95, 1.0)

@onready var _icon: Sprite2D = $Icon
@onready var _placeholder: Polygon2D = $Placeholder
@onready var _collision: CollisionShape2D = $CollisionShape2D

var _collected := false
var _base_y := 0.0
var _time := 0.0
var _bob_tween: Tween


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	add_to_group(PICKUP_GROUP)
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	monitoring = true
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	_apply_visuals()

	var manager := _manager()
	var id := collectible_id()
	if id.is_empty() or manager == null:
		push_warning("CollectiblePickup at %s has no valid definition or manager." % get_path())
		_deactivate()
		return
	if manager.has_collected(id):
		_collected = true
		visible = false
		_deactivate()
		queue_free()
		return
	_start_bob()


func collectible_id() -> String:
	return definition.id if definition != null else ""


## True as soon as the collection was accepted, even while the fading
## animation still plays. Useful for tests and for other level logic.
func is_collected() -> bool:
	return _collected


## Stops the idle bob so a delivery animation can control the node.
func suspend_idle_motion() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_bob_tween = null


## Restarts the idle bob from the current position.
func resume_idle_motion() -> void:
	if _collected or not is_inside_tree():
		return
	_base_y = position.y
	_start_bob()


## Plays the NPC hand-over intro. The pickup must already be in the tree at
## `from`. It fades/scales in, flies in a small arc, bounces once and only then
## becomes collectable.
func play_delivery(from: Vector2, landing: Vector2, arc_height: float, duration: float) -> void:
	if _collected or not is_inside_tree():
		return
	suspend_idle_motion()
	_set_collect_enabled(false)
	global_position = from
	scale = Vector2(0.35, 0.35)
	modulate.a = 0.0

	var total := maxf(duration, 0.35)
	var appear := minf(0.14, total * 0.22)
	var flight := total * 0.52
	var bounce := total * 0.14
	var settle := maxf(total - appear - flight - bounce * 2.0, 0.05)
	var apex := from.lerp(landing, 0.5) + Vector2(0.0, -maxf(arc_height, 2.0))

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, appear)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, appear).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "global_position", apex, flight * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", landing, flight * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var bounce_height := maxf(arc_height * 0.22, 2.0)
	tween.tween_property(self, "global_position:y", landing.y - bounce_height, bounce).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position:y", landing.y, bounce).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_interval(settle)
	await tween.finished

	if not is_inside_tree() or _collected:
		return
	global_position = landing
	_set_collect_enabled(true)
	resume_idle_motion()


func _manager() -> Node:
	return get_node_or_null("/root/Collectibles")


func _apply_visuals() -> void:
	if definition == null or definition.image == null:
		_icon.visible = false
		_placeholder.visible = true
		_placeholder.color = placeholder_color
		return

	_icon.texture = definition.image
	var texture_size := definition.image.get_size()
	var largest := maxf(texture_size.x, texture_size.y)
	if largest > 0.0:
		_icon.scale = Vector2.ONE * (ICON_PIXELS / largest)
	# Show the icon only after its final scale is set: otherwise the renderer can
	# present one frame of the raw texture at full size when the node enters.
	_icon.visible = true
	_placeholder.visible = false


func _start_bob() -> void:
	_bob_tween = create_tween().set_loops()
	_bob_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var lowest := _base_y + bob_amplitude
	var highest := _base_y - bob_amplitude
	_bob_tween.tween_property(self, "position:y", lowest, bob_speed).from(_base_y)
	_bob_tween.tween_property(self, "position:y", highest, bob_speed * 2.0).from(lowest)
	_bob_tween.tween_property(self, "position:y", _base_y, bob_speed).from(highest)


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group(PLAYER_GROUP):
		return
	var manager := _manager()
	var id := collectible_id()
	if manager == null or id.is_empty():
		return

	var accepted: bool = manager.try_collect(id)
	_collected = true
	# Disabling monitoring directly inside body_entered is forbidden while the
	# physics server flushes queries. Deferring it takes effect this frame.
	_deactivate()
	if not accepted:
		queue_free()
		return

	collected.emit(id)
	_play_collect_animation()


func _set_collect_enabled(enabled: bool) -> void:
	monitoring = enabled
	if _collision != null:
		_collision.set_deferred("disabled", not enabled)


func _deactivate() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if _collision != null:
		_collision.set_deferred("disabled", true)


func _play_collect_animation() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	if collect_animation_time <= 0.0:
		queue_free()
		return
	var fade := create_tween().set_parallel(true)
	fade.tween_property(self, "scale", Vector2(1.3, 1.3), collect_animation_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(self, "modulate:a", 0.0, collect_animation_time).set_trans(Tween.TRANS_SINE)
	fade.chain().tween_callback(queue_free)

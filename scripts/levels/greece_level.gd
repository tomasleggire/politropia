extends Node2D

## Greece level skeleton: builds placeholder collision and visuals from
## GreeceLayout and clamps the camera to the room Luz is in. Art and abilities
## come in later tasks.

const VOID_COLOR := Color("05060a")
const SOLID_COLOR := Color("3a3f4d")
const ONE_WAY_COLOR := Color("5c7ea8")
const ROOM_COLORS := {
	"T1": Color("2b3a4a"),
	"T2": Color("2f4046"),
	"T3": Color("4a3030"),
	"Shaft": Color("26293a"),
	"ShaftAlcove": Color("3a3350"),
	"Altar": Color("40382a"),
	"Exit": Color("2a4034"),
	"Entrada": Color("2a2f3f"),
	"B2": Color("30343f"),
	"B3": Color("3a2f3f"),
}
const MARKER_COLORS := {
	"greece_medal_spot": Color("f2c94c"),
	"greece_exit_door": Color("56d6a0"),
	"greece_boss_arena": Color("e05252"),
	"greece_double_jump_gate": Color("b07cf0"),
}
const MARKER_RADIUS := 14.0
const PLAYER_COLLISION_LAYER := 1
const PLACEHOLDER_COLOR := Color("fff2a8")
const PLACEHOLDER_PICKUP_RADIUS := 26.0
const CONTACT_DAMAGE_SCENE := preload("res://scenes/world/contact_damage.tscn")
const BOOK_FLYER_SCENE := preload("res://scenes/enemies/book_flyer.tscn")
const SPIKE_COLOR := Color("c0392b")
const SPIKE_TOOTH_WIDTH := 16.0
const SPIKES_GROUP := &"greece_spikes"
const ENEMY_SCENES := {
	GreeceLayout.WALKER: preload("res://scenes/enemies/walker.tscn"),
	GreeceLayout.FLYER: preload("res://scenes/enemies/flyer.tscn"),
	GreeceLayout.CHARGER: preload("res://scenes/enemies/charger.tscn"),
	GreeceLayout.SHOOTER: preload("res://scenes/enemies/shooter.tscn"),
}
const OUT_OF_BOUNDS_MARGIN := 200.0
const BODY_CENTER_OFFSET := GreeceLayout.BODY_CENTER_OFFSET

## Emitted when Luz moves from one camera room to another (a doorway
## transition, or a respawn or hazard return that lands in a different room).
## `from_room` and `to_room` are GreeceLayout room names, with the medal alcove
## counted as part of "Shaft". The EnemyRegistry listens: entering a room
## resets its living enemies to their spawn and pauses every other room.
signal room_changed(from_room: StringName, to_room: StringName)

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _desk: Node2D = $StillnessDesk
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _solids: Node2D = $Solids
@onready var _markers: Node2D = $Markers

var _room := ""
var _camera_bounds := Rect2()
var _doors: Array[Dictionary] = []
var _transition := RoomTransition.new()


func _ready() -> void:
	# Player already adds itself to the "player" group in its own _ready().
	_desk.position = GreeceLayout.DESK_POSITION
	_player.position = GreeceLayout.SPAWN
	_camera.target = _player
	_camera.world_size = GreeceLayout.WORLD_SIZE
	_doors = GreeceLayout.doorways()
	_build_backgrounds()
	_build_collision()
	_build_markers()
	_build_double_jump_placeholder()
	_build_hazards()
	_build_enemies()
	_transition.name = "RoomTransition"
	_transition.setup(_player, _camera)
	_transition.room_switched.connect(_on_room_switched)
	add_child(_transition)
	room_changed.connect(_on_room_changed)
	_player.respawned.connect(_on_player_reset)
	_player.safe_ground_returned.connect(_enter_room_snapped)
	CheckpointService.restore_player_for_scene(_player, scene_file_path)
	_enter_room_snapped()


func _exit_tree() -> void:
	# Lift the off-room pause so other levels' enemies are never frozen.
	EnemyRegistry.set_active_room(&"")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if _player.global_position.y > GreeceLayout.WORLD_SIZE.y + OUT_OF_BOUNDS_MARGIN:
		_player.fall_out_of_bounds()
		return
	_follow_room()


## The camera room Luz is in (the alcove counts as the shaft).
func get_room() -> StringName:
	return StringName(_room)


## Starts a doorway transition when her body centre crosses into the other
## room's half of a passage. Anywhere else the camera room simply follows her
## (a respawn or hazard return can land her in another room): bounds switch at
## once, which is hidden by the fade those already play.
func _follow_room() -> void:
	if _transition.is_active():
		return
	var center := _player.global_position + BODY_CENTER_OFFSET
	if not _player.is_input_locked():
		var crossing := GreeceLayout.transition_for(center, _room, _doors)
		if not crossing.is_empty():
			_transition.begin(crossing["door"], crossing["from"], crossing["to"])
			return
	if GreeceLayout.in_transition_door(center, _room, _doors):
		return
	var room := GreeceLayout.camera_room(GreeceLayout.room_for(center, _room))
	if room != _room:
		_switch_room(room)


func _on_room_changed(_from_room: StringName, to_room: StringName) -> void:
	EnemyRegistry.enter_room(to_room)


func _on_room_switched(_from_room: String, to_room: String) -> void:
	_set_room(to_room)
	_camera_bounds = GreeceLayout.camera_bounds(to_room)


## After a respawn: the death fade already covers the cut, and she wakes with
## no doorway walk-out.
func _on_player_reset() -> void:
	_transition.abort()
	_enter_room_snapped()


## After a spawn, respawn, checkpoint restore or hazard return: pick the room
## and jump to it.
func _enter_room_snapped() -> void:
	_switch_room(GreeceLayout.camera_room(GreeceLayout.room_for(_player.global_position + BODY_CENTER_OFFSET, "")))


func _switch_room(room: String) -> void:
	_set_room(room)
	_camera_bounds = GreeceLayout.camera_bounds(room)
	_camera.set_room_bounds(_camera_bounds, 0.0)
	_camera.snap_to_target()


func _set_room(room: String) -> void:
	var previous := _room
	_room = room
	if previous == "":
		EnemyRegistry.set_active_room(StringName(room))
	elif previous != room:
		room_changed.emit(StringName(previous), StringName(room))


func _build_backgrounds() -> void:
	var world := Rect2(Vector2.ZERO, GreeceLayout.WORLD_SIZE)
	LevelGeometry.add_color_rect(_backgrounds, world, VOID_COLOR, -40)
	var rooms := GreeceLayout.rooms()
	for room_name: String in rooms:
		var rect: Rect2 = rooms[room_name]
		var visual := LevelGeometry.add_color_rect(_backgrounds, rect, ROOM_COLORS[room_name], -30)
		visual.name = room_name


func _build_collision() -> void:
	for rect: Rect2 in GreeceLayout.solids():
		LevelGeometry.add_solid(_solids, rect, SOLID_COLOR)
	for rect: Rect2 in GreeceLayout.one_ways():
		LevelGeometry.add_one_way_platform(_solids, rect, ONE_WAY_COLOR)


func _build_markers() -> void:
	var markers := GreeceLayout.markers()
	for marker_name: String in markers:
		var marker := Marker2D.new()
		marker.name = marker_name
		marker.position = markers[marker_name]
		var group := GreeceLayout.marker_group(marker_name)
		marker.add_to_group(group)
		marker.add_child(_make_diamond(MARKER_COLORS[group]))
		_markers.add_child(marker)


## Temporary stand-in for the boss reward: touching it unlocks the double jump
## for this run only (nothing is persisted).
func _build_double_jump_placeholder() -> void:
	var pickup := Area2D.new()
	pickup.name = "DoubleJumpPlaceholder"
	pickup.position = GreeceLayout.markers()["BossArena"] + BODY_CENTER_OFFSET
	pickup.collision_layer = 0
	pickup.collision_mask = PLAYER_COLLISION_LAYER
	pickup.add_to_group(&"greece_placeholder")
	var circle := CircleShape2D.new()
	circle.radius = PLACEHOLDER_PICKUP_RADIUS
	var shape := CollisionShape2D.new()
	shape.shape = circle
	pickup.add_child(shape)
	pickup.add_child(_make_diamond(PLACEHOLDER_COLOR))
	pickup.body_entered.connect(_on_double_jump_placeholder_touched.bind(pickup))
	_markers.add_child(pickup)


func _on_double_jump_placeholder_touched(body: Node2D, pickup: Area2D) -> void:
	if body != _player:
		return
	_player.unlock_double_jump()
	pickup.hide()
	pickup.set_deferred("monitoring", false)


## Spike rows: red teeth that hurt on contact.
func _build_hazards() -> void:
	for rect: Rect2 in GreeceLayout.hazards():
		var hazard := CONTACT_DAMAGE_SCENE.instantiate() as ContactDamage
		hazard.name = "Spikes"
		hazard.kind = ContactDamage.Kind.HAZARD
		hazard.position = rect.get_center()
		hazard.add_to_group(SPIKES_GROUP)
		hazard.add_child(_make_spike_row(rect.size))
		_markers.add_child(hazard)
		hazard.set_area_size(rect.size)


## Instantiates every placement of `GreeceLayout.enemies()` before the first
## room is entered, so the registry can pause the ones outside it.
func _build_enemies() -> void:
	var holder := Node2D.new()
	holder.name = "Enemies"
	add_child(holder)
	for entry: Dictionary in GreeceLayout.enemies():
		var packed_scene: PackedScene = BOOK_FLYER_SCENE \
				if entry.get("variant", &"") == &"book" \
				else ENEMY_SCENES[entry["archetype"]]
		var enemy := packed_scene.instantiate() as Enemy
		enemy.name = entry["enemy_id"]
		enemy.enemy_id = entry["enemy_id"]
		enemy.start_facing = entry["facing"]
		enemy.position = entry["position"]
		holder.add_child(enemy)


## A row of triangular teeth filling `size`; the last tooth is narrower.
func _make_spike_row(size: Vector2) -> Node2D:
	var row := Node2D.new()
	row.z_index = 10
	var half := size * 0.5
	var x := -half.x
	while x < half.x:
		var x1 := minf(x + SPIKE_TOOTH_WIDTH, half.x)
		row.add_child(_make_polygon(SPIKE_COLOR, [
			Vector2(x, half.y), Vector2((x + x1) * 0.5, -half.y), Vector2(x1, half.y),
		]))
		x = x1
	return row


func _make_polygon(color: Color, points: Array[Vector2]) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.color = color
	polygon.polygon = PackedVector2Array(points)
	return polygon


func _make_diamond(color: Color) -> Polygon2D:
	var diamond := Polygon2D.new()
	diamond.color = color
	diamond.z_index = 10
	diamond.polygon = PackedVector2Array([
		Vector2(0.0, -MARKER_RADIUS),
		Vector2(MARKER_RADIUS, 0.0),
		Vector2(0.0, MARKER_RADIUS),
		Vector2(-MARKER_RADIUS, 0.0),
	])
	return diamond

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
const HAZARD_COLOR := Color("c0392b")
const HAZARD_STRIPE_COLOR := Color("1a0d0d")
const HAZARD_STRIPE_WIDTH := 16.0
const OUT_OF_BOUNDS_MARGIN := 200.0
## Centre of the standing collider, relative to the feet the player node sits on.
const BODY_CENTER_OFFSET := Vector2(0.0, -29.0)

@onready var _player: Player = $Player
@onready var _camera: RoomCamera = $RoomCamera
@onready var _desk: Node2D = $StillnessDesk
@onready var _backgrounds: Node2D = $Backgrounds
@onready var _solids: Node2D = $Solids
@onready var _markers: Node2D = $Markers

var _room := ""
var _camera_bounds := Rect2()


func _ready() -> void:
	# Player already adds itself to the "player" group in its own _ready().
	_desk.position = GreeceLayout.DESK_POSITION
	_player.position = GreeceLayout.SPAWN
	_camera.target = _player
	_camera.world_size = GreeceLayout.WORLD_SIZE
	_build_backgrounds()
	_build_collision()
	_build_markers()
	_build_double_jump_placeholder()
	_build_hazards()
	_player.respawned.connect(_enter_room_snapped)
	_player.safe_ground_returned.connect(_enter_room_snapped)
	CheckpointService.restore_player_for_scene(_player, scene_file_path)
	_enter_room_snapped()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if _player.global_position.y > GreeceLayout.WORLD_SIZE.y + OUT_OF_BOUNDS_MARGIN:
		_player.fall_out_of_bounds()
		return
	_follow_room()


## Moves the camera onto the room Luz stands in, blending when it changes.
func _follow_room() -> void:
	var room := GreeceLayout.room_for(_player.global_position + BODY_CENTER_OFFSET, _room)
	if room != _room:
		_room = room
		_apply_camera_bounds(-1.0)


## After a spawn, respawn or checkpoint restore: pick the room and jump to it.
func _enter_room_snapped() -> void:
	_room = GreeceLayout.room_for(_player.global_position + BODY_CENTER_OFFSET, "")
	_apply_camera_bounds(0.0)
	_camera.snap_to_target()


func _apply_camera_bounds(transition_time: float) -> void:
	var bounds := GreeceLayout.camera_bounds(_room)
	if bounds != _camera_bounds or transition_time == 0.0:
		_camera_bounds = bounds
		_camera.set_room_bounds(bounds, transition_time)


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


## Marked placeholder hazards: red striped strips that hurt on contact.
func _build_hazards() -> void:
	for rect: Rect2 in GreeceLayout.hazards():
		var hazard := CONTACT_DAMAGE_SCENE.instantiate() as ContactDamage
		hazard.name = "HazardPlaceholder"
		hazard.kind = ContactDamage.Kind.HAZARD
		hazard.position = rect.get_center()
		hazard.add_to_group(&"greece_placeholder")
		hazard.add_child(_make_striped_strip(rect.size))
		_markers.add_child(hazard)
		hazard.set_area_size(rect.size)


func _make_striped_strip(size: Vector2) -> Node2D:
	var strip := Node2D.new()
	strip.z_index = 10
	var half := size * 0.5
	strip.add_child(_make_polygon(HAZARD_COLOR, [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	]))
	var x := -half.x
	while x < half.x:
		var x1 := minf(x + HAZARD_STRIPE_WIDTH * 0.5, half.x)
		strip.add_child(_make_polygon(HAZARD_STRIPE_COLOR, [
			Vector2(x, half.y), Vector2(x1, half.y), Vector2(minf(x1 + half.y, half.x), -half.y),
			Vector2(minf(x + half.y, half.x), -half.y),
		]))
		x += HAZARD_STRIPE_WIDTH
	return strip


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

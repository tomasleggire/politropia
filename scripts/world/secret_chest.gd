extends Node2D
class_name SecretChest

signal chest_opened
signal chest_failed

const INTERACTABLE_GROUP := &"interactable"

@export_group("Scenes")
@export var minigame_scene: PackedScene
@export var reward_scene: PackedScene

@export_group("Reward")
@export var reward_offset: Vector2 = Vector2(0, -24)

@export_group("Revelation Path")
## Intermediate platform centres in this chest's local coordinates.
@export var revelation_waypoints: PackedVector2Array = PackedVector2Array()
@export_range(1.0, 120.0, 1.0) var reveal_duration := 30.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: Sprite2D = $Sprite2D
@onready var _revelation_guide: RevelationGuide = $RevelationGuide
@onready var _reveal_timer: Timer = $RevealTimer

var player_nearby: bool = false
var revealed: bool = false
var opened: bool = false
var minigame_active: bool = false

var _player: Node = null


func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)
	# Start hidden and disable interaction.
	_reveal_timer.timeout.connect(hide_chest)
	hide_chest()

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	_bind_player()
	_bind_player.call_deferred()


func _exit_tree() -> void:
	_set_touch_interact_available(false)
	if is_instance_valid(_player) and _player.has_signal(&"open_eyes_activated") and _player.is_connected(&"open_eyes_activated", reveal):
		_player.disconnect(&"open_eyes_activated", reveal)


func _bind_player() -> void:
	if is_instance_valid(_player):
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player:
		_player = player
		if _player.has_signal(&"open_eyes_activated") and not _player.is_connected(&"open_eyes_activated", reveal):
			_player.connect(&"open_eyes_activated", reveal)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_bind_player()

	if can_interact() and Input.is_action_just_pressed(&"interact"):
		interact()


func can_interact() -> bool:
	return revealed and not opened and not minigame_active and player_nearby


## Touch controls call request_interact() on the interactable group.
func request_interact() -> bool:
	if not can_interact():
		return false
	interact()
	return true


func _refresh_interaction() -> void:
	_set_touch_interact_available(can_interact())


func _set_touch_interact_available(available: bool) -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null and touch.has_method(&"set_interact_available"):
		touch.set_interact_available(self, available)


# Called by the skill system when the chest is revealed.
func reveal() -> void:
	if not revealed:
		revealed = true
		show()
		interaction_area.monitoring = true
		_check_player_overlap()
		_check_player_overlap.call_deferred()
	if opened:
		return
	_reveal_timer.start(reveal_duration)
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var route := PackedVector2Array([to_local(player.global_position)])
	route.append_array(revelation_waypoints)
	# The chest sprite is offset from this scene's origin.
	route.append(sprite.position)
	_revelation_guide.show_route(route)


func hide_chest() -> void:
	_reveal_timer.stop()
	revealed = false
	player_nearby = false
	hide()

	interaction_area.monitoring = false
	_revelation_guide.hide_guide()
	_refresh_interaction()


func _check_player_overlap() -> void:
	if not interaction_area.monitoring:
		player_nearby = false
		_refresh_interaction()
		return
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group(&"player"):
			player_nearby = true
			_refresh_interaction()
			return
	if is_instance_valid(_player) and _player is Node2D:
		var col_shape := interaction_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col_shape != null and col_shape.shape is RectangleShape2D:
			var rect_shape := col_shape.shape as RectangleShape2D
			var area_center := col_shape.global_position
			var diff := ((_player as Node2D).global_position - area_center).abs()
			if diff.x <= rect_shape.size.x * 0.5 + 8.0 and diff.y <= rect_shape.size.y * 0.5 + 16.0:
				player_nearby = true
				_refresh_interaction()
				return


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		player_nearby = true
		_refresh_interaction()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		player_nearby = false
		_refresh_interaction()


func interact() -> void:
	if not can_interact():
		return

	start_minigame()


func start_minigame() -> void:
	if minigame_scene == null:
		push_error("HiddenChest: No minigame scene assigned.")
		return

	minigame_active = true
	_refresh_interaction()

	var minigame = minigame_scene.instantiate()

	minigame.completed.connect(_on_minigame_completed)

	get_tree().root.add_child(minigame)


func _on_minigame_completed(success: bool) -> void:
	minigame_active = false

	if success:
		open_chest()
	else:
		_refresh_interaction()
		chest_failed.emit()


func open_chest() -> void:
	if opened:
		return

	opened = true
	_reveal_timer.stop()
	_revelation_guide.hide_guide()

	# Disable further interaction.
	interaction_area.monitoring = false
	_refresh_interaction()

	drop_reward()
	chest_opened.emit()


func drop_reward() -> void:
	if reward_scene == null:
		push_warning("HiddenChest: No reward scene assigned.")
		return

	var reward = reward_scene.instantiate()

	get_tree().current_scene.add_child(reward)

	if reward is Node2D:
		reward.global_position = global_position + reward_offset


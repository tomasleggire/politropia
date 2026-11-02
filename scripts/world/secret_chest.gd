extends Node2D
class_name SecretChest

signal chest_opened
signal chest_failed

@export_group("Scenes")
@export var minigame_scene: PackedScene
@export var reward_scene: PackedScene

@export_group("Reward")
@export var reward_offset: Vector2 = Vector2(0, -24)

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: Sprite2D = $Sprite2D

var player_nearby: bool = false
var revealed: bool = false
var opened: bool = false
var minigame_active: bool = false


func _ready() -> void:
	# Start hidden and disable interaction.
	hide_chest()
	
	# Connect to the REVEAL skill signal 
	var player = get_tree().get_first_node_in_group("player")

	if player:
		player.open_eyes_activated.connect(reveal)
	else:
		push_error("HiddenChest: Player not found!")

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if not revealed or opened or minigame_active:
		return

	if player_nearby and Input.is_action_just_pressed("interact"):
		interact()


# Called by the skill system when the chest is revealed.
func reveal() -> void:
	if revealed:
		return

	revealed = true
	show()

	interaction_area.monitoring = true


func hide_chest() -> void:
	revealed = false
	hide()

	interaction_area.monitoring = false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false


func interact() -> void:
	if opened or minigame_active or not revealed:
		return

	start_minigame()


func start_minigame() -> void:
	if minigame_scene == null:
		push_error("HiddenChest: No minigame scene assigned.")
		return

	minigame_active = true

	var minigame = minigame_scene.instantiate()

	minigame.completed.connect(_on_minigame_completed)

	get_tree().root.add_child(minigame)


func _on_minigame_completed(success: bool) -> void:
	minigame_active = false

	if success:
		open_chest()
	else:
		chest_failed.emit()


func open_chest() -> void:
	if opened:
		return

	opened = true

	drop_reward()
	chest_opened.emit()

	# Disable further interaction.
	interaction_area.monitoring = false


func drop_reward() -> void:
	if reward_scene == null:
		push_warning("HiddenChest: No reward scene assigned.")
		return

	var reward = reward_scene.instantiate()

	get_tree().current_scene.add_child(reward)

	if reward is Node2D:
		reward.global_position = global_position + reward_offset

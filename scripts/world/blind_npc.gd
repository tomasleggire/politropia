class_name BlindNPC
extends CharacterBody2D

const REWARD_ID := "ruby_owl_read_aloud"
const REWARD_DEFINITION_PATH := "res://data/collectibles/definitions/ruby_owl_read_aloud.tres"
const REWARD_PICKUP_SCENE := preload("res://scenes/world/collectible_pickup.tscn")
const REWARD_DEFINITION: CollectibleDefinition = preload("res://data/collectibles/definitions/ruby_owl_read_aloud.tres")

@export_group("Reward delivery")
## Point where the coin leaves the NPC's hands, in the NPC's local sprite units.
## The node scale is applied, so it follows the placed NPC.
@export var reward_origin_offset := Vector2(230.0, 238.0)
## Point in front of the NPC where the coin lands, in local sprite units. The Y
## value is ignored: the coin always lands on the NPC's floor line.
@export var reward_landing_offset := Vector2(330.0, 0.0)
## How high the small arc rises above the straight line between both points.
@export var reward_arc_height := 24.0
## Total time of the hand-over (appear + arc + bounce + settle), in seconds.
@export var reward_flight_time := 0.62

var initial_dialogue: Array[String] = []
var final_dialogue: Array[String] = []

@onready var interaction_area: Area2D = $InteractionArea
@onready var speech_bubble: SpeechBubble = $SpeechBubble
@onready var prompt_icon: Control = get_node_or_null("PromptIcon")
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _player_in_range := false
var _is_talking := false
var quest_accepted := false
var quest_completed := false

var _reward_pickup: CollectiblePickup
var _delivery_in_progress := false

func _ready() -> void:
	_sync_quest_progress()
	_setup_dialogues()
	
	if prompt_icon:
		prompt_icon.hide()
		
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	
	if speech_bubble:
		speech_bubble.finished.connect(_on_dialogue_finished)

	# A previous visit may have handed over the coin without Luz touching it.
	# Recover it once the level is fully in the tree.
	_restore_pending_reward.call_deferred()

# Construcción de los textos con la paleta unificada de accesibilidad
func _setup_dialogues() -> void:
	var d1 = (
		DialogueColor.tag("Todos", DialogueColor.CREMA) + " " +
		DialogueColor.tag("los", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("libros,", DialogueColor.AZUL) + " " +
		DialogueColor.tag("por", DialogueColor.CREMA) + " " +
		DialogueColor.tag("más", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("diversos", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("que", DialogueColor.CREMA) + " " +
		DialogueColor.tag("sean,", DialogueColor.AZUL) + "\n" +
		DialogueColor.tag("constan", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("de", DialogueColor.CREMA) + " " +
		DialogueColor.tag("elementos", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("iguales:", DialogueColor.AZUL) + " " +
		DialogueColor.tag("el", DialogueColor.CREMA) + " " +
		DialogueColor.tag("espacio,", DialogueColor.NARANJA) + "\n" +
		DialogueColor.tag("el", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("punto,", DialogueColor.AZUL) + " " +
		DialogueColor.tag("la", DialogueColor.CREMA) + " " +
		DialogueColor.tag("coma", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("y", DialogueColor.CREMA) + " " +
		DialogueColor.tag("las", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("letras...", DialogueColor.AZUL)
	)
	
	var d2 = (
		DialogueColor.tag("Debido", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("a", DialogueColor.CREMA) + " " +
		DialogueColor.tag("mi", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("condición", DialogueColor.AZUL) + " " +
		DialogueColor.tag("no", DialogueColor.CREMA) + " " +
		DialogueColor.tag("puedo", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("leer", DialogueColor.AMARILLO) + "\n" +
		DialogueColor.tag("por", DialogueColor.AZUL) + " " +
		DialogueColor.tag("mi", DialogueColor.CREMA) + " " +
		DialogueColor.tag("cuenta", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("y", DialogueColor.CREMA) + " " +
		DialogueColor.tag("preciso", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("de", DialogueColor.AZUL) + " " +
		DialogueColor.tag("otros", DialogueColor.NARANJA) + "\n" +
		DialogueColor.tag("que", DialogueColor.CREMA) + " " +
		DialogueColor.tag("me", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("presten", DialogueColor.AZUL) + " " +
		DialogueColor.tag("sus", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("ojos.", DialogueColor.CREMA)
	)
	
	var d3 = (
		DialogueColor.tag("Hay", DialogueColor.CREMA) + " " +
		DialogueColor.tag("un", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("libro", DialogueColor.AZUL) + " " +
		DialogueColor.tag("muy", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("especial", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("en", DialogueColor.CREMA) + " " +
		DialogueColor.tag("la", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("sala", DialogueColor.AZUL) + " " +
		DialogueColor.tag("de", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("curación.", DialogueColor.CREMA) + "\n" +
		DialogueColor.tag("¿Podrías", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("buscarlo", DialogueColor.AZUL) + " " +
		DialogueColor.tag("para", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("mí?", DialogueColor.CREMA)
	)
	
	initial_dialogue = [d1, d2, d3]
	
	var f1 = (
		DialogueColor.tag("¡Puedo", DialogueColor.AZUL) + " " +
		DialogueColor.tag("sentir", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("el", DialogueColor.CREMA) + " " +
		DialogueColor.tag("relieve", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("de", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("este", DialogueColor.AZUL) + " " +
		DialogueColor.tag("pergamino!", DialogueColor.CREMA) + "\n" +
		DialogueColor.tag("Gracias", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("por", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("traérmelo.", DialogueColor.AZUL)
	)
	
	final_dialogue = [f1]

func _start_dialogue() -> void:
	_is_talking = true
	if prompt_icon:
		prompt_icon.hide()
		
	if speech_bubble:
		if not quest_accepted:
			speech_bubble.start_dialogue(initial_dialogue)
		elif has_required_book() and not quest_completed:
			speech_bubble.start_dialogue(final_dialogue)
		else:
			var recordatorio: Array[String] = [
				DialogueColor.tag("El", DialogueColor.CREMA) + " " +
				DialogueColor.tag("libro", DialogueColor.NARANJA) + " " +
				DialogueColor.tag("que", DialogueColor.AZUL) + " " +
				DialogueColor.tag("necesito", DialogueColor.AMARILLO) + " " +
				DialogueColor.tag("está", DialogueColor.NARANJA) + " " +
				DialogueColor.tag("en", DialogueColor.CREMA) + " " +
				DialogueColor.tag("la", DialogueColor.AMARILLO) + " " +
				DialogueColor.tag("sala", DialogueColor.AZUL) + " " +
				DialogueColor.tag("de", DialogueColor.NARANJA) + " " +
				DialogueColor.tag("curación...", DialogueColor.CREMA)
			]
			speech_bubble.start_dialogue(recordatorio)

func _on_dialogue_finished() -> void:
	_is_talking = false
	
	if not quest_accepted:
		quest_accepted = true
		var progress := _quest_progress()
		if progress != null:
			progress.call("accept")
		print("Misión aceptada: Buscar libro en sala de curación")
	elif has_required_book() and not quest_completed:
		quest_completed = _give_reward()

func has_required_book() -> bool:
	return true

func _quest_progress() -> Node:
	return get_node_or_null("/root/BlindQuestProgress")

func _sync_quest_progress() -> void:
	var progress := _quest_progress()
	if progress != null:
		quest_accepted = bool(progress.call("is_accepted"))
		quest_completed = bool(progress.call("is_completed"))
	if _has_reward_collected():
		quest_accepted = true
		quest_completed = true

func _has_reward_collected() -> bool:
	var manager := get_node_or_null("/root/Collectibles")
	return manager != null and bool(manager.call("has_collected", REWARD_ID))

## Hands over the ruby owl once. Returns true only when the reward is already
## granted or was granted by this call.
func _give_reward() -> bool:
	if _delivery_in_progress:
		return quest_completed
	if _has_reward_collected():
		return true
	var existing := _find_existing_reward_pickup()
	if existing != null:
		_reward_pickup = existing
		return true

	var progress := _quest_progress()
	if progress != null and bool(progress.call("is_reward_granted")):
		return _spawn_pending_reward()

	var pickup := _create_reward_pickup(_delivery_origin())
	if pickup == null:
		push_warning("BlindNPC: could not create the ruby owl reward pickup.")
		return false

	_reward_pickup = pickup
	_delivery_in_progress = true
	if progress != null:
		progress.call("complete")
		progress.call("grant_reward")
	print("Misión completada: Recompensa entregada al jugador")
	_animate_delivery(pickup)
	return true

## Called when Luz comes back to the room after leaving the coin behind.
func _restore_pending_reward() -> void:
	if not is_inside_tree():
		return
	var progress := _quest_progress()
	if progress == null or not bool(progress.call("is_reward_granted")):
		return
	if _has_reward_collected() or _find_existing_reward_pickup() != null:
		return
	_spawn_pending_reward()

func _spawn_pending_reward() -> bool:
	if _has_reward_collected():
		return true
	var existing := _find_existing_reward_pickup()
	if existing != null:
		_reward_pickup = existing
		return true

	var pickup := _create_reward_pickup(_delivery_landing())
	if pickup == null:
		push_warning("BlindNPC: could not recover the pending ruby owl reward.")
		return false
	_reward_pickup = pickup
	# A small fade/scale-in so the recovered coin does not pop into view.
	pickup.scale = Vector2(0.6, 0.6)
	pickup.modulate.a = 0.0
	var tween := pickup.create_tween().set_parallel(true)
	tween.tween_property(pickup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pickup, "modulate:a", 1.0, 0.2)
	return true

func _animate_delivery(pickup: CollectiblePickup) -> void:
	await pickup.play_delivery(_delivery_origin(), _delivery_landing(), reward_arc_height, reward_flight_time)
	_delivery_in_progress = false

func _create_reward_pickup(at: Vector2) -> CollectiblePickup:
	var host := get_parent() as Node2D
	if host == null:
		host = get_tree().current_scene as Node2D
	if host == null:
		return null
	var pickup := REWARD_PICKUP_SCENE.instantiate() as CollectiblePickup
	if pickup == null:
		return null
	pickup.definition = REWARD_DEFINITION
	pickup.position = host.to_local(at)
	# Hide it before entering the tree: the delivery/recovery tween fades it in,
	# so a spawn frame can never flash the coin at the origin.
	pickup.scale = Vector2(0.35, 0.35)
	pickup.modulate.a = 0.0
	host.add_child(pickup)
	if pickup.is_queued_for_deletion():
		return null
	return pickup

func _find_existing_reward_pickup() -> CollectiblePickup:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(CollectiblePickup.PICKUP_GROUP):
		var pickup := node as CollectiblePickup
		if pickup != null and not pickup.is_queued_for_deletion() and pickup.collectible_id() == REWARD_ID:
			return pickup
	return null

func _delivery_origin() -> Vector2:
	var node_scale := global_scale.abs()
	return global_position + Vector2(
		reward_origin_offset.x * node_scale.x,
		reward_origin_offset.y * node_scale.y
	)

func _delivery_landing() -> Vector2:
	var node_scale := global_scale.abs()
	var landing_x := global_position.x + reward_landing_offset.x * node_scale.x
	return Vector2(landing_x, _floor_global_y() - CollectiblePickup.ICON_PIXELS * 0.5 - 2.0)

func _floor_global_y() -> float:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		var half_height := (collision.shape as RectangleShape2D).size.y * 0.5
		return global_position.y + (collision.position.y + half_height) * absf(global_scale.y)
	return global_position.y + 120.0 * absf(global_scale.y)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = true
		if not _is_talking:
			_start_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = false
		_is_talking = false

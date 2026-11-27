class_name LibrarianNPC
extends CharacterBody2D

@export var npc_name := "Bibliotecario"

@export_multiline var dialogue: Array[String] = []
@onready var speech_bubble: NpcSpeechBubble = $SpeechBubble
@onready var interaction_area: Area2D = $InteractionArea
#01@onready var prompt_icon: Control = $PromptIcon
@onready var prompt: InteractionPrompt = $InteractionPrompt

var _player_in_range := false
var _is_talking := false

func _ready() -> void:
	add_to_group(&"interactable")
	prompt.hide_prompt()
	
	
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	speech_bubble.finished.connect(_on_dialogue_finished)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and request_interact():
		get_viewport().set_input_as_handled()

func request_interact() -> bool:
	if not _player_in_range:
		return false

	if _is_talking:
		speech_bubble.advance_dialogue()
		return true

	_start_dialogue()
	return true

func _on_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return

	_player_in_range = true
	_refresh_interaction()

func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return

	_player_in_range = false
	_refresh_interaction()

func _is_player(body: Node2D) -> bool:
	return body.is_in_group(&"player") or body is Player

func _refresh_interaction() -> void:
	var available := _player_in_range and not _is_talking
	var touch := get_node_or_null("/root/TouchControls")

	if touch != null:
		touch.set_interact_available(self, available)
		
		if touch.visible:
			prompt.hide_prompt()
		elif available:
			prompt.show_prompt()
		else:
			prompt.hide_prompt()
	else:
		if available:
			prompt.show_prompt()
		else:
			prompt.hide_prompt()


func _start_dialogue() -> void:
	if _is_talking:
		return
	_is_talking = true
	_refresh_interaction()


	var colored_dialogue: Array[String] = DialogueColor.color_dialogue(dialogue)
	
	speech_bubble.start_dialogue(colored_dialogue)

var icono 

func _on_dialogue_finished() -> void:
	_is_talking = false
	var learned := AbilityProgress.record(&"focus")
	if learned:
		$AbilityUnlockPopup.show_ability(
			"Focus",
			"Luz aprendió a concentrar su energía para recuperar salud.",
			load("res://assets/ui/open_eyes_learned.png")
		)

	call_deferred("_refresh_interaction")

func _exit_tree() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		touch.set_interact_available(self, false)

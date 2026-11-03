class_name LibrarianNPC
extends CharacterBody2D

@export var npc_name := "Filósofo"

@onready var speech_bubble: LibrarianSpeechBubble = $LibrarianSpeechBubble
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_icon: Control = $PromptIcon

var _player_in_range := false
var _is_talking := false

func _ready() -> void:
	if prompt_icon:
		prompt_icon.hide()
		
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	
	if speech_bubble:
		speech_bubble.finished.connect(_on_dialogue_finished)

func _start_dialogue() -> void:
	_is_talking = true
	if prompt_icon:
		prompt_icon.hide()
		
	var frase = (
		DialogueColor.tag("No", DialogueColor.CREMA) + " " +
		DialogueColor.tag("todos", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("los", DialogueColor.CREMA) + " " +
		DialogueColor.tag("secretos", DialogueColor.AZUL) + " " +
		DialogueColor.tag("están", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("ocultos.", DialogueColor.NARANJA) + "\n" +
		DialogueColor.tag("Algunos", DialogueColor.CREMA) + " " +
		DialogueColor.tag("solo", DialogueColor.NARANJA) + " " +
		DialogueColor.tag("esperan", DialogueColor.AZUL) + " " +
		DialogueColor.tag("ser", DialogueColor.AMARILLO) + " " +
		DialogueColor.tag("revelados.", DialogueColor.NARANJA)
	)
	
	if speech_bubble:
		speech_bubble.show_text(frase)

func _on_dialogue_finished() -> void:
	_is_talking = false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = true
		if not _is_talking:
			_start_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = false
		_is_talking = false

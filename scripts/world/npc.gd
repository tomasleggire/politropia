class_name NPC
extends CharacterBody2D

@export var npc_name := "Filósofo"
@export_multiline var dialogue_lines: Array[String] = [
	"[[bgcolor=#5c5470]No[/bgcolor]   [bgcolor=#2e5a44]todos[/bgcolor]   [bgcolor=#6b406b]los[/bgcolor]    [bgcolor=#8c7a50]secretos[/bgcolor]

 [bgcolor=#8c7a50]están[/bgcolor]   [bgcolor=#2e5a44]ocultos[/bgcolor].

[bgcolor=#6b406b]Algunos[/bgcolor]    [bgcolor=#8c7a50]solo[/bgcolor]    [bgcolor=#3f51b5]esperan[/bgcolor]

[bgcolor=#2e5a44]ser[/bgcolor]    [bgcolor=#883949]revelados[/bgcolor]."
]

@onready var interaction_area: Area2D = $InteractionArea
@onready var speech_bubble: SpeechBubble = $SpeechBubble
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

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and not _is_talking:
		if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
			get_viewport().set_input_as_handled()
			_start_dialogue()

func _start_dialogue() -> void:
	_is_talking = true
	if prompt_icon:
		prompt_icon.hide()
	if speech_bubble:
		speech_bubble.start_dialogue(dialogue_lines)

func _on_dialogue_finished() -> void:
	_is_talking = false
	if _player_in_range and prompt_icon:
		prompt_icon.show()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = true
		if not _is_talking and prompt_icon:
			prompt_icon.show()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = false
		if prompt_icon:
			prompt_icon.hide()

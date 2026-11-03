class_name BlindNPC
extends CharacterBody2D

var initial_dialogue: Array[String] = []
var final_dialogue: Array[String] = []

@onready var interaction_area: Area2D = $InteractionArea
@onready var speech_bubble: SpeechBubble = $SpeechBubble
@onready var prompt_icon: Control = $PromptIcon
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _player_in_range := false
var _is_talking := false
var quest_accepted := false
var quest_completed := false

func _ready() -> void:
	_setup_dialogues()
	
	if prompt_icon:
		prompt_icon.hide()
		
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)
	
	if speech_bubble:
		speech_bubble.finished.connect(_on_dialogue_finished)

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
			var recordatorio = [
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
		print("Misión aceptada: Buscar libro en sala de curación")
	elif has_required_book() and not quest_completed:
		quest_completed = true
		_give_reward()

func has_required_book() -> bool:
	return true

func _give_reward() -> void:
	print("Misión completada: Recompensa entregada al jugador")

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = true
		if not _is_talking:
			_start_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body is Player or "Luz" in body.name or "Player" in body.name:
		_player_in_range = false
		_is_talking = false

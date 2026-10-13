extends Control

const ESCENA_JUEGO := "res://scenes/levels/greece/zone_1.tscn"

@onready var btn_nueva: Button = %NewGame
@onready var btn_continuar: Button = %Continue
@onready var btn_coleccionables: Button = %Collectables
@onready var btn_salir: Button = %Exit

func _ready() -> void:
	btn_continuar.disabled = true  # sin guardado por ahora
	btn_nueva.pressed.connect(_on_nueva_partida)
	btn_coleccionables.pressed.connect(_on_coleccionables)
	btn_salir.pressed.connect(get_tree().quit)
	btn_nueva.grab_focus()
	# Empieza a cargar el juego en segundo plano
	ResourceLoader.load_threaded_request(ESCENA_JUEGO)

func _on_nueva_partida() -> void:
	btn_nueva.disabled = true  # evita tocar dos veces
	# Si todavía no terminó de cargar, espera  lo que falte
	var escena: PackedScene = ResourceLoader.load_threaded_get(ESCENA_JUEGO)
	if escena != null:
		get_tree().change_scene_to_packed(escena)
	else:
		# Fallback por si la carga diferida falla
		get_tree().change_scene_to_file(ESCENA_JUEGO)

func _on_coleccionables() -> void:
	print("Coleccionables: pendiente")

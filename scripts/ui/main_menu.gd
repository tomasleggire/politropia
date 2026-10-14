extends Control

const ESCENA_JUEGO := "res://scenes/levels/library/zone_1.tscn"
const ESCENA_INTRO := "res://scenes/ui/new_game_intro.tscn"

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
	_reset_new_game_progress()
	get_tree().change_scene_to_file(ESCENA_INTRO)


func _reset_new_game_progress() -> void:
	for service_path in ["/root/CheckpointService", "/root/EnemyRegistry", "/root/BossProgress", "/root/FragmentProgress", "/root/MapProgress", "/root/SecretProgress"]:
		var service := get_node_or_null(service_path)
		if service != null and service.has_method("clear"):
			service.call("clear")
	TutorialSign.reset_seen()

func _on_coleccionables() -> void:
	var toast := get_node_or_null("/root/PickupToast")
	if toast != null:
		toast.show_toast("Próximamente")

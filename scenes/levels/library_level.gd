extends Node2D

@onready var player: Player = $Player   # Revisa que en el árbol de la escena se llame exactamente "Player"
@onready var hud = $HUD                # Revisa que en el árbol de la escena se llame exactamente "HUD"

func _ready() -> void:
	if is_instance_valid(player) and is_instance_valid(hud):
		# Conectamos la señal de vida del jugador al método del HUD
		if player.has_signal("health_changed") and hud.has_method("_on_player_health_changed"):
			player.health_changed.connect(hud._on_player_health_changed)
		else:
			push_warning("The player health signal or HUD handler is unavailable")

		if player.has_signal("energy_changed") and hud.has_method("_on_player_energy_changed"):
			player.energy_changed.connect(hud._on_player_energy_changed)

		# Forzamos el primer disparo para dibujar los corazones iniciales
		hud._on_player_health_changed(player.current_health, player.max_health)
		hud._on_player_energy_changed(player.current_energy, player.max_energy)
	else:
		push_warning("The library player or HUD node is unavailable")

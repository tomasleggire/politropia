extends CanvasLayer

@onready var hearts_container: HBoxContainer = $PlayerUI/HeartsContainer
@onready var energy_bar: TextureProgressBar = $PlayerUI/EnergyBar

@export var heart_full_texture: Texture2D
@export var heart_empty_texture: Texture2D

func _on_player_health_changed(current_health: int, max_health: int) -> void:
	if hearts_container == null:
		return

	# Limpiar los corazones anteriores
	for child in hearts_container.get_children():
		child.queue_free()

	# Crear las imágenes según la vida actual
	for i in range(max_health):
		var heart := TextureRect.new()
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.custom_minimum_size = Vector2(32, 32) # Ajusta el tamaño que quieras en pantalla
		
		if i < current_health:
			heart.texture = heart_full_texture
		else:
			heart.texture = heart_empty_texture
			
		hearts_container.add_child(heart)

func _on_player_energy_changed(current_energy: float, max_energy: float) -> void:
	if is_instance_valid(energy_bar):
		energy_bar.max_value = max_energy
		energy_bar.value = current_energy

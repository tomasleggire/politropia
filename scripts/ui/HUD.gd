extends CanvasLayer

@onready var hearts_container: HBoxContainer = $PlayerUI/HeartsContainer
@onready var energy_bar: TextureProgressBar = $PlayerUI/EnergyBar
@onready var fragment_count: Label = $PlayerUI/FragmentCounter/Count

@export var heart_full_texture: Texture2D
@export var heart_empty_texture: Texture2D

@export_group("Layout")
## Scales the whole top-left block (portrait, hearts, energy bar, counter).
## 1.0 is the original art size; hearts stay legible on a phone down to ~0.6.
@export_range(0.5, 1.5, 0.05) var hud_scale := 0.75:
	set(value):
		hud_scale = value
		_apply_scale()

func _ready() -> void:
	_apply_scale()
	var progress := get_node_or_null("/root/FragmentProgress")
	if progress == null:
		return
	progress.fragment_collected.connect(_on_fragment_collected)
	_show_fragments(progress.count(), progress.total())


func _apply_scale() -> void:
	var player_ui := get_node_or_null("PlayerUI") as Control
	if player_ui != null:
		player_ui.scale = Vector2.ONE * hud_scale


func _on_fragment_collected(_id: int, count: int, total: int) -> void:
	_show_fragments(count, total)


func _show_fragments(count: int, total: int) -> void:
	fragment_count.text = "%d/%d" % [count, total]


## Función que conecta al jugador y dibuja la interfaz de entrada
func bind_player(player: Player) -> void:
	if player == null:
		return

	# Conectar señales
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)
		
	if not player.soul_changed.is_connected(_on_player_soul_changed):
		player.soul_changed.connect(_on_player_soul_changed)

	# DIBUJAR DE ENTRADA (Esto es lo que te faltaba):
	var cur_hp: int = player.get_health() if player.has_method("get_health") else player._health
	var max_hp: int = player.get_max_health() if player.has_method("get_max_health") else player.max_health
	_on_player_health_changed(cur_hp, max_hp)

	_on_player_soul_changed(player.get_soul(), player.get_max_soul())

func _on_player_health_changed(current_health: int, max_health: int) -> void:
	if hearts_container == null:
		hearts_container = get_node_or_null("PlayerUI/HeartsContainer") as HBoxContainer

	if hearts_container == null:
		return

	# Limpia los corazones anteriores
	for child in hearts_container.get_children():
		hearts_container.remove_child(child)
		child.queue_free()

	# Crea las imágenes según la vida actual
	for i in range(max_health):
		var heart := TextureRect.new()
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.custom_minimum_size = Vector2(32, 32)
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		if i < current_health:
			heart.texture = heart_full_texture
		else:
			heart.texture = heart_empty_texture

		hearts_container.add_child(heart)

## The energy bar is the soul meter: it fills with enemy hits and is spent by
## the focus heal.
func _on_player_soul_changed(current_soul: int, max_soul: int) -> void:
	if energy_bar == null:
		energy_bar = get_node_or_null("PlayerUI/EnergyBar") as TextureProgressBar

	if is_instance_valid(energy_bar):
		energy_bar.max_value = max_soul
		energy_bar.value = current_soul

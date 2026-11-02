extends CanvasLayer

signal completed(success: bool)

@export_group("Puzzle")
@export var target_word: String = "BIBLIOTECA"
@export var syllables: PackedStringArray = ["BI", "BLIO", "TE", "CA"]

@onready var title: Label = $Overlay/CenterContainer/PanelContainer/VBoxContainer/Title
@onready var instructions: Label = $Overlay/CenterContainer/PanelContainer/VBoxContainer/Instructions
@onready var answer_slots: HBoxContainer = $Overlay/CenterContainer/PanelContainer/VBoxContainer/AnswerSlots
@onready var available_syllables: GridContainer = $Overlay/CenterContainer/PanelContainer/VBoxContainer/AvailableSyllables
@onready var feedback: Label = $Overlay/CenterContainer/PanelContainer/VBoxContainer/Feedback
@onready var check_button: Button = $Overlay/CenterContainer/PanelContainer/VBoxContainer/CheckButton

# Stores the original syllable indices selected by the player.
# -1 means the slot is empty.
var selected_indices: Array[int] = []

# Stores the shuffled order of the syllables.
var shuffled_syllables: Array[String] = []

var finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	$Overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Overlay/CenterContainer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	available_syllables.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback.custom_minimum_size = Vector2(0, 24)

	check_button.pressed.connect(_on_check_pressed)

	available_syllables.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Disable touch controls while in the mini game.
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		false
	)

	shuffle_syllables()
	create_answer_slots()
	create_syllable_buttons()

	_update_check_button()


# Randomize the available syllables.
func shuffle_syllables() -> void:
	shuffled_syllables.clear()

	for syllable in syllables:
		shuffled_syllables.append(syllable)

	shuffled_syllables.shuffle()


# Create one empty button for each syllable.
func create_answer_slots() -> void:
	selected_indices.clear()
	var normal_style = preload("res://assets/ui/minigame/slots/slot_normal.tres")
	var hover_style = preload("res://assets/ui/minigame/slots/slot_hover.tres")
	var pressed_style = preload("res://assets/ui/minigame/slots/slot_pressed.tres")

	for child in answer_slots.get_children():
		child.queue_free()

	for i in range(syllables.size()):
		selected_indices.append(-1)

		var slot := Button.new()
		slot.custom_minimum_size = Vector2(80, 65)
		slot.text = "?"
		slot.add_theme_font_size_override("font_size", 24)

		slot.pressed.connect(_on_slot_pressed.bind(i))
		
		slot.add_theme_stylebox_override("normal", normal_style)
		slot.add_theme_stylebox_override("hover", hover_style)
		slot.add_theme_stylebox_override("pressed", pressed_style)

		slot.add_theme_color_override("font_color", Color("#FFFFFF"))
		slot.add_theme_font_size_override("font_size", 24)

		answer_slots.add_child(slot)


# Create the shuffled syllable buttons.
func create_syllable_buttons() -> void:
	available_syllables.columns = 4
	var normal_style = preload("res://assets/ui/minigame/syllables/syllable_normal.tres")
	var hover_style = preload("res://assets/ui/minigame/syllables/syllable_hover.tres")
	var pressed_style = preload("res://assets/ui/minigame/syllables/syllable_pressed.tres")

	for child in available_syllables.get_children():
		child.queue_free()

	for i in range(shuffled_syllables.size()):
		var button := Button.new()
		
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", pressed_style)

		button.add_theme_color_override("font_color", Color("#FFFFFF"))
		button.add_theme_color_override("font_disabled_color", Color("#8995A2"))
		button.add_theme_font_size_override("font_size", 24)

		button.text = shuffled_syllables[i]
		button.custom_minimum_size = Vector2(85, 65)
		button.add_theme_font_size_override("font_size", 24)

		button.pressed.connect(_on_syllable_pressed.bind(i))

		available_syllables.add_child(button)


# Player selects a syllable.
func _on_syllable_pressed(index: int) -> void:
	if finished:
		return

	# Don't allow selecting an already used syllable.
	if index in selected_indices:
		return

	# Find the first empty answer slot.
	for i in range(selected_indices.size()):
		if selected_indices[i] == -1:
			selected_indices[i] = index
			break

	update_answer_slots()
	update_syllable_buttons()
	_update_check_button()

	feedback.text = ""


# Player taps an occupied answer slot to remove its syllable.
func _on_slot_pressed(index: int) -> void:
	if finished:
		return

	selected_indices[index] = -1

	update_answer_slots()
	update_syllable_buttons()
	_update_check_button()

	feedback.text = ""


# Refresh the answer slots.
func update_answer_slots() -> void:
	for i in range(selected_indices.size()):
		var slot: Button = answer_slots.get_child(i)

		if selected_indices[i] == -1:
			slot.text = "?"
		else:
			slot.text = shuffled_syllables[selected_indices[i]]


# Refresh available syllables.
func update_syllable_buttons() -> void:
	for i in range(shuffled_syllables.size()):
		var button: Button = available_syllables.get_child(i)

		button.disabled = i in selected_indices


# Enable the check button only when every slot is filled.
func _update_check_button() -> void:
	check_button.disabled = -1 in selected_indices


# Check the assembled word.
func _on_check_pressed() -> void:
	if finished:
		return

	var assembled_word := ""

	for index in selected_indices:
		assembled_word += shuffled_syllables[index]

	if assembled_word.to_upper() == target_word.to_upper():
		_on_success()
	else:
		_on_failure()


# Successful puzzle.
func _on_success() -> void:
	finished = true

	feedback.text = "¡Correcto!"
	check_button.disabled = true

	await get_tree().create_timer(0.8).timeout
	
	# Enable UI again
	get_tree().call_group(
		&"touch_controls",
		&"set_controls_enabled",
		true
	)

	completed.emit(true)
	queue_free()


# Incorrect answer.
func _on_failure() -> void:
	feedback.text = "¡Intentá de nuevo!"

extends CanvasLayer
signal popup_closed

@onready var overlay: Control = $Overlay
@onready var title_label: Label = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/Title
@onready var ability_icon: TextureRect = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/AbilityIcon
@onready var ability_name: Label = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/AbilityName
@onready var description: RichTextLabel = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/Description
@onready var continue_button: Button = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/ContinueButton

var _popup_open := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.hide()
	continue_button.pressed.connect(close_popup)

func show_ability(
	display_name: String,
	detail: String,
	icon: Texture2D
) -> void:
	ability_name.text = display_name
	description.text = DialogueColor.color_text(detail)
	ability_icon.texture = icon

	_popup_open = true
	overlay.show()
	get_tree().paused = true

	continue_button.grab_focus()

func close_popup() -> void:
	if not _popup_open:
		return

	_popup_open = false
	overlay.hide()
	get_tree().paused = false

	popup_closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _popup_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

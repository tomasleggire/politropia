extends Control

## Collectibles gallery, opened from the main menu's "Collectables" button.
##
## It reads the full catalog and the session state from the `Collectibles`
## autoload and never stores progress itself. Locked items show a silhouette and
## hide their title and text until the player finds them in the world.
##
## HOW TO EDIT: the layout lives in `scenes/ui/collectibles_gallery.tscn`; the
## data comes from `data/collectibles/catalog.tres` (see the final report for the
## step-by-step recipe to add a new collectible).

@export_file("*.tscn") var main_menu_scene := "res://scenes/ui/main_menu.tscn"

const LOCKED_TITLE := "???"
const LOCKED_CATEGORY := "Bloqueado"
const LOCKED_TEXT := "Este coleccionable todavía no fue descubierto.\n\nRecorré los niveles para encontrarlo."
const EMPTY_TEXT := "El catálogo todavía no tiene coleccionables."
const MISSING_MANAGER_TEXT := "No se pudo cargar el progreso de coleccionables."

@onready var _back: Button = %Back
@onready var _progress: Label = %Progress
@onready var _left_panel: PanelContainer = %LeftPanel
@onready var _right_panel: PanelContainer = %RightPanel
@onready var _grid_scroll: ScrollContainer = %GridScroll
@onready var _grid: GridContainer = %Grid
@onready var _slot_template: Button = %SlotTemplate
@onready var _empty_state: Label = %EmptyState
@onready var _detail_icon: CollectibleIcon = %DetailIcon
@onready var _category: Label = %Category
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_scroll: ScrollContainer = %DetailScroll
@onready var _detail_text: RichTextLabel = %DetailText
@onready var _detail_hint: Label = %DetailHint

var _definitions: Array[CollectibleDefinition] = []
var _slots: Array[Button] = []
var _selected_index := -1


func _ready() -> void:
	# This screen belongs to the menus: keep the gameplay touch overlay hidden.
	get_tree().call_group(&"touch_controls", &"set_controls_enabled", false)
	_back.pressed.connect(_on_back_pressed)
	refresh()
	if not _slots.is_empty():
		_slots[0].grab_focus()


func _exit_tree() -> void:
	get_tree().call_group(&"touch_controls", &"set_controls_enabled", true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	if main_menu_scene.is_empty():
		push_warning("CollectiblesGallery: main_menu_scene is empty.")
		return
	get_tree().change_scene_to_file(main_menu_scene)


## Rebuilds the grid from the catalog and the current session state.
func refresh() -> void:
	var manager := _manager()
	_definitions.clear()
	if manager != null:
		for definition: CollectibleDefinition in manager.call("get_all_definitions"):
			if definition != null:
				_definitions.append(definition)

	_rebuild_grid()
	_empty_state.visible = _definitions.is_empty()
	_left_panel.visible = not _definitions.is_empty()
	_right_panel.visible = not _definitions.is_empty()

	if manager == null:
		_progress.text = "0 / 0"
		_empty_state.text = MISSING_MANAGER_TEXT
		_selected_index = -1
		return
	if _definitions.is_empty():
		_progress.text = "0 / 0"
		_empty_state.text = EMPTY_TEXT
		_selected_index = -1
		return

	_empty_state.text = EMPTY_TEXT
	_progress.text = "%d / %d" % [
		int(manager.call("get_collected_count")),
		_definitions.size(),
	]
	var first_unlocked := -1
	for i in _definitions.size():
		if manager.call("has_collected", _definitions[i].id):
			first_unlocked = i
			break
	select_item(first_unlocked if first_unlocked >= 0 else 0)


## Shows the detail of one catalog entry. Locked entries never reveal their
## title, category or text.
func select_item(index: int) -> void:
	if index < 0 or index >= _definitions.size():
		return
	var manager := _manager()
	if manager == null:
		return
	_selected_index = index
	for i in _slots.size():
		_slots[i].button_pressed = i == index

	var definition := _definitions[index]
	var unlocked: bool = manager.call("has_collected", definition.id)
	var accent := _category_color(definition.category)
	_detail_icon.set_definition(definition, not unlocked, accent)
	_detail_title.text = definition.title if unlocked else LOCKED_TITLE
	_category.text = definition.category if unlocked else LOCKED_CATEGORY
	_detail_text.text = definition.content if unlocked else LOCKED_TEXT
	_detail_hint.text = "Encontrado en esta sesión" if unlocked else "Encontralo en el mundo"
	_detail_scroll.scroll_vertical = 0


func get_slot_count() -> int:
	return _slots.size()


func get_selected_index() -> int:
	return _selected_index


func get_selected_title() -> String:
	return _detail_title.text


func get_selected_category() -> String:
	return _category.text


func get_selected_body() -> String:
	return _detail_text.text


func is_selected_locked() -> bool:
	if _selected_index < 0 or _selected_index >= _definitions.size():
		return true
	var manager := _manager()
	return manager == null or not bool(manager.call("has_collected", _definitions[_selected_index].id))


func get_progress_text() -> String:
	return _progress.text


func _manager() -> Node:
	return get_node_or_null("/root/Collectibles")


func _rebuild_grid() -> void:
	for slot in _slots:
		_grid.remove_child(slot)
		slot.queue_free()
	_slots.clear()

	for i in _definitions.size():
		var definition := _definitions[i]
		var slot := _slot_template.duplicate() as Button
		slot.name = "Slot%d" % i
		slot.visible = true
		slot.tooltip_text = "Coleccionable bloqueado"
		_grid.add_child(slot)
		_slots.append(slot)

		var manager := _manager()
		var unlocked := manager != null and bool(manager.call("has_collected", definition.id))
		var accent := _category_color(definition.category)
		var icon := slot.get_node("Content/Icon") as CollectibleIcon
		icon.set_definition(definition, not unlocked, accent)
		var name_label := slot.get_node("Content/Name") as Label
		name_label.text = definition.title if unlocked else LOCKED_TITLE
		name_label.add_theme_color_override(
			"font_color",
			accent.lightened(0.45) if unlocked else Color(0.38, 0.45, 0.53, 1.0)
		)
		if unlocked:
			slot.tooltip_text = "%s · %s" % [definition.title, definition.category]
		_style_slot(slot, accent, unlocked)
		slot.pressed.connect(_on_slot_pressed.bind(i))


func _on_slot_pressed(index: int) -> void:
	select_item(index)


func _style_slot(slot: Button, accent: Color, unlocked: bool) -> void:
	var border := accent.darkened(0.12) if unlocked else Color(0.19, 0.25, 0.32, 1.0)
	for state in ["normal", "hover", "pressed"]:
		var original := slot.get_theme_stylebox(state)
		if original == null:
			continue
		var style := original.duplicate() as StyleBoxFlat
		if style == null:
			continue
		style.border_color = border.lightened(0.2) if state != "normal" else border
		slot.add_theme_stylebox_override(state, style)


func _category_color(category: String) -> Color:
	match category.to_lower():
		"historia":
			return Color(0.93, 0.73, 0.35, 1.0)
		"aprendizaje":
			return Color(0.36, 0.85, 0.95, 1.0)
		"cultura":
			return Color(0.72, 0.55, 0.95, 1.0)
		"personajes":
			return Color(0.5, 0.85, 0.55, 1.0)
		_:
			return Color(0.55, 0.7, 0.95, 1.0)

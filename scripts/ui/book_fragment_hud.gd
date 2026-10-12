extends CanvasLayer

const FRAGMENT_IDS := ["fragmento_1", "fragmento_2", "fragmento_3", "fragmento_4"]
const ICON_TEXTURES := [
	preload("res://assets/world/fragmento_libro.png"),
	preload("res://assets/world/fragmento_libro_2.png"),
	preload("res://assets/world/fragmento_libro_3.png"),
	preload("res://assets/world/fragmento_libro_4.png"),
]
const INACTIVE_TINT := Color(0.42, 0.45, 0.5, 0.78)
const CARRIED_TINT := Color(1.0, 0.76, 0.28, 1.0)
const DEPOSITED_TINT := Color(1.0, 0.88, 0.48, 1.0)

var _icons: Array[TextureRect] = []
var _deposit_marks: Array[Polygon2D] = []
var _container: HBoxContainer


func _ready() -> void:
	layer = 35
	_container = HBoxContainer.new()
	_container.name = "BookFragments"
	_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_container.offset_left = -180.0
	_container.offset_top = 12.0
	_container.offset_right = -14.0
	_container.offset_bottom = 54.0
	_container.add_theme_constant_override("separation", 4)
	add_child(_container)
	for texture in ICON_TEXTURES:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(38, 38)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = texture
		_container.add_child(icon)
		_icons.append(icon)
		var mark := Polygon2D.new()
		mark.polygon = PackedVector2Array([
			Vector2(-5, -1), Vector2(-2, 2), Vector2(4, -4),
			Vector2(6, -2), Vector2(-2, 6), Vector2(-7, 1),
		])
		mark.position = Vector2(29, 28)
		mark.color = Color("fff1a8")
		mark.visible = false
		icon.add_child(mark)
		_deposit_marks.append(mark)
	var state := get_node("/root/BookFragmentState")
	state.state_changed.connect(_on_state_changed)
	get_tree().scene_changed.connect(_refresh)
	_refresh()


func _on_state_changed(_level_id: String) -> void:
	_refresh()


func _refresh(_scene: Node = null) -> void:
	var state := get_node_or_null("/root/BookFragmentState")
	if state == null:
		return
	var level_id: String = state.current_level_id()
	for index in FRAGMENT_IDS.size():
		var fragment_id: String = FRAGMENT_IDS[index]
		var deposited: bool = state.get_deposited(level_id).has(fragment_id)
		var carried: bool = state.get_carried(level_id).has(fragment_id)
		_icons[index].modulate = DEPOSITED_TINT if deposited else CARRIED_TINT if carried else INACTIVE_TINT
		_deposit_marks[index].visible = deposited

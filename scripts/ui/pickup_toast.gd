extends CanvasLayer

## On-screen notification (autoload `PickupToast`): a title and an optional
## subtitle slide in at the top of the screen (a little right of center, to
## clear the hearts), stay a couple of seconds and fade out.
## Several calls queue up and play one after another.
##
## USAGE, from any script, one line:
##   PickupToast.show_toast("Titulo", "Subtitulo")
##
## It already reacts by itself to `FragmentProgress.fragment_collected` and to
## every Player's `ability_unlocked`, so those pickups need no extra code. To
## announce a new ability add an entry to `ability_texts`.
##
## Why an autoload and not a per-level prefab: it must outlive zone changes (a
## toast started at a door keeps playing), any script must reach it with one
## line, and it needs no placement work from teammates.

@export_group("Timing")
## Seconds the toast stays fully visible.
@export_range(0.5, 8.0, 0.1) var hold_time := 2.5
@export_range(0.05, 1.5, 0.05) var fade_in_time := 0.35
@export_range(0.05, 1.5, 0.05) var fade_out_time := 0.45
## Pixels the toast slides down while fading in.
@export var slide_distance := 14.0

@export_group("Texts")
## Format with the fragment number and the total, e.g. "Fragmento del libro 2/4".
@export var fragment_title := "Fragmento del libro %d/%d"
@export var fragment_subtitle := "Llevalos al atril para reconstruirlo"
@export var all_fragments_subtitle := "El libro está completo: llevalo al atril"
## `ability id -> [title, subtitle]`, used for `Player.ability_unlocked`.
@export var ability_texts: Dictionary = {
	&"double_jump": ["Doble salto", "Saltá de nuevo en el aire"],
}

var _queue: Array[Array] = []
var _playing := false

@onready var _slide: Control = $Root/Slide
@onready var _title: Label = $Root/Slide/Panel/Margin/Box/Title
@onready var _subtitle: Label = $Root/Slide/Panel/Margin/Box/Subtitle


func _ready() -> void:
	_slide.modulate.a = 0.0
	_slide.visible = false
	var progress := get_node_or_null("/root/FragmentProgress")
	if progress != null:
		progress.fragment_collected.connect(_on_fragment_collected)
	get_tree().node_added.connect(_on_node_added)
	for player in get_tree().get_nodes_in_group(&"player"):
		_watch_player(player)


## Queues a toast. `subtitle` may be empty.
func show_toast(title: String, subtitle := "") -> void:
	_queue.append([title, subtitle])
	if not _playing:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		return
	_playing = true
	var entry: Array = _queue.pop_front()
	_title.text = entry[0]
	_subtitle.text = entry[1]
	_subtitle.visible = not String(entry[1]).is_empty()
	_slide.visible = true
	_slide.modulate.a = 0.0
	_slide.position.y = -slide_distance
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_slide, "modulate:a", 1.0, fade_in_time)
	tween.parallel().tween_property(_slide, "position:y", 0.0, fade_in_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_time)
	tween.tween_property(_slide, "modulate:a", 0.0, fade_out_time)
	tween.tween_callback(_on_toast_finished)


func _on_toast_finished() -> void:
	_slide.visible = false
	_play_next()


func _on_fragment_collected(_id: int, count: int, total: int) -> void:
	var subtitle := all_fragments_subtitle if count >= total else fragment_subtitle
	show_toast(fragment_title % [count, total], subtitle)


func _on_node_added(node: Node) -> void:
	if node is Player:
		_watch_player(node)


func _watch_player(player: Node) -> void:
	if player.has_signal(&"ability_unlocked") and not player.is_connected(&"ability_unlocked", _on_ability_unlocked):
		player.connect(&"ability_unlocked", _on_ability_unlocked)


func _on_ability_unlocked(ability: StringName) -> void:
	var texts: Variant = ability_texts.get(ability)
	if texts is Array and texts.size() >= 2:
		show_toast(texts[0], texts[1])

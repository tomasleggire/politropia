class_name HookItem
extends Area2D

## Fragmento brillante de la sala 1: gancho visual inmediato.

signal collected

@export var story_text: String = "queda algo arriba"
@export var pickup_stream: AudioStream
@export var notice_stream: AudioStream

var _story: StoryLine
var _visual: Polygon2D
var _glow: Polygon2D
var _base_y: float = 0.0
var _time: float = 0.0
var _noticed: bool = false
var _sfx: AudioStreamPlayer
var _notice_sfx: AudioStreamPlayer


func setup(story: StoryLine) -> void:
	_story = story


func _ready() -> void:
	_base_y = position.y
	monitoring = true
	collision_layer = 0
	collision_mask = 1

	_glow = Polygon2D.new()
	_glow.color = Color(1.0, 0.85, 0.35, 0.22)
	_glow.polygon = _make_diamond(34.0)
	add_child(_glow)

	_visual = Polygon2D.new()
	_visual.color = Color(1.0, 0.92, 0.45, 1.0)
	_visual.polygon = _make_diamond(16.0)
	add_child(_visual)

	var ring := Polygon2D.new()
	ring.color = Color(1.0, 0.7, 0.2, 0.55)
	ring.polygon = _make_ring(22.0, 18.0)
	add_child(ring)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 26.0
	col.shape = shape
	add_child(col)

	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"Master"
	_sfx.volume_db = -2.0
	if pickup_stream != null:
		_sfx.stream = pickup_stream
	add_child(_sfx)

	_notice_sfx = AudioStreamPlayer.new()
	_notice_sfx.bus = &"Master"
	_notice_sfx.volume_db = -10.0
	if notice_stream != null:
		_notice_sfx.stream = notice_stream
	add_child(_notice_sfx)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_visual.rotation = sin(_time * 1.8) * 0.25
	_glow.scale = Vector2.ONE * (1.0 + 0.12 * sin(_time * 3.0))
	position.y = _base_y + sin(_time * 2.4) * 10.0

	# Aviso suave la primera vez que el jugador está cerca en X (misma sala).
	if not _noticed:
		var players := get_tree().get_nodes_in_group("player")
		for node in players:
			if node is Node2D and absf((node as Node2D).global_position.x - global_position.x) < 220.0:
				_noticed = true
				if _notice_sfx.stream != null:
					_notice_sfx.play()
				break


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if _sfx.stream != null:
		_sfx.play()
	if _story != null:
		_story.show_line(story_text, &"hook_item")
	body.set_meta("has_fragment", true)
	collected.emit()
	visible = false
	set_deferred("monitoring", false)
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(0.35).timeout
	queue_free()


func _make_diamond(r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -r),
		Vector2(r * 0.7, 0),
		Vector2(0, r),
		Vector2(-r * 0.7, 0),
	])


func _make_ring(outer_r: float, inner_r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(Vector2(cos(a), sin(a)) * outer_r)
	for i in range(steps - 1, -1, -1):
		var a := float(i) / float(steps) * TAU
		pts.append(Vector2(cos(a), sin(a)) * inner_r)
	return pts

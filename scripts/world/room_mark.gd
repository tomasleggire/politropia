class_name RoomMark
extends Area2D

## Marca en la pared: glyphs torcidos (parcial) o alineados (resuelto).

signal revealed(mark_id: StringName)

@export var mark_id: StringName = &"mark"
@export var story_text: String = ""
@export var resolved: bool = false
@export var glyph_color: Color = Color(0.92, 0.86, 0.72, 0.85)
@export var whisper_stream: AudioStream

var _story: StoryLine
var _time: float = 0.0
var _triggered: bool = false
var _sfx: AudioStreamPlayer


func setup(story: StoryLine) -> void:
	_story = story


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1

	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 90)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"Master"
	_sfx.volume_db = -8.0
	if whisper_stream != null:
		_sfx.stream = whisper_stream
	add_child(_sfx)

	body_entered.connect(_on_body_entered)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var base := Vector2(-24, -30)
	if resolved:
		_draw_aligned(base)
	else:
		_draw_twisted(base)


func _draw_twisted(base: Vector2) -> void:
	var jitter := sin(_time * 1.7) * 1.2
	# Tres trazos desalineados (casi letras, nunca texto).
	draw_line(base + Vector2(0, jitter), base + Vector2(8, 40 + jitter), glyph_color, 3.0, true)
	draw_line(base + Vector2(18, -4 - jitter), base + Vector2(6, 36), glyph_color, 3.0, true)
	draw_line(base + Vector2(28, 6), base + Vector2(42, 2 + jitter * 2.0), glyph_color, 3.0, true)
	draw_circle(base + Vector2(12, -10), 3.0, Color(glyph_color.r, glyph_color.g, glyph_color.b, 0.5))


func _draw_aligned(base: Vector2) -> void:
	var pulse := 0.75 + 0.25 * sin(_time * 2.2)
	var c := Color(glyph_color.r, glyph_color.g, glyph_color.b, glyph_color.a * pulse)
	draw_line(base + Vector2(0, 0), base + Vector2(0, 42), c, 3.5, true)
	draw_line(base + Vector2(0, 0), base + Vector2(22, 0), c, 3.5, true)
	draw_line(base + Vector2(0, 21), base + Vector2(16, 21), c, 3.5, true)
	draw_line(base + Vector2(30, 0), base + Vector2(30, 42), c, 3.5, true)
	draw_line(base + Vector2(30, 42), base + Vector2(48, 42), c, 3.5, true)


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not (body is Player):
		return
	_triggered = true
	if _sfx.stream != null:
		_sfx.play()
	if _story != null and story_text != "":
		_story.show_line(story_text, mark_id)
	revealed.emit(mark_id)

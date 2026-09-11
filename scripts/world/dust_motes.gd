extends Node2D

## Polvo flotante decorativo por sala.

var room_origin: Vector2 = Vector2.ZERO
var room_size: Vector2 = Vector2(720, 1280)
var mote_count: int = 18
var mote_color: Color = Color(1, 1, 1, 0.25)

var _motes: Array[Dictionary] = []


func _ready() -> void:
	for i in mote_count:
		_motes.append({
			"pos": Vector2(
				room_origin.x + fmod(float(i * 97 + 13), room_size.x),
				room_origin.y + fmod(float(i * 53 + 29), room_size.y)
			),
			"speed": 8.0 + float(i % 5) * 3.0,
			"phase": float(i) * 0.7,
			"size": 1.5 + float(i % 3),
		})


func _process(delta: float) -> void:
	queue_redraw()
	for mote in _motes:
		mote["phase"] = float(mote["phase"]) + delta
		var p: Vector2 = mote["pos"]
		p.y -= float(mote["speed"]) * delta * 0.35
		p.x += sin(float(mote["phase"]) * 0.8) * 6.0 * delta
		if p.y < room_origin.y:
			p.y = room_origin.y + room_size.y
		if p.x < room_origin.x:
			p.x = room_origin.x + room_size.x
		if p.x > room_origin.x + room_size.x:
			p.x = room_origin.x
		mote["pos"] = p


func _draw() -> void:
	for mote in _motes:
		var p: Vector2 = mote["pos"]
		var s: float = mote["size"]
		var a := mote_color.a * (0.55 + 0.45 * sin(float(mote["phase"])))
		draw_circle(p, s, Color(mote_color.r, mote_color.g, mote_color.b, a))

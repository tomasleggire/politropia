class_name AltarDriftSheets
extends Node2D

## Two loose sheets that fall slowly through the light shaft, fluttering as
## they turn. They keep the idle altar alive and stay behind Luz.

@export_group("Fall")
@export var top_y := -150.0
@export var bottom_y := -36.0
@export var periods := PackedFloat32Array([24.0, 30.0])
@export var phases := PackedFloat32Array([0.15, 0.62])
@export var sway := PackedFloat32Array([9.0, 12.0])
@export var start_x := 13.0
@export_range(0.0, 0.5, 0.01) var lean := 0.09
@export_range(0.0, 1.0, 0.05) var max_alpha := 0.85

var _sheets: Array[Sprite2D] = []
var _base_scale := Vector2.ONE


func _ready() -> void:
	for child: Node in get_children():
		var sheet := child as Sprite2D
		if sheet != null:
			_sheets.append(sheet)
	if not _sheets.is_empty():
		_base_scale = _sheets[0].scale
	step(0.0)


## Positions are a pure function of `time`, so the drift is deterministic.
func step(time: float) -> void:
	for i: int in mini(_sheets.size(), mini(periods.size(), mini(phases.size(), sway.size()))):
		var life := fposmod(time / periods[i] + phases[i], 1.0)
		var y := lerpf(top_y, bottom_y, life)
		var flutter := time * 0.9 + float(i) * 2.3
		var sheet := _sheets[i]
		# The beam leans in from the right: its centre moves left as it falls.
		sheet.position = Vector2(start_x + sin(time * 0.45 + float(i) * 1.7) * sway[i] + lean * (top_y - y), y)
		sheet.rotation = sin(time * 0.7 + float(i) * 1.3) * 0.6
		sheet.scale = Vector2(_base_scale.x * (0.35 + 0.65 * absf(cos(flutter))), _base_scale.y)
		sheet.modulate.a = max_alpha * sqrt(sin(PI * life))

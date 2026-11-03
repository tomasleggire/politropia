class_name MainMenuStage
extends Node2D
## Painted "El Umbral" backdrop of the main menu. Everything lives in the
## 1672x941 art space of the layers; the stage itself is scaled to COVER the
## viewport so wider phones never show gaps. Ambient life (parallax drift, god
## rays, sun glow, candle flicker, golden dust) is built and animated here.

const ART_SIZE := Vector2(1672.0, 941.0)
const ART_CENTER := ART_SIZE * 0.5
const SUN_POSITION := Vector2(1100.0, 330.0)
const LUZ_SCALE := 0.787  # 261 art px tall: ~100 viewport px at 640x360.
const CANDLE_POSITIONS: Array[Vector2] = [
	Vector2(45.0, 690.0),
	Vector2(748.0, 255.0),
	Vector2(460.0, 30.0),
	Vector2(1610.0, 160.0),
	Vector2(1560.0, 600.0),
]
## Beam origin (art space), width, length and breathing phase.
const BEAMS: Array[Dictionary] = [
	{"origin": Vector2(1230.0, 90.0), "width": 150.0, "length": 900.0, "phase": 0.0},
	{"origin": Vector2(1120.0, 130.0), "width": 80.0, "length": 820.0, "phase": 1.7},
	{"origin": Vector2(1300.0, 70.0), "width": 100.0, "length": 760.0, "phase": 3.1},
	{"origin": Vector2(1010.0, 190.0), "width": 55.0, "length": 700.0, "phase": 4.6},
]

@export_group("Parallax")
@export var vista_overscan := 1.05
@export var arch_overscan := 1.03
@export var vista_drift := Vector2(13.0, 5.0)  # art px
@export var arch_drift := Vector2(4.5, 1.7)
@export var drift_period := 18.0  # seconds

@export_group("Luz")
@export var luz_position := Vector2(1115.0, 790.0)
@export var luz_tint := Color(0.52, 0.52, 0.74)
@export var shadow_size := Vector2(150.0, 26.0)

@export_group("Light")
@export var beam_direction_degrees := 133.0
@export var beam_alpha := 0.5
@export var beam_breath_period := 7.0
@export var sun_glow_alpha := 0.5
@export var sun_pulse_period := 5.0
@export var candle_alpha := 0.55
@export var candle_flicker_speed := 2.4
@export var dust_amount := 40

var _time := 0.0
var _beams: Array[Polygon2D] = []
var _sun_glow: Sprite2D
var _candles: Array[Sprite2D] = []
var _noise := FastNoiseLite.new()

@onready var _vista_layer: Node2D = $VistaLayer
@onready var _arch_layer: Node2D = $ArchLayer
@onready var luz: AnimatedSprite2D = %Luz


## Scale + offset that map the art space onto a viewport so it covers it fully.
static func compute_stage_transform(viewport_size: Vector2) -> Transform2D:
	var s := maxf(viewport_size.x / ART_SIZE.x, viewport_size.y / ART_SIZE.y)
	var offset := (viewport_size - ART_SIZE * s) * 0.5
	return Transform2D(0.0, Vector2(s, s), 0.0, offset)


static func make_radial_texture(size: int, hard_stop: float = 1.0) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, hard_stop * 0.45, hard_stop])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


static func additive_material() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material


func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 1.0
	luz.sprite_frames = LuzAnimationCatalog.build_sprite_frames()
	luz.position = luz_position
	luz.offset = Vector2(0.0, -157.0)  # Feet row of the 512 px cells at y = 0.
	luz.scale = Vector2.ONE * LUZ_SCALE
	luz.modulate = luz_tint
	luz.play(&"idle")
	_build_contact_shadow()
	_build_sun_glow()
	_build_beams()
	_build_candles()
	_build_dust()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	_apply_drift()


func _process(delta: float) -> void:
	_time += delta
	_apply_drift()
	for i in _beams.size():
		var wave := 0.5 + 0.5 * sin(TAU * _time / beam_breath_period + float(BEAMS[i]["phase"]))
		_beams[i].modulate.a = beam_alpha * (0.45 + 0.55 * wave)
	var pulse := 0.5 + 0.5 * sin(TAU * _time / sun_pulse_period)
	_sun_glow.modulate.a = sun_glow_alpha * (0.7 + 0.3 * pulse)
	for i in _candles.size():
		var flicker := _noise.get_noise_1d(_time * candle_flicker_speed + float(i) * 37.0)
		_candles[i].modulate.a = candle_alpha * clampf(0.8 + 0.45 * flicker, 0.35, 1.0)


func _fit_to_viewport() -> void:
	transform = compute_stage_transform(get_viewport_rect().size)


func _apply_drift() -> void:
	var wave := sin(TAU * _time / drift_period)
	var lift := sin(TAU * _time / (drift_period * 1.3) + 1.0)
	_place_layer(_vista_layer, vista_overscan, vista_drift, wave, lift)
	_place_layer(_arch_layer, arch_overscan, arch_drift, wave, lift)


## Scales a layer about the art center (overscan) and offsets it by the drift.
func _place_layer(layer: Node2D, overscan: float, drift: Vector2, wave: float, lift: float) -> void:
	layer.scale = Vector2.ONE * overscan
	layer.position = ART_CENTER * (1.0 - overscan) + Vector2(drift.x * wave, drift.y * lift)


func _build_contact_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "ContactShadow"
	shadow.texture = make_radial_texture(64)
	shadow.position = luz_position + Vector2(0.0, 3.0)
	shadow.scale = shadow_size / 64.0
	shadow.modulate = Color(0.02, 0.01, 0.05, 0.9)
	_arch_layer.add_child(shadow)
	_arch_layer.move_child(shadow, luz.get_index())


func _build_sun_glow() -> void:
	_sun_glow = Sprite2D.new()
	_sun_glow.name = "SunGlow"
	_sun_glow.texture = make_radial_texture(128)
	_sun_glow.material = additive_material()
	_sun_glow.position = SUN_POSITION
	_sun_glow.scale = Vector2.ONE * 4.2
	_sun_glow.modulate = Color(1.0, 0.82, 0.5, sun_glow_alpha)
	_vista_layer.add_child(_sun_glow)


func _build_beams() -> void:
	var edge := Gradient.new()
	edge.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	edge.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var edge_texture := GradientTexture2D.new()
	edge_texture.gradient = edge
	edge_texture.width = 64
	edge_texture.height = 2
	edge_texture.fill_from = Vector2(0.0, 0.0)
	edge_texture.fill_to = Vector2(1.0, 0.0)
	for beam in BEAMS:
		_beams.append(_make_beam(beam, edge_texture))


func _make_beam(beam: Dictionary, edge_texture: Texture2D) -> Polygon2D:
	var half: float = float(beam["width"]) * 0.5
	var length: float = beam["length"]
	var poly := Polygon2D.new()
	poly.name = "Beam"
	poly.texture = edge_texture
	poly.material = additive_material()
	poly.polygon = PackedVector2Array([
		Vector2(0.0, -half), Vector2(length, -half * 1.5),
		Vector2(length, half * 1.5), Vector2(0.0, half)
	])
	poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(64, 0), Vector2(64, 0)])
	var head := Color(1.0, 0.86, 0.55, 1.0)
	var tail := Color(1.0, 0.8, 0.5, 0.3)
	poly.vertex_colors = PackedColorArray([head, tail, tail, head])
	poly.position = beam["origin"]
	poly.rotation = deg_to_rad(beam_direction_degrees)
	poly.modulate.a = beam_alpha
	_arch_layer.add_child(poly)
	return poly


func _build_candles() -> void:
	var texture := make_radial_texture(64)
	for candle_position in CANDLE_POSITIONS:
		var glow := Sprite2D.new()
		glow.name = "CandleGlow"
		glow.texture = texture
		glow.material = additive_material()
		glow.position = candle_position
		glow.scale = Vector2.ONE * 1.9
		glow.modulate = Color(1.0, 0.68, 0.3, candle_alpha)
		_arch_layer.add_child(glow)
		_candles.append(glow)


func _build_dust() -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([
		Color(1, 0.85, 0.5, 0), Color(1, 0.85, 0.5, 0.9),
		Color(1, 0.85, 0.5, 0.9), Color(1, 0.85, 0.5, 0)
	])
	var dust := CPUParticles2D.new()
	dust.name = "Dust"
	dust.texture = make_radial_texture(8)
	dust.material = additive_material()
	dust.position = Vector2(920.0, 400.0)
	dust.amount = dust_amount
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(340.0, 240.0)
	dust.direction = Vector2(-1.0, 0.5)
	dust.spread = 35.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 6.0
	dust.initial_velocity_max = 16.0
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 2.2
	dust.color_ramp = fade
	_arch_layer.add_child(dust)

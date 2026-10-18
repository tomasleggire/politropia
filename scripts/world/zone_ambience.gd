@tool
class_name ZoneAmbience
extends Node2D

## Drop ONE `scenes/world/zone_ambience.tscn` in each zone. Pick the biome look
## in `style` (data/ambience/library.tres or greece.tres): it tints the world
## and adds a soft vignette. Both live on layers below the HUD, so the UI is
## never tinted. Luz also gets a small light so she reads in dark tints.

const LUZ_LIGHT_NAME := "AmbienceLuzLight"
const AMBIENT_LIGHT := preload("res://scenes/world/ambient_light.tscn")

@export var style: AmbienceStyle:
	set(value):
		style = value
		_apply()
## 0 leaves the world untinted, 1 applies the full style tint.
@export_range(0.0, 1.0, 0.05) var tint_strength := 1.0:
	set(value):
		tint_strength = value
		_apply()
@export var vignette_enabled := true:
	set(value):
		vignette_enabled = value
		_apply()

@export_group("Luz")
## Adds the small light that follows Luz.
@export var luz_light_enabled := true

@onready var _tint: CanvasModulate = $Tint
@onready var _vignette: ColorRect = $VignetteLayer/Vignette


func _ready() -> void:
	_apply()
	if not Engine.is_editor_hint():
		_attach_luz_light.call_deferred()


func _apply() -> void:
	if not is_node_ready():
		return
	var look := style if style != null else AmbienceStyle.new()
	_tint.color = Color.WHITE.lerp(look.tint_color, tint_strength)
	_vignette.visible = vignette_enabled and look.vignette_strength > 0.0
	var material := _vignette.material as ShaderMaterial
	material.set_shader_parameter(&"level", 1.0)
	material.set_shader_parameter(&"max_darkness", look.vignette_strength)
	material.set_shader_parameter(&"tint", Vector3(look.vignette_color.r, look.vignette_color.g, look.vignette_color.b))


func _attach_luz_light() -> void:
	if not luz_light_enabled or style == null:
		return
	var luz := get_tree().get_first_node_in_group(&"player")
	if luz == null or luz.has_node(LUZ_LIGHT_NAME):
		return
	var light := AMBIENT_LIGHT.instantiate() as AmbientLight
	light.name = LUZ_LIGHT_NAME
	light.light_color = style.luz_light_color
	light.base_energy = style.luz_light_energy
	light.radius = style.luz_light_radius
	light.position = Vector2(0.0, -20.0)
	luz.add_child(light)

class_name TutorialSign
extends Node2D

## A world signpost that teaches something. Drag `scenes/world/tutorial_sign.tscn`
## into a zone, put its base on the floor, then fill in the Inspector:
##   - Content: `title` and `text` (BBCode ok, e.g. [color=#e0b94f]word[/color]).
##   - Look: `marker_style` picks what marks the spot: a small firefly swarm
##     (default, it does not look interactable), the old signpost, or nothing.
##   - Trigger: size and offset of the area that makes the panel appear.
##   - Behavior: `show_once` makes it appear only the first time Luz reads it
##     during a run (reset by New Game).
## When Luz walks into the trigger a gothic text panel fades in at the top of
## the screen (screen space, so it stays readable on a phone); it fades out
## when she leaves. The panel uses `assets/ui/gothic_theme.tres`.

@export_group("Content")
@export var title := ""
@export_multiline var text := ""

@export_group("Look")
## What marks the spot in the world. The panel works the same in every style.
@export var marker_style := MarkerStyle.FIREFLIES
@export_group("Fireflies")
## How many fireflies of the small swarm are shown.
@export_range(1, 7) var firefly_count := 4
## Size of the area the fireflies drift in (pixels).
@export var firefly_radii := Vector2(26.0, 11.0)
## Height of the swarm above the sign's base (pixels, positive is up).
@export var firefly_height := 30.0
@export_range(0.0, 1.0, 0.05) var firefly_brightness := 0.85

@export_group("Trigger")
## Size of the area (pixels) that shows the panel. The origin is the sign's base.
@export var trigger_size := Vector2(140.0, 90.0)
## Offset of the area's center from the sign's base. Negative y is up.
@export var trigger_offset := Vector2(0.0, -36.0)

@export_group("Behavior")
## Show only the first time per run. Re-entering the room keeps it hidden.
@export var show_once := false
@export_range(0.05, 1.5, 0.05) var fade_time := 0.3

@export_group("Panel")
@export_range(120.0, 460.0, 10.0) var panel_width := 280.0
## Distance from the top of the screen to the panel (clears the HUD and toasts).
@export var panel_top := 100.0
@export var center_text := true

enum MarkerStyle { FIREFLIES, SIGNPOST, NONE }

const FIREFLY_SWARM := preload("res://scenes/world/firefly_swarm.tscn")

## `sign key -> true` for every show-once sign already read this run.
static var _seen: Dictionary = {}

var _reading := false
var _fade_tween: Tween
var _hint_tween: Tween

@onready var _area: Area2D = $TriggerArea
@onready var _shape: CollisionShape2D = $TriggerArea/CollisionShape2D
@onready var _visual: Node2D = $Visual
@onready var _hint: Polygon2D = $Visual/Hint
@onready var _root: Control = $PanelLayer/Root
@onready var _panel: PanelContainer = $PanelLayer/Root/Panel
@onready var _title_label: Label = $PanelLayer/Root/Panel/Margin/Box/Title
@onready var _body: RichTextLabel = $PanelLayer/Root/Panel/Margin/Box/Body


## Forgets every read show-once sign (new game, tests).
static func reset_seen() -> void:
	_seen.clear()


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = trigger_size
	_shape.shape = rect
	_area.position = trigger_offset
	_title_label.text = title
	_title_label.visible = not title.is_empty()
	_body.text = "[center]%s[/center]" % text if center_text else text
	_panel.custom_minimum_size.x = panel_width
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.offset_top = panel_top
	_root.modulate.a = 0.0
	_root.visible = false
	_visual.visible = marker_style == MarkerStyle.SIGNPOST
	if marker_style == MarkerStyle.FIREFLIES:
		_add_fireflies()
	if marker_style != MarkerStyle.SIGNPOST or (show_once and is_seen()):
		_hint.visible = false
	else:
		_start_hint_pulse()
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _add_fireflies() -> void:
	var swarm := FIREFLY_SWARM.instantiate() as FireflySwarm
	swarm.name = "Fireflies"
	swarm.base_active = firefly_count
	swarm.brightness = firefly_brightness
	swarm.wander_center = Vector2(0.0, -firefly_height)
	swarm.wander_radii = firefly_radii
	add_child(swarm)
	swarm.setup(hash(name))


func has_fireflies() -> bool:
	return get_node_or_null("Fireflies") != null


func is_seen() -> bool:
	return _seen.has(_key())


func is_panel_visible() -> bool:
	return _root.visible and _root.modulate.a > 0.0


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player") or _reading:
		return
	if show_once and is_seen():
		return
	_reading = true
	_fade_panel(1.0)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"player") or not _reading:
		return
	_reading = false
	_fade_panel(0.0)
	if show_once:
		_seen[_key()] = true
		_hint.visible = false


func _key() -> String:
	var scene_path := owner.scene_file_path if owner != null else ""
	return "%s:%s" % [scene_path, name]


func _fade_panel(alpha: float) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	if alpha > 0.0:
		_root.visible = true
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_root, "modulate:a", alpha, fade_time)
	if alpha <= 0.0:
		_fade_tween.tween_callback(func() -> void: _root.visible = false)


func _start_hint_pulse() -> void:
	_hint_tween = create_tween().set_loops()
	_hint_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 1.1).from(0.35)
	_hint_tween.tween_property(_hint, "modulate:a", 0.35, 1.1)

class_name HealthHud
extends CanvasLayer

## Hollow Knight style health: one pip per point of max health, top-left
## inside the safe area (so a notch or Dynamic Island never covers it). It
## sits above the altar vignette (30) and below the touch controls (100),
## which live at the bottom of the screen. It listens to the player's
## health_changed, which also covers hits, the desk heal and the respawn.
## It keeps processing while the tree is paused: the desk freezes the world
## during a rest but heals at the celebration peak, and the refill must show
## right then, not when Luz stands up.

const HUD_LAYER := 40

@export_group("Layout")
@export var pip_size := Vector2(15.0, 15.0)
@export var pip_spacing := 4.0
## Distance from the safe area's top-left corner to the first pip.
@export var edge_margin := Vector2(12.0, 10.0)

@export_group("Art")
## Optional final art for every pip; the drawn placeholder is used when unset.
@export var full_texture: Texture2D
@export var empty_texture: Texture2D

@export_group("Soul Meter")
@export var meter_size := Vector2(22.0, 22.0)
## Optional final art for the soul vessel; the drawn placeholder is used when unset.
@export var meter_full_texture: Texture2D
@export var meter_empty_texture: Texture2D

@export_group("Feedback")
## Delay between consecutive pips when several refill at once.
@export var refill_stagger := 0.08

var _player: Player
var _pips: Array[HealthPip] = []
var _meter: SoulMeter
var _shown := 0
var _safe_override := Rect2()

@onready var _row: HBoxContainer = $Root/Pips


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = HUD_LAYER
	_row.add_theme_constant_override(&"separation", int(pip_spacing))
	_build_meter()
	get_viewport().size_changed.connect(_place)
	_place()
	if _player == null:
		var found := get_tree().get_first_node_in_group(&"player") as Player
		if found != null:
			bind_player(found)


func bind_player(player: Player) -> void:
	if _player != null and _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.disconnect(_on_health_changed)
		_player.soul_changed.disconnect(_on_soul_changed)
	_player = player
	if _player == null:
		return
	_player.health_changed.connect(_on_health_changed)
	_player.soul_changed.connect(_on_soul_changed)
	_on_soul_changed(_player.get_soul(), _player.get_max_soul())
	_rebuild(_player.get_max_health())
	_show_instantly(_player.get_health())


func is_bound() -> bool:
	return _player != null


func get_pips() -> Array[HealthPip]:
	return _pips


func get_meter() -> SoulMeter:
	return _meter


## Rect (in viewport pixels) the HUD must stay inside. On a phone it is the
## display's safe area mapped to the viewport; elsewhere the whole viewport.
func get_safe_rect() -> Rect2:
	if _safe_override.has_area():
		return _safe_override
	var viewport_rect := get_viewport().get_visible_rect()
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if not OS.has_feature("mobile") or window.x <= 0.0 or window.y <= 0.0 or not safe.has_area():
		return viewport_rect
	var factor := viewport_rect.size / window
	var mapped := Rect2(safe.position * factor, safe.size * factor).intersection(viewport_rect)
	return mapped if mapped.has_area() else viewport_rect


## Pins the safe area to `rect` (viewport pixels), e.g. for tests or previews.
func set_safe_area(rect: Rect2) -> void:
	_safe_override = rect
	_place()


func _place() -> void:
	_row.position = get_safe_rect().position + edge_margin
	if _meter != null:
		_meter.position = _row.position + Vector2(0.0, pip_size.y + pip_spacing)


func _build_meter() -> void:
	_meter = SoulMeter.new()
	_meter.custom_minimum_size = meter_size
	_meter.size = meter_size
	_meter.full_texture = meter_full_texture
	_meter.empty_texture = meter_empty_texture
	$Root.add_child(_meter)


func _on_soul_changed(current: int, maximum: int) -> void:
	_meter.set_soul(current, maximum, current >= _player.focus_cost)


func _on_health_changed(current: int, maximum: int) -> void:
	if maximum != _pips.size():
		_rebuild(maximum)
		_show_instantly(current)
		return
	var count := clampi(current, 0, maximum)
	for index: int in range(count, _shown):
		_pips[index].play_lose()
	for index: int in range(_shown, count):
		_pips[index].play_refill(float(index - _shown) * refill_stagger)
	_shown = count


func _show_instantly(current: int) -> void:
	_shown = clampi(current, 0, _pips.size())
	for index: int in _pips.size():
		_pips[index].set_full(index < _shown)


func _rebuild(maximum: int) -> void:
	for pip: HealthPip in _pips:
		_row.remove_child(pip)
		pip.queue_free()
	_pips.clear()
	for index: int in maxi(maximum, 0):
		var pip := HealthPip.new()
		pip.custom_minimum_size = pip_size
		pip.full_texture = full_texture
		pip.empty_texture = empty_texture
		_row.add_child(pip)
		_pips.append(pip)

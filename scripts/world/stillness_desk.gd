@tool
class_name StillnessDesk
extends Node2D

## Reusable checkpoint: a school desk fused with a cathedral lectern. Resting
## is one transaction (commit -> rest -> release) that heals Luz, records the
## checkpoint in `CheckpointService`, regenerates resettable enemies and hands
## control back only when the activation sequence is over. Global checkpoint
## state lives in the service; this node owns interaction and presentation.
## All art lives under `Visuals` so final sprites can replace it without
## touching this logic.

signal rest_started(checkpoint_id: StringName)
signal rest_completed(checkpoint_id: StringName)
signal phase_changed(phase: Phase)

enum Phase { DORMANT, AWAKENED, COMMIT, RESTING, RELEASE }

## Touch controls call `request_interact()` on this group; only the desk with
## Luz in range accepts it.
const INTERACTABLE_GROUP := &"interactable"
const AWAKENED_INTENSITY := 0.4
const PARALLAX_STRENGTH := 0.06
const PARALLAX_LIMIT := 10.0

@export_group("Checkpoint")
## Unique per checkpoint across the whole game. Required.
@export var checkpoint_id: StringName = &""

@export_group("Rest Sequence")
## Time Luz holds the committed pose before the effects apply.
@export_range(0.0, 3.0, 0.05) var commit_duration := 0.5
## Time the restoring effects play (heal, save, enemy reset feedback).
@export_range(0.0, 5.0, 0.05) var resting_duration := 1.6
## Time the desk settles before control returns.
@export_range(0.0, 3.0, 0.05) var release_duration := 0.5
## Freeze the rest of the world while Luz rests.
@export var pause_world := true

var _phase := Phase.DORMANT
var _run_id := 0
var _player: Player
var _transaction_player: Player
var _paused_by_desk := false
var _time := 0.0
var _intensity := 0.0
var _lift := 0.0
var _intensity_tween: Tween
var _lift_tween: Tween

@onready var _anchor: Marker2D = $SpawnAnchor
@onready var _area: Area2D = $InteractionArea
@onready var _prompt: InteractionPrompt = $InteractionPrompt
@onready var _background: Node2D = %Background
@onready var _glow: Node2D = %Glow
@onready var _candle_glow: Node2D = %CandleGlow
@onready var _flame: Node2D = %Flame
@onready var _ink_glow: Node2D = %InkGlow
@onready var _ripple: Node2D = %Ripple
@onready var _papers: Node2D = %Papers
@onready var _pendulum: Node2D = %Pendulum
@onready var _beam: Node2D = %Beam
@onready var _pan_left: Node2D = %PanLeft
@onready var _pan_right: Node2D = %PanRight
@onready var _mist: CPUParticles2D = %Mist


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(INTERACTABLE_GROUP)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	CheckpointService.checkpoint_activated.connect(_on_checkpoint_activated)
	_sync_resting_phase()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if CheckpointService.checkpoint_activated.is_connected(_on_checkpoint_activated):
		CheckpointService.checkpoint_activated.disconnect(_on_checkpoint_activated)
	_abort_transaction()
	TouchControls.set_interact_available(self, false)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if checkpoint_id == &"":
		warnings.append("checkpoint_id is required and must be unique per checkpoint.")
	return warnings


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and request_rest():
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_animate_environment()


## Public entry point for the keyboard action and future touch buttons.
## Returns true when a rest transaction started.
func request_rest() -> bool:
	if not can_rest():
		return false
	_run_rest(_player)
	return true


## Generic entry point for the touch Interact button.
func request_interact() -> bool:
	return request_rest()


func can_rest() -> bool:
	return (
		checkpoint_id != &""
		and _is_idle()
		and _player != null
		and is_instance_valid(_player)
		and _player.is_inside_tree()
		and not _player.is_meditating()
	)


func get_phase() -> Phase:
	return _phase


func get_spawn_position() -> Vector2:
	return _anchor.global_position


# -- Transaction ---------------------------------------------------------------

func _run_rest(player: Player) -> void:
	_run_id += 1
	var run := _run_id
	_transaction_player = player
	player.tree_exiting.connect(_on_player_tree_exiting)
	_set_phase(Phase.COMMIT)
	_commit(player)
	rest_started.emit(checkpoint_id)
	_tween_intensity(1.0, commit_duration)
	if not await _wait(commit_duration, run):
		return

	_set_phase(Phase.RESTING)
	_apply_rest_effects(player)
	_pulse_papers(resting_duration)
	if not await _wait(resting_duration, run):
		return

	_set_phase(Phase.RELEASE)
	_tween_intensity(AWAKENED_INTENSITY, release_duration)
	if not await _wait(release_duration, run):
		return

	_finish_transaction()
	_sync_resting_phase()
	rest_completed.emit(checkpoint_id)


func _commit(player: Player) -> void:
	_prompt.hide_prompt()
	TouchControls.set_interact_available(self, false)
	player.global_position = _anchor.global_position
	player.velocity = Vector2.ZERO
	player.enter_meditation()
	if pause_world:
		get_tree().paused = true
		_paused_by_desk = true


func _apply_rest_effects(player: Player) -> void:
	player.restore_full_health()
	player.apply_checkpoint(_anchor.global_position)
	CheckpointService.activate(checkpoint_id, _owner_scene_path(), _anchor.global_position)
	CheckpointService.reset_resettable_enemies()


## Waits `seconds` on a tween bound to this node. Returns false when the
## transaction was aborted meanwhile; if the desk itself is freed the tween
## dies with it and the caller simply never resumes.
func _wait(seconds: float, run: int) -> bool:
	var timer := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	timer.tween_interval(maxf(seconds, 0.001))
	await timer.finished
	return run == _run_id and _phase in [Phase.COMMIT, Phase.RESTING, Phase.RELEASE]


func _finish_transaction() -> void:
	if _paused_by_desk and is_inside_tree():
		get_tree().paused = false
	_paused_by_desk = false
	var player := _transaction_player
	_transaction_player = null
	if player != null and is_instance_valid(player):
		if player.tree_exiting.is_connected(_on_player_tree_exiting):
			player.tree_exiting.disconnect(_on_player_tree_exiting)
		player.exit_meditation()


## Safe from any point of a running transaction (desk or player leaving).
func _abort_transaction() -> void:
	if _phase in [Phase.DORMANT, Phase.AWAKENED]:
		return
	_run_id += 1
	_finish_transaction()
	_phase = Phase.DORMANT


func _on_player_tree_exiting() -> void:
	_abort_transaction()
	_sync_resting_phase()


func _owner_scene_path() -> String:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path != "":
		return current.scene_file_path
	if owner != null:
		return owner.scene_file_path
	return ""


func _is_idle() -> bool:
	return _phase == Phase.DORMANT or _phase == Phase.AWAKENED


func _set_phase(phase: Phase) -> void:
	_phase = phase
	phase_changed.emit(phase)


func _sync_resting_phase() -> void:
	var awakened := CheckpointService.is_active(checkpoint_id, _owner_scene_path())
	_set_phase(Phase.AWAKENED if awakened else Phase.DORMANT)
	_tween_intensity(AWAKENED_INTENSITY if awakened else 0.0, 0.6)
	_refresh_prompt()


func _on_checkpoint_activated(_id: StringName, _scene_path: String, _spawn: Vector2) -> void:
	if _is_idle():
		_sync_resting_phase()


# -- Interaction ---------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		_refresh_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body == _player and _is_idle():
		_player = null
		_refresh_prompt()


func _refresh_prompt() -> void:
	var available := can_rest()
	if available:
		_prompt.show_prompt()
	else:
		_prompt.hide_prompt()
	TouchControls.set_interact_available(self, available)


# -- Presentation --------------------------------------------------------------

func _tween_intensity(target: float, duration: float) -> void:
	if _intensity_tween != null:
		_intensity_tween.kill()
	_intensity_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_intensity_tween.tween_property(self, "_intensity", target, maxf(duration, 0.001))


## Papers lift off the lectern, fan out, then rebind flat.
func _pulse_papers(duration: float) -> void:
	if _lift_tween != null:
		_lift_tween.kill()
	_lift_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_lift_tween.tween_property(self, "_lift", 1.0, duration * 0.45).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_interval(duration * 0.1)
	_lift_tween.tween_property(self, "_lift", 0.0, duration * 0.45).set_ease(Tween.EASE_IN)


func _animate_environment() -> void:
	var t := _time
	var energy := _intensity
	_pendulum.rotation = sin(t * 1.3) * lerpf(0.12, 0.38, energy)
	_beam.rotation = sin(t * 0.9 + 1.0) * lerpf(0.04, 0.12, energy)
	_pan_left.rotation = -_beam.rotation
	_pan_right.rotation = -_beam.rotation

	var flicker := 1.0 + sin(t * 11.0) * 0.06 + sin(t * 7.3) * 0.09
	_flame.scale = Vector2(1.0 + sin(t * 9.0) * 0.08, flicker + energy * 0.25)
	_candle_glow.modulate.a = clampf(0.75 + (flicker - 1.0) * 1.5 + energy * 0.5, 0.0, 1.5)

	_ripple.scale.x = 1.0 + sin(t * 3.1) * 0.3 * (1.0 + energy)
	_ink_glow.modulate.a = 0.5 + sin(t * 2.4) * 0.2 + energy * 0.6

	var breath := sin(t * 1.6) * 0.12
	_glow.modulate.a = clampf(0.3 + energy * 0.7 + breath, 0.0, 1.5)
	_glow.scale = Vector2.ONE * (0.92 + energy * 0.25 + breath * 0.3)

	_animate_papers(t)
	_mist.speed_scale = 1.0 + energy
	_animate_parallax()


func _animate_papers(t: float) -> void:
	var sheets := _papers.get_children()
	for i in sheets.size():
		var sheet := sheets[i] as Node2D
		var spread := float(i) - 1.0
		sheet.position = Vector2(spread * 6.0 * _lift, -_lift * (10.0 + 5.0 * i) + sin(t * 2.0 + i) * 1.5 * _lift)
		sheet.rotation = spread * 0.35 * _lift + sin(t * 1.7 + i) * 0.08 * _lift


## Background drifts against the camera, bounded so it never detaches.
func _animate_parallax() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var view_center := viewport.get_canvas_transform().affine_inverse() * (viewport.get_visible_rect().size * 0.5)
	var offset := (global_position - view_center) * PARALLAX_STRENGTH
	_background.position = offset.limit_length(PARALLAX_LIMIT)

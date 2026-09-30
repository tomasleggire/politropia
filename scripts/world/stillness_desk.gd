@tool
class_name StillnessDesk
extends Node2D

## Reusable checkpoint: a school desk fused with a cathedral lectern. Resting
## is one ritual: Luz mounts the desk, celebrates (heal, checkpoint and enemy
## reset land at the celebration peak), sits until the player gives input and
## then dismounts. Global checkpoint state lives in the service; this node owns
## interaction, the ritual phases and the static altar layers under `Visuals`.

signal rest_started(checkpoint_id: StringName)
signal rest_completed(checkpoint_id: StringName)
signal phase_changed(phase: Phase)
## Celebration beats other nodes choreograph FX on. `first` is true the first
## time this checkpoint id is ever activated.
signal celebration_started(first: bool)
signal celebration_peak
signal celebration_finished
signal dismount_started
## The `rest_sit` loop wrapped to its first frame; FX re-sync breathing here.
signal breath_cycle_started

enum Phase { DORMANT, AWAKENED, MOUNT, CELEBRATE, RESTING, DISMOUNT }

## Touch controls call `request_interact()` on this group; only the desk with
## Luz in range accepts it.
const INTERACTABLE_GROUP := &"interactable"
const PARALLAX_STRENGTH := 0.06
const PARALLAX_LIMIT := 6.0
## Where the peak (heal, checkpoint, reset) lands in the celebration: the
## first one ignites for 1.2s after 0.6s of stillness; a repeat is condensed.
const FIRST_PEAK_RATIO := 0.6
const REPEAT_PEAK_RATIO := 0.45
## Rest clip frames (0-based) where the backpack leaves and returns to Luz.
const BACKPACK_DROP_FRAME := 3
const BACKPACK_PICKUP_FRAME := 4
const MOUNT_CLIP := &"rest_mount"
const SIT_CLIP := &"rest_sit"
const DISMOUNT_CLIP := &"rest_dismount"
const DEFAULT_BREATH_PERIOD := 2.0
## Extra wait past a clip's length before the ritual advances without its finished signal.
const CLIP_FALLBACK_MARGIN := 0.25
const CLIP_FALLBACK_MIN := 0.5

@export_group("Checkpoint")
## Unique per checkpoint across the whole game. Required.
@export var checkpoint_id: StringName = &""

@export_group("Rest Sequence")
## Celebration length the first time this checkpoint is ever activated.
@export_range(0.0, 6.0, 0.05) var first_celebration_duration := 3.0
## Celebration length for every later rest at this checkpoint.
@export_range(0.0, 3.0, 0.05) var repeat_celebration_duration := 1.0
## Input is ignored this long after resting begins.
@export_range(0.0, 2.0, 0.05) var exit_grace := 0.35
## Freeze the rest of the world while Luz rests.
@export var pause_world := true

## Seconds one `rest_sit` loop takes; FX sync their breathing to it.
var breath_period := DEFAULT_BREATH_PERIOD

var _phase := Phase.DORMANT
var _run_id := 0
var _player: Player
var _transaction_player: Player
var _paused_by_desk := false
var _exit_armed := false

@onready var _anchor: Marker2D = $SpawnAnchor
@onready var _area: Area2D = $InteractionArea
@onready var _prompt: InteractionPrompt = $InteractionPrompt
@onready var _background: Node2D = %Background
@onready var _backpack: Node2D = %BackpackProp


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(INTERACTABLE_GROUP)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	CheckpointService.checkpoint_activated.connect(_on_checkpoint_activated)
	_backpack.visible = false
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


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_animate_parallax()


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


## Seconds from the celebration's start to its peak.
func get_celebration_peak_time(first: bool) -> float:
	if first:
		return first_celebration_duration * FIRST_PEAK_RATIO
	return repeat_celebration_duration * REPEAT_PEAK_RATIO


func get_phase() -> Phase:
	return _phase


func get_spawn_position() -> Vector2:
	return _anchor.global_position


# -- Transaction ---------------------------------------------------------------

func _run_rest(player: Player) -> void:
	_run_id += 1
	_transaction_player = player
	player.tree_exiting.connect(_on_player_tree_exiting)
	player.meditation_finished.connect(_on_meditation_interrupted)
	player.rest_exit_requested.connect(_on_rest_exit_requested)
	player.rest_animation_finished.connect(_on_rest_animation_finished)
	player.rest_animation_frame_changed.connect(_on_rest_animation_frame_changed)
	_exit_armed = false
	_set_phase(Phase.MOUNT)
	_commit(player)
	rest_started.emit(checkpoint_id)
	player.play_rest_animation(MOUNT_CLIP)
	_arm_clip_fallback(MOUNT_CLIP, Phase.MOUNT, _run_id)


func _commit(player: Player) -> void:
	_prompt.hide_prompt()
	TouchControls.set_interact_available(self, false)
	player.global_position = _anchor.global_position
	player.velocity = Vector2.ZERO
	player.enter_meditation()
	# The source art is right-facing and the backpack prop sits left of the desk.
	player.face_direction(1)
	var sit_length := player.get_animation_length(SIT_CLIP)
	breath_period = sit_length if sit_length > 0.0 else DEFAULT_BREATH_PERIOD
	_backpack.visible = false
	if pause_world:
		get_tree().paused = true
		_paused_by_desk = true


func _on_rest_animation_finished(clip: StringName) -> void:
	if clip == MOUNT_CLIP and _phase == Phase.MOUNT:
		_run_celebration(_run_id)
	elif clip == DISMOUNT_CLIP and _phase == Phase.DISMOUNT:
		_complete_dismount()


func _on_rest_animation_frame_changed(clip: StringName, frame: int) -> void:
	if clip == SIT_CLIP and frame == 0:
		breath_cycle_started.emit()
	if clip == MOUNT_CLIP and _phase == Phase.MOUNT and frame >= BACKPACK_DROP_FRAME:
		_backpack.visible = true
	elif clip == DISMOUNT_CLIP and _phase == Phase.DISMOUNT and frame >= BACKPACK_PICKUP_FRAME:
		_backpack.visible = false


func _run_celebration(run: int) -> void:
	var first := not CheckpointService.was_ever_activated(checkpoint_id)
	var duration := first_celebration_duration if first else repeat_celebration_duration
	var peak_time := get_celebration_peak_time(first)
	_set_phase(Phase.CELEBRATE)
	_transaction_player.play_rest_animation(SIT_CLIP)
	celebration_started.emit(first)
	if not await _wait(peak_time, run):
		return
	_apply_rest_effects(_transaction_player)
	celebration_peak.emit()
	if not await _wait(duration - peak_time, run):
		return
	celebration_finished.emit()
	_begin_resting(run)


func _apply_rest_effects(player: Player) -> void:
	player.restore_full_health()
	player.apply_checkpoint(_anchor.global_position)
	CheckpointService.activate(checkpoint_id, _owner_scene_path(), _anchor.global_position)
	CheckpointService.reset_resettable_enemies()


func _begin_resting(run: int) -> void:
	_set_phase(Phase.RESTING)
	_exit_armed = false
	if not await _wait(exit_grace, run):
		return
	_exit_armed = true


func _on_rest_exit_requested() -> void:
	if _phase == Phase.RESTING and _exit_armed:
		_begin_dismount()


func _begin_dismount() -> void:
	_exit_armed = false
	_set_phase(Phase.DISMOUNT)
	dismount_started.emit()
	_transaction_player.play_rest_animation(DISMOUNT_CLIP)
	_arm_clip_fallback(DISMOUNT_CLIP, Phase.DISMOUNT, _run_id)


func _complete_dismount() -> void:
	_finish_transaction()
	_sync_resting_phase()
	rest_completed.emit(checkpoint_id)


## Advances MOUNT/DISMOUNT even when the clip's finished signal never arrives
## (missing clip, dropped signal). The phase check makes it fire exactly once.
func _arm_clip_fallback(clip: StringName, phase: Phase, run: int) -> void:
	var length := _transaction_player.get_animation_length(clip)
	var timeout := 0.0 if length <= 0.0 else maxf(length + CLIP_FALLBACK_MARGIN, CLIP_FALLBACK_MIN)
	if await _wait(timeout, run) and _phase == phase:
		_on_rest_animation_finished(clip)


## Waits `seconds` on a tween bound to this node. Returns false when the
## transaction was aborted meanwhile; if the desk itself is freed the tween
## dies with it and the caller simply never resumes.
func _wait(seconds: float, run: int) -> bool:
	var timer := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	timer.tween_interval(maxf(seconds, 0.001))
	await timer.finished
	return run == _run_id


func _finish_transaction() -> void:
	if _paused_by_desk and is_inside_tree():
		get_tree().paused = false
	_paused_by_desk = false
	_exit_armed = false
	_backpack.visible = false
	var player := _transaction_player
	_transaction_player = null
	if player != null and is_instance_valid(player):
		_disconnect_player(player)
		player.exit_meditation()


func _disconnect_player(player: Player) -> void:
	if player.tree_exiting.is_connected(_on_player_tree_exiting):
		player.tree_exiting.disconnect(_on_player_tree_exiting)
	if player.meditation_finished.is_connected(_on_meditation_interrupted):
		player.meditation_finished.disconnect(_on_meditation_interrupted)
	if player.rest_exit_requested.is_connected(_on_rest_exit_requested):
		player.rest_exit_requested.disconnect(_on_rest_exit_requested)
	if player.rest_animation_finished.is_connected(_on_rest_animation_finished):
		player.rest_animation_finished.disconnect(_on_rest_animation_finished)
	if player.rest_animation_frame_changed.is_connected(_on_rest_animation_frame_changed):
		player.rest_animation_frame_changed.disconnect(_on_rest_animation_frame_changed)


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


## The player left meditation on its own (e.g. respawn) mid-transaction.
func _on_meditation_interrupted() -> void:
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
	if available and not TouchControls.visible:
		_prompt.show_prompt()
	else:
		_prompt.hide_prompt()
	TouchControls.set_interact_available(self, available)


# -- Presentation --------------------------------------------------------------

## Background drifts against the camera, bounded so it never detaches.
func _animate_parallax() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var view_center := viewport.get_canvas_transform().affine_inverse() * (viewport.get_visible_rect().size * 0.5)
	var offset := (global_position - view_center) * PARALLAX_STRENGTH
	_background.position = offset.limit_length(PARALLAX_LIMIT)

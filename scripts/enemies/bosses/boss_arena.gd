@tool
class_name BossArena
extends Node2D

## Drag-and-drop boss fight. Drop `boss_arena.tscn` into a level, size the
## arena, and put the boss (an Artemis instance, or any Enemy with the same small
## contract) in as a child, or point `boss_path` at it.
##
## The fight: Luz walks into the trigger, the two doors close, the camera locks
## to the arena, the name card and the health bar show, and the boss is engaged.
## When Luz dies and wakes up, everything resets and the trigger is armed again.
## When the boss falls, the doors open, the camera is released and the reward
## (the double jump) appears. A beaten boss stays beaten, as a corpse where she
## fell: see BossProgress. Loading the arena again (a revisit, a scene reload)
## puts the corpse back, opens everything, and re-spawns the reward if it was
## never picked up, so a reload can never lose the double jump.
##
## Audio cues: `Sfx/DoorsClose`, `Sfx/DoorsOpen` and `Sfx/BossIntro` are empty
## `AudioStreamPlayer` slots; assign streams to them. Each cue also emits
## `sfx_cue`.
##
## Boss contract: an `Enemy` (`hit`, `died`, `reset_to_spawn`, `get_health`). The
## optional methods `engage()`, `set_arena_limits(left_x, right_x)`,
## `set_manual_engage(on)` and `is_fresh()` are used when the boss has them.
## Do not scale or rotate the arena: its rects are read as plain offsets.
##
## The editor draws the arena (cyan), the trigger (yellow), the doors (red) and
## the reward spot (white). Nothing is drawn in game.

signal fight_started
signal fight_reset
signal arena_cleared
signal reward_spawned(reward: DoubleJumpReward)
## The trigger re-arm routine ended: `armed` is true when the trigger came back
## on, false when it gave up (the arena left the tree or the fight state changed).
## Never emitted if the arena is freed mid-wait (the routine is simply dropped).
signal rearm_finished(armed: bool)
## A sound cue fired (`DoorsClose`, `DoorsOpen`, `BossIntro`), even with an empty stream.
signal sfx_cue(cue: StringName)

enum FightState { ARMED, ACTIVE, DEFEATED }

const BAR_SCENE := preload("res://scenes/ui/boss_health_bar.tscn")
const REWARD_SCENE := preload("res://scenes/world/double_jump_reward.tscn")
const PLAYER_GROUP := &"player"
const PROGRESS_PATH := "/root/BossProgress"
const DOOR_LAYER := 1
## Solids and the player share layer 1; the trigger only looks for her.
const TRIGGER_MASK := 1
## Reward height above the floor (the centre of Luz's body).
const REWARD_HEIGHT := 28.0
const PHASE_THRESHOLD_PROPERTY := &"phase_two_threshold"
const CUE_DOORS_CLOSE := &"DoorsClose"
const CUE_DOORS_OPEN := &"DoorsOpen"
const CUE_BOSS_INTRO := &"BossIntro"
const EDITOR_ARENA_COLOR := Color(0.2, 0.9, 1.0)
const EDITOR_TRIGGER_COLOR := Color(1.0, 0.9, 0.2)
const EDITOR_DOOR_COLOR := Color(1.0, 0.3, 0.3)

@export_group("Arena")
## Local rect of the fight. Its left and right edges are the walls the boss
## clamps to, and the whole rect is what the camera is locked to.
@export var arena_rect := Rect2(-434.0, -340.0, 868.0, 400.0):
	set(value):
		arena_rect = value
		_refresh()

@export_group("Trigger")
## Local rect: Luz entering it starts the fight. Keep it away from the doors.
@export var trigger_rect := Rect2(-200.0, -200.0, 400.0, 200.0):
	set(value):
		trigger_rect = value
		_refresh()

@export_group("Doors")
## Local position of each door's feet (bottom centre).
@export var left_door := Vector2(-422.0, 0.0):
	set(value):
		left_door = value
		_refresh()
@export var right_door := Vector2(422.0, 0.0):
	set(value):
		right_door = value
		_refresh()
@export var door_size := Vector2(24.0, 200.0):
	set(value):
		door_size = value
		_refresh()
## Seconds a door takes to fall shut or rise (0 is instant).
@export var door_time := 0.25

@export_group("Camera Shake")
## Light shake when the doors slam shut (pixels, seconds).
@export var door_shake_strength := 3.0
@export var door_shake_time := 0.25

@export_group("Boss")
## The boss when it is not a direct child of the arena.
@export var boss_path: NodePath
## The title card and the health bar show this name. Rename or localize it here.
@export var boss_name := "Artemis"

@export_group("Intro")
## How long the name card shows.
@export var title_time := 1.2
## Seconds between the trigger and the boss waking up.
@export var engage_delay := 0.8
## Seconds the camera takes to settle on the arena (0 is instant).
@export var camera_blend_time := 0.5

@export_group("Defeat")
## Beat between the boss falling and the arena opening.
@export var defeat_beat := 1.2

@export_group("Reward")
@export var reward_enabled := true
## Optional Node2D to drop the reward on. Empty: the arena's centre, on the floor
## where the boss started.
@export var reward_marker: NodePath

var _state := FightState.ARMED
var _boss: Enemy
var _boss_id: StringName = &""
var _player: Player
var _bar: BossHealthBar
var _reward: DoubleJumpReward
var _doors_closed := false
var _boss_resets := 0
var _door_tween: Tween
var _intro_tween: Tween
var _defeat_tween: Tween
var _camera: Camera2D
var _camera_locked := false
var _had_room_bounds := false
var _saved_room_bounds := Rect2()
var _saved_limits: Array[int] = []

@onready var _trigger: Area2D = $Trigger
@onready var _trigger_shape: CollisionShape2D = $Trigger/CollisionShape2D
@onready var _door_left: StaticBody2D = $DoorLeft
@onready var _door_right: StaticBody2D = $DoorRight


func _ready() -> void:
	_apply_layout()
	if Engine.is_editor_hint():
		return
	_set_doors_physics(false)
	_snap_doors(false)
	_bar = BAR_SCENE.instantiate() as BossHealthBar
	add_child(_bar)
	_trigger.body_entered.connect(_on_trigger_body_entered)
	_boss = _find_boss()
	if _boss == null:
		push_warning("BossArena %s has no boss: add one as a child or set boss_path." % get_path())
		return
	_boss_id = _boss.get_enemy_key()
	if _already_defeated():
		_enter_defeated_state()
		return
	_connect_boss()
	_feed_boss()


func _exit_tree() -> void:
	# Never leave the camera locked on an arena that is going away.
	if not Engine.is_editor_hint():
		_unlock_camera(0.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _find_boss() == null:
		warnings.append("No boss found. Add one as a child or set boss_path.")
	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(arena_rect, EDITOR_ARENA_COLOR, false, 2.0)
	draw_rect(trigger_rect, Color(EDITOR_TRIGGER_COLOR, 0.15), true)
	draw_rect(trigger_rect, EDITOR_TRIGGER_COLOR, false, 1.0)
	for foot: Vector2 in [left_door, right_door]:
		draw_rect(Rect2(foot - Vector2(door_size.x * 0.5, door_size.y), door_size), EDITOR_DOOR_COLOR, false, 2.0)
	var spot := Vector2(arena_rect.get_center().x, arena_rect.end.y - REWARD_HEIGHT)
	draw_circle(spot, 5.0, Color.WHITE)


## -- Public API --------------------------------------------------------------

func get_state() -> FightState:
	return _state


func get_boss() -> Enemy:
	return _boss


func get_bar() -> BossHealthBar:
	return _bar


func get_reward() -> DoubleJumpReward:
	return _reward


## Plays the empty-by-default slot `cue` under `Sfx` (no-op without a stream).
func play_cue(cue: StringName) -> void:
	sfx_cue.emit(cue)
	var player := get_node_or_null("Sfx/" + String(cue)) as AudioStreamPlayer
	if player != null and player.stream != null:
		player.play()


func are_doors_closed() -> bool:
	return _doors_closed


func get_doors() -> Array[StaticBody2D]:
	return [_door_left, _door_right]


func is_trigger_armed() -> bool:
	return _trigger.monitoring


## The arena rect in world space.
func get_world_rect() -> Rect2:
	return Rect2(to_global(arena_rect.position), arena_rect.size)


## How many times the arena itself had to reset the boss after Luz woke up. Zero
## when the checkpoint contract (EnemyRegistry and the checkpoint group) got
## there first, which is the normal case: no double reset.
func get_boss_reset_count() -> int:
	return _boss_resets


## -- Layout ---------------------------------------------------------------------

func _refresh() -> void:
	queue_redraw()
	_apply_layout()


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var shape := RectangleShape2D.new()
	shape.size = trigger_rect.size
	_trigger_shape.shape = shape
	_trigger.position = trigger_rect.get_center()
	_layout_door(_door_left)
	_layout_door(_door_right)
	_snap_doors(_doors_closed)


func _layout_door(door: StaticBody2D) -> void:
	var shape := RectangleShape2D.new()
	shape.size = door_size
	(door.get_node("CollisionShape2D") as CollisionShape2D).shape = shape
	var half := door_size * 0.5
	(door.get_node("Visual") as Polygon2D).polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])


## Door centre when shut, and when raised out of the way (a full height up).
func _door_y(door: StaticBody2D, closed: bool) -> float:
	var foot := left_door if door == _door_left else right_door
	return foot.y - door_size.y * 0.5 - (0.0 if closed else door_size.y)


func _door_x(door: StaticBody2D) -> float:
	return (left_door if door == _door_left else right_door).x


func _snap_doors(closed: bool) -> void:
	for door: StaticBody2D in get_doors():
		door.position = Vector2(_door_x(door), _door_y(door, closed))
		door.visible = closed


## -- Doors ----------------------------------------------------------------------------

func _set_doors(closed: bool) -> void:
	_doors_closed = closed
	_kill(_door_tween)
	if closed:
		_set_doors_physics(true)
		_set_doors_visible(true)
		play_cue(CUE_DOORS_CLOSE)
		BossFeel.shake_camera(get_viewport(), door_shake_strength, door_shake_time)
	else:
		play_cue(CUE_DOORS_OPEN)
	if door_time <= 0.0:
		_snap_doors(closed)
		_finish_doors(closed)
		return
	_door_tween = create_tween().set_parallel(true)
	for door: StaticBody2D in get_doors():
		_door_tween.tween_property(door, "position:y", _door_y(door, closed), door_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if closed else Tween.EASE_OUT)
	_door_tween.chain().tween_callback(_finish_doors.bind(closed))


func _finish_doors(closed: bool) -> void:
	if closed:
		return
	_set_doors_physics(false)
	_set_doors_visible(false)


## Deferred: a door may close from inside the trigger's physics callback.
func _set_doors_physics(on: bool) -> void:
	for door: StaticBody2D in get_doors():
		door.get_node("CollisionShape2D").set_deferred(&"disabled", not on)


func _set_doors_visible(on: bool) -> void:
	for door: StaticBody2D in get_doors():
		door.visible = on


## -- Camera ------------------------------------------------------------------------------

## Least invasive lock: clamp the camera that is current right now to the arena
## rect, and put back exactly what it had. A RoomCamera gets room bounds, which is
## what room transitions use too; a plain Camera2D gets its limits.
func _lock_camera() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or _camera_locked:
		return
	_camera = camera
	_camera_locked = true
	var rect := get_world_rect()
	if camera is RoomCamera:
		var room := camera as RoomCamera
		_had_room_bounds = room.has_room_bounds()
		_saved_room_bounds = room.get_target_room_bounds()
		room.set_room_bounds(rect, camera_blend_time)
		return
	_saved_limits = [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)


func _unlock_camera(blend: float) -> void:
	if not _camera_locked:
		return
	_camera_locked = false
	if not is_instance_valid(_camera):
		return
	if _camera is RoomCamera:
		var room := _camera as RoomCamera
		if _had_room_bounds:
			room.set_room_bounds(_saved_room_bounds, blend)
		else:
			room.clear_room_bounds(blend)
		return
	_camera.limit_left = _saved_limits[0]
	_camera.limit_top = _saved_limits[1]
	_camera.limit_right = _saved_limits[2]
	_camera.limit_bottom = _saved_limits[3]


## -- Boss wiring -----------------------------------------------------------------------

func _find_boss() -> Enemy:
	if not boss_path.is_empty():
		return get_node_or_null(boss_path) as Enemy
	for child: Node in get_children():
		if child is Enemy:
			return child as Enemy
	return null


func _connect_boss() -> void:
	_boss.hit.connect(_on_boss_hit)
	_boss.died.connect(_on_boss_died)
	if _boss.has_method(&"set_manual_engage"):
		_boss.call(&"set_manual_engage", true)


## Hands the boss the real walls; without this she probes for them.
func _feed_boss() -> void:
	if is_instance_valid(_boss) and _boss.has_method(&"set_arena_limits"):
		var rect := get_world_rect()
		_boss.call(&"set_arena_limits", rect.position.x, rect.end.x)


func _engage_boss() -> void:
	if _state == FightState.ACTIVE and is_instance_valid(_boss) and _boss.has_method(&"engage"):
		_boss.call(&"engage")


## The notch sits where the boss starts its second phase, if it has one.
func _notch_ratio() -> float:
	var threshold: Variant = _boss.get(PHASE_THRESHOLD_PROPERTY)
	return float(threshold) if threshold != null else BossHealthBar.NO_NOTCH


func _on_boss_hit(_amount: int, remaining: int) -> void:
	_bar.set_health(remaining)


## -- Fight ----------------------------------------------------------------------------------

func _on_trigger_body_entered(body: Node2D) -> void:
	if _state != FightState.ARMED or not _boss_alive() or not body.is_in_group(PLAYER_GROUP):
		return
	var player := body as Player
	if player != null:
		_start_fight(player)


func _boss_alive() -> bool:
	return is_instance_valid(_boss) and not _boss.is_dead()


func _start_fight(player: Player) -> void:
	_state = FightState.ACTIVE
	_bind_player(player)
	_trigger.set_deferred(&"monitoring", false)
	_feed_boss()
	_set_doors(true)
	_lock_camera()
	_bar.setup(boss_name, _boss.max_health, _notch_ratio())
	_bar.set_health(_boss.get_health())
	_bar.show_bar()
	_bar.show_title(boss_name, title_time)
	play_cue(CUE_BOSS_INTRO)
	_kill(_intro_tween)
	_intro_tween = create_tween()
	_intro_tween.tween_interval(engage_delay)
	_intro_tween.tween_callback(_engage_boss)
	fight_started.emit()


func _bind_player(player: Player) -> void:
	_player = player
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
		player.respawned.connect(_on_player_respawned)


## Luz fell: the boss stops where it is, so it neither keeps shooting at a
## corpse nor engages from a pending intro, until she wakes up.
func _on_player_died() -> void:
	if _state != FightState.ACTIVE:
		return
	_kill(_intro_tween)
	if is_instance_valid(_boss):
		_boss.set_ai_active(false)


func _on_player_respawned() -> void:
	if _state == FightState.ACTIVE:
		_reset_fight()


## Back to a fresh, armed arena. The boss reset itself is deferred: the player's
## respawn asks every checkpoint-resettable enemy to reset right after this
## signal, so by the time it runs the boss is usually fresh already.
func _reset_fight() -> void:
	_state = FightState.ARMED
	_kill(_intro_tween)
	_bar.hide_title()
	_bar.hide_bar(false)
	_set_doors(false)
	_unlock_camera(0.0)
	_rearm_trigger()
	_reset_boss.call_deferred()
	fight_reset.emit()


## Two physics steps after the reset: Luz was just teleported away, and a trigger
## armed in the same step can still see her at the old spot and start the fight.
func _rearm_trigger() -> void:
	for _step: int in 2:
		if not is_inside_tree():
			rearm_finished.emit(false)
			return
		await get_tree().physics_frame
	var armed := is_inside_tree() and _state == FightState.ARMED
	if armed:
		_trigger.monitoring = true
	rearm_finished.emit(armed)


func _reset_boss() -> void:
	if _state != FightState.ARMED or not is_instance_valid(_boss) or _boss.is_dead():
		return
	if not (_boss.has_method(&"is_fresh") and _boss.call(&"is_fresh")):
		_boss.reset_to_spawn()
		_boss_resets += 1
	_boss.set_ai_active(true)


## -- Defeat -------------------------------------------------------------------------------------

func _on_boss_died(_enemy: Enemy) -> void:
	if _state == FightState.DEFEATED:
		return
	var was_active := _state == FightState.ACTIVE
	_state = FightState.DEFEATED
	_kill(_intro_tween)
	_trigger.set_deferred(&"monitoring", false)
	if not was_active:
		_bar.hide_title()
		_bar.hide_bar(false)
	_remember_defeat()
	_leave_checkpoint_contract()
	if _boss.has_signal(&"corpse_settled"):
		_boss.connect(&"corpse_settled", _remember_defeat)
	_defeat_tween = create_tween()
	_defeat_tween.tween_interval(defeat_beat)
	_defeat_tween.tween_callback(_open_arena)


func _open_arena() -> void:
	_bar.hide_title()
	_bar.hide_bar()
	_set_doors(false)
	_unlock_camera(camera_blend_time)
	_spawn_reward()
	arena_cleared.emit()


func _spawn_reward() -> void:
	if not reward_enabled:
		return
	_reward = REWARD_SCENE.instantiate() as DoubleJumpReward
	add_child(_reward)
	_reward.global_position = _reward_position()
	_reward.collected.connect(_on_reward_collected)
	reward_spawned.emit(_reward)


func _on_reward_collected(_player: Node) -> void:
	var progress := _progress()
	if progress != null:
		progress.mark_reward_claimed(_boss_id)


func _reward_position() -> Vector2:
	if not reward_marker.is_empty():
		var marker := get_node_or_null(reward_marker) as Node2D
		if marker != null:
			return marker.global_position
	var floor_y := get_world_rect().end.y
	if is_instance_valid(_boss):
		floor_y = _boss.get_spawn_position().y
	return Vector2(get_world_rect().get_center().x, floor_y - REWARD_HEIGHT)


## -- Permanence ----------------------------------------------------------------------------

func _progress() -> Node:
	return get_node_or_null(PROGRESS_PATH)


## Also called again when the corpse settles, so the stored spot is the one she
## really rests on (a kill in mid-air falls first).
func _remember_defeat() -> void:
	var progress := _progress()
	if progress != null and is_instance_valid(_boss):
		progress.mark_defeated(_boss_id, _boss.global_position, _boss.get_facing())


func _already_defeated() -> bool:
	var progress := _progress()
	return progress != null and progress.is_defeated(_boss_id)


## A boss beaten earlier: she lies as a corpse where she fell, nothing closes,
## and the reward comes back if it was never picked up.
func _enter_defeated_state() -> void:
	_state = FightState.DEFEATED
	_trigger.monitoring = false
	var corpse: Dictionary = _progress().get_corpse(_boss_id)
	_boss.make_corpse_at(corpse["position"], corpse["facing"])
	_leave_checkpoint_contract()
	_resolve_reward()


## Out of the checkpoint contract: a desk rest or Luz's death must not revive her.
func _leave_checkpoint_contract() -> void:
	_boss.remove_from_group(Enemy.GROUP_RESETTABLE)


## Defeated but never claimed: the reward comes back unless Luz already double
## jumps. Without a Luz in the tree yet (the arena can be ready first) the decision
## waits for her, never assuming she lacks the ability.
func _resolve_reward() -> void:
	if not reward_enabled or _progress().is_reward_claimed(_boss_id):
		return
	var player := get_tree().get_first_node_in_group(PLAYER_GROUP)
	if player == null:
		get_tree().node_added.connect(_on_node_added_for_reward)
	elif not _can_double_jump(player):
		_spawn_reward()


func _on_node_added_for_reward(node: Node) -> void:
	if not node.is_in_group(PLAYER_GROUP):
		return
	get_tree().node_added.disconnect(_on_node_added_for_reward)
	# Deferred: the player is still entering the tree and its state is not final.
	_resolve_reward.call_deferred()


func _can_double_jump(player: Node) -> bool:
	return player.has_method(&"has_double_jump") and player.call(&"has_double_jump")


func _kill(tween: Tween) -> void:
	if tween != null:
		tween.kill()

@tool
class_name Enemy
extends CharacterBody2D

## Base of every enemy archetype.
##
## Hit seam: the player's AttackHitbox (an Area2D on the player_attack layer)
## reports bodies on the enemies layer; Player resolves the hit and calls
## `receive_hit()` on the target. Enemies therefore never reference the player
## script, and any node with a `receive_hit` method can be struck.
##
## Lifecycle: alive -> corpse (on death) -> alive again via reset_to_spawn().
## The EnemyRegistry autoload owns persistence (see enemy_registry.gd); this
## class only exposes the helpers it needs.
##
## Subclasses override `_think()` (sets velocity.x each physics frame),
## `_reset_ai()` and optionally `_on_player_found()`.

signal hit(amount: int, remaining: int)
signal died(enemy: Enemy)

const ENEMY_LAYER := 8
## Solids (1) and one-way platforms (2).
const WORLD_MASK := 3
const GROUP_ENEMIES := &"enemies"
const GROUP_RESETTABLE := &"checkpoint_resettable"
const REGISTRY_PATH := "/root/EnemyRegistry"
const CORPSE_TINT := Color(0.32, 0.32, 0.36, 0.85)
const CORPSE_SQUASH := 0.55

## Unique per level: persistence (corpses) is keyed by it.
@export var enemy_id: StringName = &"":
	set(value):
		enemy_id = value
		if is_inside_tree():
			update_configuration_warnings()
## Facing at spawn: -1 left, 1 right.
@export_enum("Left:-1", "Right:1") var start_facing := -1

@export_group("Health")
@export var max_health := 2
## 0 takes the full recoil, 1 is not pushed at all.
@export_range(0.0, 1.0) var knockback_resistance := 0.0

@export_group("Contact")
@export var contact_damage := 1

@export_group("Hit Reaction")
@export var flash_time := 0.08
## Freezes only this enemy for a moment on a non-lethal hit.
## Never touches Engine.time_scale.
@export var hit_stop_time := 0.04
@export var recoil_speed := 160.0
@export var recoil_time := 0.10

@export_group("Physics")
@export var gravity := 1400.0
@export var max_fall_speed := 900.0

## Room that owns this enemy, assigned by the registry from the spawn point.
var home_room: StringName = &""

var _health := 0
var _dead := false
var _ai_active := true
var _facing := -1
var _spawn_position := Vector2.ZERO
var _recoil_left := 0.0
var _recoil_velocity := 0.0
var _hit_stop_left := 0.0
var _flash_left := 0.0
var _visual: Node2D
var _flash: Polygon2D
var _contact: ContactDamage
var _player_ref: Node


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if enemy_id.is_empty():
		warnings.append("enemy_id is empty. It must be unique per level: corpses persist by it.")
	return warnings


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_MASK
	add_to_group(GROUP_ENEMIES)
	add_to_group(GROUP_RESETTABLE)
	_health = max_health
	_spawn_position = global_position
	_facing = 1 if start_facing >= 0 else -1
	_visual = get_node_or_null("Visual") as Node2D
	_setup_flash()
	_setup_contact()
	_apply_visual()
	if enemy_id.is_empty():
		push_warning("Enemy %s has no enemy_id; using its node path." % get_path())
	var registry := _registry()
	if registry != null:
		registry.register(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var registry := _registry()
	if registry != null:
		registry.unregister(self)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_tick_flash(delta)
	_ensure_player_excluded()
	if _hit_stop_left > 0.0:
		_hit_stop_left -= delta
		return
	if _dead:
		_update_corpse(delta)
		return
	if not _ai_active:
		return
	if _recoil_left > 0.0:
		_recoil_left -= delta
		velocity.x = _recoil_velocity
	else:
		_think(delta)
	_apply_gravity(delta)
	move_and_slide()


## -- Public API --------------------------------------------------------------

func is_dead() -> bool:
	return _dead


func get_health() -> int:
	return _health


func get_facing() -> int:
	return _facing


func get_spawn_position() -> Vector2:
	return _spawn_position


func is_ai_active() -> bool:
	return _ai_active


## The registry key: the exported id, or the node path when it was left empty.
func get_enemy_key() -> StringName:
	return enemy_id if not enemy_id.is_empty() else StringName(str(get_path()))


## Off-room enemies are paused by the registry: no AI, no gravity.
func set_ai_active(active: bool) -> void:
	_ai_active = active


## Applies one hit coming from `source_position`. Returns false, changing
## nothing, when the enemy is already a corpse or the damage is not positive.
func receive_hit(damage: int, source_position: Vector2, _attack_name: StringName = &"") -> bool:
	if _dead or damage <= 0:
		return false
	_health = maxi(_health - damage, 0)
	hit.emit(damage, _health)
	_flash_left = flash_time
	_set_flash_visible(true)
	if _health == 0:
		make_corpse_at(global_position, _facing)
		died.emit(self)
		return true
	_hit_stop_left = hit_stop_time
	_start_recoil(source_position)
	return true


## Full health, spawn position and facing, AI idle. Also revives a corpse.
func reset_to_spawn() -> void:
	_revive()
	_health = max_health
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_facing = 1 if start_facing >= 0 else -1
	_recoil_left = 0.0
	_hit_stop_left = 0.0
	_flash_left = 0.0
	_set_flash_visible(false)
	_reset_ai()
	_apply_visual()
	reset_physics_interpolation()
	set_physics_process(true)


## Turns this enemy into a corpse resting at `at`: dimmed, non-colliding and
## harmless. If it is in the air it falls with gravity and then freezes.
func make_corpse_at(at: Vector2, facing: int) -> void:
	_dead = true
	global_position = at
	_facing = 1 if facing >= 0 else -1
	velocity = Vector2.ZERO
	_recoil_left = 0.0
	collision_layer = 0
	if _contact != null:
		_contact.monitoring = false
	_apply_visual()
	reset_physics_interpolation()
	set_physics_process(true)


## Checkpoint contract (group `checkpoint_resettable`): a desk rest or Luz's
## death revives everything, corpses included.
func reset_to_checkpoint_state() -> void:
	var registry := _registry()
	if registry != null:
		registry.forget(get_enemy_key())
	reset_to_spawn()


## -- Hooks for archetypes ------------------------------------------------------

## Sets velocity.x for this frame. Gravity and movement are applied after.
func _think(_delta: float) -> void:
	pass


func _reset_ai() -> void:
	pass


func _on_player_found(_player: Node) -> void:
	pass


## -- Internals -----------------------------------------------------------------

func _registry() -> Node:
	return get_node_or_null(REGISTRY_PATH)


func _apply_gravity(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _update_corpse(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if is_on_floor():
		set_physics_process(false)


func _revive() -> void:
	if not _dead:
		return
	_dead = false
	collision_layer = ENEMY_LAYER
	if _contact != null:
		_contact.monitoring = true


func _start_recoil(source_position: Vector2) -> void:
	var side := signf(global_position.x - source_position.x)
	if is_zero_approx(side):
		side = -float(_facing)
	_recoil_velocity = side * recoil_speed * (1.0 - knockback_resistance)
	_recoil_left = recoil_time


## Registers once per player instance: the player lives on the same physics
## layer as solids, so the enemy would otherwise be blocked by her body.
func _ensure_player_excluded() -> void:
	if is_instance_valid(_player_ref):
		return
	_player_ref = get_tree().get_first_node_in_group(&"player")
	if _player_ref is PhysicsBody2D:
		add_collision_exception_with(_player_ref as PhysicsBody2D)
		_on_player_found(_player_ref)


func _setup_contact() -> void:
	_contact = get_node_or_null("ContactDamage") as ContactDamage
	if _contact == null:
		return
	_contact.kind = ContactDamage.Kind.ENEMY
	_contact.damage = contact_damage
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is RectangleShape2D:
		_contact.position = body.position
		_contact.set_area_size((body.shape as RectangleShape2D).size)


## Placeholder hurt flash: a white copy of the "Body" polygon shown briefly.
func _setup_flash() -> void:
	var body := get_node_or_null("Visual/Body") as Polygon2D
	if body == null:
		return
	_flash = Polygon2D.new()
	_flash.polygon = body.polygon
	_flash.color = Color.WHITE
	_flash.z_index = 1
	_flash.visible = false
	_visual.add_child(_flash)


func _tick_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_set_flash_visible(false)


func _set_flash_visible(visible_now: bool) -> void:
	if _flash != null:
		_flash.visible = visible_now


func _apply_visual() -> void:
	if _visual == null:
		return
	_visual.scale = Vector2(float(_facing), CORPSE_SQUASH if _dead else 1.0)
	_visual.modulate = CORPSE_TINT if _dead else Color.WHITE
	_visual.z_index = -1 if _dead else 0

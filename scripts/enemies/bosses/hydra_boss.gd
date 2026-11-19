class_name HydraBoss
extends BossEnemy

## La Hidra, the optional Greece boss: a target-priority and platforming fight.
## A static body near the right wall with three heads at different heights
## (low, middle, high) that Luz reaches by climbing the arena platforms. Each head
## has its own health and its own attack; a killed head stays as a stump and the
## ones left get fiercer. The order Luz picks changes the fight.
##
##   BITER   (low)   BITE_LUNGE   the neck lunges at the point Luz stood on, then the
##                                head sits stuck: the moment to punish it.
##   SPITTER (high)  VENOM_VOLLEY arcing globs on marked spots; each leaves a puddle.
##   SWEEPER (mid)   NECK_SWEEP   a marked tier is swept end to end: change tier.
##
## Phases are the heads left (3, 2, 1) and come from head deaths, not from health:
## `phases_from_health` is off and a severed head calls `_advance_phase()`. With
## three heads one head attacks at a time; with two the heads attack as a duo and
## their attacks overlap; with one the last head is in a frenzy and also throws
## weaker versions of the dead heads' attacks.
##
## The root body is never hit. The heads are the hurtboxes (children of `Heads`):
## each forwards the hit to `hit_head`, which clamps it to the head's remaining
## health and runs the base `receive_hit`, so the shared pool, the bar, the final
## blow and the engage gate all stay in the base. The pool always equals the sum
## of the heads.
##
## The platforms are discovered from the group `hydra_platform` under the `Platforms`
## node of the arena that holds this boss (see HydraTiers), so they can be moved freely. Hazards (venom, markers, hitboxes) live in the
## world beside the boss and are all removed by `_clear_hazards()`.
##
## Art (docs/bosses/HYDRA_ANIMATIONS.md): every piece is optional and independent. The body
## wears a sprite under `Visual`, each head its own sprite and a textured neck (`HydraHead`),
## the venom its sprites (`HydraVenom`) and the platforms the boss scans a drawn slab. A piece
## with no art keeps its placeholder; with none at all it looks and plays exactly as before.

enum Attack { BITE_LUNGE, VENOM_VOLLEY, NECK_SWEEP }

const HEAD_COUNT := 3
const HIT_DAMAGE := 1
## Floor-marker slots of the telegraph given to each concurrent attack.
const MARKERS_PER_RUN := 8
const LEAD_SLOT := 0
const ECHO_SLOT := 1
const NO_ECHO := -1.0
## Margin between a lunge target and the arena walls.
const LUNGE_WALL_MARGIN := 24.0
const SWEEP_MARKER_PULSE_RATE := 12.0
const MOUTH_OFFSET := Vector2(-26.0, 0.0)

@export_group("Layout")
## Distance between the body and the right wall of the arena.
@export var right_wall_margin := 68.0
## How far above its tier's surface the middle of a resting head sits.
@export var head_rest_height := 34.0
## Speed at which a head returns to its resting place, and at which it coils back.
@export var retract_speed := 520.0
## Venom spots stay at least this far from the body.
@export var body_gap_for_spots := 100.0

@export_group("Biter")
## Seconds of the red aim line that tracks Luz; it locks for the last `bite_lock_time`.
@export var bite_telegraph := 0.9
@export var bite_lock_time := 0.15
@export var bite_speed := 900.0
## The longest lunge from the head's resting place.
@export var bite_reach := 460.0
## How far the head coils back toward the body during the wind-up.
@export var bite_coil := 36.0
@export var bite_hitbox_size := 44.0
## Seconds the head stays stuck, extended, after the lunge: the punish window.
@export var bite_stuck_time := 0.8

@export_group("Spitter")
@export var venom_telegraph := 0.8
@export var venom_count := 3
## Distance between two neighbouring marked spots.
@export var venom_spacing := 150.0
@export var venom_interval := 0.2
@export var venom_flight_time := 0.7
@export var venom_arc_height := 90.0
## Seconds a puddle keeps hurting.
@export var venom_pool_time := 3.5
@export var venom_pool_width := 88.0
@export var venom_recover := 0.7

@export_group("Sweeper")
@export var sweep_telegraph := 0.95
@export var sweep_speed := 700.0
@export var sweep_recover := 0.8
## Height of the swept band (it covers a standing Luz and not the tier below).
@export var sweep_band_height := 56.0
## How far the head pulls back from its shoulder before the sweep, and how close to
## the left wall it ends.
@export var sweep_start_gap := 60.0
@export var sweep_end_margin := 36.0

@export_group("Enrage")
## Each dead head multiplies the telegraphs by this (never below the base minimum).
@export var enrage_telegraph_scale := 0.85
## One more venom glob and this much faster sweeps per dead head.
@export var enrage_extra_globs := 1
@export var enrage_sweep_speed_gain := 0.25
## The last head: its own attacks are this much faster, recoveries and pauses this short.
@export var frenzy_strength := 1.2
@export var frenzy_recover_scale := 0.6
## How much more often the last head draws its own attack than a dead head's.
@export var frenzy_native_weight := 2.0

@export_group("Weak Versions")
## The last head throwing a dead head's attack: slower and gentler.
@export var weak_telegraph_scale := 1.15
@export var weak_speed_scale := 0.8
@export var weak_venom_count := 2

@export_group("Duo")
## With two heads left, seconds between the lead's start and the second head's.
@export var duo_offset := 0.7

@export_group("Art")
@export_file("*.json") var animation_manifest := "res://assets/enemies/hydra/animation_manifest.json"

@export_group("Testing")
## Off: the fight loop never starts an attack by itself (tests call `start_attack`).
@export var auto_attack := true

var _heads: Array[HydraHead] = []
var _tiers := HydraTiers.new()
var _lead: Run
var _echo: Run
var _echo_delay := NO_ECHO
var _next_head: HydraHead
var _last_head: HydraHead
var _hit_head: HydraHead
var _venoms: Array[HydraVenom] = []
var _art: HydraArt
var _art_on := false
var _sprite_scale := 1.0
var _sprite_fx: BossSpriteFx
## The contract clip last requested for the body (not the fallback it resolved to).
var _clip: StringName = &""

@onready var _heads_root: Node2D = get_node_or_null("Heads") as Node2D
@onready var _sprite: AnimatedSprite2D = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D


## One head carrying out one attack: the shared state of the lead attack (driven
## by the base lifecycle) and of the echo attack of the duo (driven by `_tick`).
class Run extends RefCounted:
	var head: HydraHead
	var attack := 0
	var weak := false
	var phase := BossEnemy.AttackPhase.TELEGRAPH
	var left := 0.0
	var slot := 0
	var aim := Vector2.LEFT
	var aim_length := 0.0
	var locked := false
	var lock_point := Vector2.ZERO
	var slab := Rect2()
	var venoms: Array[HydraVenom] = []
	var spat := 0
	var spit_clock := 0.0
	## The phase hook ended and no next phase began: the run is over or was cut short.
	var ended := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_setup_art()
	_collect_heads()
	_begin_layout()
	_dress_platforms.call_deferred()
	if _dead:
		_sever_all_heads()


func _exit_tree() -> void:
	super._exit_tree()
	for venom: HydraVenom in _venoms:
		if is_instance_valid(venom) and not venom.is_queued_for_deletion():
			venom.queue_free()
	_venoms.clear()


## -- Public API --------------------------------------------------------------

func get_heads() -> Array[HydraHead]:
	return _heads


func get_living_heads() -> Array[HydraHead]:
	var living: Array[HydraHead] = []
	for head: HydraHead in _heads:
		if not head.is_severed():
			living.append(head)
	return living


func get_head(kind: HydraHead.Kind) -> HydraHead:
	for head: HydraHead in _heads:
		if head.kind == kind:
			return head
	return null


func get_dead_head_count() -> int:
	return _heads.size() - get_living_heads().size()


## Remaining health of every head added up; it always equals the boss health.
func get_head_health_sum() -> int:
	var total := 0
	for head: HydraHead in _heads:
		total += head.health
	return total


## The factor the telegraphs shrink by after the heads that died.
func get_enrage_scale() -> float:
	return pow(enrage_telegraph_scale, float(get_dead_head_count()))


func get_tiers() -> HydraTiers:
	return _tiers


func has_art() -> bool:
	return _art_on


## The body clip last requested (empty without body art).
func get_clip() -> StringName:
	return _clip


func get_art() -> HydraArt:
	return _art


## The heads that are carrying out an attack right now (the lead and the echo).
func get_attacking_heads() -> Array[HydraHead]:
	var attacking: Array[HydraHead] = []
	for run: Run in [_lead, _echo]:
		if run != null and not attacking.has(run.head):
			attacking.append(run.head)
	return attacking


## The attack `head` is carrying out, NO_ATTACK when it is idle.
func get_run_attack(head: HydraHead) -> int:
	var run := _run_of(head)
	return run.attack if run != null else NO_ATTACK


func is_run_weak(head: HydraHead) -> bool:
	var run := _run_of(head)
	return run != null and run.weak


func get_run_phase(head: HydraHead) -> int:
	var run := _run_of(head)
	return run.phase if run != null else NO_ATTACK


## The point the biter's lunge locked on.
func get_run_lock_point(head: HydraHead) -> Vector2:
	var run := _run_of(head)
	return run.lock_point if run != null else Vector2.ZERO


## The marked tier band of a sweep.
func get_run_slab(head: HydraHead) -> Rect2:
	var run := _run_of(head)
	return run.slab if run != null else Rect2()


## The venom spots of the spitter's volley.
func get_run_spots(head: HydraHead) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var run := _run_of(head)
	if run != null:
		for venom: HydraVenom in run.venoms:
			spots.append(venom.get_spot())
	return spots


func get_active_venoms() -> Array[HydraVenom]:
	var active: Array[HydraVenom] = []
	for venom: HydraVenom in _venoms:
		if is_instance_valid(venom) and venom.is_active():
			active.append(venom)
	return active


## Places the body at the right wall and lays the heads out on the platform tiers.
func set_arena_limits(left_x: float, right_x: float) -> void:
	super.set_arena_limits(left_x, right_x)
	if _dead:
		return
	global_position.x = maxf(left_x, right_x) - right_wall_margin
	_spawn_position.x = global_position.x
	reset_physics_interpolation()
	if is_node_ready() and not _heads.is_empty():
		_begin_layout()


## The platforms may have moved since the scene loaded: read them when the fight starts.
func engage() -> void:
	if not _engaged:
		_begin_layout()
	super.engage()


## A head forwards Luz's slash here. The damage is clamped to what the head has
## left, taken from the head and from the shared pool together; a head at zero
## is severed and the phase advances.
func hit_head(head: HydraHead, damage: int, source_position: Vector2, attack_name: StringName = &"") -> bool:
	if head == null or head.is_severed() or damage <= 0 or _dead:
		return false
	var applied := mini(damage, head.health)
	_hit_head = head
	head.health -= applied
	var landed := receive_hit(applied, source_position, attack_name)
	_hit_head = null
	if not landed:
		head.health += applied
		return false
	head.flash()
	_grant_soul()
	if head.health <= 0 and not _dead:
		_sever_head(head)
	return true


## Starts `attack` with the head that owns it (or a living head when its own is
## dead: a weaker version). Used by the fight loop and by tests.
func start_attack(attack: int) -> void:
	if _dead:
		return
	_close_attack_phase()
	_finish_run(_lead)
	_lead = _make_run(attack, _lead_head_for(attack), LEAD_SLOT)
	if _lead == null:
		return
	super.start_attack(attack)


func make_corpse_at(at: Vector2, facing: int) -> void:
	super.make_corpse_at(at, facing)
	_sever_all_heads()


## -- BossEnemy hooks ---------------------------------------------------------------

## Per-frame work in every state: the echo attack, the returning heads, the
## telegraph drawing. The lead attack is driven by the base lifecycle.
func _tick(delta: float) -> void:
	_sync_sprite()
	if _heads.is_empty():
		return
	if _lead != null and _lead.ended:
		_finish_run(_lead)
		_lead = null
	_tick_echo(delta)
	_tick_duo(delta)
	_send_idle_heads_home()
	for head: HydraHead in _heads:
		head.advance(delta)
	_paint_telegraph()


func _choose_next_action() -> int:
	if not auto_attack:
		return NO_ATTACK
	var living := get_living_heads()
	if living.is_empty():
		return NO_ATTACK
	if living.size() == 1:
		_next_head = living[0]
		return _draw_attack(_frenzy_weights(living[0]))
	var candidates: Array[HydraHead] = []
	for head: HydraHead in living:
		if _run_of(head) == null:
			candidates.append(head)
	if candidates.is_empty():
		return NO_ATTACK
	if candidates.size() > 1:
		candidates.erase(_last_head)
	elif candidates[0] == _last_head:
		# The other head is still busy with its echo: wait instead of repeating.
		return NO_ATTACK
	var pick := candidates[rng.randi_range(0, candidates.size() - 1)]
	_next_head = pick
	_last_head = pick
	return int(pick.kind)


func _fight_delay() -> float:
	return super._fight_delay() * get_enrage_scale() * _recover_scale()


func _telegraph_time(attack_id: int) -> float:
	return _run_telegraph_time(_lead) if _lead != null else _base_telegraph(attack_id, false)


func _active_time(_attack_id: int) -> float:
	return _run_active_time(_lead) if _lead != null else 0.1


func _recover_time(attack_id: int) -> float:
	return _run_recover_time(_lead) if _lead != null else _base_recover(attack_id)


func _begin_attack_phase(_attack_id: int, phase_id: AttackPhase) -> void:
	if _lead == null:
		return
	if phase_id == AttackPhase.TELEGRAPH:
		_schedule_duo()
	_start_run_phase(_lead, phase_id, _state_left)
	_paint_telegraph()


func _update_attack_phase(_attack_id: int, _phase_id: AttackPhase, _delta: float) -> void:
	if _lead == null:
		return
	_lead.left = _state_left
	_run_update(_lead)


func _end_attack_phase(_attack_id: int, phase_id: AttackPhase) -> void:
	if _lead == null:
		return
	_run_end(_lead)
	_lead.ended = true
	if phase_id == AttackPhase.RECOVER:
		_finish_run(_lead)
		_lead = null


func _on_phase_entered(_phase_id: int) -> void:
	_echo_delay = NO_ECHO
	_drop_echo()


func _on_transition_started(_phase_id: int) -> void:
	for head: HydraHead in get_living_heads():
		head.roar(phase_transition_time)


func _clear_hazards() -> void:
	for venom: HydraVenom in _venoms:
		if is_instance_valid(venom):
			venom.release()
	for head: HydraHead in _heads:
		_disarm(head)
	_lead = null
	_echo = null
	_echo_delay = NO_ECHO
	_clear_telegraph()


## The root body is never struck: only a head, through `hit_head`, opens this.
func _accepts_hit(_damage: int, _source_position: Vector2) -> bool:
	return _hit_head != null


func _root_layer() -> int:
	return 0


## The Hydra never turns: it always faces the arena.
func _update_facing() -> void:
	pass


func _setup_flash() -> void:
	# A hit flashes the head that took it, not the body.
	pass


func _reset_ai() -> void:
	_next_head = null
	_last_head = null
	_hit_head = null
	if not _heads.is_empty():
		_begin_layout()
		for head: HydraHead in _heads:
			head.restore(_rest_point(head))
	super._reset_ai()
	if _heads_root != null:
		_heads_root.visible = true
	_clip = &""
	_cancel_visual_pose()
	_sync_sprite()


func _apply_visual() -> void:
	super._apply_visual()
	_cancel_visual_pose()
	_sync_sprite()
	if _heads_root != null:
		var corpse := _dead or _state == State.DEFEATED
		_heads_root.modulate = CORPSE_TINT if corpse else Color.WHITE
		# The drawn defeat shows the severed necks itself.
		_heads_root.visible = not (corpse and _has_clip(&"defeat"))


## -- Art -------------------------------------------------------------------------------------

## Reads the manifest and, when the body has art, shows its sprite and hides the placeholder
## polygon. The heads, the venom and the platforms dress themselves from the same art, each one
## independent of the body.
func _setup_art() -> void:
	_art = HydraArt.load_from(animation_manifest)
	_art_on = _sprite != null and _art.has_body()
	if _sprite == null:
		return
	_sprite.visible = _art_on
	if not _art_on:
		return
	_sprite.sprite_frames = _art.catalog().build_sprite_frames()
	_sprite.offset = _art.catalog().sprite_offset()
	_sprite_scale = _art.catalog().sprite_scale()
	_visual.move_child(_sprite, 0)
	var placeholder := _visual.get_node_or_null("Body") as CanvasItem
	if placeholder != null:
		placeholder.visible = false
	_bind_sprite_fx()
	_clip = &""
	_apply_visual()


## The telegraph glow of the phase beat is drawn on the sprite itself, so it follows the art.
func _bind_sprite_fx() -> void:
	_sprite_fx = BossSpriteFx.new(_sprite)
	if _telegraph != null:
		_telegraph.bind_sprite_fx(_sprite_fx)


## The drawn clips carry the slump of the corpse, so the sprite undoes `Visual`'s tilt and
## squash and keeps only the facing flip.
func _cancel_visual_pose() -> void:
	if not _art_on or _visual == null:
		return
	var pose := Transform2D(_visual.rotation, _visual.scale, 0.0, Vector2.ZERO)
	var wanted := Transform2D(0.0, Vector2(_visual.scale.x, 1.0), 0.0, Vector2.ZERO)
	var basis := pose.affine_inverse() * wanted
	_sprite.transform = Transform2D(basis.x * _sprite_scale, basis.y * _sprite_scale, _sprite.position)


func _has_clip(clip: StringName) -> bool:
	return _art_on and _sprite.sprite_frames.has_animation(clip)


## Picks the body clip for what the state machine is doing and plays it when it changes. A
## pure read of the logic: no state or timer is touched.
func _sync_sprite() -> void:
	if not _art_on:
		return
	var request := _clip_request()
	if request[0] != _clip:
		_play(request[0], request[1])


## [clip, duration] for the current state; duration 0 plays at the clip's own speed.
func _clip_request() -> Array:
	match _state:
		State.DEFEATED:
			return [&"defeat", defeat_time]
		State.TRANSITION:
			return [&"roar", phase_transition_time]
		State.IDLE:
			if _intro_left > 0.0:
				return [&"roar", _intro_left]
	return [&"idle", 0.0]


## Plays the contract clip `clip` (or the closest drawn one) stretched to last `duration`
## seconds. A corpse restored from an earlier run shows the last frame at once.
func _play(clip: StringName, duration := 0.0) -> void:
	_clip = clip
	var resolved := _art.catalog().resolve_clip(clip)
	if resolved.is_empty():
		return
	var frames := _sprite.sprite_frames
	var count := frames.get_frame_count(resolved)
	var fps := frames.get_animation_speed(resolved)
	var fit := 1.0
	if duration > 0.0 and count > 0 and fps > 0.0:
		fit = (float(count) / fps) / duration
	_sprite.play(resolved, fit)
	if _state == State.DEFEATED and _defeat_left <= 0.0:
		_sprite.pause()
		_sprite.frame = count - 1


## Dresses the platforms the boss scans (the group inside its arena), the ones teammates moved
## or added included: it runs at every rescan and never doubles a sprite.
func _dress_platforms() -> void:
	if _art == null or not is_inside_tree():
		return
	var alt := false
	for platform: Node in _tiers.platform_nodes():
		if is_instance_valid(platform) and _art.dress_platform(platform, alt):
			alt = not alt


## -- Heads and layout ------------------------------------------------------------------

func _collect_heads() -> void:
	_heads.clear()
	if _heads_root == null:
		return
	var total := 0
	for child: Node in _heads_root.get_children():
		var head := child as HydraHead
		if head != null:
			head.bind_boss(self)
			head.bind_art(_art)
			_heads.append(head)
			total += head.head_max_health
	# The pool is the sum of the heads by construction.
	if total > 0 and total != max_health:
		max_health = total
		if not _dead:
			_health = total


## Reads the platform tiers and puts every living head on its resting place.
func _begin_layout() -> void:
	if not is_inside_tree():
		return
	_tiers.rebuild(get_tree(), _spawn_position.y, _platforms_root())
	_dress_platforms()
	for head: HydraHead in _heads:
		head.rest_global = _rest_point(head)
		if not head.is_severed():
			head.snap_to(head.rest_global)


## The `Platforms` node of the closest ancestor that has one (this boss's own
## arena); null when the boss stands alone, which falls back to the whole tree.
func _platforms_root() -> Node:
	var host := get_parent()
	while host != null:
		var platforms := host.get_node_or_null("Platforms")
		if platforms != null:
			return platforms
		host = host.get_parent()
	return null


func _rest_point(head: HydraHead) -> Vector2:
	return Vector2(global_position.x + head.rest_dx, _tiers.tier_y(head.tier) - head_rest_height)


func _send_idle_heads_home() -> void:
	for head: HydraHead in _heads:
		if head.is_severed() or _run_of(head) != null:
			continue
		head.goal = head.rest_global
		head.speed = retract_speed
		head.set_stuck(false)
		head.set_horizontal_neck(false)
		head.set_pose(HydraHead.IDLE)


func _sever_head(head: HydraHead) -> void:
	head.sever()
	if _echo != null and _echo.head == head:
		_drop_echo()
	if _lead != null and _lead.head == head:
		_close_attack_phase()
		_finish_run(_lead)
		_lead = null
		if _state == State.ATTACK:
			_begin_fight()
	_advance_phase()


func _sever_all_heads() -> void:
	_lead = null
	_echo = null
	for head: HydraHead in _heads:
		head.sever()


func _disarm(head: HydraHead) -> void:
	head.set_stuck(false)
	head.set_horizontal_neck(false)
	head.set_pose(HydraHead.IDLE)
	head.hitbox.set_deferred(&"monitoring", false)


func _grant_soul() -> void:
	# Heads are not in the `enemies` group (tests and probes cast that whole group
	# to Enemy), so Luz's own soul rule does not see them: the boss pays it.
	if _luz_valid():
		_luz.add_soul(_luz.soul_per_hit)


func _living_count() -> int:
	return get_living_heads().size()


func _is_frenzy() -> bool:
	return _living_count() == 1


func _recover_scale() -> float:
	return frenzy_recover_scale if _is_frenzy() else 1.0


## Draw weights of the last head: its own attack counts more than a dead head's.
func _frenzy_weights(head: HydraHead) -> PackedFloat32Array:
	var weights := PackedFloat32Array([1.0, 1.0, 1.0])
	weights[int(head.kind)] = frenzy_native_weight
	return weights


## -- Runs: the attack of one head -----------------------------------------------------

func _make_run(attack: int, head: HydraHead, slot: int) -> Run:
	if head == null:
		return null
	var run := Run.new()
	run.head = head
	run.attack = attack
	run.weak = int(head.kind) != attack
	run.slot = slot
	return run


## The head that carries out `attack`: the one picked by the fight loop, else the
## one that owns the attack, else any living head that is not busy.
func _lead_head_for(attack: int) -> HydraHead:
	var picked := _next_head
	_next_head = null
	if picked != null and not picked.is_severed():
		return picked
	var owner_head := get_head(attack as HydraHead.Kind)
	if owner_head != null and not owner_head.is_severed():
		return owner_head
	for head: HydraHead in get_living_heads():
		if _run_of(head) == null:
			return head
	return null


func _run_of(head: HydraHead) -> Run:
	for run: Run in [_lead, _echo]:
		if run != null and run.head == head:
			return run
	return null


func _start_run_phase(run: Run, phase_id: int, duration: float) -> void:
	run.phase = phase_id as AttackPhase
	run.left = duration
	run.ended = false
	_run_begin(run)


## Ends a run for good: unspat venom is withdrawn, the hitbox is off, the head
## is free to go home. Globs already thrown keep flying: they are hazards now.
func _finish_run(run: Run) -> void:
	if run == null:
		return
	_run_end(run)
	for venom: HydraVenom in run.venoms:
		if is_instance_valid(venom) and venom.get_state() == HydraVenom.State.PLANNED:
			venom.release()
	run.venoms.clear()
	_disarm(run.head)
	if run == _echo:
		_echo = null


func _run_begin(run: Run) -> void:
	_pose_head(run)
	match run.attack:
		Attack.BITE_LUNGE:
			_bite_begin(run)
		Attack.VENOM_VOLLEY:
			_venom_begin(run)
		Attack.NECK_SWEEP:
			_sweep_begin(run)


func _run_update(run: Run) -> void:
	match run.attack:
		Attack.BITE_LUNGE:
			_bite_update(run)
		Attack.VENOM_VOLLEY:
			_venom_update(run)
		Attack.NECK_SWEEP:
			_sweep_update(run)


## The head shows the clip of the phase its attack is in; a stuck head and a roar override it.
func _pose_head(run: Run) -> void:
	match run.phase:
		AttackPhase.TELEGRAPH:
			run.head.set_pose(HydraHead.TELEGRAPH)
		AttackPhase.ACTIVE:
			run.head.set_pose(HydraHead.ATTACK)
		_:
			run.head.set_pose(HydraHead.IDLE)


## The hitbox is never left armed after a phase; the head's position is not
## touched, so a stuck head stays where it landed.
func _run_end(run: Run) -> void:
	run.head.hitbox.set_deferred(&"monitoring", false)


func _run_telegraph_time(run: Run) -> float:
	return _base_telegraph(run.attack, run.weak)


func _run_active_time(run: Run) -> float:
	match run.attack:
		Attack.BITE_LUNGE:
			return run.head.global_position.distance_to(run.lock_point) / _bite_speed(run) + 0.1
		Attack.VENOM_VOLLEY:
			return float(maxi(run.venoms.size() - 1, 0)) * venom_interval + venom_flight_time
		Attack.NECK_SWEEP:
			return absf(_sweep_start_x(run) - _sweep_end_x()) / _sweep_speed(run) + 0.05
	return 0.1


func _run_recover_time(run: Run) -> float:
	return _base_recover(run.attack)


func _run_duration(run: Run, phase_id: int) -> float:
	match phase_id:
		AttackPhase.TELEGRAPH:
			return maxf(_run_telegraph_time(run), MIN_TELEGRAPH)
		AttackPhase.ACTIVE:
			return _run_active_time(run)
	return _run_recover_time(run)


func _base_telegraph(attack: int, weak: bool) -> float:
	var base := bite_telegraph
	match attack:
		Attack.VENOM_VOLLEY:
			base = venom_telegraph
		Attack.NECK_SWEEP:
			base = sweep_telegraph
	var time := base * get_enrage_scale()
	if weak:
		time = base * weak_telegraph_scale
	return maxf(time, MIN_TELEGRAPH)


## The stuck head is the punish window: it is never shortened. The other
## recoveries shrink in the frenzy.
func _base_recover(attack: int) -> float:
	match attack:
		Attack.VENOM_VOLLEY:
			return venom_recover * _recover_scale()
		Attack.NECK_SWEEP:
			return sweep_recover * _recover_scale()
	return bite_stuck_time


## The echo of the duo: the second head's attack, overlapping the lead's.
func _schedule_duo() -> void:
	if auto_attack and _living_count() == 2:
		_echo_delay = duo_offset


func _tick_duo(delta: float) -> void:
	if _echo_delay == NO_ECHO:
		return
	_echo_delay -= delta
	if _echo_delay > 0.0:
		return
	_echo_delay = NO_ECHO
	_start_echo()


func _start_echo() -> void:
	if _echo != null or _lead == null or _living_count() != 2:
		return
	for head: HydraHead in get_living_heads():
		if head != _lead.head and _run_of(head) == null:
			_echo = _make_run(int(head.kind), head, ECHO_SLOT)
			_start_run_phase(_echo, AttackPhase.TELEGRAPH, maxf(_run_telegraph_time(_echo), MIN_TELEGRAPH))
			return


func _tick_echo(delta: float) -> void:
	if _echo == null:
		return
	_echo.left -= delta
	_run_update(_echo)
	if _echo.left > 0.0:
		return
	match _echo.phase:
		AttackPhase.TELEGRAPH:
			_run_end(_echo)
			_start_run_phase(_echo, AttackPhase.ACTIVE, _run_duration(_echo, AttackPhase.ACTIVE))
		AttackPhase.ACTIVE:
			_run_end(_echo)
			_start_run_phase(_echo, AttackPhase.RECOVER, _run_duration(_echo, AttackPhase.RECOVER))
		AttackPhase.RECOVER:
			_finish_run(_echo)


func _drop_echo() -> void:
	if _echo != null:
		_finish_run(_echo)
	_echo = null


## -- BITE_LUNGE ------------------------------------------------------------------------

func _bite_begin(run: Run) -> void:
	var head := run.head
	match run.phase:
		AttackPhase.TELEGRAPH:
			run.locked = false
			_aim_bite(run)
			head.goal = head.rest_global + Vector2(bite_coil, 0.0)
			head.speed = retract_speed
		AttackPhase.ACTIVE:
			head.goal = run.lock_point
			head.speed = _bite_speed(run)
			head.set_hitbox_rect(Rect2(Vector2.ONE * -bite_hitbox_size * 0.5, Vector2.ONE * bite_hitbox_size))
			_set_hitbox(head.hitbox, true)
		AttackPhase.RECOVER:
			head.set_stuck(true)


func _bite_update(run: Run) -> void:
	match run.phase:
		AttackPhase.TELEGRAPH:
			if run.locked:
				return
			_aim_bite(run)
			if run.left <= bite_lock_time:
				run.locked = true
				run.lock_point = Vector2(
					_clamp_to_arena(run.head.global_position.x + run.aim.x * run.aim_length, LUNGE_WALL_MARGIN),
					run.head.global_position.y + run.aim.y * run.aim_length,
				)
		AttackPhase.ACTIVE:
			_hurt_luz_once(run.head.hitbox, HIT_DAMAGE)


## Points the aim line at the middle of Luz's body, no farther than the lunge reaches.
func _aim_bite(run: Run) -> void:
	var from := run.head.global_position
	run.aim = _aim_at_luz(from)
	var distance := bite_reach * 0.5
	if _luz_valid():
		distance = from.distance_to(_luz.global_position + PLAYER_CENTER_OFFSET)
	run.aim_length = minf(distance, bite_reach)


func _bite_speed(run: Run) -> float:
	var speed := bite_speed
	if run.weak:
		speed *= weak_speed_scale
	elif _is_frenzy():
		speed *= frenzy_strength
	return speed


## -- VENOM_VOLLEY ----------------------------------------------------------------------

func _venom_begin(run: Run) -> void:
	match run.phase:
		AttackPhase.TELEGRAPH:
			run.venoms.clear()
			for spot: Vector2 in _plan_venom_spots(_venom_count(run)):
				var venom := _acquire_venom()
				venom.plan(spot, venom_pool_width, venom_flight_time, venom_arc_height, venom_pool_time)
				run.venoms.append(venom)
			run.spat = 0
			run.spit_clock = 0.0
		AttackPhase.ACTIVE:
			run.spat = 0
			run.spit_clock = 0.0


func _venom_update(run: Run) -> void:
	if run.phase != AttackPhase.ACTIVE:
		return
	run.spit_clock += get_physics_process_delta_time()
	while run.spat < run.venoms.size() and run.spit_clock >= float(run.spat) * venom_interval:
		run.venoms[run.spat].launch(run.head.global_position + MOUTH_OFFSET)
		run.head.roar(venom_interval, HydraHead.ATTACK)
		run.spat += 1


func _venom_count(run: Run) -> int:
	if run.weak:
		return weak_venom_count
	return venom_count + get_dead_head_count() * enrage_extra_globs


## The first spot is where Luz stands; the others fan out on both sides of it, on
## whichever surface (floor or platform) lies under each spot at her level.
func _plan_venom_spots(count: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var center_x := _luz_x()
	var feet_y := _luz.global_position.y if _luz_valid() else _tiers.floor_y
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var bounds := _arena_bounds()
	var min_x := bounds.x + LUNGE_WALL_MARGIN
	var max_x := maxf(global_position.x - body_gap_for_spots, min_x)
	for i: int in count:
		var offset := 0.0
		if i > 0:
			offset = side * venom_spacing * float(ceili(float(i) / 2.0))
			side = -side
		var x := clampf(center_x + offset, min_x, max_x)
		spots.append(Vector2(x, _tiers.surface_below(x, feet_y)))
	return spots


func _acquire_venom() -> HydraVenom:
	for venom: HydraVenom in _venoms:
		if is_instance_valid(venom) and not venom.is_active():
			return venom
	var extra := HydraVenom.new()
	extra.bind_art(_art)
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(extra)
	_venoms.append(extra)
	return extra


## -- NECK_SWEEP ------------------------------------------------------------------------

func _sweep_begin(run: Run) -> void:
	var head := run.head
	match run.phase:
		AttackPhase.TELEGRAPH:
			run.slab = _sweep_slab(_luz_tier())
			head.set_horizontal_neck(true)
			head.goal = Vector2(_sweep_start_x(run), _slab_center_y(run.slab))
			head.speed = retract_speed
		AttackPhase.ACTIVE:
			head.global_position.y = _slab_center_y(run.slab)
			head.goal = Vector2(_sweep_end_x(), head.global_position.y)
			head.speed = _sweep_speed(run)
			_fit_sweep_hitbox(run)
			_set_hitbox(head.hitbox, true)
		AttackPhase.RECOVER:
			head.goal = head.rest_global
			head.speed = retract_speed
			head.set_horizontal_neck(false)


func _sweep_update(run: Run) -> void:
	if run.phase == AttackPhase.ACTIVE:
		_fit_sweep_hitbox(run)
		_hurt_luz_once(run.head.hitbox, HIT_DAMAGE)


func _luz_tier() -> int:
	if not _luz_valid():
		return HydraHead.Tier.MID
	return _tiers.tier_of(_luz.global_position.y)


## The band swept for `tier`: from the left wall to the shoulders, as tall as
## `sweep_band_height`, covering a Luz standing on that tier's surface.
func _sweep_slab(tier: int) -> Rect2:
	var left := _arena_bounds().x
	var right := _heads_shoulder_x()
	var top := _tiers.tier_y(tier) - sweep_band_height + 4.0
	return Rect2(left, top, maxf(right - left, 1.0), sweep_band_height)


func _slab_center_y(slab: Rect2) -> float:
	return slab.position.y + slab.size.y * 0.5


func _heads_shoulder_x() -> float:
	return global_position.x + (_heads[0].shoulder.x if not _heads.is_empty() else 0.0)


func _sweep_start_x(_run: Run) -> float:
	return _heads_shoulder_x() - sweep_start_gap


func _sweep_end_x() -> float:
	return _arena_bounds().x + sweep_end_margin


func _sweep_speed(run: Run) -> float:
	var speed := sweep_speed * (1.0 + enrage_sweep_speed_gain * float(get_dead_head_count()))
	if run.weak:
		speed *= weak_speed_scale
	elif _is_frenzy():
		speed *= frenzy_strength
	return speed


## The hitbox is the whole extended neck: from the head back to the shoulder.
func _fit_sweep_hitbox(run: Run) -> void:
	var head := run.head
	var length := maxf(_heads_shoulder_x() - head.global_position.x + 30.0, 30.0)
	head.set_hitbox_rect(Rect2(-30.0, -sweep_band_height * 0.5, length, sweep_band_height))


## -- Telegraph drawing -------------------------------------------------------------------

## Redraws the aim line and the sweep band of every run that is winding up. The
## base clears the telegraph when an attack turns active; this puts back what
## still has to show (the other head's wind-up).
func _paint_telegraph() -> void:
	if _telegraph == null:
		return
	_telegraph.hide_aim_line()
	_telegraph.hide_floor_markers()
	if _state == State.ATTACK and _lead != null and _lead.phase == AttackPhase.TELEGRAPH:
		_paint_run(_lead)
	if _echo != null and _echo.phase == AttackPhase.TELEGRAPH:
		_paint_run(_echo)


func _paint_run(run: Run) -> void:
	match run.attack:
		Attack.BITE_LUNGE:
			_telegraph.show_aim_line(run.head.global_position, run.aim, run.aim_length, BossTelegraph.MELEE_COLOR, run.locked, run.slot)
		Attack.NECK_SWEEP:
			var alpha := 0.3 + 0.15 * sin(_clock * SWEEP_MARKER_PULSE_RATE)
			_telegraph.show_floor_marker(run.slot * MARKERS_PER_RUN, run.slab, BossTelegraph.MELEE_COLOR, alpha)

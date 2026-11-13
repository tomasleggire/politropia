extends SceneTree
## Collectible passives: definition data, manager totals, persistence through
## IDs, and the player's effective stats (health, damage, energy, dash, jump).
## Run: godot --headless --path . --script res://tests/collectible_passives_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PICKUP_SCENE := preload("res://scenes/world/collectible_pickup.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MANAGER_SCRIPT := preload("res://scripts/world/collectibles_manager.gd")
const WATCHDOG_SECONDS := 120.0
const FLOOR_RECT := Rect2(-600.0, 0.0, 1200.0, 100.0)

const HEALTH_A := "fixture_health_a"
const HEALTH_B := "fixture_health_b"
const DAMAGE := "fixture_damage"
const ENERGY := "fixture_energy"
const DASH := "fixture_dash"
const JUMP := "fixture_jump"
const JUMP_SMALL := "fixture_jump_small"
const NONE := "fixture_none"
const ZERO_HEALTH := "fixture_zero_health"
const NEGATIVE_HEALTH := "fixture_negative_health"
const NAN_HEALTH := "fixture_nan_health"
const INF_DAMAGE := "fixture_inf_damage"
const NEGATIVE_JUMP := "fixture_negative_jump"


class HitRecorder:
	extends Node2D
	var hits: Array = []

	func receive_hit(damage: int, _source_position: Vector2, attack_name: StringName) -> bool:
		hits.append({"damage": damage, "attack": attack_name})
		return true


var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player
var _saved_definitions: Array
var _saved_by_id: Dictionary


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		print("FAIL: watchdog")
		quit(1))
	await _run()
	_restore_real_catalog()
	_free_rig()
	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)


func _manager() -> Node:
	return root.get_node("Collectibles")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	await process_frame
	_saved_definitions = _manager()._definitions
	_saved_by_id = _manager()._definitions_by_id
	_restore_real_catalog()

	_case_definition_defaults()
	_case_manager_totals()
	_case_invalid_values()
	await _case_persistence()
	await _case_player_base()
	await _case_health()
	await _case_damage()
	await _case_energy()
	await _case_dash()
	await _case_jump()
	await _case_recreation_and_clear()
	await _case_pickup_only_on_first_collect()


# -- Fixtures -----------------------------------------------------------------

func _make_definition(id: String, effect: int, value: float) -> CollectibleDefinition:
	var definition := CollectibleDefinition.new()
	definition.id = id
	definition.title = id
	definition.set("passive_effect", effect)
	definition.passive_value = value
	return definition


func _fixtures() -> Array[CollectibleDefinition]:
	var definitions: Array[CollectibleDefinition] = []
	definitions.append(_make_definition(HEALTH_A, CollectibleDefinition.PassiveEffect.MAX_HEALTH, 1.0))
	definitions.append(_make_definition(HEALTH_B, CollectibleDefinition.PassiveEffect.MAX_HEALTH, 2.0))
	definitions.append(_make_definition(DAMAGE, CollectibleDefinition.PassiveEffect.DAMAGE, 2.0))
	definitions.append(_make_definition(ENERGY, CollectibleDefinition.PassiveEffect.MAX_ENERGY, 25.5))
	definitions.append(_make_definition(DASH, CollectibleDefinition.PassiveEffect.DASH_DURATION, 0.1))
	definitions.append(_make_definition(JUMP, CollectibleDefinition.PassiveEffect.JUMP_HEIGHT, 50.0))
	definitions.append(_make_definition(JUMP_SMALL, CollectibleDefinition.PassiveEffect.JUMP_HEIGHT, 20.0))
	definitions.append(_make_definition(NONE, CollectibleDefinition.PassiveEffect.NONE, 99.0))
	definitions.append(_make_definition(ZERO_HEALTH, CollectibleDefinition.PassiveEffect.MAX_HEALTH, 0.0))
	definitions.append(_make_definition(NEGATIVE_HEALTH, CollectibleDefinition.PassiveEffect.MAX_HEALTH, -3.0))
	definitions.append(_make_definition(NAN_HEALTH, CollectibleDefinition.PassiveEffect.MAX_HEALTH, NAN))
	definitions.append(_make_definition(INF_DAMAGE, CollectibleDefinition.PassiveEffect.DAMAGE, INF))
	definitions.append(_make_definition(NEGATIVE_JUMP, CollectibleDefinition.PassiveEffect.JUMP_HEIGHT, -10.0))
	return definitions


func _install_fixtures() -> void:
	_free_rig()
	var manager := _manager()
	manager.call("clear")
	manager._definitions = _fixtures()
	manager._definitions_by_id = {}
	for definition: CollectibleDefinition in manager._definitions:
		manager._definitions_by_id[definition.id] = definition


func _restore_real_catalog() -> void:
	var manager := _manager()
	manager.call("clear")
	if not _saved_definitions.is_empty():
		manager._definitions = _saved_definitions
		manager._definitions_by_id = _saved_by_id


func _collect(id: String) -> bool:
	return bool(_manager().call("try_collect", id))


func _total(effect: int) -> float:
	return float(_manager().call("get_passive_total", effect))


# -- Rig ----------------------------------------------------------------------

func _build_rig() -> void:
	_free_rig()
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(0.0, -10.0)
	_rig.add_child(_player)
	await _frames(20)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null


# -- Cases --------------------------------------------------------------------

func _case_definition_defaults() -> void:
	print("CASE definition defaults")
	var fresh := CollectibleDefinition.new()
	check(fresh.passive_effect == CollectibleDefinition.PassiveEffect.NONE, "a new definition defaults to NONE")
	check(is_equal_approx(fresh.passive_value, 0.0), "a new definition defaults to a zero value")
	check(is_equal_approx(fresh.passive_bonus(), 0.0), "NONE contributes no bonus even with a value")

	var none_with_value := _make_definition("none_value", CollectibleDefinition.PassiveEffect.NONE, 42.0)
	check(is_equal_approx(none_with_value.passive_bonus(), 0.0), "NONE ignores its configured value")

	var negative := _make_definition("negative", CollectibleDefinition.PassiveEffect.MAX_HEALTH, -2.0)
	var zero := _make_definition("zero", CollectibleDefinition.PassiveEffect.MAX_HEALTH, 0.0)
	var not_a_number := _make_definition("nan", CollectibleDefinition.PassiveEffect.MAX_HEALTH, NAN)
	var infinite := _make_definition("inf", CollectibleDefinition.PassiveEffect.MAX_HEALTH, INF)
	check(is_equal_approx(negative.passive_bonus(), 0.0), "negative values are ignored")
	check(is_equal_approx(zero.passive_bonus(), 0.0), "zero values are ignored")
	check(is_equal_approx(not_a_number.passive_bonus(), 0.0), "NaN values are ignored")
	check(is_equal_approx(infinite.passive_bonus(), 0.0), "infinite values are ignored")

	var definitions := _manager().call("get_all_definitions") as Array
	var all_none := definitions.size() == 6
	for definition: CollectibleDefinition in definitions:
		all_none = all_none and definition.passive_effect == CollectibleDefinition.PassiveEffect.NONE
		all_none = all_none and is_equal_approx(definition.passive_value, 0.0)
	check(definitions.size() == 6, "the real catalog still has six collectibles")
	check(all_none, "every real collectible remains NONE")


func _case_manager_totals() -> void:
	print("CASE manager totals")
	_install_fixtures()
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 0.0), "an empty session has no health bonus")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.DAMAGE), 0.0), "an empty session has no damage bonus")

	check(_collect(HEALTH_A), "a fixture health id is collected")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 1.0), "one health id adds its bonus")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.DAMAGE), 0.0), "an unrelated effect stays zero")

	check(not _collect(HEALTH_A), "the same id cannot be collected twice")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 1.0), "a duplicate id does not double its bonus")

	check(_collect(HEALTH_B), "a second health id is collected")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 3.0), "different ids with the same effect stack additively")

	check(_collect(DAMAGE), "the damage id is collected")
	check(_collect(ENERGY), "the energy id is collected")
	check(_collect(DASH), "the dash id is collected")
	check(_collect(JUMP), "the jump id is collected")
	check(_collect(NONE), "the NONE id is collected")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 3.0), "another effect does not change health")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.DAMAGE), 2.0), "the damage total is exact")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_ENERGY), 25.5), "the energy total is exact")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.DASH_DURATION), 0.1), "the dash total is exact")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.JUMP_HEIGHT), 50.0), "the jump total is exact")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.NONE), 0.0), "NONE is never summed")
	check(is_equal_approx(_total(999), 0.0), "an unknown effect sums to zero")
	check(not _collect("not_in_the_fixture_catalog"), "an id outside the catalog is rejected")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 3.0), "a rejected id grants nothing")

	_manager().call("clear")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 0.0), "clear resets the health total")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.JUMP_HEIGHT), 0.0), "clear resets the jump total")


func _case_invalid_values() -> void:
	print("CASE invalid values")
	_install_fixtures()
	check(_collect(ZERO_HEALTH), "a zero-value health id is a valid collectible")
	check(_collect(NEGATIVE_HEALTH), "a negative-value health id is a valid collectible")
	check(_collect(NAN_HEALTH), "a NaN-value health id is a valid collectible")
	check(_collect(INF_DAMAGE), "an infinite-value damage id is a valid collectible")
	check(_collect(NEGATIVE_JUMP), "a negative-value jump id is a valid collectible")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 0.0), "zero, negative and NaN health values add nothing")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.DAMAGE), 0.0), "an infinite damage value adds nothing")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.JUMP_HEIGHT), 0.0), "a negative jump value adds nothing")
	check(int(_manager().call("get_collected_count")) == 5, "invalid bonuses are still collected normally")


func _case_persistence() -> void:
	print("CASE persistence")
	_install_fixtures()
	_collect(HEALTH_A)
	_collect(JUMP)
	var snapshot: Dictionary = _manager().call("to_dict")
	check(snapshot.get("collected") is Array and (snapshot["collected"] as Array).size() == 2, "the save data stores the collected ids")
	check(not snapshot.has("passives"), "no separate passive data is written to the save")

	_manager().call("clear")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 0.0), "clear removes the bonuses before restore")
	_manager().call("from_dict", snapshot)
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 1.0), "restoring ids rebuilds the health bonus")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.JUMP_HEIGHT), 50.0), "restoring ids rebuilds the jump bonus")

	_manager().call("from_dict", snapshot)
	_manager().call("from_dict", snapshot)
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.MAX_HEALTH), 1.0), "restoring the same ids again does not stack the health bonus")
	check(is_equal_approx(_total(CollectibleDefinition.PassiveEffect.JUMP_HEIGHT), 50.0), "restoring the same ids again does not stack the jump bonus")

	# A fresh manager instance with the same catalog + saved ids behaves like a
	# full app restart: passives are reconstructed, never read from player stats.
	var clone := MANAGER_SCRIPT.new()
	root.add_child(clone)
	await process_frame
	clone._definitions = _manager()._definitions
	clone._definitions_by_id = _manager()._definitions_by_id
	clone.call("from_dict", snapshot)
	check(is_equal_approx(float(clone.call("get_passive_total", CollectibleDefinition.PassiveEffect.MAX_HEALTH)), 1.0), "a fresh manager reconstructs health from saved ids")
	check(is_equal_approx(float(clone.call("get_passive_total", CollectibleDefinition.PassiveEffect.JUMP_HEIGHT)), 50.0), "a fresh manager reconstructs jump from saved ids")
	clone.free()
	await process_frame


func _case_player_base() -> void:
	print("CASE player base")
	_install_fixtures()
	await _build_rig()
	check(_player.get_max_health() == 5, "without passives max health is the authored five")
	check(_player.get_health() == 5, "without passives health starts full")
	check(_player.attack_damage == 1, "without passives attack damage is the authored one")
	check(is_equal_approx(_player.max_energy, 100.0), "without passives max energy is the authored one")
	check(is_equal_approx(_player.current_energy, 100.0), "without passives energy starts full")
	check(is_equal_approx(_player.dash_duration, 0.43), "without passives the ground dash keeps its duration")
	check(is_equal_approx(_player.air_dash_duration, 0.30), "without passives the air dash keeps its duration")
	check(is_equal_approx(_player._jump_height_bonus_percent, 0.0), "without passives there is no jump height bonus")
	check(is_equal_approx(_player._jump_velocity, -_player._rise_gravity * _player.jump_time_to_apex), "without passives the launch speed matches the original formula")
	check(_player._base_max_health == 5 and _player._base_attack_damage == 1, "the base stats are captured separately")
	check(is_equal_approx(_player._base_dash_duration, 0.43) and is_equal_approx(_player._base_jump_height, 120.0), "base dash and jump values come from the scene")


func _case_health() -> void:
	print("CASE health")
	_install_fixtures()
	await _build_rig()
	var events: Array = []
	var on_health := func(current: int, maximum: int) -> void:
		events.append(Vector2i(current, maximum))
	_player.health_changed.connect(on_health)

	check(_player.take_damage(2, _player.global_position), "the player can take damage before collecting")
	check(_player.get_health() == 3, "two points of damage leave three hearts")

	check(_collect(HEALTH_A), "a one-heart passive is collected")
	check(_player.get_max_health() == 6, "max health rises by the first bonus")
	check(_player.get_health() == 4, "the new heart arrives full")
	check(_collect(HEALTH_B), "a second health passive is collected")
	check(_player.get_max_health() == 8, "health bonuses from different ids stack")
	check(_player.get_health() == 6, "the two new hearts arrive full")

	check(_player.heal(99) == 2, "healing fills up to the new maximum")
	check(_player.get_health() == 8, "the player can reach the bonused maximum")
	check(_player._base_max_health == 5, "the base max health stays untouched")

	_manager().call("clear")
	check(_player.get_max_health() == 5, "clearing the ids removes the health bonus")
	check(_player.get_health() == 5, "health is clamped to the restored maximum")
	check(events.size() >= 4, "health changes are announced to the HUD")
	_player.health_changed.disconnect(on_health)


func _case_damage() -> void:
	print("CASE damage")
	_install_fixtures()
	await _build_rig()
	var target := HitRecorder.new()
	_rig.add_child(target)

	check(_player.attack_damage == 1, "base outgoing damage is one")
	check(_collect(DAMAGE), "the damage passive is collected")
	check(_player.attack_damage == 3, "the bonus is added to Luz's outgoing damage")
	check(_player._base_attack_damage == 1, "the base damage stays one")

	_player._resolve_attack_hit(target, &"attack_ground_1")
	check(target.hits.size() == 1, "one slash calls receive_hit once")
	check(int(target.hits[0]["damage"]) == 3, "the final outgoing damage carries the bonus once")
	_player._resolve_attack_hit(target, &"attack_ground_1")
	check(int(target.hits[1]["damage"]) == 3, "a second slash does not accumulate the bonus")

	_manager().call("clear")
	check(_player.attack_damage == 1, "clearing the ids restores the base damage")
	_player._resolve_attack_hit(target, &"attack_ground_1")
	check(int(target.hits[2]["damage"]) == 1, "the next slash uses the base damage again")


func _case_energy() -> void:
	print("CASE energy")
	_install_fixtures()
	await _build_rig()
	check(_player.use_energy(40.0), "the player can spend base energy")
	check(is_equal_approx(_player.current_energy, 60.0), "spending energy lowers the current charge")

	check(_collect(ENERGY), "the energy passive is collected")
	check(is_equal_approx(_player.max_energy, 125.5), "the bonus raises the maximum capacity")
	check(is_equal_approx(_player.current_energy, 60.0), "raising capacity does not refill the current charge")
	check(_player.get_soul() == 0, "the energy passive does not create or change soul")

	_player.gain_energy(999.0)
	check(is_equal_approx(_player.current_energy, 125.5), "the current charge can reach the bonused capacity")
	check(is_equal_approx(_player._base_max_energy, 100.0), "the base capacity stays untouched")

	_manager().call("clear")
	check(is_equal_approx(_player.max_energy, 100.0), "clearing the ids restores the base capacity")
	check(is_equal_approx(_player.current_energy, 100.0), "the current charge is clamped to the base capacity")


func _case_dash() -> void:
	print("CASE dash")
	_install_fixtures()
	await _build_rig()
	var old_frames := _player._animation_sprite_frames

	_player._start_dash()
	check(is_equal_approx(_player._active_dash_duration, 0.43), "the first dash snapshots the base duration")
	check(_collect(DASH), "the dash passive is collected during the dash")
	check(is_equal_approx(_player.dash_duration, 0.53), "the effective ground dash gains the bonus")
	check(is_equal_approx(_player.air_dash_duration, 0.40), "the effective air dash gains the bonus")
	check(is_equal_approx(_player._active_dash_duration, 0.43), "the dash in progress keeps its old duration")
	check(_player._dash_animation_dirty, "the dash clip change is deferred while dashing")
	check(_player._dash_speed_at(0.45) < 200.0, "the current dash movement still uses its snapshotted duration")
	check(_player._animation_sprite_frames == old_frames, "the clips are not swapped in the middle of a dash")

	_player._enter_state(Player.State.IDLE)
	_player._start_dash()
	check(not _player._dash_animation_dirty, "the next dash flushes the deferred clip rebuild")
	check(_player._animation_sprite_frames != old_frames, "the dash clips are rebuilt with the new duration")
	check(is_equal_approx(_player._active_dash_duration, 0.53), "the next dash snapshots the bonused duration")
	check(_player._dash_speed_at(0.45) > 200.0, "the longer dash keeps moving at the old end time")

	_manager().call("clear")
	check(is_equal_approx(_player.dash_duration, 0.43), "clearing the ids restores the ground dash duration")
	check(is_equal_approx(_player.air_dash_duration, 0.30), "clearing the ids restores the air dash duration")
	_player._enter_state(Player.State.IDLE)


func _case_jump() -> void:
	print("CASE jump")
	_install_fixtures()
	await _build_rig()
	var base_rise_gravity := _player._rise_gravity
	var base_fall_gravity := _player._fall_gravity
	var base_jump_speed := absf(_player._jump_velocity)
	var base_double_speed := absf(_player._double_jump_velocity)

	check(_collect(JUMP), "the jump passive is collected")
	check(is_equal_approx(_player._jump_height_bonus_percent, 50.0), "the jump bonus is read as a percentage")
	check(is_equal_approx(_player._rise_gravity, base_rise_gravity), "the rise gravity is preserved")
	check(is_equal_approx(_player._fall_gravity, base_fall_gravity), "the fall gravity is preserved")
	check(is_equal_approx(absf(_player._jump_velocity), base_jump_speed * sqrt(1.5)), "the ground launch speed is scaled by sqrt(1 + percent / 100)")
	check(is_equal_approx(absf(_player._double_jump_velocity), base_double_speed * sqrt(1.5)), "the double jump gets the same height bonus")
	var predicted_rise := (_player._jump_velocity * _player._jump_velocity) / (2.0 * _player._rise_gravity)
	check(is_equal_approx(predicted_rise, _player._base_jump_height * 1.5), "the extra percentage becomes extra apex height")
	check(is_equal_approx(_player.jump_release_multiplier, 0.45), "the variable jump release multiplier is untouched")

	# Collecting while airborne updates the next air jump, not the current arc.
	_player.global_position = Vector2(0.0, -210.0)
	await _frames(2)
	check(not _player.is_on_floor(), "the player is airborne for the next check")
	_player.velocity.y = -80.0
	check(_collect(JUMP_SMALL), "a second jump passive is collected while airborne")
	check(is_equal_approx(_player._jump_height_bonus_percent, 70.0), "the airborne collection stacks the height percentage")
	check(is_equal_approx(_player.velocity.y, -80.0), "the current rise is not teleported by the collection")
	check(is_equal_approx(absf(_player._double_jump_velocity), base_double_speed * sqrt(1.7)), "the next air jump uses the new bonus")

	_player.can_double_jump = true
	_player._air_jumps_left = 1
	_player._coyote_left = 0.0
	_player._jump_pressed_now = true
	check(_player._try_air_jump(), "the player can still start an air jump")
	check(is_equal_approx(_player.velocity.y, _player._double_jump_velocity), "the air jump launches with the bonused speed")

	_manager().call("clear")
	check(is_equal_approx(_player._jump_height_bonus_percent, 0.0), "clearing the ids removes the jump bonus")
	check(is_equal_approx(_player._rise_gravity, base_rise_gravity) and is_equal_approx(_player._fall_gravity, base_fall_gravity), "clearing keeps the authored gravity")
	check(is_equal_approx(absf(_player._jump_velocity), base_jump_speed), "clearing restores the base ground launch speed")
	check(is_equal_approx(absf(_player._double_jump_velocity), base_double_speed), "clearing restores the base double jump speed")


func _case_recreation_and_clear() -> void:
	print("CASE recreation")
	_install_fixtures()
	await _build_rig()
	_collect(HEALTH_A)
	_collect(HEALTH_B)
	_collect(DAMAGE)
	_collect(ENERGY)
	_collect(DASH)
	_collect(JUMP)
	check(_player.get_max_health() == 8, "all health ids apply together")
	check(_player.attack_damage == 3, "the damage id applies together with the rest")
	check(is_equal_approx(_player.max_energy, 125.5), "the energy id applies together with the rest")
	check(is_equal_approx(_player.dash_duration, 0.53), "the dash id applies together with the rest")
	check(is_equal_approx(_player._jump_height_bonus_percent, 50.0), "the jump id applies together with the rest")

	# A new Player (scene change, retry or reload) rebuilds the same stats from
	# the collected ids; it never adds the bonuses a second time.
	await _build_rig()
	check(_player.get_max_health() == 8, "a recreated player keeps the same health maximum")
	check(_player.attack_damage == 3, "a recreated player keeps the same damage")
	check(is_equal_approx(_player.max_energy, 125.5), "a recreated player keeps the same energy capacity")
	check(is_equal_approx(_player.dash_duration, 0.53), "a recreated player keeps the same dash duration")
	check(is_equal_approx(_player._jump_height_bonus_percent, 50.0), "a recreated player keeps the same jump bonus")
	check(not _collect(HEALTH_A), "an already collected id is still rejected after recreation")
	check(_player.get_max_health() == 8, "the rejected duplicate does not grant a second bonus")

	var snapshot: Dictionary = _manager().call("to_dict")
	_manager().call("from_dict", snapshot)
	_manager().call("from_dict", snapshot)
	check(_player.get_max_health() == 8 and _player.attack_damage == 3, "restoring the same save twice is idempotent on the player")

	_manager().call("clear")
	check(_player.get_max_health() == 5, "clearing the ids restores the base health on a live player")
	check(_player.attack_damage == 1, "clearing the ids restores the base damage on a live player")
	check(is_equal_approx(_player.max_energy, 100.0), "clearing the ids restores the base energy on a live player")
	check(is_equal_approx(_player.dash_duration, 0.43), "clearing the ids restores the base dash on a live player")
	check(is_equal_approx(_player._jump_height_bonus_percent, 0.0), "clearing the ids restores the base jump on a live player")


func _make_pickup(definition: CollectibleDefinition, at: Vector2) -> CollectiblePickup:
	var pickup := PICKUP_SCENE.instantiate() as CollectiblePickup
	pickup.definition = definition
	pickup.position = at
	pickup.collect_animation_time = 0.4
	return pickup


func _case_pickup_only_on_first_collect() -> void:
	print("CASE pickup")
	_install_fixtures()
	await _build_rig()
	var definition := _manager()._definitions_by_id[HEALTH_A] as CollectibleDefinition
	var pickup := _make_pickup(definition, Vector2(0.0, -30.0))
	_rig.add_child(pickup)
	await _frames(4)
	check(bool(_manager().call("has_collected", HEALTH_A)), "a successful pickup collects its id")
	check(_player.get_max_health() == 6, "a successful pickup grants its passive")
	check(not pickup.monitoring and pickup.get_node("CollisionShape2D").disabled, "the collected pickup deactivates immediately")

	await _frames(30)
	var duplicate := _make_pickup(definition, Vector2(0.0, -30.0))
	_rig.add_child(duplicate)
	await _frames(4)
	check(not is_instance_valid(duplicate) or duplicate.is_queued_for_deletion(), "a reloaded pickup for a collected id removes itself")
	check(_player.get_max_health() == 6, "the reloaded pickup does not grant the passive again")
	check(int(_manager().call("get_collected_count")) == 1, "the reloaded pickup does not duplicate progress")

	var snapshot: Dictionary = _manager().call("to_dict")
	_manager().call("from_dict", snapshot)
	check(_player.get_max_health() == 6, "reloading the saved collectible does not double the passive")

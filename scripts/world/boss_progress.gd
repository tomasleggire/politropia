extends Node

## Bosses beaten during this run (autoload `BossProgress`).
##
## Why its own autoload: EnemyRegistry forgets every kill on a desk rest or a
## death (that is its rule for ordinary enemies), and a boss must not return
## from either. Like the registry and CheckpointService it has to outlive the
## level scene, so a re-entered or reloaded arena still knows its boss is gone.
## Per boss it keeps: defeated, where the corpse lies (position and facing) and
## whether the reward was picked up. BossArena owns what to do with it.
##
## SAVE SYSTEM NOTE: the project has no disk save yet, so this lives only for
## the run. When one is added, call `to_dict()` / `from_dict()` and store the
## result in the SAME save as the player's abilities (the double jump), written
## at the same moment. Out of sync it softlocks: a save with `reward_claimed`
## true but an old player without the double jump can never get it back. The
## safe direction is the other one: defeated and unclaimed makes the arena
## re-spawn the pickup on load.

const SAVE_VERSION := 1

var _bosses: Dictionary = {}


## Records the defeat. `at` and `facing` say where the corpse lies. Calling it
## again keeps the reward flag and only moves the corpse.
func mark_defeated(boss_id: StringName, at := Vector2.ZERO, facing := 1) -> void:
	var record := _record(boss_id)
	record["defeated"] = true
	record["position"] = at
	record["facing"] = 1 if facing >= 0 else -1


func is_defeated(boss_id: StringName) -> bool:
	return _bosses.has(boss_id) and _bosses[boss_id]["defeated"]


## `{"position": Vector2, "facing": int}` of the corpse, empty when not defeated.
func get_corpse(boss_id: StringName) -> Dictionary:
	if not is_defeated(boss_id):
		return {}
	var record: Dictionary = _bosses[boss_id]
	return {"position": record["position"], "facing": record["facing"]}


func mark_reward_claimed(boss_id: StringName) -> void:
	_record(boss_id)["reward_claimed"] = true


func is_reward_claimed(boss_id: StringName) -> bool:
	return _bosses.has(boss_id) and _bosses[boss_id]["reward_claimed"]


## Forgets every boss (tests, new game).
func clear() -> void:
	_bosses.clear()


## Plain data (JSON friendly) for a future save system.
func to_dict() -> Dictionary:
	var bosses := {}
	for boss_id: StringName in _bosses:
		var record: Dictionary = _bosses[boss_id]
		var at: Vector2 = record["position"]
		bosses[String(boss_id)] = {
			"defeated": record["defeated"],
			"x": at.x,
			"y": at.y,
			"facing": record["facing"],
			"reward_claimed": record["reward_claimed"],
		}
	return {"version": SAVE_VERSION, "bosses": bosses}


## Replaces everything with `data`. All or nothing: if the version, the layout or
## any entry's field types are wrong nothing is applied and the result is a clean
## slate. Missing fields take their defaults; present ones must be well typed.
func from_dict(data: Dictionary) -> void:
	_bosses.clear()
	if not _is_number(data.get("version")) or int(data["version"]) != SAVE_VERSION or not data.get("bosses") is Dictionary:
		return
	var saved: Dictionary = data["bosses"]
	for key: Variant in saved:
		if not saved[key] is Dictionary or not _entry_is_valid(saved[key]):
			return
	for key: Variant in saved:
		_restore(StringName(str(key)), saved[key])


func _entry_is_valid(entry: Dictionary) -> bool:
	for flag: String in ["defeated", "reward_claimed"]:
		if entry.has(flag) and not entry[flag] is bool:
			return false
	for axis: String in ["x", "y"]:
		if entry.has(axis) and not _is_number(entry[axis]):
			return false
	# JSON turns integers into floats, so 1.0 and -1.0 are valid.
	return not entry.has("facing") or (_is_number(entry["facing"]) and absf(float(entry["facing"])) == 1.0)


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _restore(boss_id: StringName, saved: Dictionary) -> void:
	var record := _record(boss_id)
	record["defeated"] = saved.get("defeated", false)
	record["position"] = Vector2(float(saved.get("x", 0.0)), float(saved.get("y", 0.0)))
	record["facing"] = int(saved.get("facing", 1))
	record["reward_claimed"] = saved.get("reward_claimed", false)


func _record(boss_id: StringName) -> Dictionary:
	if not _bosses.has(boss_id):
		_bosses[boss_id] = {"defeated": false, "position": Vector2.ZERO, "facing": 1, "reward_claimed": false}
	return _bosses[boss_id]

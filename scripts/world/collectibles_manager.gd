extends Node

## Session-scoped collectible progress (autoload `Collectibles`).
##
## The catalog is the explicit list of every collectible in the game. Only IDs
## that exist in that catalog can be collected, so a typo in a level object is
## reported instead of becoming an invisible "ghost" entry.
##
## World objects, the gallery and the main menu use only this public API.
## Everything else is private. The IDs are saved by `SaveService` (see
## `to_dict()`/`from_dict()`), never by pickups or the gallery. Passive bonuses
## are derived from those IDs, so they need no separate persistence.
##
## The catalog is the source of truth for each passive effect; this manager only
## sums the definitions of the collected IDs, so the same ID can never grant its
## bonus twice and the totals are always rebuilt from scratch.

signal collectibles_changed
signal collectible_collected(id: String, count: int, total: int)

const CATALOG_PATH := "res://data/collectibles/catalog.tres"

var _definitions: Array[CollectibleDefinition] = []
var _definitions_by_id: Dictionary = {}
var _collected: Dictionary = {}


func _ready() -> void:
	_load_catalog()


func _load_catalog() -> void:
	_definitions.clear()
	_definitions_by_id.clear()

	var catalog := load(CATALOG_PATH) as CollectibleCatalog
	if catalog == null:
		push_error("Collectibles: could not load the catalog at %s" % CATALOG_PATH)
		return

	for definition in catalog.items:
		if definition == null:
			push_warning("Collectibles: the catalog contains a null definition; skipping it.")
			continue
		var id := definition.id
		if id.is_empty():
			push_warning("Collectibles: a definition without an id was skipped.")
			continue
		if _definitions_by_id.has(id):
			push_warning("Collectibles: duplicate catalog id '%s'; keeping the first definition." % id)
			continue
		_definitions.append(definition)
		_definitions_by_id[id] = definition


## True when this session already registered `id`.
func has_collected(id: String) -> bool:
	return _collected.has(id)


## Registers `id` for the first time. Returns false for a duplicate or for an
## ID that is not in the catalog (and reports the unknown ID with a warning).
func try_collect(id: String) -> bool:
	if not _definitions_by_id.has(id):
		push_warning("Collectibles: '%s' is not in the catalog; collection rejected." % id)
		return false
	if _collected.has(id):
		return false
	_collected[id] = true
	collectible_collected.emit(id, get_collected_count(), get_total_count())
	collectibles_changed.emit()
	return true


## IDs collected during this session, sorted alphabetically.
func get_collected_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _collected.keys():
		ids.append(String(id))
	ids.sort()
	return ids


## Every definition of the catalog, in catalog order.
func get_all_definitions() -> Array[CollectibleDefinition]:
	return _definitions.duplicate()


func get_total_count() -> int:
	return _definitions.size()


func get_collected_count() -> int:
	return _collected.size()


## Sum of the passive bonuses of `effect` across every collected definition.
## Rebuilt from the collected IDs on every call, so it is idempotent, stacks
## different IDs additively, counts an ID once, and ignores NONE/invalid values.
func get_passive_total(effect: int) -> float:
	if effect == CollectibleDefinition.PassiveEffect.NONE:
		return 0.0
	var total := 0.0
	for id: Variant in _collected.keys():
		var definition: CollectibleDefinition = _definitions_by_id.get(id)
		if definition == null or definition.passive_effect != effect:
			continue
		total += definition.passive_bonus()
	return total


## Forgets the collectibles of this session. It never touches the catalog or
## any other progress system.
func clear() -> void:
	if _collected.is_empty():
		return
	_collected.clear()
	collectibles_changed.emit()


func to_dict() -> Dictionary:
	return {"version": 1, "collected": get_collected_ids()}


func from_dict(data: Dictionary) -> void:
	_collected.clear()
	if int(data.get("version", 0)) == 1 and data.get("collected") is Array:
		for id: Variant in data["collected"]:
			if (id is String or id is StringName) and _definitions_by_id.has(String(id)):
				_collected[String(id)] = true
	collectibles_changed.emit()

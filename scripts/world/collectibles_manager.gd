extends Node

## Session-scoped collectible progress (autoload `Collectibles`).
##
## The catalog is the explicit list of every collectible in the game. Only IDs
## that exist in that catalog can be collected, so a typo in a level object is
## reported instead of becoming an invisible "ghost" entry.
##
## World objects, the gallery and the main menu use only this public API.
## Everything else is private, which keeps a future save system in one place:
## save `get_collected_ids()` and restore that list inside this script.
##
## SAVE SYSTEM NOTE: no disk persistence yet, on purpose. When it exists, load
## the saved IDs here in `_ready()` and write them after `try_collect()`/`clear()`
## without changing any caller.

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


## Forgets the collectibles of this session. It never touches the catalog or
## any other progress system.
func clear() -> void:
	if _collected.is_empty():
		return
	_collected.clear()
	collectibles_changed.emit()

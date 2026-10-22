class_name CollectibleCatalog
extends Resource

## Explicit list of every collectible in the game, including the ones that
## belong to levels that are not loaded. The gallery reads this list so it can
## show the whole collection from the main menu.

@export var items: Array[CollectibleDefinition] = []

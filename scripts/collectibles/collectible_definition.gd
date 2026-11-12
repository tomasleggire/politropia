class_name CollectibleDefinition
extends Resource

## Static data for one collectible.
##
## `id` is the stable key used by the session state and by every world object.
## Never use the title as an identifier: the team can change the title, the
## text or the image without losing collected progress.

## Optional passive bonus granted the first time this collectible is collected.
## The player rebuilds its effective stats from the collected IDs, so one ID can
## never grant the same bonus twice (not even after a scene reload or Continue).
enum PassiveEffect {
	NONE,
	MAX_HEALTH,
	DAMAGE,
	MAX_ENERGY,
	DASH_DURATION,
	JUMP_HEIGHT,
}

@export_group("Identity")
## Stable, unique identifier (for example "library_first_steps").
@export var id: String = ""
## Name shown in the gallery.
@export var title: String = ""
## Category shown as a small label in the gallery.
@export var category: String = ""

@export_group("Passive Bonus")
## Effect granted on first collection. Keep it NONE for collectibles that should
## not alter gameplay. Every ID with the same effect stacks additively.
@export var passive_effect: PassiveEffect = PassiveEffect.NONE
## Bonus amount, in the unit of the selected effect:
## MAX_HEALTH = extra hearts, DAMAGE = extra outgoing damage points,
## MAX_ENERGY = extra capacity units, DASH_DURATION = extra seconds,
## JUMP_HEIGHT = extra height percentage (100 = twice the base height).
## Zero, negative and non-finite values are ignored.
@export var passive_value: float = 0.0

@export_group("Content")
## Journal text shown when the collectible is unlocked. Multiline is allowed.
@export_multiline var content: String = ""
## Optional art. Leave it empty to use the provisional gallery placeholder.
@export var image: Texture2D = null


## Bonus this definition contributes to its effect, or 0 when it has no valid
## bonus. Keeps the manager/player free of special cases for bad Inspector data.
func passive_bonus() -> float:
	if passive_effect == PassiveEffect.NONE:
		return 0.0
	if is_nan(passive_value) or is_inf(passive_value) or passive_value <= 0.0:
		return 0.0
	return passive_value

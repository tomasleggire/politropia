class_name CollectibleDefinition
extends Resource

## Static data for one collectible.
##
## `id` is the stable key used by the session state and by every world object.
## Never use the title as an identifier: the team can change the title, the
## text or the image without losing collected progress.

@export_group("Identity")
## Stable, unique identifier (for example "library_first_steps").
@export var id: String = ""
## Name shown in the gallery.
@export var title: String = ""
## Category shown as a small label in the gallery.
@export var category: String = ""

@export_group("Content")
## Journal text shown when the collectible is unlocked. Multiline is allowed.
@export_multiline var content: String = ""
## Optional art. Leave it empty to use the provisional gallery placeholder.
@export var image: Texture2D = null

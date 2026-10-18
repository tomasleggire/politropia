class_name AmbienceStyle
extends Resource

## Look of a biome's atmosphere, used by ZoneAmbience. Duplicate
## `data/ambience/library.tres` to make a new preset and drop it in the
## ZoneAmbience `style` slot; no code needed.

@export_group("Tint")
## Ambient colour multiplied over the whole world (HUD is not touched).
## White leaves the art as painted; warm and dark values read as candlelight.
@export var tint_color := Color.WHITE

@export_group("Vignette")
## Colour of the screen-edge darkening.
@export var vignette_color := Color(0.02, 0.01, 0.0)
## 0 hides the vignette, 1 is nearly black at the corners.
@export_range(0.0, 1.0, 0.01) var vignette_strength := 0.4

@export_group("Luz light")
## Small light that follows Luz so she stays readable in dark tints.
@export var luz_light_color := Color(1.0, 0.82, 0.58)
@export_range(0.0, 2.0, 0.05) var luz_light_energy := 0.35
@export_range(32.0, 400.0, 1.0) var luz_light_radius := 110.0

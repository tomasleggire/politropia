# Politropia — Gothic library art direction

## Visual pillars

- Original high-end pixel art with crisp clusters and a readable mobile silhouette.
- Near-black navy architecture with cobalt edge light and sparse amber candlelight.
- A vast ruined cathedral-library: arches, bookcases, iron chandeliers, dust and mist.
- Collision geometry stays mechanically unchanged; cool platform crowns carry gameplay readability.
- The wanderer stays small against the architecture, with a hat, short cloak, pale scarf and no weapon.

## Palette

- Dark: `#050712`, `#090D1D`, `#101A33`, `#182B4F`
- Cool light: `#24558A`, `#4C79A8`, `#78B8DF`
- Warm accent: `#D8792E`, `#F0AE4C`
- Character cloth: `#B8C9DC`

## Generation prompt set

All three assets used the supplied image as a style/mood reference only and explicitly excluded copied composition, characters, UI and text.

1. **Library background:** wide 16:9 ruined gothic cathedral-library, layered shelves, arches, columns, chandeliers, mist and sparse candles; quiet dark lower fifth; no character or platforms.
2. **Stone texture:** seamless orthographic navy masonry with worn rectangular stones, mortar, chips and restrained cobalt glints; no scenery or directional vignette.
3. **Wanderer sheet:** exact 4x2 grid of one consistent right-facing wanderer; idle x2, walk x3, jump, fall and land; transparent background, aligned scale and feet.

The built-in image-generation workflow was used. `tools/process_gothic_assets.py` creates the optimized runtime assets from their generated sources.

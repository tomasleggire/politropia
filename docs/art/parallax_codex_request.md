# Parallax art request for Codex

Final backdrop layers for the library and Greece biomes. The game already runs
with provisional layers built from existing art (`data/parallax/library.tres`,
`data/parallax/greece.tres`); each delivered PNG replaces one of them by
dropping it into the matching texture slot of the style resource. No code
change is needed.

## Game constraints

- Pixel art, nearest-neighbour filtering, 1 art pixel = 1 game unit. The base
  view is 640x360 and grows up to about 800x500 on wide phones and tablets.
- Landscape camera that follows Luz through zones up to roughly 2500x1300
  units. The layers scroll slower than the world, so they must be taller and
  wider than one screen (sizes below).
- One style across both biomes: the same pixel density, outline weight and
  shading as the current tiles and the existing library and Greece
  backgrounds. Do not paint at a higher or lower pixel scale.
- The game tints each biome at runtime (warm candlelight in the library,
  golden dusk in Greece), so paint neutral-to-slightly-warm colours and leave
  the final grading to the engine. Keep values readable but not bright: the
  gameplay layer (tiles, Luz, enemies) must always stand out from the backdrop.
- No characters, UI, text, platforms or anything that looks walkable.
- RGBA PNG. Transparent background wherever a layer is not a full picture.

## Layers per biome

Four layers per biome, listed from far to near. Sizes are in art pixels
(= game units).

| Layer | Slot in the style | Size | Transparency | Scroll |
|-------|-------------------|------|--------------|--------|
| 1. Far | `far_texture` | 2048x1024 | Opaque | slow (0.45) |
| 2. Mid silhouettes | `mid_textures` (3 to 6 sprites) | 64-128 px wide, 160-320 px tall each | Transparent | medium (0.7) |
| 3. Fog | `fog_texture` | 1024x128, seamless on the left and right edges | Greyscale mask | drifts sideways |
| 4. Near haze | `haze_texture` | 1024x128, seamless on the left and right edges | Greyscale mask | faster than the world |

### 1. Far

The distant scenery, one picture per zone family (a zone can reuse the
biome's default). It scrolls at a fraction of Luz's speed, so keep the
important detail in the central 60%: the engine crops the edges.

- Library: the vast hall seen from far away. Arches, bookcase walls, tall
  windows with soft light, mist. Dark navy and brown, sparse amber highlights.
  A quiet, dark lower fifth so the floor tiles read.
- Greece: the Aegean vista. Hills, cypresses, a temple on a ridge, sea and
  haze, a dusk sky. Pale and atmospheric, lower contrast than the tiles, with
  no strong shapes at the bottom edge.
- It must not contain a floor line: the real ground is drawn by the tiles.

### 2. Mid silhouettes

Separate small sprites that the engine scatters across the zone at random
spacing and tints as hazy dark shapes. Each one stands on its bottom edge.

- Library: bookcases, an arch, a tall window frame, a pillar, a chandelier on
  a chain (hanging ones are ok: say so, they will be flagged to hang from the
  top).
- Greece: cypress trees, a column with its capital, a ruined wall, a bush.
- Flat, readable silhouette first, with a little interior detail. They will be
  drawn at 1x or 2x only, so paint them at the size they should appear at 1x.
- Name them `mid_<biome>_<what>.png`.

### 3 and 4. Fog and haze

Greyscale only. White is fully fogged, black is empty; the engine colours the
mask and fades it at the top and bottom. The left and right edges must tile
without a visible seam. Soft clumps of mist: fog is finer and slower, the near
haze is larger, softer blobs.

## Palette

Stay inside the project's existing palettes (see
`docs/GOTHIC_ART_DIRECTION.md` for the library).

- Library: darks `#050712`, `#090D1D`, `#101A33`, `#182B4F`, cool light
  `#24558A`, `#4C79A8`, warm accent `#D8792E`, `#F0AE4C`, plus the warm browns
  already in the library tiles.
- Greece: sandstone, terracotta and olive from the Greece tiles, with the
  pale blue-grey of the current backgrounds for distance. Keep saturation
  below the tiles so the backdrop recedes.

## Delivery

- Files under `assets/art/library/Parallax/` and `assets/art/greece/Parallax/`.
- Keep the files named by layer: `far_<zone>.png`, `mid_<biome>_<what>.png`,
  `fog.png`, `haze.png`.
- Mention which zones each far picture is meant for. The mapping is done in the
  `ParallaxBackdrop` instance of that zone (`style`) or in the style resource.

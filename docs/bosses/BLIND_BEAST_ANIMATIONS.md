# Blind Beast animation contract

Audience: Codex (art agent) and whoever runs the processing script. Goal: replace El Topo's `Polygon2D` placeholders (and his drawn-by-code hazards) with final art **without touching gameplay**.
Numbers come from `scripts/enemies/bosses/blind_beast_boss.gd` and `scenes/enemies/bosses/blind_beast.tscn`. The fight itself is described in `docs/bosses/BLIND_BEAST.md`. The format mirrors `docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md`.

---

## 1. Character brief

Same style as Luz, Artemis and El Profesor: thick dark outline `#1A1410`, cel shading in 2-3 steps, flat shapes, one palette.

| Aspect | Direction |
|---|---|
| Who | The blind old man of the library side quest (`assets/world/blind_npc.jpg`) turned into a giant blind STAR-NOSED MOLE: the star nose feels vibrations. He stands upright and hunched like an old man, in place; he never walks above ground. |
| References | `tools/art_sources/blind_beast/concept/` (the approved concept) and `tools/art_sources/blind_beast/prompts/character_concept.md`. |
| Keeps from the old man | The grey hair tuft, the milky blind eyes, the torn charcoal jacket, the dark red tie and the wooden cane. |
| Star nose | Pink, **roughly `#E07A8F` with shadow `#A8485E`**, in every pose that shows the head. It is the size reference of the script (2.3): keep those two tones, no other large pink area (the hands and claws are NOT that pink). |
| Mood | Eerie, never gory. Blind: the head turns toward sound, the nose twitches. The corpse is a collapsed old-man-mole with the cane beside him. |
| Burrowed | He is **never drawn as the character** while burrowed: only the `mound` prop (4.1). |

---

## 2. Technical contract

### 2.1 Nodes

| Path (under `BlindBeast`, a `CharacterBody2D`) | Contract |
|---|---|
| `Visual` (`Node2D`) | Code owns it: `scale.x = facing`, `visible` (hidden while burrowed), `position`, `modulate` (stun and corpse tints; with drawn art the stun tint is `STUN_ART_STRENGTH` 0.25 of the placeholder tint and the corpse dims to `ART_CORPSE_TINT`, both in `BossEnemy`), tilt and squash of the placeholder corpse. Art never animates these. |
| `Visual/AnimatedSprite2D` | The final art, first child of `Visual` (so the flash and glow clones draw above it). `texture_filter = 4`, `scale = 0.2896`, `offset = (0, -192)`. |
| `Visual/Body`, `Nose`, `Claws` | Placeholders. Visible only when no art exists. The telegraph glow and the white hit flash are drawn on the sprite itself by `shaders/sprite_glow.gdshader` (`BossSpriteFx`), so they follow the exact silhouette; without art the old polygon clones are used. |
| `CollisionShape2D` | 40 x 64 at `(0, -32)` on this scene only (the base boss is 26 x 56, the placeholder was 46 x 38) so Luz's hits connect with the drawn torso and head. It applies with or without art. |
| Hazards | Drawn by code in `Hazards` (a top level node); they poll boxes against Luz. Their size and timing do not change (4). |

### 2.2 Origin, facing and scale

- **Origin = feet, horizontally centred** (the feet centre of each cell sits on the cell centre).
- **Art faces RIGHT (+x).** `Visual.scale.x = facing` flips it. Asymmetric props (the cane) are correct for the right-facing frame.
- The drawn clips already carry the lean, the swipe and the slump: the sprite undoes `Visual`'s corpse tilt and squash and keeps only the facing flip. While he sinks, the drawn `dig_in` replaces the code's sinking (`Visual.position.y`), so the frames are **cut at the floor line** (lower body under the ground) and must NOT be shifted down in the cell.
- **On-screen size:** about **70 px** from sole to the top of the head when standing (Luz 48, Artemis 56, El Profesor 92; his eruption column is 56 x 90). The thin cane top and a hair wisp that stick out do not count. Same on-screen pixel scale as Artemis: `sprite_scale` **0.2896** (= 0.1448 x 512 / 256).
- **Processed cell: 448 x 448 px, feet row 416** (`animation_manifest.json`: `cell`, `feet_row`). Standing height in the cell = 70 / 0.2896 = 242 px. The cell leaves 416 px (120 screen px, about 1.7x his height) above the feet for the raised slam pose, and 448 px (130 screen px, 65 each side of the feet) for the widest pose, the claw swipe. `offset.y = -(416 - 224) = -192`. Same cell and feet row as El Profesor so the two bosses share one set of numbers.
- `emerge` and `dig_in` are drawn **cut at the floor line**: the lower body is under the ground, so the cut edge of the frame sits on the feet row like the soles of every other clip. They align to the feet row exactly like the rest, and the pipeline aligns them on their largest component (`body_feet`) so flying dirt never moves the row.
- All frames of all clips share the cell size and the feet row. No per-frame offset in code.

### 2.3 Raw sheets and the pipeline

Codex draws raw magenta sheets of **1536 x 1024**: `claw` is **3 columns x 2 rows** (512 x 512 cells, the swipe is wide), every other sheet is **4 x 2** (384 x 512 cells). Codex does not keep exact geometry: the script splits by connected components per grid cell.
Raw file: `tools/art_sources/blind_beast/raw/blind_beast_<sheet>_raw.png`. Output: `assets/enemies/blind_beast/blind_beast_<sheet>_sheet.png` + `animation_manifest.json` (`cell`, `feet_row`, `sprite_scale`, `sheets {file: {grid, clips, events}}`, `props` and `fx` `{sheet, sprite_scale, grid, clips, content}`).

Scale rules (script `tools/process_blind_beast_sheets.py`, helpers in `tools/boss_sheet_pipeline.py`):

- The `exposed_idle` frames set the base: median height sole to the top of the head, scaled to 242 px. The top is the first row whose solid pixels are at least 15% of the widest row (`body_height`), so the thin cane (a few percent of the width) or a hair wisp that sticks out above the head is skipped.
- Codex draws each sheet at a slightly different size, so each sheet is scaled to match the **size of the pink star nose** of `exposed` (`color_block_size`: pixels within a tolerance of `#E07A8F` or `#A8485E`, opened to drop specks; the topmost large block, sqrt of its area, median over the sheet). The nose exists in every pose that shows the head. `size_cells` limits the measured cells, and cells where no nose is found are ignored:

  | Sheet | `size_cells` | Why |
  |---|---|---|
  | `burrow` | `height_cells` 3 | the nose swings between side-on and front-on in this sheet (measured 14 to 59 raw px), so the standing, cane-in-hand frame 3 is matched by body height to the `exposed` idle height instead of by nose |
  | `intro` | 4-7 | the first frames show the old man, before the nose exists |
  | `defeat` | 0-4 | the lying frames hide the head |
  | others | all | the nose is visible |

  `scale_mult` tunes a sheet by hand. A sheet whose nose measures 0 in every measured cell stops the script with an error naming the sheet.
- `props` and `fx` are keyed with a stricter magenta cut (`EFFECT_KEY_HIGH` 60) and `clear_pink_leaks` cleans the magenta that bled into them (their art is brown, beige and grey only): strongly magenta pixels and every pink region that borders the keyed background along more than `LEAK_OPEN_SHARE` of its outline (the pale pocket beside the eruption column) become transparent together with their faint fringe, a pink region enclosed by outline (a dust puff painted pale pink) turns beige, and the pale puffs get their red capped over green so they share one beige.
- Colours: Codex paints the jacket and the fur in a slightly different tone in every sheet. `harmonise_colours` shifts the muted tones of every character sheet to the `exposed` sheet, per tone class (`TONES`: the cool, purple-brown jacket and the warm fur, skin and shirt) and per lightness band (`pipeline.match_tones`, two passes). Saturated accents (the red tie, the pink nose) fade out of the shift (chroma fade), and it runs after the scales are measured, so the nose size reference is read from the raw colours. Without the `exposed` sheet nothing changes.
- Edge despill: the character sheets are keyed with `pipeline.despill_edges`: the antialiased silhouette edge is un-mixed from the magenta against the measured outline colour (`unmix_fringe`), so no pink or purple halo is left on semi-transparent edge pixels. `props` and `fx` are not despilled.
- Props and effects have no figure: every cell keeps its place in the raw cell, each clip is cropped with one shared box and centred in a **256 px cell** at one fixed factor (`EFFECT_SCALE` 0.5, so a raw 384 x 512 cell fits). The game rescales each effect to its hazard from the per-clip `content` box.
- A props or fx cell with no drawn pixels stops the script with an error naming the sheet and the cell.
- Unused cells are dropped; clip indices in the manifest are for the compacted sheet.

Run (Pillow, numpy and scipy are not in the system Python; use a venv, nothing global):

```
python3 -m venv /tmp/politropia-art-venv && /tmp/politropia-art-venv/bin/pip install pillow numpy scipy
/tmp/politropia-art-venv/bin/python tools/process_blind_beast_sheets.py --preview <dir>
```

Missing raw sheets are skipped with a message (exit 0); sheets already processed stay in the manifest. `--preview DIR` writes each sheet with the feet row and reference lines for Luz (48 px), Artemis (56 px) and El Topo (70 px), and the measured nose size.

### 2.4 Sheet plan (raw cells in reading order)

| Sheet | Cells -> clips |
|---|---|
| `exposed` | `exposed_idle` 0-3 (loop), `dazed` 4-7 (loop) |
| `burrow` | `emerge` 0-3, `dig_in` 4-7 |
| `claw` (3 x 2) | `claw_windup` 0-1, `claw_strike` 2-3, `claw_recover` 4-5 |
| `slam` | `slam_windup` 0-1, `slam_strike` 2-3, `phase_change` 4-7 |
| `intro` | `intro` 0-7 (the old man turning into the beast); the clip table lists 12 entries, `0, 0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7`, so the old man holds a third of the reveal, his hunch a sixth and the change into the mole the other half. The sheet keeps its 8 cells; the manifest clip repeats the indices and the catalog adds one frame per entry. |
| `defeat` | `defeat` 0-7 (6-7 are the corpse) |
| `props` (no figure) | `mound` 0-3 (loop), `rock` 4, `rock_alt` 5, `crack` 6, `spike` 7 |
| `claw_fx` (2 x 2, one effect) | `claw_swipe` 0-3: three bone-coloured claw slashes sweeping from the upper left to the lower right and raking the ground (thin scratch lines, strike, follow-through with earth, remnants and dust) |
| `fx` (no figure) | `erupt_column` 0-2, `pulse_wave` 3-4, `dust_puff` 5, `rock_impact` 6, `dig_dirt` 7 |

---

## 3. Clip table

The boss asks for clips by these names. A clip that is not drawn resolves through the fallbacks (`CLIP_FALLBACKS` in the boss) and then to `exposed_idle`. A **strike** is a short clip that shows when ACTIVE starts. Playback speed is derived at play time (`frames / fps / duration`); a clip never decides when a state ends: the state machine ends it and the clip is cut or holds its last frame (one-shot clips hold, `exposed_idle` and `dazed` loop).

| Clip | Trigger in code | Duration source | Loop | Fallback |
|---|---|---|---|---|
| `exposed_idle` | He is above ground and nothing else applies: after an eruption, probe, chain or pulse (RECOVER), FLINCH and STAGGER while exposed, the claw counter's aftermath | open-ended | loop | none (default) |
| `dazed` | `STUN`: the missed eruption (`missed_stun_time` 1.8 s), the pulse that felt nothing (`tremor_confused_time` 1.2 s), Hyperfocus dragging him up (`hyperfocus_stun_time` 1.2 s) | open-ended | loop | `exposed_idle` |
| `emerge` | ERUPTION and DEBRIS_TOSS ACTIVE (the column is up): he rises through it, still burrowed for the rules (untargetable) | `column_active_time` (0.3 s) | hold | `exposed_idle` |
| `dig_in` | `FIGHT` while he sinks after being exposed (`_digging`); he is untargetable from its first frame | `dig_in_time` (0.3 s) | hold | `exposed_idle` |
| `claw_windup` | CLAW_COUNTER TELEGRAPH | the telegraph (`claw_telegraph_time` 0.45 s, never under 0.4) | hold | `slam_windup`, then `exposed_idle` |
| `claw_strike` | CLAW_COUNTER ACTIVE (strike frame, the zone hurts) | `claw_active_time` (0.15 s) | hold | `claw_windup` |
| `claw_recover` | CLAW_COUNTER RECOVER | rest of the phase (`claw_recover_time` 0.5 s) | hold | `claw_strike` |
| `slam_windup` | TREMOR_PULSE TELEGRAPH (he is surfaced, the red glow runs) | the telegraph (`tremor_telegraph_time` 0.7 s) | hold | `claw_windup` |
| `slam_strike` | TREMOR_PULSE ACTIVE (the pulses leave; he dives when it feels Luz) | held for 0.3 s (`SLAM_STRIKE_TIME`) then the last frame | hold | `slam_windup` |
| `phase_change` | `TRANSITION` | `phase_transition_time` (1.0 s) | one-shot | `exposed_idle` |
| `intro` | `play_intro(duration)` while `IDLE`: the sprite is shown although he is burrowed, and he goes under again when it ends | the intro duration given by the arena | one-shot | not shown at all |
| `defeat` | `DEFEATED`; a restored corpse shows the last frame | `defeat_time` (0.9 s) | one-shot | `exposed_idle` |

**Burrowed there is no clip**: while he is underground (tunnelling, the telegraph of an eruption, probe or chain, the ridge) `Visual` is hidden and only the `mound` prop and the hazards are drawn. ERUPTION and DEBRIS_TOSS are the only attacks that show him rising (`emerge`); in PROBE and CHAIN_ERUPTION he stays under until RECOVER, where he shows `exposed_idle`.

**Events** (manifest `events`: clip -> frame index of the strike inside the clip): `claw_strike` and `slam_strike` at frame 0, because the clip starts when ACTIVE starts.

Gameplay overlays stay code-driven: ripples, floor cracks warnings, the claw zone's translucent warning fill, rock markers. The hit flash and the telegraph glow keep their logic and only change how they look (the shader on the sprite, as for El Profesor: `BossTelegraph.bind_sprite_fx`; a melee telegraph glows red on `claw_windup` and `slam_windup`).

## 4. Props and effects

Hazards keep their boxes, speeds and timings. With art each one shows a sprite and its placeholder is not drawn; without the art (or without that sheet) the placeholder stays, and ripples and the red floor warnings are always drawn. Each sprite is scaled from the `content` box of its clip in the manifest to the box that hurts (`BoomboxHazard.art_scale`, the single relation; a clip with no `content` box falls back to the size of one cell, never to an oversized sprite). `BlindBeastHazardArt` (extends `BoomboxEffectArt`) keeps one sprite per live hazard.

| Art | Sheet / clip | Hazard and fit |
|---|---|---|
| Mound | props `mound`, four-frame loop at 6 fps | where he tunnels (`show_mound`): 40 px wide, `WIDTH`, standing on the floor; replaces the dirt dome, the dust trail stays |
| Rocks | props `rock`, `rock_alt` (alternating) | each thrown rock (debris radius 22): `CONTAIN` in a 40 px square, spinning in flight; the landing marker stays |
| Crack | props `crack` | the warning under a future column (56 px wide): `WIDTH`, on the floor, opening as the warning runs down; the red footprint and outline stay |
| Spike | props `spike` | each braille spike that is up: `STRETCH` to its hurt box (0.8 x the slot wide, as tall as it is raised, up to 64 px), standing on the floor; the telegraphed bumps stay drawn |
| Column | fx `erupt_column`, three frames | the eruption column (56 x 90, rising for 0.1 s, up for 0.3 s): `STRETCH` to the box that hurts, frame chosen by the column's clock |
| Pulse | fx `pulse_wave`, two-frame loop at 8 fps | the tremor pulse (one per side): 40 x 24 px, `STRETCH`, on the floor, mirrored for the left-going one |
| Dust | fx `dust_puff` | a 40 px puff at the base of every eruption column |
| Rock impact | fx `rock_impact` | a 40 px puff where a rock lands |
| Dig dirt | fx `dig_dirt` | a 40 px puff where he starts to dig in |
| Claw swipe | claw_fx `claw_swipe`, four frames | the claw zone (120 x 60 px on the floor, centred on the swing origin), `WIDTH` (uniform scale, about 61 px tall), standing on the floor, mirrored toward the side he faces. Telegraph: frame 0 (thin scratch lines) held and pulsing between white and a red tint over the zone's translucent red fill (the warning stays at least as readable as the old rectangle). Active: frames 1 and 2 split over `claw_active_time` (0.15 s). After it, frame 3 lingers 0.25 s and fades as a cosmetic one-shot that touches no zone, timer or `hazard_count()`. Without the sheet the pulsing striped rectangle stays |

Processing: `claw_fx` is 2 x 2 raw cells of 768 x 512 holding four frames of one effect (about 708 x 360 raw px, flat ground edge shared by every frame). It is despilled but not recoloured (`clear_pink_leaks` would change its bone and earth colours); `clear_claw_pink_specks` only removes a separate drawn piece of at most 300 raw px whose pixels are at least 20% pink (red above green by 25 with blue within 8 under green: no bone, earth, dust or outline colour is), as the pink pebble that floated over the dust in frame 3, with its outline. Pieces attached to the dust or the claws stay. The frames keep their place relative to each other and are scaled by `CLAW_FX_SCALE` 0.52 (about 368 texels wide for the 120 px zone, so about 3 texels per game px) into one row of **400 x 208 px cells** (`CLAW_FX_CELL`), each with at least 8 px of empty margin. Manifest entry `claw_fx` (non-square grid, `cell_width` 400, `cell_height` 208). A missing raw sheet is skipped with a message.

Processing: `props` and `fx` are 4 x 2 raw cells of 384 x 512 cropped per clip with one shared box and centred in a 256 px cell at one factor (`EFFECT_SCALE` 0.5). Manifest entries `props` and `fx` carry `sheet`, `sprite_scale`, `grid`, `clips` and `content`.

## 5. Integration checklist

1. Raw sheets in `tools/art_sources/blind_beast/raw/`.
2. Run the script, check the previews: feet (or the floor cut) on the line, 70 px green/yellow/red lines at the top of the head, the nose size close between sheets, no size jumps.
3. `godot --headless --path . --import`, then `tests/blind_beast_boss_test.gd` and `tests/boss_animation_catalog_test.gd`.
4. Look at the real fight: `emerge` and `dig_in` meet the floor line, the corpse shows the last `defeat` frame, flash and glow cover the sprite, the mound hides the dirt dome, Luz's hits connect on the torso and head.

# Hydra animation contract

Audience: Codex (art agent) and whoever runs the processing script. Goal: replace La Hidra's placeholders (one body polygon, three polygon heads with a drawn-by-code neck and stump, drawn-by-code venom, grey platform slabs) with final art **without touching gameplay**.
Numbers come from `scripts/enemies/bosses/hydra_boss.gd`, `hydra/hydra_head.gd`, `hydra/hydra_venom.gd`, `scenes/enemies/bosses/hydra.tscn` and `hydra_boss_arena.tscn`. The fight itself is described in `docs/bosses/HYDRA.md`. The format mirrors `docs/bosses/BLIND_BEAST_ANIMATIONS.md`.

---

## 1. Character brief

Same style as Luz, Artemis, El Profesor and El Topo: thick dark outline `#1A1410`, cel shading in 2-3 steps, flat shapes, one palette.

| Aspect | Direction |
|---|---|
| Who | The Lernaean Hydra as a massive coiled serpent. It is a multi-part boss: a body that never moves, three separate heads on necks, and a procedural neck. |
| Reference | `tools/art_sources/hydra/prompts/character_concept.md` (the approved concept) and `tools/art_sources/hydra/prompts/sheets.md`. |
| Body | Dark teal scales with a pale ochre belly. The body sheets draw **no head**: the neck roots at the shoulders are plain stumps the neck line is drawn from. |
| Heads | They keep the gameplay colours so the target priority still reads. Biter (low): crimson, heavy jaw, big fangs. Sweeper (mid): violet, long flat blade-like snout and crest. Spitter (high): acid green, cobra hood and venom sacs. |
| Mood | Eerie, never gory. The severed necks of the defeat are dark stumps, no blood. |

---

## 2. Technical contract

### 2.1 Nodes

| Path (under `Hydra`, a `CharacterBody2D`) | Contract |
|---|---|
| `Visual` (`Node2D`) | Code owns it: `scale.x = facing` (the Hydra never turns, `start_facing` is -1, so the right-facing art looks left, toward the arena), `modulate` (corpse tint), tilt and squash of the placeholder corpse. Art never animates these. |
| `Visual/AnimatedSprite2D` | The body art, first child of `Visual`. `texture_filter = 4`, `scale = 0.2896`, `offset` from the manifest (`cell`, `feet_row`). Hidden without body art. |
| `Visual/Body` | Placeholder polygon. Visible only when the body has no art. The phase-beat glow is drawn on the sprite by `shaders/sprite_glow.gdshader` (`BossSpriteFx`), without art the old polygon glow is used. |
| `Heads/<LowHead, MidHead, HighHead>` (`HydraHead`, `Area2D`) | Hurtbox and hitbox stay exactly as they are. With art each head gets three children created by code: `Sprite` (the head), `Neck` (a textured `Line2D`) and `Stump` (shown only when severed), plus a `StuckMark` cross when the art has no `dazed` pose. The head draws its own polygons, neck line and stump only for the pieces that have no art. |
| `CollisionShape2D` | 96 x 140 at `(0, -70)`. Unchanged. |
| Venom (`HydraVenom`, created by code in the world) | With art: a glob sprite, a puddle sprite and a one-shot splash. Collision and timings unchanged. |
| Platforms (`Platforms/*` in the group `hydra_platform`) | The body keeps its collision child **named `CollisionShape2D`**. With art the boss adds a child `HydraArt` (an `AnimatedSprite2D`) and hides the `Visual` polygon. |

### 2.2 Origin, facing and scale

- **All art is drawn facing RIGHT (+x).** The body sprite goes under `Visual`, which is mirrored already. The head sprites live in `Heads` (not mirrored) and are flipped in code (`scale.x` negative) so they face the arena like today's head polygons. The stump is flipped the same way.
- **Body: origin = lowest coil, horizontally centred** (the feet centre of each cell sits on the cell centre). **On-screen size about 112 x 152 px** (the placeholder polygon is 112 x 152; the root collision is 96 x 140). Same on-screen pixel density as Artemis, El Profesor and El Topo: `sprite_scale` **0.2896** (= `pipeline.sprite_scale_for(256)`).
- **Processed body cell: 640 x 640 px, feet row 608.** Standing height in the cell = 152 / 0.2896 = 525 px, which leaves 83 px (24 screen px) above for the rearing roar. `offset.y = -(608 - 320) = -288`.
- **Head: origin = the head centre.** On-screen about **56 x 42 px** (the placeholder polygon). Crests, fangs and a hood may overhang; the hurtbox (48 x 44) and the hitbox are not touched. **Processed head cell: 288 x 288 px** (a 256 px cell left the open-mouth roar frames less than 8 px from the edge, see the margin rule below), the first `idle` frame centred on the cell (193 px = 56 screen px wide).
- **Head alignment.** Every frame of a head sheet is aligned on the **centre of the yellow eye**, not on the bounding box (an open jaw or a taller crest changes the box and would make the head jitter; the first version anchored on the top of the skull and the telegraph crest moved the head 12 screen px). A frame whose eye cannot be found falls back to the upper back of the skull. Draw **a visible yellow eye in every pose**, even a squint.
- **Neck.** Drawn by a `Line2D` with a tiled texture from the **body's neck root** to the moving head origin, **behind the body** (z -1, the body is at 0, the platform sprites at -2) so the rounded stump of the art covers the start of the neck. The root is where the head's tier stump is in the body frame that is showing (manifest `neck_roots`, see 2.3); a body without recorded roots keeps the head's `shoulder` export. The `shoulder` export itself is gameplay (the sweep start, the band and the neck hitbox read `shoulder.x` of the first head) and is not moved. The neck leaves the stump and enters the head horizontally (a cubic curve); in a sweep it bends to the head's height within 70 px of the root and runs flat, as the damage does. The script turns the `neck` cell into a seamless horizontal tile **18 px thick on screen** (outline included), drawn at 2 texels per screen px so the game's 2x downscale stays smooth, and flipped vertically so the ochre belly runs along the underside of a neck that runs left.
- **Platforms:** 160 px wide, the art's **top edge on the collision top**; the slab may hang a few px below (the collision is 16 px thick). Venom puddle 88 px wide, venom glob 19 px, stump 38 px wide.
- All frames of a sheet share the cell size. No per-frame offset in code.

### 2.3 Raw sheets and the pipeline

Codex draws raw magenta sheets of **1536 x 1024**: `body` and `defeat` are **3 columns x 2 rows** (512 x 512 cells), every other sheet is **4 x 2** (384 x 512 cells). Codex does not keep exact geometry: the script splits by connected components per grid cell.

**Keying.** The magenta is removed only where it is background: pixels within 70 (RGB distance) of #FF00FF that are connected to the sheet border, plus enclosed pockets of them (6 px or more). Every other pixel stays opaque whatever its hue, so the violet crest of the sweeper and the pink tongues survive (the shared `key_magenta` removed the violet because its magenta excess, `min(r, b) - g`, is above 90 there). Within 3 px of the background the silhouette edge is un-mixed from magenta against the outline colour (27, 15, 21): the magenta share becomes transparency and the colour becomes the outline again, and after the resize the faint edge pixels take the outline colour, so no pink halo is left (zero tinted edge pixels measured on every Hydra sheet). The art is outlined all round, which this relies on.

**Colour match.** The defeat sheet was drawn a lighter, greyer green than the body sheet. The script moves the scale greens of the defeat sheet to the mean and spread (per CIE Lab channel) of the body sheet's greens; the weight fades in with how green a pixel is, so the ochre, the outline and the dark stump openings are untouched.

**Outline.** Codex draws every sheet at its own size, so the same prompt gave a body outline about 2.8 game px thick (the 640 x 360 unit) against 1.3 to 1.8 for the heads, 1.0 for El Topo and 1.2 for El Profesor. The script measures the outer outline of each piece (the pixels within 40 RGB of the outline colour, within 4 game px of the silhouette, per px of silhouette length) and brings it to 1.15 game px: an eroded silhouette (outline pixels removed; the radius is refused if it would take more than 85 percent of the measured outline) or a grown one (a stroke in the outline colour), always before the final resize so the edge stays antialiased. The radius is solved on the reference cell and applied to every frame of the sheet. Props are measured as the game draws them (the fit of `PROP_FIT`), and the neck tile gets 1.2 game px of outline along both edges. A piece within 0.2 game px of the target is left alone.

**Margins.** `shaders/sprite_glow.gdshader` samples up to 7 texels around each texel, so every figure cell needs 8 empty texels at its edges or the glow bleeds into the next cell of the atlas. The script stops with the offending cells when a body or head cell is tighter.
Raw file: `tools/art_sources/hydra/raw/hydra_<sheet>_raw.png`. Output: `assets/enemies/hydra/hydra_<sheet>_sheet.png`, `hydra_neck.png` and `animation_manifest.json`:

```
cell, feet_row, sprite_scale                    the body sheets (640, 608, 0.2896)
sheets { file: {grid, clips, events} }          body and defeat (read by BossAnimationCatalog)
sheets.<body>.neck_roots                        clip -> per frame -> [low, mid, high] -> [x, y]: on-screen px of
                                                the right-facing art from the feet centre (x right, y down)
head_biter / head_spitter / head_sweeper        {sheet, sprite_scale, grid, clips, content}
props                                           {sheet, sprite_scale, grid, clips, content}
neck                                            {texture, thickness, tile}
```

Scale rules (script `tools/process_hydra_sheets.py`, helpers in `tools/boss_sheet_pipeline.py`):

- **Neck roots.** For the `body` sheet the script finds the three rounded stumps on the right side of every frame (the right-most silhouette point in each band of rows) and records the root 35 cell px inside each tip, lowest first (the tier order of the heads). The roots move with the idle bob and the roar, and the game moves the necks with them. A body frame without exactly three stumps stops the script.
- **Body sheets.** The content height of the first cell (`idle` 0 of `body`, cell 0 of `defeat`) is scaled to 525 px. Each sheet has its own scale (Codex draws every sheet at a slightly different size). No colour block is needed: every cell holds one isolated object. Frames are placed with the lowest coil on the feet row and the feet centre on the cell centre (the largest component only, so debris never moves the row).
- **Head sheets.** The content width of the first `idle` cell is scaled to 193 px (56 on screen), one scale per sheet, then every frame is placed on the eye anchor (2.2).
- **Props.** Like El Topo's props: every clip is cropped with one shared box (a looping puddle keeps its motion) and centred in a **256 px cell** at one fixed factor (`EFFECT_SCALE` 0.5, so a raw 384 x 512 cell fits). The game rescales each prop to its hazard from the per-clip `content` box.
- **Neck.** The `neck` cell (a straight horizontal neck piece) becomes `hydra_neck.png`: the centre half of the piece followed by its mirror image (the two edges are the same column, so the tile is seamless), cut to the drawn rows, scaled so the tile is 18 px thick on screen and padded with two transparent rows on each side (at the 2x oversampling that is one screen px). `neck.thickness` records the on-screen thickness. The neck cell is not part of the props sheet.
- A cell with no drawn pixels (also after the specks under 150 raw px are removed), or a props cell with none, stops the script with an error naming the sheet and the cell. Unused cells are dropped; clip indices in the manifest are for the compacted sheet, and the frames are looked up by raw cell number. Every texture is built first and written together, the manifest last through a temporary file, so an error never leaves new textures beside an old manifest.

Run (Pillow, numpy and scipy are not in the system Python; use a venv, nothing global):

```
python3 -m venv /tmp/politropia-art-venv && /tmp/politropia-art-venv/bin/pip install pillow numpy scipy
/tmp/politropia-art-venv/bin/python tools/process_hydra_sheets.py --preview <dir>
```

Missing raw sheets are skipped with a message (exit 0, nothing is written when none exists); sheets already processed stay in the manifest. `--raw-dir` and `--out-dir` override the folders. `--preview DIR` writes each body sheet with the feet row and reference lines for Luz (48 px), Artemis (56 px) and the Hydra (152 px), each head sheet with its origin cross and the 56 x 42 px box, the props sheet, and the neck tile repeated six times.

### 2.4 Sheet plan (raw cells in reading order)

| Sheet | Grid | Cells -> clips |
|---|---|---|
| `body` | 3 x 2 (512 x 512) | `idle` 0-3 (loop), `roar` 4-5 (phase change and intro) |
| `defeat` | 3 x 2 (512 x 512) | `defeat` 0-5 (4-5 are the corpse; the severed necks are part of the drawing) |
| `head_biter` | 4 x 2 (384 x 512) | `idle` 0-2 (loop), `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `head_sweeper` | 4 x 2 | same clips |
| `head_spitter` | 4 x 2 | same clips |
| `props` | 4 x 2 | `neck` 0, `stump` 1, `venom_glob` 2, `venom_pool` 3-4 (loop), `venom_splash` 5, `platform` 6, `platform_alt` 7 |

---

## 3. Clip table

The code asks for clips by these names. A clip that is not drawn resolves through the fallbacks (`HydraArt.CLIP_FALLBACKS`) and then to `idle`. Playback speed is derived at play time (`frames / fps / duration`); a clip never decides when a state ends: the state machine ends it and the clip is cut or holds its last frame (one-shot clips hold, `idle` loops).

### 3.1 Body

| Clip | Trigger in code | Duration source | Loop | Fallback |
|---|---|---|---|---|
| `idle` | Everything else | open-ended | loop | none (default) |
| `roar` | `TRANSITION` (a head died: `phase_transition_time`, 1.2 s) and the arena intro (`play_intro`, while `IDLE`) | the transition time or the intro duration | hold | `attack`, then `idle` |
| `defeat` | `DEFEATED`; a restored corpse shows the last frame at once | `defeat_time` (1.2 s) | hold | `idle` |

With the `defeat` clip drawn, the `Heads` node is **hidden from the start of the defeat** (the frames show the severed necks) and the sprite undoes `Visual`'s corpse tilt and squash, as El Topo's does. Without it the stumps and the placeholder corpse show as today.

### 3.2 Heads (per kind)

| Clip | Trigger in code | Duration source | Loop | Fallback |
|---|---|---|---|---|
| `idle` | Resting, retracting, recovering, the spitter between globs of a finished volley | open-ended | loop | none (default) |
| `telegraph` | The TELEGRAPH phase of that head's attack: biter coil, spitter wind-up, sweeper pull-back | the telegraph (0.9 / 0.8 / 0.95 s, shortened by the enrage) | hold | `idle` |
| `attack` | The ACTIVE phase: the biter's lunge, the sweep, the spitter spitting. The spitter restarts it with each glob (`venom_interval`, 0.2 s) | the phase, or 0.2 s per glob | hold | `idle` |
| `dazed` | The biter stuck after the lunge (`bite_stuck_time`, 0.8 s: the punish window) | the stuck time | hold | `idle` (a code-drawn cross then marks the stuck head) |
| `roar` | A phase change (`roar(phase_transition_time)`) | the transition time | hold | `attack`, then `idle` |

Priority per head: a roar overrides everything, then stuck (`dazed`), then the pose of the attack phase, then `idle`. Heads never rotate. A severed head shows no head sprite and no neck: its **stump** shows instead.

Gameplay overlays stay code-driven: the red aim line, the sweep band, the amber venom markers, the stuck cross when `dazed` is not drawn. The hit flash is drawn on each head's own sprite by `shaders/sprite_glow.gdshader` (one `BossSpriteFx` per head); without head art the white polygon flashes as before.

---

## 4. Props and effects

Hazards keep their boxes, speeds and timings. With art each one shows a sprite and its placeholder is not drawn; without the art (or without that clip) the placeholder stays, and the markers are always drawn. Each sprite is scaled from the `content` box of its clip in the manifest to the box that hurts (`BoomboxHazard.art_scale`; a clip with no `content` box falls back to the size of one cell, never to an oversized sprite). `HydraArt` extends `BoomboxEffectArt`.

| Art | Sheet / clip | Where and fit |
|---|---|---|
| Neck | `neck` (texture) | Every living head: a tiled `Line2D` of `neck.thickness` px from the body stump to the head, behind the head sprite and the body. Replaces the drawn line and its round end. |
| Stump | props `stump` | Every severed head: `WIDTH` 38 px, flipped to face left, root inset 8 px into the body stump (drawn behind the body, like the neck), drooping 4 px as the placeholder does. |
| Glob | props `venom_glob` | The flying glob: `CONTAIN` in a 19 px box, on the same arc; the markers stay. |
| Puddle | props `venom_pool`, two-frame loop at 6 fps | The landed puddle: `WIDTH` to the puddle (88 px), standing on its surface; keeps the blink of its last 0.7 s. |
| Splash | props `venom_splash` | A one-shot puff at the landing point, as wide as the puddle (grows, rises, fades, frees itself). |
| Platforms | props `platform`, `platform_alt` | Every platform the boss scans (group `hydra_platform` inside its arena), alternating the two clips in scan order (only `platform` when `platform_alt` is missing): `WIDTH` to the collision rectangle (160 px), the top edge on the collision top. The `Visual` polygon is hidden. The sprite is at z -2, behind the necks (z -1), so a sweeping neck is never hidden by the ledge. A rescan (the fight starts, a reset, the arena resizes) dresses platforms that were moved or added and refits the others without doubling sprites. |

---

## 5. Fallback rule

With no manifest or textures on disk, everything looks and plays exactly as before. A missing sheet or clip keeps its own placeholder without breaking the others (for example heads with art and a body without, or venom art without platform art). The art never changes a collision, a timing or a head position.

## 6. Integration checklist

1. Raw sheets in `tools/art_sources/hydra/raw/`.
2. Run the script, check the previews: the body feet on the line, the 152 px line at the top of the body, every head frame on the same eye position (no jitter), the head inside the green 56 x 42 box except for crests and fangs, the neck strip without a visible seam. `python tools/test_process_hydra_sheets.py` runs the synthetic checks of the script.
3. `godot --headless --path . --import`, then `tests/hydra_boss_test.gd` and `tests/boss_animation_catalog_test.gd`.
4. Look at the real fight (movie maker, `scenes/levels/test/hydra_arena.tscn`, Luz near x 160 so the boss is in view): the necks leave the stumps of the body art and follow its bob, the heads keep their tier colours, `roar` on the phase beats, the defeat frames show the severed necks while the heads are hidden, the puddle blinks before it dries, the platforms look like the old slabs in size and the player stands on their top edge.

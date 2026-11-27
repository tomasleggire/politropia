# Blind Beast art (El Topo)

Locator: `odd/tasks/blind-beast-art.md`. Engram mirror: `odd/blind-beast-art/tasks` (project `politropia`), pending while `mem_save` is refused in this session.
Branch: `feat/new-bosses` (the stacked art branches were merged into it and deleted on 2026-11-16).

## Objective

Give El Topo (`BlindBeastBoss`) final art in the same style as Artemis, Luz and El Profesor, with the same workflow and the generic pieces built for El Profesor (`tools/boss_sheet_pipeline.py`, `BossAnimationCatalog`, `shaders/sprite_glow.gdshader` with `BossSpriteFx`). Gameplay (timings, hitboxes, hazards, noise rules) does not change.

## Decisions

- Design: the blind old man of the library side quest (`assets/world/blind_npc.jpg`) transformed into a giant blind STAR-NOSED MOLE (the star nose feels vibrations), standing upright and hunched like an old man; he keeps the grey hair tuft, the milky blind eyes, torn charcoal jacket, dark red tie and the wooden cane. Prompt: `tools/art_sources/blind_beast/prompts/character_concept.md`.
- Size: about 70 px on screen to the top of the head when standing (Luz 48, Artemis 56, Profesor 92). His eruption column is 56 x 90 px. Same on-screen pixel scale (`sprite_scale` 0.2896 on the processed cell).
- He never walks above ground: burrowed he is a dirt mound (hazard art), exposed he stands in place.
- Per-sheet scale reference: the pink star nose (the boombox trick does not apply); intro frames before the nose appears are excluded through `size_cells`.
- Raw sheets 1536x1024, 4x2 cells of 384x512, except `claw` (3x2 cells of 512x512, the swipe is wide).

## Sheet plan (raw cells, reading order)

| Sheet | Grid | Clips |
|---|---|---|
| `exposed` | 4x2 | `exposed_idle` 0-3 (loop), `dazed` 4-7 (loop) |
| `burrow` | 4x2 | `emerge` 0-3, `dig_in` 4-7 |
| `claw` | 3x2 | `claw_windup` 0-1, `claw_strike` 2-3, `claw_recover` 4-5 |
| `slam` | 4x2 | `slam_windup` 0-1, `slam_strike` 2-3, `phase_change` 4-7 |
| `intro` | 4x2 | `intro` 0-7 (the old man turning into the beast) |
| `defeat` | 4x2 | `defeat` 0-7 (6-7 = corpse) |
| `props` | 4x2 | `mound` 0-3 (loop), `rock` 4, `rock_alt` 5, `crack` 6, `spike` 7 |
| `fx` | 4x2 | `erupt_column` 0-2, `pulse_wave` 3-4, `dust_puff` 5, `rock_impact` 6, `dig_dirt` 7 |

## Delivery

- Strategy: ask-on-risk. Forecast: about 1500 authored lines (contract, pipeline config, integration, hazard art, tests) plus binary art. Chain strategy: pending, asked before any PR.
- TDD: off (source: project convention, `odd/tasks/artemis-polish.md:27`). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd` (one Godot process at a time).

## Tasks

- [x] T1 Concept in the game style (route: inline, two Codex runs by the parent). Commit: the `chore(art)` commit that adds `tools/art_sources/blind_beast/concept/topo_concept_v1.png`. Chosen variant: the cleaner one (suit, shirt collar and tie readable, flatter shapes, reads better at 70 px); the shaggier variant is kept as `topo_concept_v1_alt.png`.
- [x] T2 Contract, processing script, integration with fallbacks, tests (route: delegated writer; trigger: 2+ non-trivial files). Commits `7397f29` (contract, `tools/process_blind_beast_sheets.py`, shared `color_block_size` / `require_box` / `clip_contents` in the pipeline, teacher script TypeError fixed) and `6255adb` (clips in `BlindBeastBoss`, `BlindBeastHazardArt` hooks for mound, cracks, column, spikes, rocks, pulse and puffs, `BoomboxEffectArt.art_size` fallback fix, collision 40x64 at y -32 on the Topo scene, tests). Writer decisions: cell 448, feet row 416, standing 242 px in the cell (70 on screen), nose colour block as the per-sheet reference with `size_cells` (`burrow` 0-4, `intro` 4-7, `defeat` 0-4), thin cane skipped by a 15% row-width rule; `emerge` plays while he stays untargetable; burrowed `Visual` is hidden. Writer verification: Topo `PASS 349/349` (250 + 99), teacher `PASS 412/412`, catalog `PASS 41/41`, `boss_enemy_test` `PASS 178/178`, `boss_test_hub_test` `PASS 213/213`, teacher and Artemis assets unchanged after re-running their scripts, Topo script with no raw sheets exits 0, synthetic sheets run end to end. Parent spot check: Topo `PASS 349/349`, exit 0. Untested on real art: nose colour tolerance and the cane rule.
- [x] T3 Raw sheets (route: inline, eight parallel Codex runs by the parent). Prompts in `tools/art_sources/blind_beast/prompts/sheets.md`. Commit `68d85c7`. Three sheets came back with two images; chosen: `burrow` variant 2 (hind legs and tail readable while digging), `defeat` variant 1 (corpse on its side), `props` variant 1 (larger objects).
- [x] T4 Process the sheets and hazard art: mound, cracks, column, spikes, rocks, pulse, dust (route: delegated writer). Commit `7cee608`. What the real art needed: `burrow` is scaled by body height (`height_cells` 3) because its nose measures 14 to 59 raw px depending on the pose, which replaces the `size_cells` 0-4 noted in T2; `props` and `fx` use a stricter magenta cut (`key_magenta(raw, low, high)`, defaults unchanged) plus `clear_pink_leaks`. The cane rule and the nose tolerance held. Final values: cell 448, feet row 416, 242 px standing (70 on screen), scale per sheet exposed 0.7577, burrow 0.7151, claw 0.6861, slam 0.8628, intro 0.6980, defeat 0.8279.
- [x] T5 Visual check in the real game (route: inline): movie maker capture, video for the user. Commit `34cc8dd` (spawn position, see below). Videos: `~/Downloads/topo_pelea.mp4` (full fight, 96 s) and `~/Downloads/topo_animaciones.mp4` (every clip next to Luz).

## Checks

- `tests/blind_beast_boss_test.gd` stays green (250 before this feature).
- `tests/boss_animation_catalog_test.gd`, `tests/boombox_teacher_boss_test.gd`, `tests/boss_enemy_test.gd`, `tests/boss_test_hub_test.gd` green.
- Artemis and Profesor assets unchanged after re-running their processing scripts.

## Progress and evidence

- 2026-11-16: branch created from `2b5413e`. Old man reference stored. T1: two Codex concept runs launched; both failed with "ERROR: Your workspace is out of credits. Ask your workspace owner to refill in order to continue." No image was generated. Sheet prompts are written (`prompts/sheets.md`). T2 writer launched in the background (it does not need the art).

- 2026-11-16, native review of `2b5413e..6255adb` (assessed high: `process_boundary` on `tools/process_blind_beast_sheets.py`; 16 paths, 1578 lines): consent `granted` (standing user instruction), four lenses, approved, acknowledged (lineage `review-fe8c8b023ff516fe`). Non-blocking follow-ups for T4: spike predicate drift (`blind_beast_boss.gd:1439-1440`, two lenses); sprite sync edge at `blind_beast_boss.gd:1650-1655`; `BlindBeastHazardArt` extends a Profesor-named base (`blind_beast_hazard_art.gd:2`, worth a neutral `BossEffectArt` name); loop fps literals; teacher `clip_contents` shim; Topo script error handling around `tools/process_blind_beast_sheets.py:131-133` and `:254-264`; one test at `tests/blind_beast_boss_test.gd:1366`.

- 2026-11-19: the Codex workspace has credits again. T1: both concept runs produced an image (Codex sessions `01a1f455-038d-7ba1-b336-5f44da28661a`, chosen, and `01a1f455-038d-7053-90c2-2c081cd7b625`, alternative). T3: eight sheet runs launched with the chosen concept.

- 2026-11-19, T4 (writer run plus parent spot check): `blind_beast_boss_test` `PASS 349/349` (re-run by the parent, exit 0), `boss_animation_catalog_test` `PASS 41/41`, `boombox_teacher_boss_test` `PASS 412/412`, `boss_enemy_test` `PASS 178/178`, `boss_test_hub_test` `PASS 213/213`, import with no script errors, Profesor and Artemis assets unchanged after re-running their scripts.
- 2026-11-19, T5 (parent): fight capture with the real art, 640x360. Seen: intro, eruption cycles (mound, column, emerge, dazed, dig in), both phase changes, braille ridges with the stone spikes, debris, chained eruptions, the slam with its pulse wave, defeat and corpse. Clip gallery: the twelve clips keep the feet on the floor and one size (about 70 px, Luz 48). The claw counter did not trigger in the fight capture (the driver keeps Luz invulnerable, so every eruption misses and he is stunned while exposed); its three clips were checked in the gallery only.
- Decision (2026-11-19): the boss instance in `blind_beast_boss_arena.tscn` moved from x 300 to x 0. At x 300 he was outside the 640 px view when Luz enters from the left (the camera cannot go past the arena limit), so the transformation of the old man was never on screen. He starts burrowed and untargetable, so only the distance of his first tunnel changes. `blind_beast_boss_test` `PASS 349/349` and `boss_test_hub_test` `PASS 213/213` after the change.
- 2026-11-19, native review of `6255adb..34cc8dd` (assessed high: `process_boundary` on `tools/process_blind_beast_sheets.py`; 41 paths, 1061 lines): consent `granted` (standing user instruction), four lenses, approved, acknowledged (lineage `review-0d215019b6d7a721`, authority burned). The reviewed boundary is `34cc8dd`. Non-blocking follow-ups, not done: the `height_cells` path has no guard for an empty cell or a zero height (`tools/process_blind_beast_sheets.py:188-189`, three lenses); the reference fallback can be `None` when only `burrow` exists (`:173`); the `clear_pink_leaks` docstring does not match its predicate and it also rewrites warm pixels (`:214-217`); `sizes` mixes nose sizes and body heights (`:190`); `key_magenta` does not check `high > low`; no synthetic test for the three new pipeline behaviours; the `burrow` row sits in a `size_cells` column in `docs/bosses/BLIND_BEAST_ANIMATIONS.md:57`.
- Weak spots in the art itself (writer's note, visible only when zoomed): a pale pink patch beside the top rock of eruption frame 1, a warm tint in the left puff of the rock impact, slight jacket colour differences between sheets (the `claw` sheet is more purple). Regenerating `fx` or `claw` needs Codex credits.

## Next step

Feature complete. Open: the non-blocking follow-ups above, the optional regeneration of `fx` and `claw`, and the user's play session.

# Blind Beast art (El Topo)

Locator: `odd/tasks/blind-beast-art.md`. Engram mirror: `odd/blind-beast-art/tasks` (project `politropia`), pending while `mem_save` is refused in this session.
Branch: `feat/blind-beast-art`, stacked on `feat/boombox-teacher-art` (`2b5413e`, not pushed), which is stacked on `feat/new-bosses`.

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

- [ ] T1 Concept in the game style (route: inline, two Codex runs by the parent).
- [x] T2 Contract, processing script, integration with fallbacks, tests (route: delegated writer; trigger: 2+ non-trivial files). Commits `7397f29` (contract, `tools/process_blind_beast_sheets.py`, shared `color_block_size` / `require_box` / `clip_contents` in the pipeline, teacher script TypeError fixed) and `6255adb` (clips in `BlindBeastBoss`, `BlindBeastHazardArt` hooks for mound, cracks, column, spikes, rocks, pulse and puffs, `BoomboxEffectArt.art_size` fallback fix, collision 40x64 at y -32 on the Topo scene, tests). Writer decisions: cell 448, feet row 416, standing 242 px in the cell (70 on screen), nose colour block as the per-sheet reference with `size_cells` (`burrow` 0-4, `intro` 4-7, `defeat` 0-4), thin cane skipped by a 15% row-width rule; `emerge` plays while he stays untargetable; burrowed `Visual` is hidden. Writer verification: Topo `PASS 349/349` (250 + 99), teacher `PASS 412/412`, catalog `PASS 41/41`, `boss_enemy_test` `PASS 178/178`, `boss_test_hub_test` `PASS 213/213`, teacher and Artemis assets unchanged after re-running their scripts, Topo script with no raw sheets exits 0, synthetic sheets run end to end. Parent spot check: Topo `PASS 349/349`, exit 0. Untested on real art: nose colour tolerance and the cane rule.
- [ ] T3 Raw sheets (route: inline, eight parallel Codex runs by the parent). Prompts in `tools/art_sources/blind_beast/prompts/sheets.md`.
- [ ] T4 Process the sheets and hazard art: mound, cracks, column, spikes, rocks, pulse, dust (route: delegated writer).
- [ ] T5 Visual check in the real game (route: inline): movie maker capture, video for the user.

## Checks

- `tests/blind_beast_boss_test.gd` stays green (250 before this feature).
- `tests/boss_animation_catalog_test.gd`, `tests/boombox_teacher_boss_test.gd`, `tests/boss_enemy_test.gd`, `tests/boss_test_hub_test.gd` green.
- Artemis and Profesor assets unchanged after re-running their processing scripts.

## Progress and evidence

- 2026-11-16: branch created from `2b5413e`. Old man reference stored. T1: two Codex concept runs launched; both failed with "ERROR: Your workspace is out of credits. Ask your workspace owner to refill in order to continue." No image was generated. Sheet prompts are written (`prompts/sheets.md`). T2 writer launched in the background (it does not need the art).

## Next step

Blocked on art: the Codex workspace needs credits (the user's decision). When it is refilled, relaunch the two concept runs with the same prompt, then the eight sheets.

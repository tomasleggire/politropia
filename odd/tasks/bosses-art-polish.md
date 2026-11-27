# Bosses art polish (Artemis, El Profesor, El Topo, La Hidra)

Locator: `odd/tasks/bosses-art-polish.md`. Engram mirror: `odd/bosses-art-polish/tasks` (project `politropia`), pending: `mem_save` is refused in auto mode because a hook rewrites the call.
Branch: `feat/new-bosses` (single branch by user preference).

## Objective

Leave the art of the four bosses as visually polished as possible: finish La Hidra (tracked in `odd/tasks/hydra-art.md`) and fix the visible flaws of the three bosses whose art was considered done (Artemis, El Profesor, El Topo).

## Problem

A visual audit of the processed sheets and of a gallery capture (2026-11-20, read-only agent, evidence in the session scratch folder) found flaws a player can see:

- El Topo changes outfit colour between sheets: `exposed` and `intro` have a dark aubergine-brown jacket, `claw` is clearly purple, `burrow` is olive, `defeat` is grey, `slam` is slightly navy. Measured as Lab offsets per lightness band against `exposed`: `burrow` and `defeat` about (+6, -6) in a/b, `claw` about (-3, +3), `slam` and `intro` up to (+4, -3).
- El Topo `fx`: a pale pink patch with white speckle beside the top rock of `erupt_column` frame 1 (about 12x25 source px) and a warm tint in the left puff of `rock_impact`.
- Artemis spectral stag: `stag_run` frames 1 and 5 (cells 4 and 8) are cut vertically on the left (tail and haunch clipped at x = 0). `tools/process_artemis_sheets.py:205` keeps a historical 256 px clamp for the 384 px stag cell. `stag_run` frame 7 (cell 10) has a detached speck about 20 px from the body.
- All three: semi-transparent silhouette pixels keep a faint pink/purple tint from the #FF00FF key (100 to 380 pixels per frame with hue 280-335). Not a visible halo at game scale; low priority.
- Not checked yet in a fight: hazard art against the damage area, draw order against props, flips, telegraph glow and hit flash.

## Why

Requested by the user on 2026-11-20: "seguí avanzando con todos los estilos que puedas para pulir ese boss. Estos 4, incluida Artemis. Para que visualmente estén lo más pulido posible. Si tenés que volver a retocar otros que ya están considerados terminados, hacelo." At most one agent at a time; when Codex or Claude run out of tokens, wait for the renewal and resume.

## Decisions

- El Topo colours are fixed in processing, not by regenerating sheets: a prototype (banded Lab a/b offsets against the `exposed` sheet, low-chroma pixels only so the tie and the nose keep their colour) made `burrow`, `defeat` and `claw` match `exposed` by eye. No Codex credits needed.
- The 640x360 movie-maker captures understate the art: the project stretches with `canvas_items`, so on a device the boss sprites (scale 0.2896) are drawn near 1:1. Visual checks for this feature use captures at 1920x1080. The audit's "mushy at game scale" notes on Artemis and on the boombox head come from the 640x360 capture and are not treated as defects.
- Not changed, design choices already approved by the user: the cream shirt of El Profesor (it can read as bare skin at small sizes), Artemis's finer outline (it matches Luz's, about 0.5 game px).
- Codex regeneration is reserved for a sheet that neither processing nor code can fix. None identified so far.
- Mipmaps: every sprite import has `mipmaps/generate=false` while the sprites use the mipmap filter. Enabling them would also change Luz and every enemy; out of scope, reported to the user as an option.

## Scope

In: processing scripts and shared pipeline (opt-in changes), processed assets of the four bosses, boss integration code and scenes where a visual defect needs it, contracts in `docs/bosses/`, tests.
Out: gameplay (timings, hitboxes, damage, patterns), boss design changes, Luz and regular enemies, the non-art follow-ups of `odd/tasks/bosses-polish.md`.

## Constraints

- AGENTS.md conventions; no hand-edited `.uid` files; stable node names.
- A boss whose processing did not change keeps byte-identical assets.
- Gameplay does not change; a missing asset still falls back to the placeholders.

## Delivery

- Strategy: ask-on-risk. Forecast: about 400 authored lines plus binary art. Chain strategy: pending, asked before any pull request together with the rest of `feat/new-bosses`.
- TDD: off (source: project convention, `odd/tasks/artemis-polish.md:27`). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd` (one Godot process at a time).
- Receipt-driven development: on by default; consent `granted` by standing user instruction. Last reviewed boundary: `4db8341` (was `b35bfb4` when this document was created). Pending in the slice: `69d40fa` (medium, under budget).

## Tasks

- [x] P1 El Topo: harmonise the colours of every sheet to `exposed`; clean the `fx` pink patch and the warm puff (route: delegated writer; trigger: pipeline, script, docs and tests). Commit `f352b18`.
- [x] P2 Artemis: full stag frames, drop the detached specks that are residue (route: delegated writer, same run as P1). Commit `f352b18`: the clamp was not the only cause, the stretched poses are wider than the cell, so the stag cell is now 512 x 384.
- [x] P3 Edge despill, reusing what La Hidra's T4 added, moved to the shared pipeline as opt-in (route: delegated writer, same run). Commit `f352b18`: applied to the character sheets of El Topo and El Profesor; La Hidra's output is byte-identical; Artemis is left out (her outline is light, so the measured outline colour is wrong and the pink-edge count went up).
- [x] P4 Fight review at 1920x1080 (hazards, draw order, flips, glow and flash) and fixes for what it shows (route: delegated). Commits `508e253` (Artemis hit flash and telegraph glow drawn on her sprite instead of the placeholder polygon box) and `36caaad` (no dirt mound under El Topo while the intro clip shows).
- [x] P5 Codex art for the two attacks that still draw placeholder shapes, found in P4: the pointer thrust of El Profesor (flat red polygon arrow) and the claw of El Topo (red striped rectangle). One new effect sheet per boss, processed and wired like the existing effect clips, placeholder kept as the fallback (route: Codex runs inline, integration by a delegated writer; trigger: scripts, processing, tests and docs). The same writer takes the review follow-ups below. Commits `5380012` (raw sheets and prompts), `96e4583` (follow-ups of the first review), `db97b15` (El Profesor thrust streak), `89adeed` (El Topo claw swipe) and `60022a9` (follow-ups of the second review, by a second delegated writer).
- [x] P6 Final captures for the user (route: inline). Files listed under Progress; recorded by the commit of this document.

Second round, asked by the user on 2026-11-20 ("fijate si quedan toques ... y seguí con eso"), from stills of the 1920x1080 captures (route for P7-P10: one delegated writer; trigger: shared boss script, three boss scripts, processing, tests and docs):

- [x] P7 Dazed look: with drawn art the stun no longer multiplies the body by `STUN_TINT` at full strength (El Topo turns lion-gold, El Profesor gets a yellow shirt and a gold boombox); the boss keeps his own colours with a light warm tint. Placeholders keep the full tint. Commit `ea1a0f7`.
- [x] P8 Corpse: with drawn art the corpse is dimmed less than `CORPSE_TINT` (0.32), so the drawn corpse of El Topo, El Profesor and La Hidra reads. Regular enemies and placeholders are unchanged. Artemis is left as she is (her corpse is replaced by the ending screen and her test pins the tint). Commit `ea1a0f7` (same unit as P7: both tints live in the boss base and its tests).
- [x] P9 El Topo intro: the old man is visible for one frame (about 0.1 s of the 0.8 s reveal). Hold the human frames longer inside the same duration; the arena's `engage_delay` does not change. Commit `0fad118`: the clip lists cells 0 and 1 more than once (12 entries over the same 8 cells).
- [x] P10 Claw remnant frame: remove the faint pink dots the raw art left near the dust (processing only). Commit `78b8ec0`.
- [x] P11 Captures of the changed states and updated videos (route: inline). Files listed under Progress; recorded by the commit of this document.

## Acceptance criteria

- El Topo keeps the same jacket and fur colours in every clip, judged side by side and in a fight capture.
- No stag frame is cut by a cell edge; no pink patch in the Topo eruption.
- Boss suites green: `boss_enemy_test`, `boombox_teacher_boss_test`, `blind_beast_boss_test`, `hydra_boss_test`, `boss_animation_catalog_test`, `boss_test_hub_test`, plus the Artemis suite; import with no script errors.

## Checks

The suites above; `--import`; each processing script run twice gives identical output; side-by-side strips and 1920x1080 captures looked at by eye.

## Progress and evidence

- 2026-11-20: Codex has credits again. Audit of Artemis, El Profesor and El Topo done (read-only agent, numeric checks plus contact sheets plus one gallery capture per boss). Findings above. Measured as fine: standing scale per clip, feet row (416/417 for Topo and Profesor, 224/225 for Artemis), no clipped limbs on Artemis beyond the bow tip, at least 27 px of margin around Topo and Profesor content (the 7-texel glow sampling does not reach a neighbouring cell).
- 2026-11-20: Topo colour prototype run outside the repository; the before/after strip confirms the processing route.

- 2026-11-20: P1-P4 done by one writer (commits `f352b18`, `508e253`, `36caaad`; P1-P3 share `tools/boss_sheet_pipeline.py`, so they close in one commit).
  - Looked at by the parent: the Topo colour strip (same jacket and fur in every clip, on light and dark), the stag cells before and after (whole, with margin), the eruption patch zoom, the despill zoom, and stills of the three fights at 1920x1080.
  - Checks (writer, before -> after): `--import` clean; `blind_beast_boss_test` 349 -> 349; `boombox_teacher_boss_test` 412 -> 412; `hydra_boss_test` 321 -> 321; `boss_animation_catalog_test` 41 -> 41; `boss_enemy_test` 178 -> 178; `boss_test_hub_test` 213 -> 213; `tools/test_process_hydra_sheets.py` 10 OK; new `tools/test_process_boss_sheets.py` 13 OK; every processing script run twice gives identical output equal to the committed files.
  - Parent spot check: both Python suites OK, `blind_beast_boss_test` PASS, `boombox_teacher_boss_test` PASS 412/412, ritual runner with the same 13 failing cases as the base.
  - Added by the parent: `case_flash_and_glow_on_the_sprite` in `tests/artemis_boss_test.gd` (7 checks, pass), one mound check in `tests/blind_beast_boss_test.gd` (PASS 350/350), and the flash and glow rows of `docs/bosses/ARTEMIS_ANIMATIONS.md`.
  - Known base failures, unchanged: the Artemis suite runs through `tests/stillness_desk_ritual_test.gd`, which reports `FAIL incomplete run` (now 476 of 726 checks, 469 of 719 before the new case) with 13 failing cases, the same list as on the base; `tests/artemis_room_test.gd` does not parse (removed `DoorID` names).
- 2026-11-20: native review of `9ca45d3..36caaad`: assessed high (`tools/process_artemis_sheets.py` starts other processes), consent `granted`, four lenses, approved and acknowledged (lineage `review-d512c44ce38eb476`). 13 advisory findings, none blocking. Taken as follow-ups in P5: a check that the mound is back once the fight starts (`blind_beast_boss.gd:1370`), a despill test that can fail (`tools/test_process_boss_sheets.py:107`), the docstring test renamed or dropped (`tools/test_process_boss_sheets.py:161`), a guard for a sheet with no solid pixels in `estimate_outline` (`tools/boss_sheet_pipeline.py:88`). Left as they are: the suggestions about duplicated constants and names.
- P4 findings left for the user, not changed: the shared stun tint (`STUN_TINT`, a multiply) turns El Topo lion-gold and El Profesor yellow while dazed; El Topo's intro clip lasts about 0.8 s, so the old man shows for about 0.15 s; the test arena shows grey beyond the room after a defeat (test backdrop, not a boss defect).
- 2026-11-20: P5 done. Codex gave both effect sheets on the first run (two images, 2 x 2 cells of 768 x 512, four frames of one effect each). One writer integrated them and took the follow-ups of the first review.
  - El Profesor: `thrust_fx` sheet, one row of 400 x 80 cells; the thrust hazard wears the `thrust_streak` clip (`WIDTH` fit, mirrored with his facing, played once over `thrust_strike_time`); the red arrow stays as the fallback.
  - El Topo: `claw_fx` sheet, one row of 400 x 208 cells; frame 0 pulses over the translucent zone fill while he telegraphs, frames 1 and 2 run across `claw_active_time`, frame 3 lingers 0.25 s as a cosmetic one-shot; the striped rectangle stays as the fallback.
  - Shared pipeline: optional `cell_height` for non-square cells and `effect_clip_sheet` (errors under 8 px of margin).
  - Looked at by the parent: the thrust and claw contact sheets at 1920x1080 (boss on either side, high and low thrust), and strips of both fight captures.
  - Checks (writer, before -> after): `--import` clean; `blind_beast_boss_test` 350 -> 384; `boombox_teacher_boss_test` 412 -> 428; `boss_animation_catalog_test` 41 -> 41; `boss_enemy_test` 178 -> 178; `boss_test_hub_test` 213 -> 213; `hydra_boss_test` 321 -> 321; `tools/test_process_boss_sheets.py` 13 -> 18 OK; `tools/test_process_hydra_sheets.py` 10 OK; each processing script run twice gives identical output and every earlier sheet is byte-identical.
  - Parent spot check on the committed tree (`89adeed`): both Python suites OK, `blind_beast_boss_test` PASS 384/384, `boombox_teacher_boss_test` PASS 428/428, `boss_animation_catalog_test` PASS 41/41, `boss_enemy_test` PASS 178/178.
  - Not rerun for P5: the Artemis suite (no Artemis file changed).
  - Cosmetic leftovers, not changed: thrust frame 0 is a couple of px taller than its box (the speed lines); claw frame 3 keeps a few faint pinkish dots from the raw art; the claw warning is carried mostly by the zone fill because the scratch lines are thin.
- 2026-11-20: native review of `36caaad..89adeed`: assessed high (`tools/process_blind_beast_sheets.py` starts other processes), consent `granted`, four lenses, approved and acknowledged (lineage `review-a41b6a0ef35efd93`). 11 advisory findings, none blocking. Taken in `60022a9`: the thrust late-frame check no longer waits on wall-clock time, the claw tint and strike frames are checked at controlled phases, the catalog proves a non-square grid and the two shipped ones, `linger` checks its parent first, one constant for the claw warning pulse, the `play_over` comment. Left as they are: the preview branch duplicated in both processing scripts, the `out_cell` name for non-square cells and the alpha literal of the margin check, the unguarded empty or blank inputs of `effect_clip_sheet`.
  - Checks for `60022a9` (writer, three runs each): `blind_beast_boss_test` PASS 390/390, `boombox_teacher_boss_test` PASS 428/428; once: `boss_animation_catalog_test` PASS 48/48, `boss_enemy_test` PASS 178/178. Parent spot check: the first three, same results.
  - Assessment of `60022a9`: medium, `under_budget` (100 lines), so it stays pending in the slice.
- 2026-11-20: P6 done. Captures at 1920x1080 in `~/Downloads`: `hidra_pelea.mp4`, `artemis_pelea.mp4`, `profesor_pelea.mp4`, `topo_pelea.mp4`, plus slow-motion close-ups of the two new effects, `profesor_estocada.mp4` and `topo_zarpazo.mp4`. The fight captures of El Profesor and El Topo predate `60022a9`, which changes nothing on screen.
- 2026-11-20: second round (P7-P10) done by one writer; task list committed first in `4db8341`.
  - P7: `STUN_ART_STRENGTH` 0.25 through a `has_art()` hook in the boss base; El Topo and El Profesor keep their colours while dazed. La Hidra shares the code path but nothing stuns her in the game.
  - P8: `ART_CORPSE_TINT` (0.62, 0.62, 0.68, 1.0) for bosses with art, also on La Hidra's `Heads` root; squash, tilt and z-index unchanged.
  - P9: intro clip `0,0,0,0,1,1,2,3,4,5,6,7`; the catalog adds one frame per entry and the boss stretches the clip to the reveal from its frame count, so the total stays 0.8 s. The intro sheet is byte-identical.
  - P10: `clear_claw_pink_specks` removes small separate pieces that are mostly pink (the floating pebble of frame 3, 101 px); attached pinkish rims stay on purpose.
  - Looked at by the parent, before and after at 1920x1080: El Topo and El Profesor dazed, the three corpses, the intro strip (one still every 0.1 s: the old man now shows for about 0.3 s and the mole is formed at the same time as before), the zoom of claw frame 3. The parent recorded La Hidra's fight for her corpse, which the writer could not capture.
  - Checks (writer, before -> after): `--import` clean; `blind_beast_boss_test` 390 -> 395; `boombox_teacher_boss_test` 428 -> 433; `boss_enemy_test` 178 -> 182; `hydra_boss_test` 321 -> 323; `boss_animation_catalog_test` 48 -> 48; `boss_test_hub_test` 213 -> 213; `tools/test_process_boss_sheets.py` 18 -> 26 OK; `tools/test_process_hydra_sheets.py` 10 OK; El Topo processing run twice identical, every sheet but the claw one byte-identical.
  - Parent spot check: `boss_enemy_test` PASS 182/182, `blind_beast_boss_test` PASS 395/395, `boombox_teacher_boss_test` PASS 433/433, `hydra_boss_test` PASS 323/323, `boss_animation_catalog_test` PASS 48/48, both Python suites OK. Not rerun by the parent: `boss_test_hub_test`. Not run: the Artemis suite (no Artemis file changed).
- 2026-11-20: native review of `89adeed..4db8341` (it also covers `60022a9`): assessed high (`tools/process_blind_beast_sheets.py` starts other processes), consent `granted`, four lenses, approved and acknowledged (lineage `review-3a14a264bc69753f`). 10 advisory findings, none blocking. Taken in `69d40fa` (inline, two mechanical test edits): the catalog proves the shipped intro builds twelve entries over eight cells, and the corpse test restores `art_on`. Left as they are: no live observation of the claw strike frames during ACTIVE (the mapping is checked at controlled values instead), the boundaries of the speck rule, a literal for the halo width, a frame-count literal in one test.
  - Checks for `69d40fa`: `boss_animation_catalog_test` PASS 51/51, `boss_enemy_test` PASS 182/182. Assessment: medium, `under_budget` (22 lines), pending in the slice.
- 2026-11-20: P11 done. Updated in `~/Downloads`: `profesor_pelea.mp4`, `topo_pelea.mp4`, `hidra_pelea.mp4` (1920x1080, recorded after the second round), and the before/after stills in `jefes_antes_despues/`. `topo_zarpazo.mp4` predates P10 (it still shows the pebble).

## Next step

All tasks of both rounds are done. Earlier text of this section, kept for the record: all tasks of the first round are done. Open for the user: the P4 findings listed above (stun tint, El Topo intro length) and the push and pull request of `feat/new-bosses` (chain strategy to be asked first).

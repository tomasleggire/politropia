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
- Receipt-driven development: on by default; consent `granted` by standing user instruction. Last reviewed boundary: `36caaad` (was `b35bfb4` when this document was created).

## Tasks

- [x] P1 El Topo: harmonise the colours of every sheet to `exposed`; clean the `fx` pink patch and the warm puff (route: delegated writer; trigger: pipeline, script, docs and tests). Commit `f352b18`.
- [x] P2 Artemis: full stag frames, drop the detached specks that are residue (route: delegated writer, same run as P1). Commit `f352b18`: the clamp was not the only cause, the stretched poses are wider than the cell, so the stag cell is now 512 x 384.
- [x] P3 Edge despill, reusing what La Hidra's T4 added, moved to the shared pipeline as opt-in (route: delegated writer, same run). Commit `f352b18`: applied to the character sheets of El Topo and El Profesor; La Hidra's output is byte-identical; Artemis is left out (her outline is light, so the measured outline colour is wrong and the pink-edge count went up).
- [x] P4 Fight review at 1920x1080 (hazards, draw order, flips, glow and flash) and fixes for what it shows (route: delegated). Commits `508e253` (Artemis hit flash and telegraph glow drawn on her sprite instead of the placeholder polygon box) and `36caaad` (no dirt mound under El Topo while the intro clip shows).
- [ ] P5 Codex art for the two attacks that still draw placeholder shapes, found in P4: the pointer thrust of El Profesor (flat red polygon arrow) and the claw of El Topo (red striped rectangle). One new effect sheet per boss, processed and wired like the existing effect clips, placeholder kept as the fallback (route: Codex runs inline, integration by a delegated writer; trigger: scripts, processing, tests and docs). The same writer takes the review follow-ups below.
- [ ] P6 Final captures for the user (route: inline).

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

## Next step

P5: generate the two effect sheets with Codex, then one writer integrates them and takes the review follow-ups; then P6.

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
- Receipt-driven development: on by default; consent `granted` by standing user instruction. Last reviewed boundary when this document was created: `b35bfb4`.

## Tasks

- [ ] P1 El Topo: harmonise the colours of every sheet to `exposed`; clean the `fx` pink patch and the warm puff (route: delegated writer; trigger: pipeline, script, docs and tests).
- [ ] P2 Artemis: full stag frames (no 256 px clamp on the 384 px cell), drop the detached specks that are residue (route: delegated writer, same run as P1).
- [ ] P3 Edge despill for the three bosses, reusing what La Hidra's T4 adds to the shared pipeline as opt-in (route: delegated writer, same run).
- [ ] P4 Fight review of the four bosses at 1920x1080 (hazards, draw order, flips, glow and flash) and fixes for what it shows (route: delegated).
- [ ] P5 Codex regeneration, only if P1-P4 leave a flaw that processing or code cannot fix (route: inline).
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

## Next step

Wait for La Hidra's T4 writer, then run P1-P3 with one writer, then P4.

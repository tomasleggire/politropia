# Boombox Teacher art (El Profesor)

Locator: `odd/tasks/boombox-teacher-art.md`. Engram mirror: `odd/boombox-teacher-art/tasks` (project `politropia`).
Branch: `feat/boombox-teacher-art`, stacked on `feat/new-bosses` (pushed, not merged).

## Objective

Give El Profesor (`BoomboxTeacherBoss`) final art in the same style as Artemis and Luz, made the same way Artemis was made: Codex image generation from saved prompts, raw magenta sheets, a processing script, a manifest and a catalog that builds `SpriteFrames`. Gameplay (timings, hitboxes, hazards) does not change. The other two bosses (El Topo, La Hidra) come after this one and should reuse the pipeline.

## Why

The three new bosses are playable but drawn with placeholder polygons. The user playtested the fights and approved them; the next step is that they look like Artemis.

## Decisions

- Workflow: same as Artemis (confirmed in `tools/art_sources/artemis/prompts/*.md`: `codex exec` with the built-in image generation tool, PNGs taken from `~/.codex/generated_images/<session>/`, processed by a script into `assets/enemies/<boss>/`). Codex runs from a scratch directory, never from the repository.
- Design source: the team's design sheet and two poses the user shared, stored in `tools/art_sources/boombox_teacher/concept/design_*`. The regular library teacher enemy (`assets/enemies/teacher-*.png`) is the same character.
- Style: Luz and Artemis rendering (thick dark outline `#1A1410`, cel shading 2-3 steps, flat shapes), but the teacher keeps his TALL lanky build (user: "tiene que ser alto").
- Size: about 92 px on screen to the top of the boombox (Luz 48, Artemis 56, regular teacher enemies about 85). Same on-screen pixel scale as Artemis (`sprite_scale` 0.2896 on a processed cell, i.e. 0.1448 per Luz-source pixel).
- Raw sheets are 1536x1024 with 4x2 grids of 384x512 cells (instead of Artemis's 4x3), so each figure is drawn larger; `thrust` uses 3x2 cells of 512x512 because the lunge is wide. Every character sheet asks for the same standing height, about 360 raw px (sole to boombox top). That is about 3.9 raw px per screen pixel against Artemis's 7, so his drawn detail is somewhat coarser; accepted to keep eight frames per run.
- A generic `BossAnimationCatalog` is added for the teacher and the next two bosses; Artemis keeps her own catalog untouched.

## Sheet plan (raw cells, reading order)

Source of truth: `tools/art_sources/boombox_teacher/prompts/sheets.md`.

| Sheet | Grid | Clips |
|---|---|---|
| `loco` | 4x2 | `idle` 0-3, `walk` 4-7 |
| `thrust` | 3x2 | `thrust_high_windup` 0, `thrust_high_strike` 1, `thrust_high_recover` 2, `thrust_low_windup` 3, `thrust_low_strike` 4, `thrust_low_recover` 5 |
| `throw` | 4x2 | `throw_windup` 0-1, `throw_release` 2, `throw_wait` 3, `throw_catch` 4, `kick_windup` 5, `kick_strike` 6, `kick_recover` 7 |
| `conduct` | 4x2 | `conduct` 0-3 (waves), `lecture` 4-5 (dictation), `notes` 6-7 |
| `bass` | 4x2 | `bass_lift` 0-1, `bass_slam` 2-3, `overheat` 4-7 |
| `trans` | 4x2 | `phase_change` 0-3, `intro` 4-7 |
| `defeat` | 4x2 | `defeat` 0-7 (6-7 = corpse) |
| `props` | 4x2 | `briefcase_spin` 0-3, `note` 4, `note_pair` 5, `steam` 6, `spark` 7 |

## Delivery

- Strategy: ask-on-risk. Forecast: about 1500 authored lines (pipeline, catalog, integration, tests, docs) plus binary art. Chain strategy: pending, asked before any PR.
- TDD: off (source: project convention, `odd/tasks/artemis-polish.md:27`). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd` (one Godot process at a time).

## Tasks

- [x] T1 Concept in the game style (route: inline, Codex runs by the parent). Prompt `tools/art_sources/boombox_teacher/prompts/character_concept.md`, two variants, pick one. Chosen: variant b, `concept/teacher_concept_v1.png` (closest to the team's design: rolled sleeves, black gloves and briefcase, thick outline; Codex corrected its own first take, which had a duplicated head in the lift pose). Variant a kept as `teacher_concept_v1_alt.png` (gloves leave bare wrists, legs exaggerated).
- [ ] T2 Animation contract, generic pipeline and catalog, integration with fallbacks (route: delegated writer; trigger: 2+ non-trivial files). `docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md`, shared sheet helpers in Python with Artemis output unchanged, `tools/process_boombox_teacher_sheets.py`, `BossAnimationCatalog`, clips played by `BoomboxTeacherBoss`, placeholder polygons kept as fallback, tests.
- [x] T3 Raw sheets (route: inline, eight parallel Codex runs by the parent). Prompts in `tools/art_sources/boombox_teacher/prompts/sheets.md`, raw PNGs in `tools/art_sources/boombox_teacher/raw/`. All eight sheets came back on the first run with the requested grid and poses; each was checked by eye. Known flaws to absorb in processing: Codex draws each sheet at a different scale (standing height about 445 px in `loco`, 410 in `trans`, 390 in `conduct`, 370 in `throw`), so T4 needs a per-sheet scale referenced on the boombox head (writer informed); `bass` cell 2 has a small pink spark mark (drop tiny components); in `thrust` the pointer and briefcase swap hands between wind-up and strike; in `props` the briefcase spin shows front, edge, back, edge (reads as a tumbling flip).
- [ ] T4 Process the sheets into `assets/enemies/boombox_teacher/` and tune the manifest (route: delegated writer). Previews checked by the parent.
- [ ] T5 Props in the hazards: briefcase, notes, steam, sparks (route: delegated writer).
- [ ] T6 Visual check in the real game (route: inline): frames captured from the test arena, then a build on the user's iPhone if they ask for it.

## Checks

- `tests/boombox_teacher_boss_test.gd` stays green (286 before this feature).
- New catalog and integration tests.
- Artemis: `assets/enemies/artemis/` byte-identical after re-running her processing script; Artemis suites unchanged.
- `tests/boss_enemy_test.gd`, `tests/boss_test_hub_test.gd` green.

## Progress and evidence

- 2026-11-16: branch created from `d0f7244`. Design references stored. T1: two Codex concept runs, variant b chosen. T2 writer launched (background). T3: sheet prompts written, eight Codex runs launched in parallel.
- Engram mirror: pending. `mem_save` is refused in this session ("a hook changed this call's input after auto mode reviewed it"); the repository file is the source of truth.

## Next step

Collect the eight raw sheets (T3), check each one, rerun any sheet that breaks the grid or the design, then process them (T4) once T2 lands.

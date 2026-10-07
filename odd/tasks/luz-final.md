# Luz final

## Objective
Definitive version of Luz: movement, animation, VFX and combat that look and feel like the Penitent One in Blasphemous, at the team size of 32x48, as a drag-and-drop scene teammates can place without touching code.

## Problem
Luz runs ~2x faster than the Penitent relative to her height, has no turn, skid or stop poses, no ground dust, a 4-frame run cycle and HD art downscaled to 58 px that the team describes as "not fluid, low resolution". The pogo down attack is no longer wanted.

## Why
Final university project; the quality bar is Blasphemous: careful art, fluid animation, weight, cohesion with the scenery.

## Scope
- In: Luz locomotion, size, ground VFX, jump, dash, combat (without pogo), per-animation art spec for Codex, reusable scenes.
- Out: level layout, enemies (only re-validated against the new Luz), camera unification (see `odd/tasks/camera-framing.md`).

## Constraints
- Reference videos on the user's Desktop: `Caminar.mov`, `Salto.mov`, `Dash.mov`, `Ataque.mov`, `Atacar enemigos y morir.mov` (60 fps). One video at a time.
- Team standard: 16x16 tiles, Luz 32x48, player collision width 29 px, 640x360 base resolution (now applied: `project.godot` 640x360, UI halved, `RoomCamera.view_zoom` 0.9).
- Everything must be a reusable scene configured through exported inspector properties.
- All new art and animation is produced with Codex; Claude does no art. Reuse existing assets where viable.
- Changing movement numbers can break traversal in existing levels; re-validate gaps and heights.

## TDD
Mode: off (configuration; TDD is not enforced). GDScript regression suites exist under `tests/` (run headless with `--script res://tests/<name>.gd`, see `tests/README.md`) and are run as functional checks. Other checks: Godot 4.7.2 headless boot (`--headless --path . --quit-after 120`), iPhone deploy and playtest, user feel review.

## Reference spec: Caminar.mov
Ruler: Penitent body without the hat spike = Luz 48 px.
- Run: ~2.7 body heights/s, ~130 px/s. No start animation; full speed within <=5 frames.
- Turn from idle or reversal: 3-4 frame crouch pose with no translation, then run.
- Stop: snap to a wide low skid pose, brake over 6-8 frames (~0.12 s), slide ~8-14 px, hold ~10 frames, then relax.
- Run cycle ~17-18 frames, 8-9 poses (~30 fps animation). Idle nearly static.
- Dust: opaque off-white, static in the world, shrinks in 6-frame steps with no alpha fade. Footstep puff every cycle (small), turn puff (~8 frames), stop skid (largest, ~18 frames, trailing lines behind the feet).

## Tasks
- [x] M1 Ground locomotion: Blasphemous run speed and brake, turn crouch and skid stop states (placeholder clips from existing art), Luz at 32x48 (sprite scale, collider width 29, wall and ledge probes). Route: delegated direct (player.gd ~2300 lines; preparation trigger). Checks: headless boot, iPhone feel. Done 2026-10-06: route delegated direct (trigger: preparation/writer on player.gd ~2300 lines); headless boot clean, `--check-only` clean for player.gd and luz_animation_catalog.gd, `git diff --check` clean, regression suites pass (stillness 259/259, combat 87/87, pogo 44/44, room_transition, soul_focus 52/52, enemy 62/62, greece_layout, double_jump 30/30 after retiming one ledge-walk wait for the slower run); run speed 150 px/s (spec corrected), air_max_speed 250 kept separate; commit `feat: ajustar la locomoción de Luz al estilo Blasphemous y escalarla a 32x48`; iPhone feel check pending (parent).
- [x] M2 Ground dust VFX as a reusable scene (footstep, turn, stop) driven by Luz states. Route: delegated direct, same writer as M1. Checks: headless boot, iPhone visual. Done 2026-10-06: route delegated direct (same writer as M1); headless boot clean, `--check-only` clean for player.gd and ground_dust.gd, `git diff --check` clean, new `tests/locomotion_test.gd` PASS 10/10 plus every existing suite passing (stillness 259/259, enemy_archetypes 111/111, combat, pogo, double_jump, room_transition, soul_focus, enemy, greece_layout); commit `feat: agregar polvo de suelo reutilizable para Luz`; iPhone visual check pending (parent).
  - Review follow-ups (M1/M2, non-blocking findings from the approved reliability review, 2026-10-06): R3-001 `_spawn_dust` uses a Node2D host (parent, else current scene), sets `global_position` after `add_child`, and skips with one `push_warning` when the scene is null or its root is not a GroundDust; R3-002 `_fill_placeholder_clips` creates missing `turn`/`skid` animations and checks the source `crouch` frames; R3-005 `skid_hold_time` (0.17 s) is now measured after the 0.14 s brake; R3-003/R3-004 `tests/locomotion_test.gd` bounds the slide (9-16 px), exercises the min-run-time filter and covers turn dust, skid cancel, jump out of SKID/TURN and ledge loss to FALL (26/26). Commit: `fix: robustecer el polvo y los clips provisorios de Luz y ampliar las pruebas de locomoción`.
- [ ] M3 Jump from `Salto.mov`. Route: analysis delegated, then writer. Checks: as M1, plus level traversal re-validation.
- [ ] M4 Dash from `Dash.mov`. Route: as M3.
- [ ] M5 Codex art in the CURRENT Luz style (same pipeline and ~6-7 texture px per world unit as the existing sheets and the Stillness Desk; dark outline, cel shading): run cycle with 8 poses, turn (4) and skid (6) clips replacing the crouch placeholders via the manifest. Check on the iPhone.
  - [x] M5a Codex request written from `Caminar.mov`: `tools/art_sources/luz/prompts/run_turn_skid.md` (pose refs in the gitignored `tools/art_sources/luz/refs/penitent_*_ref.png`). Decisions 2026-10-07: 8 run poses at 28 fps, no skid-relax clip, `turn_time` tuned on the iPhone (measurements disagree: 0.06 vs 0.1 s), rim light by shader instead of Codex art. Route: delegated analysis, inline file.
  - [ ] M5b User runs the two Codex prompts; raw sheets land in `tools/art_sources/luz/raw/`.
  - [ ] M5c Integrate: new processor cloned from `tools/process_luz_rest_ritual.py`, manifest entries, drop the old 4-frame `run`, `CLIP_SPEEDS["walk"]` 28 (see section 4 of the request).
- [ ] M7 Rim light shader on every Luz animation (lighter cool band on the top/back silhouette edge so the navy body reads on dark backgrounds), tunable from the inspector (color, width, direction, strength). Replaces drawing the rim with Codex, so all clips stay consistent. Checks: `--check-only`, headless boot, suites, iPhone look on dark library and bright Greece backgrounds.
- [ ] M6 Refine ground dust to match the Luz art scale (today 1 world-unit pixels look chunkier than Luz).
- [ ] C1 Remove the pogo down attack; air attack only horizontal.
- [ ] C2 Ground and air combat from `Ataque.mov` and `Atacar enemigos y morir.mov`.

## Acceptance criteria
- Luz occupies 32x48 and moves with the measured Blasphemous numbers; user confirms the feel on the iPhone.
- Luz scene and VFX scenes are drag-and-drop with grouped exports.
- Existing levels remain traversable.

## Progress
- 2026-10-06: branch `feat/luz-final` from `feat/camera-framing` after merging origin/main 265fbb4 (merge adf18a4). Caminar.mov analyzed.
- 2026-10-06: M1 implemented (run 150 px/s, turn and skid states with placeholder crouch clips, Luz 48 px tall, collider 29x46, probes and hitboxes scaled by 48/58). Pending: iPhone feel check (parent).
- 2026-10-06: M2 implemented (`scenes/vfx/ground_dust.tscn`, `scripts/vfx/ground_dust.gd`: footstep, turn and stop kinds spawned in world space by Luz; scene swappable via `ground_dust_scene`). Pending: iPhone visual check (parent).
- 2026-10-07: resolution aligned to the team standard (640x360, cb81aff); stretch mode `canvas_items` (650b233) after the user found Luz pixelated under `viewport`; user confirmed the iPhone look. Art direction decided: keep the current illustrated pixel-styled look (no true pixel-art conversion, time constraints); figure-ground rules: outline on interactive things, amber = interactable, red = danger, backgrounds less saturated than gameplay, grayscale test. Salto.mov and Dash.mov measured (Engram `luz/blasphemous-jump-spec`, `luz/blasphemous-dash-spec`; body ruler ~148 video px = 48 units). iPhone feel check of M1/M2 still pending from the user.
- 2026-10-07: user accepted M1/M2 feel and dust on the iPhone. Size check: Blasphemous art pixel = 3.0 video px, Penitent body ~48-50 game px (Luz `body_height` 48); in the teammates' map (`scenes/levels/greece/level_greece.tscn`) the active camera is the player `Camera2D` at zoom 1.0, so Luz matches the Penitent on screen; user confirmed on the iPhone. `RoomCamera.view_zoom` 0.9 only affects `greece_level.tscn`; whichever camera wins camera-framing T2 must keep zoom 1.0. Jump retune accepted; levels will be adjusted later with the team.

## Delivery
Strategy: ask-on-risk. Forecast exceeds ~400 authored lines across tasks; ask for chain strategy before the slice that crosses it.

## Next step
M7 rim light shader (Claude) while the user runs the M5 Codex prompts; then M5c integration and iPhone check. Later M3 jump, M4 dash, M6 dust, C1 remove pogo, C2 combat.

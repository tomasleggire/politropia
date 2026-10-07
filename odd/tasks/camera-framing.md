# Camera framing

## Objective
Restore a comfortable view of the world on the iPhone and end up with a single camera system.

## Problem
Commit 65c6b11 ("camara corregida", 2026-10-03) halved the base resolution from 1280x720 to 640x360 and added a player Camera2D (`scripts/camera/camara_jugador.gd`, limits from `camara_region.gd` areas). `greece_level.tscn` (the main scene) still uses `RoomCamera` (`room_camera.gd`, `view_zoom` 1.8), which was tuned at 1280x720. Result: the visible world is a quarter of what it was and two cameras compete.

## Why
Visible world = base resolution / camera zoom. 640 / 1.8 ~ 355 px wide versus 1280 / 1.8 ~ 711 px before. The HUD and touch controls also doubled in size.

## Scope
- In: base resolution, choice of a single camera, zoom tuning.
- Out: level layout, art, combat.

## Constraints
- Teammates' greybox scenes (`scenes/levels/greece/`, `scenes/levels/library/`) were framed at 640x360 with the player camera; unifying cameras needs a team decision.

## TDD
Off by configuration. GDScript regression suites exist under `tests/` (see `tests/README.md`) and run as functional checks, plus headless boot and iPhone playtest.

## Tasks
- [ ] T1 (reopened 2026-10-06) Align the base resolution with the team standard 640x360 (team normalization doc: 640x360, 16x16 tiles, Luz 32x48). Reason: the zoom problem came from `RoomCamera` zoom 1.8, not from the resolution; 1280x720 diverged from the team. Values: `project.godot` 640x360; `RoomCamera.view_zoom` 1.8 -> 0.9 (640 / 0.9 ~ 711 world px, same framing as before); touch controls, pad and button visuals, health HUD, pips and soul meter halved (fixed pixel values, no CanvasLayer scale; line widths kept >= 1 px); `tests/health_hud_test.gd` SAFE_AREA Rect2(30,20,550,300). Checks: headless boot, `--check-only`, all suites under `tests/`, `git diff --check`; iPhone playtest pending. History: first closed 2026-10-05 at 1280x720 (commit `fix: restaurar resolución base a 1280x720`).
- [ ] T2 Choose one camera (`RoomCamera` or `camara_jugador` + `camara_region`) and remove the other. Blocked on team decision.
- [ ] T3 Tune the zoom of the single camera to the agreed visible world width; iPhone playtest.

## Acceptance criteria
- One active camera in every level.
- Agreed visible world width on the iPhone; HUD and touch controls at their intended size.

## Progress
- 2026-10-05: branch `feat/camera-framing` from main 14465dd. T1 change applied and deployed to the iPhone.

- 2026-10-06: T1 reopened and applied on `feat/luz-final`: 640x360 with halved UI and `view_zoom` 0.9. iPhone playtest pending.

## Next step
Decide T2 with the team.

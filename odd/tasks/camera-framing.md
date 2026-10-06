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
Off: no GDScript test runner is configured. Checks are headless Godot export plus iPhone playtest.

## Tasks
- [x] T1 Restore base resolution to 1280x720 in `project.godot`. Route: inline (one mechanical line pair). Check: iOS export, Xcode build, install and launch on iPhone (done 2026-10-05); user confirmed framing, HUD and buttons look right on the iPhone. Commit: see git log for `fix: restaurar resolución base a 1280x720`.
- [ ] T2 Choose one camera (`RoomCamera` or `camara_jugador` + `camara_region`) and remove the other. Blocked on team decision.
- [ ] T3 Tune the zoom of the single camera to the agreed visible world width; iPhone playtest.

## Acceptance criteria
- One active camera in every level.
- Agreed visible world width on the iPhone; HUD and touch controls at their intended size.

## Progress
- 2026-10-05: branch `feat/camera-framing` from main 14465dd. T1 change applied and deployed to the iPhone.

## Next step
Decide T2 with the team.

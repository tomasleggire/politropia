# Feature: Greece level — connected room layout

## Objective
Turn the Greece art sketch into a playable, connected metroidvania level that follows the user's room diagram. Luz enters with only a normal jump and dash. Every jump on the critical path is designed against her measured movement metrics. Juani's art dresses the rooms, and collision stays cheap enough for the iPhone.

## Problem
`level/greece` (by juani) is a collage of disconnected art fragments with no level script. Luz spawns in a sealed box. Collision is one polygon per 8x8 tile (13152 cells). Tilemap colliders don't support wall cling, wall kick or ledge hang, and the one-way tiles sit on layer 1, so drop-through never fires on them.

## Why
The user wants a playable Greece level as the base for the next mechanics (medals, exit door, boss, double jump, enemies). Juani designed the room route. We build it, and Codex handles the final art and animation later.

## Room diagram (user, 2026-10-01)
- **Bottom row, left to right:** `Entrada` (spawn), then `B2` (its ceiling opens into the shaft), then `B3`. B3 is split by a double-jump gate, and a medal sits beyond it.
- **Central vertical shaft:** links B2 (bottom) with T2 (top) and holds one medal.
  - Left branch at the upper part: the altar room, with a Stillness Desk checkpoint.
  - Right branch at the lower-middle part: the `Salida` exit room, behind the four-medal door.
- **Top row, left to right:** `T1` (medal), then `T2` (wide, medal, shaft opens through its floor), then `T3`. T3 is the boss arena (Artemis), and beating the boss unlocks the double jump.
- **Intended loop:**
  1. Entrada, then B2, then climb the shaft and rest at the altar.
  2. Reach T2 and collect the medals in T2 and T1.
  3. Fight the boss in T3 and get the double jump.
  4. Drop back down the shaft into B3, pass the gate, and take the fourth medal.
  5. Go to Salida.

## Scope
- Data-driven room layout: room rects, solids, one-way platforms, doorways and markers.
- Cheap collision with LevelGeometry rect bodies. Solids go on layer 1 and one-ways on layer 2 with drop-through.
- A level script with RoomCamera, respawn when falling out of bounds, a Stillness Desk in the altar room, and spawn in Entrada.
- Placeholder markers for the 4 medals, the exit door, the boss arena and the double-jump gate. Their gameplay comes later.
- Per-room camera bounds, Hollow Knight style.
- A minimal double-jump ability, gated and off by default. It exists so the B3 gate can be verified. The boss unlock comes later.
- An art pass with juani's textures, plus a regression test for the layout constraints.

## Out of scope
- Medal pickups, door logic, boss fight, enemies, damage and HUD.
- Final art and animation, which belong to Codex.
- Editing juani's original `scenes/levels/level_greece.tscn`. It stays as the art reference.

## Constraints
- Godot 4.7, typed GDScript, AGENTS.md rules. Commits use Conventional Commits with a body in neutral Spanish and no AI attribution.
- Movement metrics, from `scripts/player/player.gd`:

  | Metric | Value |
  |---|---|
  | Full jump height | 130 px |
  | Running full jump distance | about 172 px |
  | Air dash | 144 px, horizontal only, 1 per airborne period, zeroes vy |
  | Ground dash | about 200 px |
  | Jump + apex air dash gap | about 250 px absolute max |
  | Player collider | 38x58 |
  | Wall kick | about 99 px per kick |
  | Wall jump | 78 px up, 300 out |

- Wall cling, wall kick and ledge hang work only on LevelGeometry rect solids that are at least 80 px tall and no wider than tall.
- Comfortable design limits: steps up 110 px or less, gaps 200 px or less. 200 to 230 px is "skill". A 200 px wall that is wider than tall needs the double jump.
- Camera: zoom 1.8, so one screen shows about 711x400 world px. The current clamp assumes a world origin of (0,0).
- Collision budget: a few hundred shapes at most. No per-tile physics.

## Delivery
- TDD: off (source: no project TDD mode, same as the previous features). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.
- Strategy: `single-pr` (user choice, 2026-10-01). Everything goes on the user's own branch `feat/greece-level` and lands as one PR to `main`. Juani's `level/greece` is never modified. Forecast: about 1200 to 1600 authored lines.
- Branch: `feat/greece-level`, from main `4338006`. Merge of `origin/level/greece` is `c564e49` (local, art only).
- RDD: on (default). Reviewed boundary starts at `c564e49`.

## Tasks
- [x] T1 Room layout and level skeleton (route: delegated, writer trigger: 3+ new non-trivial files)
  - Result:
    - About 750 authored lines: `greece_layout.gd` 195, `greece_level.gd` 98, `greece_level.tscn` 27, `tests/greece_layout_test.gd` 249, `tests/support/greece_reach.gd` 105, `tests/support/greece_probe.gd` 76. Above the 400 heuristic because the explicit layout table, the reachability helper and the probes belong together.
    - 85 collision shapes (62 solids + 23 one-ways). World 3664x2784. Spawn (760,2720). Desk `greece_altar_a` at (1050,1200).
    - Gate (2780,2520), 350x200. It is not clingable (`player.gd:1040-1056`: clingable means a rect at least 80 tall and not wider than tall).
    - Gate worst case: a wall jump from the B2|B3 wall, plus air control, plus an air dash reaches about 611 px against a 716 px distance. A double jump clears it with a 60 px margin.
    - Rooms: T1 64..1000, T2 1064..2600, T3 2664..3600 (y 64..544); Shaft x 1500..1860 (y 544..2240); Altar 760..1436 (y 880..1200); Exit 1924..2600 (y 1560..1880); Alcove 1860..2040 (y 1220..1380); Entrada 600..1100, B2 1164..2000 (y 2240..2720); B3 2064..3500 (y 2360..2720, low ceiling stops wall-kick climbs over the gate). Doorways are 160 tall.
    - Deviations:
      - Walls sit between rooms.
      - The T1 skill gap is a 210x100 pit with a floor.
      - The alcove floor is at y 1380, and the alcove can also be reached without the dash, so its 210 px gap is partly cosmetic.
  - Verification:
    - Import clean.
    - `greece_layout_test` PASS 39/39 (parent re-ran it: 39/39). It prints exit-time leak warnings.
    - Ritual test PASS 259/259.
    - Boot with `--quit-after 300` clean.
    - The parent viewed the overview and shaft screenshots: the layout matches the diagram.
  - Commit: `3dc23c8` feat: add connected Greece room layout. The GGA pre-commit review passed.
  - Review:
    - Range `c564e49..3dc23c8`, 13 paths, 861 lines, untracked concept PNG excluded.
    - Assessed `medium`, `slice_budget_reached`. User GRANTED.
    - Lineage `review-70b073663a9f49d1` (review-reliability): APPROVED, no findings, acknowledged.
    - The reviewed boundary advances to `3dc23c8`.
  - Follow-ups (small):
    - The reachability test hardcodes `Vector2(1050, 1200)` instead of `GreeceLayout.DESK_POSITION`. Fix in T2.
    - The Greece test prints exit-time leak warnings.
  - `scripts/levels/greece_layout.gd`: rooms, solids, one-ways, doorways, markers as typed data.
  - `scripts/levels/greece_level.gd` and `scenes/levels/greece_level.tscn`: build collision from the data, give each room a flat placeholder look, set the RoomCamera world rect, respawn on out-of-bounds, place a StillnessDesk (`greece_altar_a`) in the altar room, spawn in Entrada, and add placeholder markers.
  - Set `main_scene` to the Greece level on this branch, so the user can test it on the device.
  - Test `tests/greece_layout_test.gd`:
    - Data validation: rooms connected, critical-path steps and gaps within the metrics, gate 200 px tall (above the 130 px jump, below the ~260 px double jump) and not clingable.
    - Physics probes: spawn lands, the altar is reachable, and the gate blocks without the double jump.
- [x] T1b Make the shaft medal alcove require the jump + air dash (user request 2026-10-01: the 210 px gap was cosmetic; route: delegated, same writer as T2)
  - Commit: `75e24c7` fix: require the dash to reach the shaft medal alcove (+299/-17).
  - Geometry:
    - A corridor off the shaft with a 160-tall window (y 1170..1330) under a thin 64 px lintel.
    - Take-off sill x 1860..2040 at y 1330. Pit 220 wide (x 2040..2260) and 166 deep. Medal floor x 2260..2464, `Medal3` (2370,1330). `L1380` was replaced by `R1390`.
  - No-dash worst case: the lintel caps the rise at 102 px, so edge jumps fall at least 45 px short (the test asserts at least 25). An air dash 0.15 to 0.4 s after take-off lands.
  - Exit paths: a jump + dash back to the sill, walking off the sill to a shaft platform, or wall kicks out of the pit. No soft-lock.
  - Tests: no-dash sweeps from every nearby surface, the dash route, and the exit. A mutation (pit 150 wide) fails both the model and the probes. The test also uses `GreeceLayout.DESK_POSITION` now.
  - Risk: the gap holds only because of the lintel. Without it, the open-air no-dash reach is about 237, and the sweep test guards this.
- [x] T2 Per-room camera bounds (route: delegated, writer trigger: camera + level + test files)
  - Commit: `8ad315e` feat: clamp the camera to each Greece room (+533/-13). About 530 lines, above the 400 heuristic, because the new camera test is 356 lines.
  - Camera API: `RoomCamera.set_room_bounds(rect, t)`, `clear_room_bounds(t)`, `get_room_bounds()`, and `bounds_transition_time` 0.35 s (`@export_group("Room Bounds")`).
    - The clamp blends with a sine tween. A span smaller than the view is centred.
    - `snap_to_target` finishes the blend. Desk focus clamps to the same rect. With no bounds it behaves as before.
  - Rooms: `GreeceLayout.camera_bounds(room)` is the interior plus the 64 px wall, and the shaft bounds merge the alcove. `room_for(point, current)` has 24 px hysteresis, and doorways belong to no room.
  - Level wiring: `greece_level.gd` applies the bounds per physics tick and snaps on `respawned` and `_ready`.
  - Verification:
    - Import clean.
    - `greece_layout_test` PASS 58/58 (about 80 s; it runs real-time probes).
    - `room_camera_bounds_test` PASS 38/38 (the parent re-ran it: 38/38).
    - Ritual test PASS 259/259.
    - Boot clean.
    - The parent viewed the alcove and altar camera screenshots: the alcove geometry is correct, and the altar room is centred and framed.
  - Review:
    - Range `3dc23c8..8ad315e`, 11 paths, 870 lines. Assessed `medium`, `slice_budget_reached`. User GRANTED.
    - Lineage `review-35a057613be8b193` (review-reliability): APPROVED, acknowledged. The reviewed boundary advances to `8ad315e`.
  - Open (T4): doorway gaps show black void instead of room colour.
- [x] T3 Double-jump ability, gated, plus gate verification (route: delegated, writer trigger: player + level + tests)
  - Commit: `9bbdc58` feat: add a gated double jump (about 540 lines, mostly the new 367-line test).
  - Player:
    - `@export_group("Double Jump")`: `can_double_jump` false, `double_jump_height` 130, `air_jumps` 1. API `unlock_double_jump()`, `has_double_jump()`, signal `ability_unlocked(&"double_jump")`.
    - The air jump fires only on a fresh press after coyote time. It replaces vy, and the release multiplier applies.
    - A stale buffered press stays a ground jump. `_restore_air_actions()` resets the dash and air jumps at every former `_air_dash_used = false` site.
  - Greece: `DoubleJumpPlaceholder` (Area2D, group `greece_placeholder`) sits at `BossArena` and unlocks the double jump on touch. It is runtime only, not persisted. It will be replaced by the boss reward.
  - Measured: double jump peak about 260 px. The scripted gate run peaks at 268 against the 200 px gate (68 px margin) and reaches the Medal4 side.
  - Verification:
    - Import clean.
    - `double_jump_test` PASS 30/30 (the writer saw one earlier timing flake and fixed it by waiting on physics frames; the parent ran it twice: 30/30 both times).
    - `greece_layout_test` PASS 66/66.
    - `room_camera_bounds_test` PASS 38/38.
    - Ritual test PASS 259/259.
    - Boot clean.
  - Review:
    - Range `8ad315e..9bbdc58`, 8 paths, 572 lines. Assessed `medium`, `slice_budget_reached`. User GRANTED.
    - Lineage `review-dc1c3d95a208bfc6`: APPROVED, acknowledged. The boundary advances to `9bbdc58`.
  - Follow-ups:
    - `greece_probe.gd` types `player` as `CharacterBody2D`.
    - `double_jump_test` reads private members.
    - Decision gap: a fresh press a few px before landing fires the air jump, not a ground jump.
- [x] T2b Hollow Knight style room transitions (user correction, 2026-10-01; runs after combat C1/C2, because both touch `greece_level.gd`)
  - Crossing a doorway is NOT a continuous camera follow. There is a brief dark fade, like a very light loading screen. Then the camera snaps to the new room, and Luz appears walking out of the door she entered through.
    - Rooms can differ in size.
    - This replaces the T2 blend between rooms. The camera still clamps to each room's bounds.
  - Enemy state on leaving and re-entering a room: decision pending. The user said enemies "vuelven a… sino en el último lugar donde quedaron". Ask when the enemies step starts.
  - The camera "doesn't fully convince" the user yet. Polish comes later.
  - Enemy re-entry DECIDED (2026-10-01):
    - Killed enemies stay dead, with visible corpses, until a desk rest or death.
    - Living enemies reset to spawn at full health on re-entry.
  - Commit: `2e268f6` feat: add Hollow Knight style room transitions (+918/-37).
  - Doorways: `GreeceLayout.doorways()` gains orientation, `transitions`, sides, arrivals and lips. The `RoomTransition` node fades out 0.12 s, switches while black, and fades in 0.18 s.
  - Horizontal doors: auto-walk at 250 px/s and arrival 20 px inside the new room (`ARRIVAL_INSET`, lowered to keep clear of the B2 hazard), with a walk-out of about 32 px.
  - Vertical openings: velocity is kept, plus an upward boost that clears the lip by 24 px.
  - The player's `ScreenFade` is the single veil owner. There is no damage during a transition, the input lock clears buffers, and `room_changed(from, to)` is emitted. The alcove counts as Shaft.
  - Tests: room_transition 49/49 (the parent re-ran it: 49/49), room_camera 38/38, greece_layout 70/70, ritual 259/259.
  - Open:
    - Coming back into Entrada, the onboarding step stops the walk-out after 13 px.
    - After a vertical rise with no floor, Luz can drop back through the opening and trigger the reverse transition. Feel call for the user.
- [ ] T4 Art pass with juani's textures: NinePatch floors and walls, floating platforms, room backgrounds, decor. REASSIGNED to Codex (user, 2026-10-01: all visual work goes to Codex; backlog in Engram `codex/visual-backlog`). Claude does no art.
- [ ] T5 Device playtest and adjustments
  - 2026-10-01 playtest 1 (iPhone 16 Pro, build `f5a437a`, flat placeholder visuals):
    - User verdict: "por ahora sirve pero hay muchas cosas que mejorar". The layout is accepted as a base, and adjustments are still to be defined by the user.
    - Pending user feedback: which jumps feel wrong, unfair or too easy; the double jump firing near the ground (the T3 decision gap); and how the room camera feels.

## Acceptance criteria
- From Entrada, Luz reaches the altar, T1, T2 and the T3 arena using only jump and dash, with no impossible or blind jump.
- The B3 medal area is unreachable without the double jump and reachable with it.
- All rooms connect as in the diagram. Dropping back down the shaft works through the one-ways.
- The game boots with no errors, there are fewer than about 300 collision shapes, and the tests pass.

## Progress
- 2026-10-01: exploration done (movement, camera, level construction, desk, art, tests). Document created.
- 2026-10-01: T1 done, `3dc23c8`, review approved.
- 2026-10-01: T1b (alcove needs the dash, `75e24c7`) and T2 (room camera, `8ad315e`) done, review approved.
- 2026-10-01: T3 (gated double jump, `9bbdc58`) done, review approved.
- 2026-10-01: deployed to the iPhone and playtested; accepted as a base with many improvements pending. Branch pushed.

## Next step
Collect the user's concrete playtest adjustments (T5), then the T4 art pass with juani's textures (also fix the black void in doorway gaps).

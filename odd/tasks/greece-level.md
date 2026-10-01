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
  - `scripts/levels/greece_layout.gd`: rooms, solids, one-ways, doorways, markers as typed data.
  - `scripts/levels/greece_level.gd` and `scenes/levels/greece_level.tscn`: build collision from the data, give each room a flat placeholder look, set the RoomCamera world rect, respawn on out-of-bounds, place a StillnessDesk (`greece_altar_a`) in the altar room, spawn in Entrada, and add placeholder markers.
  - Set `main_scene` to the Greece level on this branch, so the user can test it on the device.
  - Test `tests/greece_layout_test.gd`:
    - Data validation: rooms connected, critical-path steps and gaps within the metrics, gate 200 px tall (above the 130 px jump, below the ~260 px double jump) and not clingable.
    - Physics probes: spawn lands, the altar is reachable, and the gate blocks without the double jump.
- [ ] T2 Per-room camera bounds (route TBD)
- [ ] T3 Double-jump ability, gated, plus gate verification (route TBD)
- [ ] T4 Art pass with juani's textures: NinePatch floors and walls, floating platforms, room backgrounds, decor (route TBD)
- [ ] T5 Device playtest and adjustments

## Acceptance criteria
- From Entrada, Luz reaches the altar, T1, T2 and the T3 arena using only jump and dash, with no impossible or blind jump.
- The B3 medal area is unreachable without the double jump and reachable with it.
- All rooms connect as in the diagram. Dropping back down the shaft works through the one-ways.
- The game boots with no errors, there are fewer than about 300 collision shapes, and the tests pass.

## Progress
- 2026-10-01: exploration done (movement, camera, level construction, desk, art, tests). Document created.

## Next step
T1.

# Feature: Artemis, Greece zone boss

## Objective
Build Artemis, the Greece zone boss, as a drag-and-drop scene like any other enemy. She needs a complete, polished mechanical kit: movement, tracking, attack patterns, two phases and clear telegraphs. She uses presentable placeholder visuals. A written animation contract lets Codex replace the visuals later without touching the logic.

## Problem
There is no boss or boss infrastructure: no arena lock, no boss HP bar and no phases. The Greece level only has a `BossArena` marker (greece_layout.gd:230) and a `DoubleJumpPlaceholder` reward (greece_level.gd:196-205).

## Why
The Greece zone needs its boss. Beating Artemis unlocks Luz's double jump. Teammates are still building the zone, so the boss must be droppable into any arena later.

## User decisions (2026-10-12)
- **Theme:** Artemis is a ranged huntress who kites melee-only Luz. The fight is a pursuit: Luz must break the distance.
- **Telegraphs are mandatory.** Every attack must be readable and learnable. On mobile no telegraph is shorter than 0.35 s.
- **Visuals:** presentable code placeholders now. All final art and animation goes to Codex (Engram `codex/visual-backlog`). An exact animation contract is documented for Codex.
- **Difficulty:** start ACCESSIBLE (about 30 Luz hits, generous punish windows). Every number is an `@export` and gets tuned on the iPhone later. Future tuning and design questions are raised with the user as they come up.
- The fight must never require the double jump, because the double jump is its reward.

## Design
### Luz reference (scripts/player/player.gd)
- Melee only, damage 1, 3 health pips, 1.0 s i-frames after taking damage.
- Ground combo x3, plus up, crouch and air attacks.
- Dash: 0.43 s with i-frames, cooldown 0.35. The dash blocks enemy contact and projectiles but not hazards.
- Jump height 84. The double jump is locked during this fight.

### Movement / AI
- **Kite:** keeps a preferred distance of 180–260 px and repositions between attacks for 0.6–1.2 s.
- **Backstep:** a hop backwards when Luz is closer than about 90 px. It has a cooldown.
- **Dodge:** about 30% chance on Luz's attack startup, with a 3 s cooldown. She never dodges during her own recovery.
- **Feint:** a fast approach that stops just out of melee range, then retreats.
- **Attack choice:** weighted by distance, never the same attack twice in a row.
- **Stagger:** about 6 hits within a short window stuns her for 1.5 s.

### Phase 1 (100% → 50% HP)
| Attack | Telegraph | Answer | Punish window |
|---|---|---|---|
| Aimed shot: fast straight arrow | 0.6 s draw + aim line | dash or jump | 0.5 s |
| Fan: 3 arrows at 15° | 0.45 s | dash through | 0.4 s |
| Arrow rain: shoots skyward, arrows fall on floor-marked zones with gaps | 0.8 s | stand in a gap | 0.9 s on landing |
| Dagger slash: anti-turtle when Luz stays close for more than 0.6 s | 0.35 s | dash back | none (backflip) |

### Phase 2 "Full Moon" (50% HP or less)
- Recoveries are 15% shorter.
- Chained strings, for example shot → backstep → rain.
- **Moon dive:** she leaves the screen, a glow marks Luz's X, then she dives diagonally and stays stuck in the ground for 1.2 s. This is the big punish window.
- **Spectral stag:** charges wall to wall after a 0.8 s edge glow. Luz passes it with the dash.

### Architecture
- `ArtemisBoss extends Enemy` (scripts/enemies/bosses/artemis_boss.gd, scene scenes/enemies/bosses/artemis.tscn).
  - Inherits `receive_hit`, flash, the registry and the checkpoint contract.
  - Every timing is an `@export_group`.
- Arrows reuse `EnemyProjectile` with the pooling pattern from shooter.gd.
- A separate draggable `BossArena` scene:
  - Trigger, door locks, camera lock, HP bar and name.
  - On defeat it grants the double jump.
  - The boss resets when Luz dies.
- The animation contract lives in `docs/bosses/ARTEMIS_ANIMATIONS.md`.

## Scope
- In: the boss logic, telegraph placeholders, the projectiles, the BossArena scene, the boss HP bar, a test arena scene, headless tests and the animation contract doc.
- Out: final art and animation (Codex), placing her in the Greece level (teammates and zone v2), and Luz hurt/death animations.

## Constraints
- Godot 4.7, typed GDScript, AGENTS.md rules. No `print()`.
- Mobile frame budget: no per-frame allocations. Use pooled projectiles and simple raycasts.
- Conventional Commits with the body in neutral Spanish. No AI attribution.

## TDD
Mode: off (project configuration; precedent in `odd/tasks/luz-final.md`). Headless suites run as functional checks.
Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd` (the single entrypoint; see tests/README.md).

## Applicable checks
- The full headless suite (entrypoint above).
- Godot headless boot: `--headless --path . --quit-after 120` with no script errors.
- iPhone deploy and playtest, plus a user feel review (T6).

## Delivery
- Forecast: about 1800–2200 authored changed lines (boss AI about 900, arena/HUD about 300, tests about 500, docs about 250).
- Strategy: `single-pr` with a size exception (user choice 2026-10-12, same as luz-final). All work stays on `feat/artemis-boss`, with one PR at the end and no chained PRs.

## Tasks
- [x] **T1 Core + movement + telegraph framework + aimed shot.**
  - `ArtemisBoss` scene with placeholder visual, state machine, kite/backstep/dodge/feint, HP and phase threshold, stagger.
  - A reusable telegraph FX (flash, aim line, floor marker).
  - The aimed shot.
  - Defeat sequence (no corpse), `defeated` signal and checkpoint reset.
  - Test arena `scenes/test/artemis_arena.tscn` and the `tests/artemis_boss_test.gd` suite wired into the runner.
  - Route: delegated (writer trigger: 2+ non-trivial files).
- [ ] **T2 Rest of phase 1:** fan, arrow rain with floor markers and gaps, dagger slash anti-turtle. Weighted, distance-based attack selection with no repeats. Route: delegated.
- [ ] **T3 Phase 2:** faster recoveries, chained strings, moon dive, spectral stag, phase transition beat. Route: delegated.
- [ ] **T4 BossArena:** trigger, doors, camera lock, boss HP bar and name, reset on Luz death, double jump reward. Route: delegated.
- [ ] **T5 Animation contract:** `docs/bosses/ARTEMIS_ANIMATIONS.md` (clips, frame counts, durations, hit/fire frame events, what each pose must convey) plus the Codex backlog update. Route: inline (one doc).
- [ ] **T6 Playtest and tuning:** iPhone deploy, user feel review, number pass. Route: inline.

## Progress
- 2026-10-12: design accepted; branch `feat/artemis-boss` created from main 460f501.

- 2026-10-12: T1 done (delegated writer).
  - New files: `ArtemisBoss` (`scripts/enemies/bosses/artemis_boss.gd`), `BossTelegraph`, `artemis.tscn`, `artemis_arrow.tscn`, the test arena at `scenes/levels/test/artemis_arena.tscn` (the existing test folder), and `tests/artemis_boss_test.gd` (13 cases, 60 checks, all pass; chained first in the runner).
  - `player.gd` gained the read-only accessor `is_attack_starting()`.
  - States: IDLE, REPOSITION, BACKSTEP, DODGE, FEINT, ATTACK (TELEGRAPH → ACTIVE → RECOVER), STAGGER, DEFEATED.
  - The dodge is allowed only in REPOSITION and FEINT. The first hit wakes an idle boss (`engage()`).
  - Known environmental failure on base: `scenes/levels/level_01.tscn` was removed in a1da262, so the Stillness Desk ritual cases and the health_hud and camera suites fail to load it. Base runner result: `FAIL incomplete run (13 of 263 checks ran)`. This is not caused by this feature and is left for the team.

## Open questions (raise with user when relevant)
- Is `feint_stop_distance` 80 outside Luz's reach? Tune on device.
- Should the dodge grant i-frames? Today it is only a hop.
- Cornered escape: when she is pinned in melee she just shoots. Should she hop over Luz instead?
- Should the BossArena call `engage()`? Planned for T4: yes.

## Next step
T2.

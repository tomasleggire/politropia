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
- [x] **T2 Rest of phase 1:** fan, arrow rain with floor markers and gaps, dagger slash anti-turtle. Weighted, distance-based attack selection with no repeats. Also fix the T1 review advisories (a) and (b). Route: delegated.
- [x] **T3 Phase 2 + cornered vault:** faster recoveries, chained strings, moon dive, spectral stag, the phase transition beat, and the cornered vault over Luz (user decision 2026-10-12). Also fix advisory (c). Route: delegated.
- [x] **T4 BossArena:** trigger, doors, camera lock, boss HP bar and name, reset on Luz death, double jump reward, arena bounds fed to the boss, and permanent defeat. Also fix advisories (e) and (f). Route: delegated.
- [x] **T5 Animation contract:** `docs/bosses/ARTEMIS_ANIMATIONS.md` (clips, frame counts, durations, hit/fire frame events, what each pose must convey) plus the Codex backlog update. Route: inline (one doc).
- [x] **T6 Playtest and tuning:** iPhone deploy and user feel review. Playtest 1 fixes are in 526f60c. Playtest 2 (2026-10-12): the user says she is "perfectly playable". Route: inline.
- [x] **T7 Platform-aware attacks** (user decision 2026-10-12: she must NOT use platforms, but every attack must respect their physics). The planned Greece T3 arena has three one-way platforms (greece_layout.gd:288-290).
  - Rain arrows stop on the first surface below them, and the markers are drawn on that surface.
  - The moon dive marks the whole column, and the column hits Luz on a platform.
  - The proximity rules (dagger, backstep, vault) use real 2D distance or a vertical tolerance.
  - She never ends up standing on a platform.
  - Route: delegated.
- [ ] **T8 Defeat feel + persistent corpse + save hooks.**
  - The final hit gets a freeze, white flash, about 0.5 s of slow motion and a camera shake.
  - The corpse stays where she fell across revisits, rests and deaths during the run (BossProgress stores the position and facing).
  - `to_dict`/`from_dict` hooks for a future save system. The project has no disk save; the boss must be saved together with the double jump to avoid a softlock.
  - Route: delegated.
- [ ] **T9 Camera shakes + audio hooks.**
  - Shakes on the phase-2 transition and the dive impact.
  - `AudioStreamPlayer2D` slots for every telegraph and impact, with empty streams for now.
  - The animation contract gets an audio cue table.
  - Route: delegated with T8.
- [ ] **T10 One-drag prefab + team guide.**
  - `artemis_boss_arena.tscn` with the arena and Artemis prewired.
  - `docs/bosses/BOSS_ARENA.md`: placement, sizes, unique `enemy_id`, platforms, and a Stillness Desk before the arena.
  - Route: delegated with T8.
- [ ] **T11 Push** `feat/artemis-boss` to the remote, ONLY after the user approves an iPhone build of the finished T7-T10 work (user instruction 2026-10-12). Route: inline.

## Progress
- 2026-10-12: design accepted; branch `feat/artemis-boss` created from main 460f501.

- 2026-10-12: T1 done (delegated writer).
  - New files: `ArtemisBoss` (`scripts/enemies/bosses/artemis_boss.gd`), `BossTelegraph`, `artemis.tscn`, `artemis_arrow.tscn`, the test arena at `scenes/levels/test/artemis_arena.tscn` (the existing test folder), and `tests/artemis_boss_test.gd` (13 cases, 60 checks, all pass; chained first in the runner).
  - `player.gd` gained the read-only accessor `is_attack_starting()`.
  - States: IDLE, REPOSITION, BACKSTEP, DODGE, FEINT, ATTACK (TELEGRAPH → ACTIVE → RECOVER), STAGGER, DEFEATED.
  - The dodge is allowed only in REPOSITION and FEINT. The first hit wakes an idle boss (`engage()`).
  - Known environmental failure on base: `scenes/levels/level_01.tscn` was removed in a1da262, so the Stillness Desk ritual cases and the health_hud and camera suites fail to load it. Base runner result: `FAIL incomplete run (13 of 263 checks ran)`. This is not caused by this feature and is left for the team.

- 2026-10-12: T1 native review was granted by the user and APPROVED (lineage review-4ea566f2b0645116, medium risk), then acknowledged. The reviewed boundary is now 2786b40. Two non-blocking advisory findings were carried into T2:
  - (a) `_reset_ai` does not re-enable physics processing after the defeat fade, so a checkpoint reset after `defeat_time` would revive a frozen boss.
  - (b) The RECOVER wait loop in `tests/artemis_boss_test.gd:198` never increments `t`.

- 2026-10-12: T2 done (delegated writer).
  - Fan: 3 arrows; `fan_spread_degrees` 15 is the angle between neighbouring arrows.
  - Rain: 3 zones of 56 px with 64 px gaps around Luz's x, a 0.8 s telegraph, markers pulsing, 18 pooled arrows.
  - Dagger: forced after 0.6 s within 70 px, then a backflip.
  - Weighted band selection (`weights_far`/`mid`/`near`) with no repeats.
  - Advisories fixed: an explicit physics re-enable in `_reset_ai` plus a regression test, and the bounded wait loop.
  - 19 Artemis cases, all 0 failed (parent spot check rerun).

- 2026-10-12: T2 native review was granted and APPROVED (lineage review-ceeb991b3de6ea4c, scoped to db59ecc only), then acknowledged. The boundary is now db59ecc. Advisories:
  - (c) `_plan_rain` and `_arena_bounds` read `_luz` without a null guard when `start_attack(RAIN)` is called externally. This is real and is carried into T3.
  - (d) A stale WallProbe after the rain. Verified as not a bug: `_wall_probe.position` is reset before every movement probe (artemis_boss.gd:1038). Optional hardening only.

- 2026-10-12: T3 done (delegated writer).
  - Phase transition: 1.0 s, still hittable, postponed while an attack is ACTIVE, in STAGGER or in VAULT.
  - Chains through `CHAIN_TABLE`: SHOT → hop → RAIN, FAN → MOON_DIVE, DAGGER → SHOT. At most 3 links.
  - Moon dive: leap 0.4, track 0.6, lock 0.4, stuck 1.2. The stuck window is not scaled, she is unhittable while off-screen, and contact is off while stuck.
  - Spectral stag: new `scripts/enemies/bosses/spectral_stag.gd`. It spawns at the wall farthest from Luz, is 60x48, and can be jumped or dashed.
  - Cornered vault: telegraph 0.35, apex 130, lands 80 px past Luz, cooldown 4, no contact damage. It has priority over the dagger when she is cornered.
  - Advisory (c) fixed with `_luz_x()` guards; `_wall_x` restores the probe.
  - Results: 31 Artemis cases, all 0 failed (parent spot check rerun). The only other failures depend on level_01: case_first_rest and case_level_trail_placement.

- 2026-10-12: T3 native review was granted and APPROVED (lineage review-070a1abba84a1c34, scoped to 617ddc6), then acknowledged. The boundary is now 617ddc6. Advisories carried into T4:
  - (e) `_update_hop` starts a pending chain at the end of ANY hop. The dodge is only allowed in REPOSITION/FEINT, which clear the chain, so this is likely unreachable. Harden it anyway: chain only on the chain's own hop.
  - (f) Add tests for the transition postponed by STAGGER or VAULT that fires exactly once afterwards.

- 2026-10-12: T5 done (delegated writer, run in parallel with T4).
  - `docs/bosses/ARTEMIS_ANIMATIONS.md`, 259 lines: node contract, a proposed `artemis_animation_catalog.gd` and `_play()` hook, about 45 clips derived from the exports, VFX, telegraph rules, a checklist and an unknowns list.
  - The Codex backlog in Engram is updated.
  - Deviation noted: the moon dive is VERTICAL in code (the design said diagonal). The doc follows the code.

- 2026-10-12: T4 done (delegated writer).
  - New scenes: `BossArena` (@tool debug draw: arena cyan, trigger yellow, doors red), `BossHealthBar` (name, trailing chunk, 50% notch, title card) and the `DoubleJumpReward` pickup.
  - New `BossProgress` autoload holding the beaten boss ids. A beaten boss leaves `checkpoint_resettable`, so a desk rest or death never revives her.
  - Camera lock through `RoomCamera.set_room_bounds`, saved and restored.
  - The arena feeds `set_arena_limits` to the boss.
  - Advisory (e) fixed with a `chains` flag on `_start_hop`; advisory (f) tests added.
  - The test arena now uses BossArena.
  - Results: 34 Artemis cases and 8 BossArena cases, all 0 failed (parent spot check rerun). The only failures are the level_01 ones.

- 2026-10-12: T4 native review was granted and APPROVED (lineage review-382a8f661ad26612, base 617ddc6), then acknowledged. The boundary is now 91ec13b. Advisories, fixed now as a follow-up commit:
  - (g) Softlock: the boss could be killed while the arena was ARMED, and then the doors closed on a dead boss.
  - (h) `_rearm_trigger` could resume after the arena was freed.

- 2026-10-12: advisories (g) and (h) fixed.
  - The boss cannot be damaged while she is under manual engage and IDLE.
  - The arena refuses to start a fight on a dead boss and records a defeat in any state.
  - The rearm stops if the arena has left the tree.
  - Three new tests added. Only the level_01 cases fail.

- 2026-10-12: Playtest 1 on iPhone (5a6b4e1). The user said it "looks fine" and reported three issues, all fixed (delegated writer):
  - (1) Interruptible telegraphs (user request).
    - A hit during TELEGRAPH cancels the attack. She flinches 0.25 s, then escapes with a backstep or a vault.
    - Poise cooldown: 3 s in phase 1, 4 s in phase 2. ACTIVE and RECOVER are never interrupted.
    - New FLINCH state and `attack_interrupted` signal.
  - (2) Invisible arrows. Root cause: the arrow polygon was self-overlapping and triangulated to 0 triangles. The `Hair` polygon had the same bug. Both were fixed, and arrows are now reparented beside the boss.
  - (3) Missing HUD. `health_hud.tscn` was only instanced by the deleted level_01, so it was added to the test arena. The main game levels (Greece, library, garden) lack the HUD too; this is for the team.
  - Verified with movie-writer frames and the suite (only the level_01 cases fail).

- 2026-10-12: T7 done (delegated writer).
  - Rain: one ray per arrow column; markers are split per surface.
  - `EnemyProjectile.stops_on_one_ways`, set only for Artemis arrows: a downward arrow stops on a one-way platform top.
  - Moon dive: a silver column telegraph (the hitbox already sweeps the column).
  - `vertical_engage_tolerance` 60 gates backstep, dagger, dodge, vault and the near band.
  - Her body and floor probe use mask 1 only, so she never stands on a one-way platform.
  - The test arena has 3 platforms (tops -104, -194, -104).
  - 5 new cases. Movie-writer frames confirm the markers on the platform and the dive column.

## Open questions (raise with user when relevant)
- Is `feint_stop_distance` 80 outside Luz's reach? Tune on device.
- Should the dodge grant i-frames? Today it is only a hop.
- ~~Cornered escape?~~ DECIDED 2026-10-12: she vaults over Luz when cornered. The vault is telegraphed and has a cooldown.
- Should the BossArena call `engage()`? Planned for T4: yes.
- Should the rain zones follow Luz (current) or sweep the whole floor?
- Are 18 rain arrows per volley fine on mobile? Check during the T6 playtest.
- Should the arena bounds come from BossArena in T4 instead of `arena_half_width` probes? Planned: yes.
- Does the 80 px vault landing distance feel right? Check during the T6 playtest.
- `BossProgress` lasts one run only. If Luz leaves before taking the reward and the scene reloads, the reward does not reappear. Should the arena respawn the reward when the boss is beaten but the double jump is not yet unlocked? Needs the team's save-system direction.
- Placing the arena in Greece belongs to the teammates: drop BossArena at the `BossArena` marker and remove the old `DoubleJumpPlaceholder`.
- Luz jumping more than 60 px above Artemis counts as "not close" (`vertical_engage_tolerance`). Raise it if mid-air dagger or backstep responses are missed.
- Moon dive: keep it vertical (current, the clearest read) or make it diagonal as originally designed? Check during the T6 playtest.

## Next step
T7.

# New bosses

## Objective
Add three new bosses that match Artemis in integration and depth: the library main boss (boombox-headed teacher), an optional library boss tied to the blind NPC side quest, and an optional Greece boss. Each ships as a one-drag arena prefab that teammates can place in any level.

## Problem
- Artemis is the only real boss. `artemis_boss.gd` (2312 lines) mixes the arena-facing contract, the final blow and the phase logic with Artemis-only attacks, so a new boss cannot reuse it.
- `scenes/enemies/bosses/teacher_boss_arena.tscn` is an unwired scaffold holding a plain 2 HP `teacher_enemy`.
- `BossArena` keeps the boss track playing after a non-final boss dies, and its health bar reads a single phase notch (`phase_two_threshold`).

## Why
Requested by the user on 2026-11-15: three new bosses "como Artemis" (health bar, phases, death and last-hit sequence, attack patterns), functional first with no art, each fight clearly different from the others, and placeable by teammates the same way Artemis is.

## Scope
- A shared `BossEnemy` base (extends `Enemy`) that owns everything the three bosses must do identically: arena contract, engage gating, telegraph/active/recover lifecycle, multi-phase thresholds, final blow, corpse settle, reset.
- Three bosses on that base, each with its own movement, attack set, phase changes and signature mechanic.
- One arena prefab per boss (`BossArena` + boss child), with `boss_name`, a unique `enemy_id` and `reward_enabled = false`.
- A way to reach the three fights from the demo shortcut area at the left of `library/zone_1`.
- Out of scope: final art and audio, drops and unlocks, final placement in the real zones, and any refactor of `artemis_boss.gd`.

## Boss designs
Axis per boss, so no two fights share a core loop (Artemis: agility and range).

- **Boombox Teacher — "El Profesor"** (library main): rhythm. Every strike lands on a beat that speeds up per phase. Grounded, never dodges, cannot be interrupted; the punish window is an overheat after his signature phrase.
  - Phase 1: pointer thrusts, boomerang briefcase, kick.
  - Phase 2: low and high sound waves to jump or stay under, bouncing notes.
  - Phase 3: blackboard dictation (letters fall in reading order), double-time encore ending in a bass drop.
- **The Blind Beast — "El Topo"** (library optional, blind NPC): perception. Approved by the user on 2026-11-15 with two changes: the old man himself turns into a creature (not a possessed book), and Hyperfocus must be optional. Creature proposed by the parent: a giant blind mole; code names stay creature-neutral (`BlindBeastBoss`) so a different creature is only a re-skin. He cannot see: he hears and feels loud actions (landing, dash, attack swing) and strikes the last loud spot; walking is quiet and standing still hides Luz. He spends most of the fight underground and untargetable, and is exposed after each eruption, longer when he misses.
  - Phase 1: eruption under the last noise, claw counter toward the last attack swing.
  - Phase 2: braille ridges (dot patterns of spikes rising in sequence), debris tossed at the noise spot.
  - Phase 3: tremor pulse that only detects Luz if she is grounded and moving, chained eruptions through the last noise spots, optional dimmed light.
  - Hyperfocus (`open_eyes_activated`) is a bonus only: it forces him to surface dazed, on a cooldown. The fight must be fully beatable without it.
- **The Hydra — "La Hidra"** (Greece optional): target priority and platforms. Chosen by the user on 2026-11-15 over the Minotaur. Static body, three heads with their own health at different heights, reached from platforms that ship inside the prefab (reachable with a single jump: the double jump is unlocked by Artemis). Each head has its own attack; a killed head stays as a severed stump and the remaining heads get fiercer. The order the player picks changes the fight.
  - Phases are the heads left (3, 2, 1), driven by head deaths; the bar shows total health with a notch per third.
  - Heads: biter (neck lunge at Luz's platform), spitter (venom arcs and pools that deny floor), sweeper (horizontal sweep along one platform level).

## Constraints
- Godot 4.7 GDScript conventions from AGENTS.md. Do not hand-edit `.uid` files.
- `artemis_boss.gd`, the Artemis scenes and `teacher_boss_arena.tscn` stay untouched.
- Changes to `boss_arena.gd` and `boss_health_bar.gd` must be backward compatible: Artemis behaves exactly as before.
- No new boss triggers `GameCompletion` (`BossArena._is_final_boss()` stays `_boss is ArtemisBoss`).
- `enemy_id` values are unique across the whole run (`BossProgress` is global).
- `DoorID.ID` values are saved as ints in scenes: append only, never reorder.
- Placeholder visuals are polygons; no new textures.

## Delivery
- Branch: `feat/new-bosses` from main `82eb468`.
- Strategy: ask-on-risk. Forecast: ~4700 authored changed lines (base ~600, each boss ~1300 with tests, demo access ~200), above the ~400 budget. Chain strategy: pending, to be asked at delivery time. Planned slices: one per task (T1 to T5).
- TDD: off (source: project convention, `odd/tasks/artemis-polish.md:27`). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.
- Receipt-driven development: on (decided by default) when read on 2026-11-15. Review boundary starts at the branch point `82eb468`.
- Commits are created by the parent after readback and a spot check; writers do not commit.

## Tasks
- [x] T1 — Shared boss base: `BossEnemy` script and inheritable base scene, `BossArena` victory music restore, multi-phase bar notches (only if backward compatible), builder notes in `docs/bosses/`, standalone `tests/boss_enemy_test.gd`. Route: delegated direct (writer trigger: several non-trivial files; preparation trigger: reading `artemis_boss.gd` and `boss_arena.gd`). Commit: the `feat(bosses)` commit that introduces `boss_enemy.gd` on `feat/new-bosses`.
- [ ] T2 — Boombox Teacher boss: script, scene, `boombox_teacher_boss_arena.tscn`, test room, standalone test. Route: delegated direct (writer trigger).
- [x] T3 — The Blind Beast boss: script, scene, `blind_beast_boss_arena.tscn`, test room, standalone test. The link from the blind NPC quest to the fight is left as a documented hook, not wired into `blind_npc.gd`. Route: delegated direct (writer trigger).
- [x] T4 — The Hydra boss: script, head parts, scene, `hydra_boss_arena.tscn` with its platforms, test room, standalone test. Route: delegated direct (writer trigger).
- [x] T6 — Base review follow-ups (advisory findings of the T1 review, accepted by the parent as in-scope proof of the acceptance criteria): a reload test where a second arena restores the corpse from `BossProgress`, a stagger case, a deferred phase beat case (threshold crossed during ACTIVE and during a stun), tighter assertions where a check could not fail, and a range guard for extra bar notches. Route: delegated direct (preparation trigger: reading the test rig before writing).
- [ ] T8 — Hydra review follow-ups (advisory findings of the T4 review): prove that a real Player attack damages a head (every hit in the suite was injected through `receive_hit`), assert the duo's echo telegraph, cover a head severed mid-attack, prove and harden platform relayout (scope the tier scan to the boss's own arena, warn on unsupported platform shapes), defer the venom pool release, and assert the enrage effects through observable behaviour. Route: delegated direct in an isolated worktree (preparation trigger).
- [x] T7 — Blind Beast review follow-ups (advisory findings of the T3 review, accepted by the parent because the boss must not soft-lock in arbitrary rooms): a pending noise that cannot be reached, or an empty attack draw, must still make him surface; braille ridge guards for empty words and for arenas narrower than the pattern; a reload test for the beast's corpse; a strict tremor assertion. Route: delegated direct in an isolated worktree (preparation trigger).
- [ ] T5 — Demo access: a way into the three test rooms from the `DemoShortcutToArtemis` area of `library/zone_1`, new `DoorID` values appended, `tests/door_links_test.gd` whitelist updated. Route: delegated direct (writer trigger; touches shared level files, so it runs alone and last).

## Acceptance criteria
- Each boss is one prefab drag: trigger, doors, camera lock, title card, health bar with phase notch, boss music, reset on Luz's death, permanent defeat through `BossProgress`.
- The final blow (flash, shake, freeze and slow motion) and the corpse settle use the same defaults as Artemis.
- Each boss has at least three attacks in phase 1, new attacks in every later phase, and a signature mechanic no other boss uses.
- Every telegraph lasts at least 0.35 s.
- A desk rest or Luz's death returns a living boss to a fresh state with no leftover hazards.
- Existing suites show no new failing case against the base.

## Checks
- Per task: the task's standalone suite passes with exit code 0.
- T1 also: `tests/game_completion_test.gd`, and the ritual runner (`tests/stillness_desk_ritual_test.gd`) compared case by case with a baseline captured before editing `boss_arena.gd`.
- Known debt on main (not caused by this work): the ritual runner reports incomplete with 13 known failing cases; `artemis_room_test.gd` references removed `DoorID` names; `enemy_archetypes_test`, `enemy_test`, `combat_test`, `greece_layout_test` and `greece_population_test` fail on the base.

## Progress
- 2026-11-15: main fast-forwarded to `82eb468`; Artemis contract, teacher enemy, blind quest and zone structure mapped (two read-only mappers).
- Engram mirror (`odd/new-bosses/tasks`): pending. `mem_save` is blocked in auto mode because a hook rewrites the call after review.

## Verification evidence
- T1 (2026-11-15), writer run plus parent spot check:
  - `tests/boss_enemy_test.gd`: `PASS 123/123` (14 cases), re-run by the parent with the same result.
  - `tests/game_completion_test.gd`: `PASS 78/78`. The baseline captured before the import step was `FAIL 1/78` ("el otro jefe no es Artemisa"); the cause was not investigated, a stale global class cache is the likely one.
  - Ritual runner (`tests/stillness_desk_ritual_test.gd`): identical case and failure lines before and after, both `FAIL incomplete run (469 of 719 checks ran)`. No regression.
  - Parent readback of the `boss_arena.gd` and `boss_health_bar.gd` diffs: additive only; Artemis gets no extra notches and keeps the final-boss path.
- T1 native review (2026-11-15), range `82eb468..27abf72`: assessed `medium` (`slice_budget_reached`, 2012 lines; reason `executable_change` in `boss_enemy.tscn`). Consent: granted by the user. One lens (`review-reliability`), result `approved`, acknowledged (lineage `review-8de003177520e98c`, authority burned). The reviewed boundary is now `27abf72`. The unrelated untracked file `tools/art_sources/checkpoint/concept/stillness_desk_concept_v1.png` was declared excluded.
  - Advisory findings, none blocking: music restore on every `_open_arena` call (checked by the parent: `_open_arena` has two callers, the non-final defeat and the fallback when the completion screen is unavailable; a reload of a cleared arena goes through `_enter_defeated_state` and never calls it, so Artemis is unaffected and no change is needed); no stagger case and the deferred phase beat unproved; the corpse restore on reload not exercised; extra notches without a range guard. The last three are T6.
- T6 (2026-11-15), writer run plus parent spot check. Commit: the `fix(bosses)` commit after `27abf72`.
  - `tests/boss_enemy_test.gd`: `PASS 178/178` (21 cases), re-run by the parent with exit 0. New cases: phase beat deferred during an ACTIVE strike and during a stun, phase beat during a telegraph, stagger, corpse restored on reload, corpse made before entering the tree, extra notch range.
  - Defect found and fixed in `boss_enemy.gd`: a corpse made with `make_corpse_at` before the boss entered the tree came out of `Enemy._ready` collidable, with live contact damage and the wrong facing. The registry path (corpse restored after `_ready`) was not affected.
  - Correction to the T1 notes: a threshold crossed during a telegraph starts the transition beat immediately, inside `receive_hit`; it is deferred only during an ACTIVE strike, a stagger or a stun.
  - `tests/game_completion_test.gd`: `PASS 78/78`. Ritual runner: same case and failure lines as the baseline.
  - Native review assessment of `27abf72..83d355b`: `medium` (`executable_change` in `boss_enemy.gd`), 252 lines, `review_due` false (`under_budget`). It stays pending in the slice; the reviewed boundary is still `27abf72`.
  - Known nit: after the PASS line the suite prints an engine error from a deferred `CheckpointService.restore_pending_player` call on a freed player during teardown. It does not change the exit code; whether it predates T6 was not established.
- T3 (2026-11-15), writer run in an isolated worktree (commit `489d00f`), cherry-picked onto `feat/new-bosses` as the `feat(bosses)` commit "agrega al Topo". Parent spot check on the integrated branch, which already has the T6 base fix:
  - `tests/blind_beast_boss_test.gd`: `PASS 199/199` (19 cases), exit 0. The writer also reported `boss_enemy_test` and `game_completion_test` passing and a clean smoke load of `scenes/levels/test/blind_beast_arena.tscn` in its worktree.
  - Decisions taken by the writer, conservative readings: contact damage is off for the whole fight, so every hit comes from a telegraphed hazard; the probe fires only after `patience_time` of silence; the claw counter only reacts inside exposed, unstunned windows; a landing after hurt knockback counts as loud; dash detection uses the rising edge of `is_dash_invulnerable()`. The dim overlay shipped on CanvasLayer 30, below the HUD (40) and the bar (41).
  - Quest hook documented in `docs/bosses/BLIND_BEAST.md`, not wired.
  - Native review of `27abf72..48dd725` (T6 plus T3, 2698 lines): assessed `medium` (`slice_budget_reached`). Consent: granted by the user. One lens (`review-reliability`), result `approved`, acknowledged (lineage `review-aed7d9cff575dcf5`, authority burned). The reviewed boundary is now `48dd725`.
  - Advisory findings, none blocking, all taken into T7: the anti-stall probe is unreachable while a noise is pending, so an unreachable noise spot or an empty weighted draw leaves him burrowed (the parent confirmed the code path in `_choose_next_action`; noise spots are clamped to the arena when recorded, so inside a flat `BossArena` the spot is reachable, but an obstruction on the floor line is not covered); the braille ridge has no guard for an empty word or for an arena narrower than the pattern; the beast's corpse on reload is not exercised; the last tremor assertion cannot fail.
- T4 (2026-11-15), writer run in an isolated worktree (commit `2777966`), cherry-picked onto `feat/new-bosses` as the `feat(bosses)` commit "agrega a la Hidra". Parent spot check on the integrated branch:
  - `tests/hydra_boss_test.gd`: `PASS 149/149` (13 cases, includes a corpse reload case), exit 0. `tests/boss_enemy_test.gd`: `PASS 178/178`.
  - As shipped: LOW head is the biter, MID the sweeper, HIGH the spitter; 12 health each. Luz's single jump is 120 px in `player.tscn` (the script default is 84), platform steps are 56 px, and the suite computes reachability from the real player values. Five platforms in group `hydra_platform` under the arena's `Platforms` node; the boss rereads them at engage and reset.
  - Decisions taken by the writer: heads are NOT in group `enemies` (`greece_population_test` and `greece_probe` cast the whole group to `Enemy`), so soul is granted by calling `add_soul` on each landed hit; venom globs are harmless in flight and only the puddle hurts; only the biter gets stuck after attacking; platforms are static prefab nodes, so a different `arena_rect` moves the body and sweep ends but teammates must move the platforms themselves.
- T4 native review of `48dd725..e273ca5` (2611 lines): assessed `medium` (`slice_budget_reached`). Consent: granted by the user. One lens (`review-reliability`), result `approved`, acknowledged (lineage `review-fe85d30d5171bad4`, authority burned). The reviewed boundary is now `e273ca5`. Six advisory findings, none blocking, all taken into T8. The parent checked the one with gameplay consequences: `scripts/player/attack_hitbox.gd` connects both `body_entered` and `area_entered`, so area hurtboxes are on a supported path, but no test drives a real attack into a head yet.
- T7 (2026-11-16), writer run in an isolated worktree (commit `abbf462`), cherry-picked as the `fix(bosses)` commit "evita que el Topo quede enterrado sin atacar". Parent spot check on the integrated branch: `tests/blind_beast_boss_test.gd` `PASS 246/246` (25 cases), exit 0.
  - Soft-lock guard: new tunable `stuck_tunnel_time` (3 s). When the gap to a pending noise stops shrinking for that long he erupts where he is and the noise counts as answered; an empty weighted draw falls back to ERUPTION.
  - Braille ridge: empty or invalid words are skipped, the ridge is capped to the slots that fit inside the arena, and with no valid word the attack becomes an eruption.
  - Defect found by the new reload cases and fixed: a restored corpse still reported `is_hittable()` true, because `_show_corpse` never turned it off.
- T1 notes for boss authors: `stagger_hits` defaults to 0 (off); the base keeps `collision_mask` 3; facing is not updated during ATTACK or STUN; `_on_phase_entered` fires at the crossing, the beat starts on the next `_think`.

- 2026-11-15: user approved the three concepts with changes (blind creature instead of a tome, Hydra instead of the Minotaur, Hyperfocus optional). T1 writer told to support event-driven phases, multi-part bosses and a non-hittable state.

## Next step
T1 (running), then T2, T3 and T4 in parallel, one writer each in an isolated worktree, then T5.

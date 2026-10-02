# Feature: The Stillness Desk checkpoint

## Objective

Implement The Stillness Desk as a reusable, placeable checkpoint component for any future level. Resting must be a coherent gameplay transaction: Luz commits to meditation, the world pauses safely, health is restored, the respawn point is updated, resettable enemies are regenerated, checkpoint state is retained, and control returns only after the activation sequence completes.

## Problem

The prototype currently advances the player's checkpoint through invisible x-coordinate thresholds in `level_01.gd`. There is no reusable checkpoint scene, interaction action, health API, meditation state, enemy reset contract, or cross-scene checkpoint owner. The final map is unknown, so checkpoint behavior must not depend on a specific level layout.

## Why

- Designers need to place functional checkpoints anywhere without duplicating level logic.
- The checkpoint must communicate recovery, danger reset, and save/respawn state as one readable transaction.
- The altar must feel native to Politropia: a school desk fused with a cathedral lectern, ruler/protractor geometry, paper roots, cobalt ink, amber candlelight, and restrained environmental movement.

## Authorized scope

- Create a reusable Stillness Desk scene and supporting scripts/resources.
- Add a dedicated interaction action and a reusable interaction prompt.
- Add explicit player checkpoint, health, meditation, input-lock, and animation seams needed by the component.
- Add persistent runtime checkpoint ownership and a reset contract for future enemies.
- Place one instance in the current prototype level and remove invisible checkpoint-threshold ownership.
- Generate or derive only the art and animation assets required for the production component.
- Update this document and its Engram mirror after every completed task.
- Create Conventional Commits on `feat/stillness-desk-checkpoint`.

## Out of scope

- Designing the final world map or final checkpoint cadence.
- Copying visual layouts, names, assets, or animations from other games.
- Implementing a complete enemy roster or combat damage system unrelated to checkpoint needs.
- Push, pull request creation, merge, or release without a separate user decision.

## Product and architecture decisions

1. The placed object is a self-contained `PackedScene`; levels only instance and position it.
2. A dedicated global checkpoint service owns active checkpoint identity and runtime persistence across scene changes. The placed desk owns presentation and interaction, not global state.
3. Rest is an explicit transaction: approach -> prompt -> commit -> world pause/player meditation -> heal/checkpoint/reset effects -> activation feedback -> resume.
4. Enemy reset is group/interface based and harmless when no enemies exist. Future enemies opt in instead of the checkpoint knowing concrete enemy classes.
5. Resting regenerates opted-in enemies outside the checkpoint transaction. The behavior is visible through the activation sequence so recovery never hides its cost.
6. The world uses a bounded pause during committed meditation. The checkpoint and required player presentation continue processing while paused; normal movement/combat input remains locked.
7. The current concept image remains an art-direction source. Runtime art must preserve mobile-readable silhouettes and remain composable inside the game camera.
8. T2 ships in-engine placeholder art (shapes, particles, lights; Luz meditation reuses the crouch clip through a named animation seam). Final sprites are generated later and swapped without logic changes (user choice, 2026-09-28).

## External reference findings

- Hollow Knight benches combine respawn/save/recovery and commonly refresh defeated enemies, with a current-room exception documented by the community reference: https://hollowknight.wiki/w/Bench_%28Hollow_Knight%29
- Blasphemous level design used roughly one checkpoint per area and no more than seven screens between them; this is a return-time precedent, not a fixed Politropia rule: https://www.gamedeveloper.com/design/how-i-blasphemous-i-level-design-iterates-on-classic-metroidvanias
- The checkpoint must borrow interaction principles only. Its visual identity and animation language remain original to Politropia.

## Constraints

- Godot 4.7 and typed GDScript.
- Preserve stable referenced node names and do not hand-edit generated `.uid` files.
- No debug `print()` statements in committed code.
- Keep keyboard/controller and current touch input behavior functional.
- Technical artifacts, identifiers, code comments, and UI strings are English.
- Existing unrelated untracked `.DS_Store` files must remain untouched.
- The 400-line ODD task heuristic is advisory; split by coherent behavior, never by file type or code golf.

## Effective verification mode

- TDD: off for this feature because no ODD TDD mode or automated unit-test runner is configured.
- Source: the existing project tracker records Godot 4.7 headless loading as the known runner and no automated unit-test runner.
- Required checks: focused structural inspection, Godot import/headless project load, targeted runtime harness where practical, and interactive scene/device playtest for final visual acceptance.

## Route and trigger evidence

- Feature route: delegated direct ODD.
- Mapping trigger: fired; understanding required player, level, project input/autoload, world interaction, animation catalog, and concept-asset files. A read-only explorer produced the architecture map.
- Writer trigger: expected to fire for every implementation task because the component spans multiple non-trivial files. Use one bounded writer at a time; no parallel writers.
- Verification trigger: builds and runtime checks are delegated independently after each work unit when required.

## Delivery forecast

- Estimated authored change: 700-1,000 lines across reusable runtime code, scenes, integration, and task evidence; generated image pixels excluded.
- Delivery strategy: `ask-on-risk` (ODD default).
- Chain strategy: `stacked-to-main` (user choice, 2026-09-28). Each slice targets `main` and merges in order.
- Slice boundaries: planned one slice per task (T1, T2, T3, T4); exact commits recorded under Commit evidence.
- Initial reviewed boundary: `46a14d4` (branch point from `main`).

## Tasks

- [x] **T0 — Explore and define the recoverable feature contract**
  - Map current player, checkpoint, input, level, animation, and world-component seams.
  - Research comparable checkpoint transaction patterns without copying their presentation.
  - Create this feature tracker before the first source write.
  - Acceptance: architecture, constraints, verification mode, route, and delivery forecast are recorded.
  - Evidence: read-only agents `checkpoint_code_map` and `checkpoint_reference_research`; feature tracker at this path.

- [x] **T1 — Add reusable checkpoint state and player meditation contract**
  - Add a global checkpoint service with stable checkpoint identity and runtime persistence across scene changes.
  - Add a dedicated `interact` action.
  - Add typed player APIs for health restoration, checkpoint application, meditation entry/exit, input locking, and safe transient-state cleanup.
  - Add a resettable enemy/group contract that is safe when no enemies exist.
  - Acceptance: APIs are explicit, reusable, and independent of `level_01`; existing movement/combat behavior remains unchanged outside meditation.
  - Verification: parse/import, headless project load, focused script harness for checkpoint activation and player lock/heal lifecycle.
  - Route: delegated direct (writer trigger: `player.gd`, new service, `project.godot`).
  - API: `CheckpointService` autoload (`activate`, `is_active`, `has_checkpoint_for_scene`, `get_spawn_position_for_scene`, `apply_to_player`, `reset_resettable_enemies`, `clear`, signal `checkpoint_activated`); enemy contract = group `checkpoint_resettable` + `reset_to_checkpoint_state()`; player `restore_full_health`, `enter_meditation`/`exit_meditation`, `set_input_locked`, `clear_transient_state`, `apply_checkpoint`, signals `health_changed`, `meditation_started`, `meditation_finished`. `interact` = E / joypad button 2.
  - Deferred to T2/T3: meditation animation, touch path for `interact`, whether `respawn()` restores health/clears transients, low-ceiling headroom check on exit.

- [x] **T2 — Build the animated Stillness Desk component**
  - Create a placeable checkpoint scene with an interaction area, anchor, prompt, and animation controller.
  - Implement dormant, commit, awakened, resting, and release phases.
  - Add mobile-readable environment motion: pendulum, candle, cobalt inkwell, brass scale, breathing light, paper lift/rebind, mist/dust, and restrained background parallax.
  - Add a meditation presentation for Luz that preserves her identity, ruler, backpack logic, and readable silhouette.
  - Acceptance: the scene runs independently, repeated activation is deterministic, interruption/exit restores control, and no component depends on a concrete level.
  - Verification: standalone component harness plus visual readback/screenshots.
  - Route: delegated direct (writer trigger: desk scene/script, prompt scene/script, `player.gd`).
  - API: `StillnessDesk` (`scenes/world/stillness_desk.tscn`); exports `checkpoint_id` (config warning if empty), `commit_duration` 0.5, `resting_duration` 1.6, `release_duration` 0.5, `pause_world` true; `SpawnAnchor` child = rest + respawn point; signals `rest_started`, `rest_completed`, `phase_changed`; `request_rest() -> bool` (touch entry point), `can_rest()`, `get_phase()`, `get_spawn_position()`. Reusable `InteractionPrompt` (`scenes/ui/interaction_prompt.tscn`). Player seam: meditating plays `meditate` if present, else `crouch`.
  - Deferred to T3/T4: touch/keyboard prompt switching, facing Luz toward the desk, weak glow/mist/arch contrast, Luz overlapping the left paper root.

- [x] **T3 — Integrate one checkpoint into the prototype level**
  - Instance the component in `level_01.tscn` at a safe playable location.
  - Remove the invisible x-threshold checkpoint ownership from `level_01.gd`.
  - Apply persisted checkpoint state when the matching scene starts.
  - Acceptance: interaction works through the dedicated action, resting updates respawn, heal/reset effects occur once, death/respawn returns to the desk, and the level contains no checkpoint-specific duplicated logic.
  - Verification: headless project load and interactive keyboard/touch playtest.
  - Route: delegated direct (writer trigger: level scene/script, touch controls, desk, service, player).
  - Result: desk `level_01_desk_a` at (420, 620) on solid floor; x-threshold `CHECKPOINTS` removed; level start calls `CheckpointService.restore_player_for_scene(player, scene_file_path)`; `respawn()` now restores full health and clears transient state; desk now also calls `player.apply_checkpoint(anchor)` on rest (T2 gap found by harness); touch contract = group `interactable` + `request_interact()`, `TouchControls.set_interact_available(source, available)`, Interact button hidden out of range and during meditation.
  - Known gap: the prototype course previously had 5 threshold checkpoints (up to x=5350); it now has one desk near the start, so late deaths return to it. More desks are a level-design decision.
  - Not verified: real-device touch and keyboard `E` end to end (touch was simulated); respawn while mid-rest.

- [x] **T4 — Final regression, visual polish, and recovery record**
  - Run full applicable Godot checks and inspect errors/warnings.
  - Validate repeated rest, pause/unpause, scene reload, respawn, touch controls, and empty enemy-group behavior.
  - Update task evidence, changed-line count, review assessment state, and next delivery step.
  - Acceptance: all required checks are recorded honestly; failures or unavailable checks remain explicit.
  - Route: delegated direct (writer trigger: desk scene/script, player).
  - Result: soft additive radial glows (Halo/Core/CandleGlow/InkGlow), brighter arch rim + fill, visible mist, `SpawnAnchor` -58 → -76 (clears the paper root); `Player.face_towards(target_x)` (meditation only) called at commit; `respawn()` exits meditation first and the desk aborts cleanly on `meditation_finished`; key prompt hidden when `TouchControls` is visible.
  - Device playtest: PASSED by the user on iPhone 16 Pro (2026-09-28, build d013cfb) — touch interact, rest, respawn at desk, repeated rests. Documented, not fixed: low-ceiling headroom check when leaving meditation.

## Progress

- Current task: feature complete; device playtest passed.
- Next step: push and stacked PRs to `main` (user decision). Follow-up feature: rest ritual animation and altar life (`odd/tasks/stillness-desk-rest-ritual.md`).

## Verification evidence

- Read-only code map completed; no implementation files changed during exploration.
- External design research completed with source links and explicit evidence gaps.
- T1 `Godot --headless --path . --import`: completed, no error/parse/warning lines.
- T1 `Godot --headless --path . --quit-after 120`: clean load (writer run and parent spot check).
- T2 `Godot --headless --path . --import` and `--quit-after 120`: 0 error/warning/parse lines (writer run and parent spot check).
- T2 throwaway harness (scratchpad only): 25/25 checks — pause during rest, meditation lock at anchor, heal 2 → max, service id/spawn match, signals once, unpause/release, deterministic repeat, busy re-request ignored, freeing desk or player mid-rest unpauses and releases.
- T2 screenshots (Metal render, scratchpad): dormant/resting/awakened; parent viewed `resting.png`, silhouettes readable. Harness note: `--script` harnesses cannot reference `Player`/`StillnessDesk` types (autoload not yet registered); use untyped refs.
- T3 `--import` and `--quit-after 120`: 0 error/warning/parse lines (writer run and parent spot check).
- T3 harness on `level_01` (scratchpad only): 15/15 — desk id set, start at (180, 620) without checkpoint, touch button hidden/visible by range, simulated touch starts rest, hidden during meditation, checkpoint active for scene after rest, respawn at anchor with full health, level re-instance places Luz at desk, `clear()` restores original start, empty reset group ok. `rg` finds no threshold-checkpoint code. Screenshot viewed by parent: desk on floor, prompt and diamond Interact button visible.
- T4 `--import` and `--quit-after 120`: 0 error/warning/parse lines (writer run and parent spot check).
- T4 regression harness on `level_01` (scratchpad): 41/41 — 3 deterministic rests (pause, meditation, release, full health, AWAKENED), dummy resettable reset exactly once per rest, facing toward desk, touch button visibility, prompt hidden on touch, respawn mid-rest unpauses/releases/restores process mode, `face_towards` ignored outside meditation, movement regression ok, scene reload at desk. Parent viewed `l01_resting.png`: soft glow, readable arch, Luz clear of roots facing the desk.
- T1 throwaway `--script` harness (deleted): service activate/query/miss ok; empty resettable-group reset no error; `interact` has 2 events; meditation locks input and blocks movement while tree paused (`process_mode` ALWAYS); exit restores mode and movement; heal from 2 → 5 emits one `health_changed`. Only exit-time ObjectDB leak warnings (normal for `--script`).

## Commit evidence

- T0 + T1: `063f371` feat: add checkpoint service and player meditation contract (slice 1; 5 paths, 358 changed lines incl. tracker). GGA pre-commit review: PASSED.
- T1 review assessment (`--base-ref 46a14d4 --committed-only`, untracked excluded): risk `medium` (`executable_change` project.godot), `review_due=false` (`under_budget`). Reviewed boundary stays `46a14d4`; pending in slice.
- T2: `3a33a1b` feat: add Stillness Desk checkpoint component (slice 2; GGA PASSED).
- Slice assessment after T2 (`--base-ref 46a14d4 --committed-only`, untracked excluded): risk `medium`, 11 paths, 1058 changed lines, `review_due=true` (`slice_budget_reached`). Native review START lineage `review-c37ee063db401ded` returned the candidate consent envelope; user chose `declined` (candidate-scoped, validated `declined_this_candidate`). Off path: tier `medium` → writer self-verification + parent spot check (done). Reviewed boundary advances to `3a33a1b`.
- T3: `7425bc2` feat: integrate Stillness Desk into level 01 (slice 3; GGA PASSED; no .DS_Store staging after local exclude).
- T3 assessment (`--base-ref 3a33a1b --committed-only`, untracked excluded): risk `medium` (`executable_change` level_01.tscn), 9 paths, 152 lines, `review_due=false` (`under_budget`). Boundary stays `3a33a1b`; pending in slice.
- T4: `4c64021` fix: polish Stillness Desk visuals and rest interruption (slice 4; GGA PASSED).
- T3+T4 assessment (`--base-ref 3a33a1b --committed-only`, untracked excluded): risk `medium`, 10 paths, 241 lines, `review_due=false` (`under_budget`). Boundary stays `3a33a1b`; the T3+T4 range is pending review until a later commit reaches the budget or delivery.
- Incident: first commit attempt staged the untracked `.DS_Store` files and failed with an invalid object; they were unstaged (`git rm --cached`) and remain untracked on disk. Recurred on T2; mitigated by adding `.DS_Store` to local `.git/info/exclude` (files untouched). Likely source: the opencode reviewer run by the GGA pre-commit hook (unverified).

## Rollback boundaries

- T0 rollback: remove only `odd/tasks/stillness-desk-checkpoint.md` and its Engram mirror.
- T1: revert `063f371` (service, `interact` action, player health/meditation APIs).
- T2: revert `3a33a1b` (desk + prompt scenes/scripts, meditation animation seam).
- T3: revert `7425bc2` (restores x-threshold checkpoints, removes desk instance and touch button).
- T4: revert `4c64021` (visual polish, facing, respawn-mid-rest abort).

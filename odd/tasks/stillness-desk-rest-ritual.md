# Feature: Stillness Desk rest ritual and altar life

## Objective

Turn the functional Stillness Desk checkpoint into a designed rest ritual. Luz mounts the desk, sits cross-legged, celebrates the activation, breathes while resting, and dismounts when the player moves. The altar gets final layered pixel art and restrained, warm ambient life. Every effect must carry meaning in the rest transaction.

## Problem

The checkpoint works on device (parent feature `odd/tasks/stillness-desk-checkpoint.md`, device playtest passed 2026-09-28). It still uses placeholder in-engine art, reuses the crouch clip as a "meditation" pose, and releases Luz on a timer. Nothing celebrates the activation, and the altar has no ambient identity.

## Why

- The rest point is a key emotional beat in a metroidvania. It must read as refuge, reward, and a moment of stillness.
- Readable ritual beats make the transaction legible: the player can tell when healing, saving, and the world reset happen.
- The final art must match Luz's pixel-art rendering, so she can believably sit on the desk.

## Design intent

- **Palette meaning**: the world is cold blue; amber means refuge. The altar is the warmest thing on screen.
- **Stillness metaphor**: time stops while Luz rests. The pendulum settles to center when she sits and resumes swinging when she leaves. The existing world pause becomes the metaphor, not just a technical guard.
- **Beacon**: a few fireflies drift around the dormant altar, readable from a distance, as wayfinding to a safe place.
- **Ritual beats**:
  1. Approach: prompt; fireflies idle.
  2. Mount: Luz sets her backpack on the floor and climbs onto the desk. She sits cross-legged with the ruler across her knees, as in the concept.
  3. Celebration: the pendulum stills, the floor protractor ring sweeps alight like a clock hand, papers lift and orbit, fireflies gather around Luz, and a warm bloom plays. Heal and checkpoint activation happen on this beat.
  4. Rest loop: Luz breathes with her eyes closed. The altar light breathes on the same period as Luz, and papers drift slowly.
  5. Dismount: triggered by player movement/jump/interact input, not a timer. Luz hops down and picks up the backpack; papers settle, the pendulum resumes, and fireflies disperse.
- **First vs repeat**: the first activation of a desk gets the full ceremony. Repeat rests get a short version so resting never becomes tedious.
- **Restraint**: effects must never obscure Luz's silhouette or the prompt/touch button. Everything must stay mobile-readable, with particle counts bounded for iPhone performance.

## Authorized scope

- Generate Luz clips with Codex image generation through the existing pipeline (`tools/process_luz_sheet.py`, `assets/player/luz/animation_manifest.json`): mount (with backpack drop), sit/rest breathing loop, dismount (with backpack pickup).
- Generate layered final altar art with Codex in the same pixel-art style, scaled for Luz to sit on the desk: desk body, pendulum, candle, inkwell, papers, floor protractor ring, paper roots, and the dropped backpack prop.
- Rework the desk rest state machine: mount/celebrate/rest/dismount, input-driven release, and first-vs-repeat ceremony.
- Add ambient and celebration FX: fireflies, warm flickering lights, ring sweep, paper orbit, breathing light synchronized with Luz, dust motes.
- Keep `StillnessDesk` public API and `CheckpointService` contracts stable for levels.
- Update this document and its Engram mirror after every completed task; create Conventional Commits on `feat/stillness-desk-rest-ritual`.

## Out of scope

- Audio assets (no sound pipeline exists; leave named hooks only if cheap).
- New gameplay systems (damage, enemies, save files).
- Copying Hollow Knight presentation or assets; only the interaction principle is borrowed (stay seated until input; a celebration beat on activation).
- Push, PR, merge, or release without a separate user decision.

## Constraints

- Godot 4.7, typed GDScript, AGENTS.md rules, no debug `print()`, no hand-edited `.uid` files, stable referenced node names.
- Raw generated art lives under gitignored `tools/art_sources/*/raw/`; processed runtime art lives under `assets/`.
- The art direction source is `tools/art_sources/checkpoint/concept/stillness_desk_concept_v1.png`. The Luz identity reference is `tools/art_sources/luz/refs/luz_identity_ref.png`.
- Technical artifacts are in English. Commit bodies are in neutral Spanish, with no AI attribution.
- The ~400-line ODD heuristic is advisory only.

## Effective verification mode

- TDD: off (no ODD TDD mode or unit-test runner configured; same source as the parent feature).
- Checks: raw and processed contact sheets plus onion skins inspected per clip and layer; headless `--import` and `--quit-after 120` clean; scratchpad `--script` regression harness for the rest state machine; non-headless screenshots per ritual beat; iPhone device playtest by the user.

## Route and trigger evidence

- Route: delegated direct ODD.
- Mapping: codebase known from the parent feature. This session read the concept, the prior prompt format (`tools/art_sources/luz/prompts/t5_attack_art.md`), and the raw-art ignore rules.
- Writer trigger: fires for every implementation task (multi-file art pipeline plus scene/script work). One bounded writer at a time.

## Delivery forecast

- Estimated authored change: 600-900 lines (manifest/catalog, desk state machine, FX scenes/scripts, prompts, tracker); generated pixels excluded.
- Delivery strategy: `ask-on-risk`. Chain strategy: `stacked-to-main` (user choice, 2026-09-29), one PR per task after the checkpoint PRs.
- Base: stacked on `feat/stillness-desk-checkpoint` at `d013cfb`. Initial reviewed boundary: `3a33a1b` (the T3+T4 range from the parent feature is still pending review).

## Tasks

- [x] **T0 — Design the ritual and record the feature contract**
  - Acceptance: design intent, scope, art decision, and verification are recorded.
  - Evidence: user approved the ritual direction and chose final layered altar art via Codex (2026-09-28).

- [x] **T1 — Luz rest clips spike (mount, sit loop, dismount)**
  - Generate with Codex image generation using the Luz identity reference, an existing in-game sheet, and the concept. Save the prompts under `tools/art_sources/luz/prompts/` and the raw sheets under `tools/art_sources/luz/raw/`. Process them into a runtime sheet and add manifest clips.
  - Acceptance: identity fidelity, consistent scale/baseline with the existing clips, a readable sitting silhouette on a desk-height surface, a backpack drop/pickup that reads, and no cell bleed.
  - Verification: raw + processed contact sheets and onion skins inspected; catalog smoke test; headless load clean.

- [x] **T2 — Layered altar art**
  - Generate the desk body, pendulum, candle, inkwell, papers, floor protractor ring, paper roots, and backpack prop as separate transparent layers, sized so the T1 sitting Luz fits on the desk top. Save the processed layers under `assets/world/stillness_desk/`.
  - Acceptance: matches Luz's rendering and the concept palette; layers are cleanly separable for animation; the desk top height matches the sitting clip.
  - Verification: layer contact sheet plus a composite with the sitting Luz, inspected.

- [x] **T3 — Rest ritual state machine and Luz integration**
  - Replace the `Visuals` placeholders with the T2 layers (keep node names stable where scripts reference them).
  - Phases: mount -> celebrate -> rest loop -> dismount on player input; first-vs-repeat ceremony; backpack prop handoff; Luz positioned on the desk top.
  - Acceptance: public API is stable; interruption (respawn/free) still unpauses and releases; touch and keyboard both release; deterministic repeats.
  - Verification: regression harness (extends the parent's 41 checks), headless load clean, screenshots per beat.
  - Route: delegated direct (writer trigger: desk scene/script, player, service).
  - Result: `Phase { DORMANT, AWAKENED, MOUNT, CELEBRATE, RESTING, DISMOUNT }`; signals `celebration_started(first)`, `celebration_peak`, `celebration_finished`, `dismount_started` (+ existing); exports `first_celebration_duration` 2.4, `repeat_celebration_duration` 0.8, `exit_grace` 0.35 (removed commit/resting/release durations); `breath_period` = 2.0s from `rest_sit`; heal/activate/apply_checkpoint/enemy reset once at peak (ratio 0.4). Player: `play_rest_animation`, `get_animation_length`, `face_direction`, signals `rest_exit_requested`, `rest_animation_finished`, `rest_animation_frame_changed`; exit on just-pressed actions or touch request_* while meditating. Service: `was_ever_activated(id)`. Scene: Sprite2D layers at 0.175, flame AnimatedSprite2D, pendulum pivot node, ring squashed 0.5 and split back/front (+ hidden lit overlay), `SpawnAnchor` at (0,0), Mist and Scale removed.
  - Parent review of screenshots: ACCEPTED — warm altar reads as a shrine in the cold level, seat fit correct, backpack handoff reads, ring grounded (subtle until T4 sweep), arch fits the camera.
  - Known: scene generated by a throwaway script then hand-trimmed; the `.tscn` is now the source of truth. Touch exit covered via `request_jump` only; real-device test pending.

- [x] **T4 — Altar life and celebration FX**
  - Fireflies (beacon idle, gather on celebrate, disperse on dismount), warm flickering lights, floor ring sweep, paper orbit, pendulum still/resume, breathing light synced to the sit loop, dust motes.
  - Acceptance: every effect maps to a ritual beat; Luz silhouette and UI are never obscured; particle budget is bounded.
  - Verification: screenshots per beat, harness checks for beat sequencing, device playtest by the user.
  - Route: delegated direct (writer trigger: FX orchestrator + 6 component scripts + shader + desk/scene + processor). Two interruptions from macOS sleep; resumed after the parent started `caffeinate`.
  - Result: `stillness_desk_fx.gd` orchestrator (pendulum, lights, breath clock, bloom) + `firefly_swarm.gd`, `paper_orbit.gd`, `floor_ring_sweep.gd` (+ `shaders/ring_sweep.gdshader`, additive amber), `altar_motes.gd`, `altar_fx_kit.gd`, `luz_orbit.gd` (face-safe depth rule). Beats: idle → 7 seeded fireflies with a beacon and pendulum ±5.7°/2.4s; awakened is warmer; celebrate → pendulum eases to 0 and holds, fireflies gather, first only: +3 fireflies and a 1.2s clockwise ring sweep (repeat: 0.3s fade); peak → bloom behind Luz (first 1.5x/0.7α, repeat 1.0x/0.3α), papers lift and orbit; resting → glow and ring breathe on `breath_period` re-synced at `rest_sit` frame 0, motion 0.45x; dismount → pendulum resumes, fireflies disperse, papers glide home behind Luz, ring fades. Desk: `_arm_clip_fallback` (length + 0.25s, min 0.5s) fixes R3-001/R3-002; new signal `breath_cycle_started`. De-spill: 0 magenta pixels (from 255), layout md5 unchanged.
  - Parent review: first pass accepted with two fixes (ring payoff too weak; papers crossing the face on dismount); both fixed and re-viewed.

- [ ] **T5 — Regression, device playtest, and recovery record**
  - Run full checks, deploy to the iPhone, and record the playtest outcome, evidence, and the next delivery step.
  - Review fixes applied: shader `x*x` plus clamped radii/softness and atan bias (Metal-safe); paper `z_index` restore; `_usable_count()` array guard; honest `get_fx_node_count()` (36, `FX_NODE_BUDGET` 40); `center_x`; ring `*_alpha` renames; explicit `_reset_to_idle()`; `level_01` null-safe player.
  - Committed test: `tests/stillness_desk_ritual_test.gd` (139 checks; README with the run command); iOS export excludes `tests/*`.
  - Commit: `ceda801` fix: harden Stillness Desk FX and add ritual regression test. Review (range `1a7ace6..ceda801`, 10 paths, 582 lines): `medium`, `slice_budget_reached`; User GRANTED. Lineage `review-9f4b480fca98caa7` (review-reliability) → APPROVED and acknowledged. Reviewed boundary advances to `ceda801`. Findings triage: R3-002 test double-disconnect → not real (the full test log has no error/warning; the desk reconnects per rest). Follow-ups (not blocking): R3-001 `_reset_to_idle` runs on every DORMANT/AWAKENED change, including scene start (idempotent, but confirm no visible pop on device); R3-003 wall-clock duration checks could flake under load (move them to frame-delta time); R3-004 no test drives `_usable_count()` with mismatched arrays.
  - Deploy: iOS export (tests excluded) + xcodebuild + devicectl install/launch on the iPhone 16 Pro OK (2026-09-29). Device playtest: PENDING (user).
  - Verification: headless import/load clean; committed test `PASS 139/139` (writer and parent spot check; about 75s; exit 1 confirmed on a forced failure); ring look unchanged vs T4 screenshots.

- [x] **T6 — Fix: cannot dismount on device (touch)**
  - Device playtest (user, 2026-09-29): "no me deja bajarme, si me muevo o toco cualquier botón no pasa nada".
  - Root cause: the `TouchControls` autoload inherited the pause, so while the tree was paused for the rest its `_input` never ran and no touch reached the player. The committed test called `player.request_jump()` directly and bypassed the real path (a test gap).
  - Fix: `TouchControls` `process_mode = ALWAYS` (safe: the player is input-locked during the rest). Test: new check "rest1 touch controls process while paused". RED observed without the fix (probe `can_process=false`; test `FAIL 1/140`), GREEN with it (`PASS 140/140`); headless load clean.

## Progress

- Current task: T6 fix deployed; design iteration 2 (user feedback) next.
- Next step: record the playtest; then push/PRs (stacked-to-main, user decision). Pending: Codex roots redo once credits are refilled.

## Verification evidence

- T1 first pass: Codex generated mount/sit/dismount (invocation: `codex exec -s workspace-write --skip-git-repo-check -i <identity ref> -i <locomotion sheet> -i <concept> -o <msg> "<prompt>"`). The sit and dismount sheets came back on opaque magenta, keyed out by the new `tools/process_luz_rest_ritual.py`. Processed into `assets/player/luz/luz_rest_sheet.png`; catalog smoke OK; headless load clean.
- T1 parent review (first pass): REJECTED pending fixes. mount frame 4 loses the ruler and floats in a "superman" pose; dismount frames 2-3 show the backpack on her back before the frame-4 pickup; dismount frame 1 drifts about 100px right. Targeted edit pass requested.
- T1 fix pass: mount frame 4 and dismount frames 2-3 edited per frame with Codex (pre-edit sheets kept in `tools/art_sources/luz/raw/edits/`); dismount frame 1 drift corrected with processor `dx`. Parent re-review: ACCEPTED. Mount frame 4 is a coil-and-reach with the ruler held; the backpack first returns at the dismount frame 4 pickup. Minor: dismount frame 3 jacket slightly bluer; edited frames marginally softer (not visible at 0.175). Re-verified: catalog smoke OK (8/4/8 frames, only `rest_sit` loops), headless import and `--quit-after 120` clean. A stray duplicate Codex edit process was stopped by the parent; processed sheet md5 `a8471eb5`.
- T1 clip speeds 8/2/10 fps are provisional; tune in T3 against the desk.
- T2 first pass: 4 Codex runs (desk+arch, roots+ring, props, misc). The Codex sandbox could not copy into the repo, so outputs were copied from `~/.codex/generated_images`. `tools/process_stillness_desk_art.py` (no subprocess) exports 15 layers + `layout.json` to `assets/world/stillness_desk/` (origin = floor under desk centre; seat (0,150); backpack (-125,0); pendulum pivot (0,571), length 167). The lit ring is derived from the unlit one (identical geometry). The desk is stretched 1.2x horizontally to 324 px.
- T2 parent review: desk, arch, pendulum, props, flame, backpack and ring ACCEPTED (seat fit correct; style coherent at game scale). `roots` REJECTED: a central noodle pile hides the desk's centre panel and is rendered painterly. Redo requested as left/right clusters from the legs.
- T2 roots redo BLOCKED: Codex workspace out of credits (2 attempts, 0 images). Interim deterministic fix: `split_roots()` masks the centre ±65px and emits `roots_left.png`/`roots_right.png` pivoted at the legs (x=∓140, z=10); every other layer is md5-identical. Parent viewed the composite: centre panel clear, roots flow from the legs; still the softer painterly render. Pending (user: refill Codex credits): regenerate the roots with the prompt saved in `tools/art_sources/checkpoint/prompts/stillness_desk_layers.md`, then swap the two PNGs.
- T4 headless `--import` + `--quit-after 120`: 0 error/warning/parse lines. T3 harness 90/90 after T4. T4 FX harness `scratchpad/t4.gd` 32/32 (pendulum still <1e-4 while resting, ring alpha lifecycle, sweep only on first, firefly counts 7/10/7, papers home within 1px after dismount and abort, fallbacks advance with the finished signal disconnected, FX process while paused, ≤40 FX nodes, seeded determinism). Perf: 8.32 ms average over 601 resting frames on Mac (vsync-capped); iPhone unmeasured.
- T3 headless `--import` + `--quit-after 120`: 0 error/warning/parse lines. T3 harness `scratchpad/t3.gd`: 90/90 PASS (phase/clip order; backpack visibility 0 bad of 1407 samples; first 2.40s vs repeat 0.80s; effects once at peak; seated >5s idle; held key and grace-window input ignored; exit via action_press, touch request_jump, InputEventAction, real InputEventKey; paused from commit to dismount end; respawn mid-rest in all 4 phases clean; player/desk freed clean; reload at desk; `clear()` resets record). Only SCRIPT ERRORs come from the harness freeing the player (`level_01.gd:32`, pre-existing).
- T2 headless `--import` + `--quit-after 120`: 0 error/warning/parse lines.
- T3 notes from the review: squash the floor ring vertically and split it front/back around the desk (a side-view floor has little depth); ink_box is hidden behind inkwell/paper, so adjust offsets; check the arch (about 103x126 units) against the level ceiling/camera.
- T1 geometry for T2: desk top 150px above the feet row = 26.25 world units (hip height; Luz stands 58); seated head about 68 units; seated body centered on the player x. Backpack prop swaps: off at mount frame 3, pickup at dismount frame 4.

## Commit evidence

- T1: `cd5055d` feat: add Luz rest ritual animation clips (also carries the parent feature's device-playtest note).
- Review (range `3a33a1b..cd5055d`, 17 paths, 804 lines, untracked excluded): risk `high` (`process_boundary` in `tools/process_luz_rest_ritual.py`). Lineage `review-0a2a8a61e728bd07` consent: user `declined` (validated `declined_this_candidate`). Off path, high tier: independent read-only verifier PASSED 4/4. No subprocess/shell/eval in the processor or any `tools/*.py` (the high flag was a false positive); deterministic rerun byte-identical (md5 `a8471eb5`, manifest identical); manifest diff additions only; catalog registers only the 3 clips; headless clean; smoke 8/4/8 frames, only `rest_sit` loops, 24 animations total. Follow-up (low): manifest rewrite is not atomic. Reviewed boundary advances to `cd5055d`.
- Note: the selection submission without `--base-ref/--committed-only` silently widened the target to the whole branch from `46a14d4`; resubmitted with the preflight selectors to match target `7eef734e`.
- T2: `88a5c18` feat: add layered Stillness Desk altar art (39 paths; all intended files staged before commit, no index corruption).
- Review (range `cd5055d..88a5c18`, 39 paths, 1547 lines incl. PNG/.import/layout): risk `high` (`process_boundary` in `tools/process_stillness_desk_art.py`; parent `rg` found no subprocess). Lineage `review-7fda1771e8cf9a4f`: user `declined` (validated). Off path, high tier: independent read-only verifier: safety PASS (no process/eval/exec, writes confined, no deletes; high flag was a false positive), determinism PASS (18/18 md5), headless PASS; asset integrity has a follow-up: 255 faint magenta fringe pixels (alpha ≤29) across 16 layers. Fix scheduled after T3: de-spill/zero RGB for alpha ≤30 in the keyer and re-export. Reviewed boundary advances to `88a5c18`.
- T3: `9bda34e` feat: add Stillness Desk rest ritual phases.
- T3 review (range `88a5c18..9bda34e`, 5 paths, 741 lines): risk `medium`, `slice_budget_reached`. User GRANTED. Lineage `review-f898b12f6a4c766a`, lens `review-reliability` → APPROVED and acknowledged (`gentle-ai.review-acknowledged/v1`). Reviewed boundary advances to `9bda34e`.
- T3 advisory findings (non-blocking, parent triage): R3-001/R3-002 mount/dismount advance only on `animation_finished`, with no timeout fallback → FIX in T4. R3-003 stale wait after abort → no change (abort increments `_run_id`, line 295). R3-004 harness not committed → commit it in T5. R3-005 `request_attack_upgrade` exit → no change (touch always calls `request_attack` first). R3-006 in-memory activation record → documented; no save system exists.
- T4: `1a7ace6` feat: bring the Stillness Desk altar to life.
- T4 review (range `9bda34e..1a7ace6`, 36 paths, 912 lines): risk `high` (processor false positive plus new FX logic). User GRANTED. Lineage `review-e0c973b69fa4b1f3`, 4 lenses (risk, resilience, readability, reliability) run concurrently → APPROVED and acknowledged. Reviewed boundary advances to `1a7ace6`.
- T4 advisory findings, parent triage (all fixed in T5): R3-001 `pow()` with a negative base in `ring_sweep.gdshader:25` (NaN risk on Metal/iPhone) → use a squared term. R3-002 paper `z_index` not restored → save/restore it. R3-003 harness uncommitted → commit it. R3-004 array bounds in `paper_orbit.gd` → clamp/assert. R2-001 `get_fx_node_count` misnamed/miscounts (the ≤40 claim rested on it) → honest count. R2-002 dead `center.y` → `center_x`. R2-003 ambiguous `resting_level` → rename in the ring. R2-004 implicit abort path → an explicit named reset.
- Incident: the GGA hook again wrote index entries with missing blobs (manifest); recovered with `git read-tree HEAD` + re-add; `fsck` clean, history intact. Rule: stage every intended change before committing.

## Rollback boundaries

- T0: remove only this document and its Engram mirror.
- Later tasks record their own boundaries.

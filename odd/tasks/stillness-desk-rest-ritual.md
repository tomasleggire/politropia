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

## Iteration 2 — user feedback (device playtest, 2026-09-29)

Feedback: "Se ve bien", but it can't dismount (fixed in T6). The celebration must be much more noticeable. The altar must read as clearly important, not scenery: more life, more imposing. Altar zones always have fireflies and white roots that point the way to a rest altar; today the roots are not noticeable. The filling floor light is invisible because it is almost flat, so replace it. "Necesito más y mejor en general".

Constraint: Codex is still out of credits (rechecked 2026-09-29), so iteration 2 is in-engine (shaders, lights, procedural geometry, existing components). New art can be layered on later.

Design (parent):
- **Presence from afar**: a warm volumetric light shaft falls from above onto the altar, with drifting dust. It is the only vertical light in the level, so it separates the altar from scenery. Two tall flanking candelabras reuse `gothic_candle.gd`. There is a warm floor light pool, and a warm rim/edge light on the arch and desk.
- **Vertical protractor halo replaces the floor ring**: a procedural clock/protractor sigil (outer ring + 36 ticks + inner ring + hand) behind Luz inside the arch, facing the camera. Dormant: faint engraved and slowly rotating. Awakened: warmer. Resting: ticks breathe with Luz.
- **Celebration (first)** in three staged beats over about 3s:
  1. Stillness: the pendulum stops, an edge vignette dims the world, and the camera eases in on Luz.
  2. Ignition: halo ticks light sequentially clockwise like a clock filling, the shaft swells to a pillar, then a full-ring flare and an expanding shockwave ring.
  3. Release: sparks and fireflies burst from the roots and spiral up into orbit; papers burst outward, then orbit.
  - Repeat: a ~1s condensed version. Dismount reverses the zoom and vignette and returns the shaft to idle.
- **Wayfinding trail**: a new placeable `AltarTrail` component. White paper roots crawl along the floor toward the altar, denser near it, with light pulses travelling along them toward the altar and sparse fireflies along the way. The altar's own roots join it. Placed in `level_01` leading to the desk.

- [x] **T7 — Altar presence**: light shaft + dust, vertical halo sigil (replaces the floor ring), flanking candelabras, floor light pool, rim light; idle/awakened/resting life.
  - Result: `altar_light_shaft.gd` + `light_shaft.gdshader` (200x640 additive beam leaning ~4°, noise striations, 14 falling motes; head/shoulder mask uniforms), `halo_sigil.gd` + `halo_sigil.gdshader` (2 rings, 36 ticks, inner ring, protractor scale, hand; texel-snapped; empty centre; `fill`/`flare`/`intensity`/`spin`/`warmth` + `celebrate`/`peak`/`settle_into_rest`/`set_idle`), `GothicCandle` candelabra mode ×2, floor pool, `rim_light.gdshader`, `altar_drift_sheets.gd`, `Fx/HeadShade` cool-dark backing behind Luz's head. The floor ring and its sweep script/shader were removed (PNGs kept). FX nodes 55 (budget 60).
  - Parent review: from afar the shaft makes the altar read as important; resting is imposing. First pass REJECTED on readability (blonde hair dissolved into the gold beam); fixed with the shaft mask + head shade and re-viewed (hair edge reads).
  - Verification: headless import/load clean; committed test PASS 150/150; perf 8.32 ms Mac.
  - Commits: T6 `a6f852d`; T7 `65f4e6e` (amended from `9a9f0bb`, which a nondeterministic GGA retry committed with a placeholder body. The amend adds the typing fixes GGA flagged, `@export_group("Candle")`, and a real Spanish body). Test runner now reports PASS only for a complete run (`EXPECTED_CHECKS` 150, `EXPECTED_CASES` 4; an injected mid-run error gives `FAIL incomplete run`, exit 1).
  - GGA also flagged pre-existing history outside this feature: `5248ce4` (Cursor co-author trailer, non-conventional subject) and `0e368cb`, `c2d42cf`, `ece0d5d` (AI attribution). Already on merged branches; not rewritten (a user decision).
  - Review (range `ceda801..65f4e6e`, 23 paths, 1088 lines): `medium`, `slice_budget_reached`; User GRANTED. Lineage `review-e0379fa048a76c02` (review-reliability) → APPROVED and acknowledged. Reviewed boundary advances to `65f4e6e`. Findings triage: R3-001 `TouchControls` ALWAYS also runs during any future pause (menu/dialog) → follow-up: when a pause menu exists, gate touch forwarding on a gameplay-input-allowed state; no pause menu today. R3-002 the test still bypasses the real touch path → add an end-to-end injected `InputEventScreenTouch` dismount test in T8. R3-003 the mount-abort case doesn't assert the shaft returns to the awakened level → add in T8.
  - Found: the test runner printed a false "PASS 105/105" when a script error aborted the run midway → fix in T10 (assert the expected total / completion flag; exit 1 on an incomplete run).
  - Risks: shaders unverified on Metal/iPhone; thin halo lines may shimmer on device; additive overdraw unmeasured on iPhone; head mask can drift ≤6 units at the parallax limit.
- [x] **T8 — Staged celebration**: stillness/ignition/release beats, camera ease-in + vignette, halo tick fill + flare + shockwave, root burst sparks, paper burst, repeat variant, dismount reversal.
  - Result: first celebration 3.0s with peak at 1.8s (stillness 0–0.6: pendulum stills, ticks dim, vignette 0.75 max, camera ×1.25 over 0.8s; ignition 0.6–1.8: clockwise tick fill with per-tick spark pops, shaft swell to a pillar; peak: flare + expanding shockwave (0.9s, ~2x halo) + radial bloom behind Luz, effects once; release: 24 root sparks spiral up into orbit, papers burst to 1.7x then orbit). Repeat 1.0s, peak 0.45s (zoom ×1.12, 0.35s fill, 8 sparks, no shockwave/pillar). Dismount pops the camera and vignette over 0.45s; an abort cuts everything instantly. New: `altar_sparks.gd`, `altar_shockwave.gd`, `altar_vignette.gd`, `shockwave_ring.gdshader`, `screen_vignette.gdshader`. `RoomCamera.push_focus/pop_focus/get_focus_weight/get_zoom_ratio` (camera now process ALWAYS). `StillnessDesk.get_celebration_peak_time(first)`. FX nodes 80 (budget 80).
  - Tests: 183/183 complete run — beat order recorder, repeat checks, camera/vignette reset in all abort phases, R3-002 end-to-end `InputEventScreenTouch` dismount via `Input.parse_input_event`, R3-003 shaft back to awakened after mount abort.
  - Parent review: peak strongest and readable from afar; ignition fill legible; Luz readable. Accepted.
  - Commit `e82307e` (GGA passed). Review (range `65f4e6e..e82307e`, 21 paths, 749 lines): `medium`; user GRANTED; lineage `review-c3ff5203375ec726` → APPROVED and acknowledged; boundary advances to `e82307e`. Advisory findings, all queued for T10: R3-001 dismount ease assumes the clip ≥0.45s (cut only on abort, not on normal AWAKENED); R3-002 kill the pending `_beats` tween at the peak; R3-003 wall-clock beat windows could flake (use frame/tween time or wider windows); R3-004 test freeing the desk mid-celebration/rest returns the camera home; R3-005 clamp spark life to a positive minimum.
  - Risks: vignette CanvasLayer 30 (a future HUD above it won't dim); vignette dims outer arch/candelabras a little; repeat halo snaps full→empty before refill; shaders/overdraw unmeasured on iPhone; perf Mac 8.33 ms (vsync-capped).
- [x] **T9 — `AltarTrail` wayfinding component**: procedural white roots + travelling light pulses + trail fireflies; placed in `level_01`.
  - Mechanics done (uncommitted in the working tree): `AltarTrail` (`@tool`; length/direction/trail_seed/density/branch_count/fireflies/desk_path/ground/look/pulse tunables), pulses toward the altar, awakened warm-up, outward wave at `celebration_peak`, trail fireflies (FireflySwarm "Flow" group), desk roots replaced by AltarTrail instances, 2 trails in `level_01`. Test 217/217.
  - Visual pass 1 REJECTED (parent): Line2D ribbons read as a thick glowing cable bridging air over steps; desk roots as big spiral clip-art.
  - Visual pass 2 REJECTED (parent): rasterised pixel strands that hug every block edge read as a white selection/edge-highlight outline, not organic roots; a solid white block on the step face by the desk.
  - Conclusion: an edge-following line reads as artificial; organic pixel-art roots need drawn assets. User decision (2026-09-29): ship the mechanics working technically, with the art done later when Codex resets. Design correction: roots were too invasive; the zone should be SUBTLE, with MORE FIREFLIES that hint the altar is near, not a path that guides directly. → Level trails: roots rendering off by default (`show_roots`), directed pulses only visible with roots; firefly hint field denser closer to the altar, drifting freely (no flow toward the altar). Desk roots stay, subtler.
  - Final: `show_roots` (default true; false on both level trails → no canvas or strands); `root_alpha`/`max_thickness`; desk roots length 40, density 0.9, 4 forks, thickness 2, alpha 0.6, flat under the desk. `FireflySwarm` "Field" mode (`field_span`/`field_direction`/`field_band`/`field_drift`, `base_count`, `get_home_position()`): homes stratified with density rising toward the altar, 10–80 units above ground, free seeded drift + slow rise + blink, warmer when awakened; level trails 12 and 10 fireflies. The raster root renderer (texel-quantised strands, surface-following probe, pulse packets, outward wave) is kept for future art.
  - Parent review of `t9_v10_*`: reads as a subtle hint zone (scattered fireflies thickening toward the altar, no guide line); desk roots faint. ACCEPTED.
  - Verification: import/load clean; committed test PASS 225/225 (complete run).
  - Commit `179c081`. GGA reported FAILED yet allowed the commit ("Could not determine review status", STRICT_MODE=false); parent re-ran `gga run --ci --no-cache`: code typing/naming/grouping pass; violation: oversized test functions (`run_flow_cases` ~193 lines, `run_trail_cases` 173, `run_fx_cases` ~149, `record_celebration` 48) → fix in T10. Pre-existing and out of scope (user decision): hand-authored scene UIDs from `ece0d5d` (`level_01.tscn`, `player.tscn`, `touch_controls.tscn`…) and AI-attribution commits `ece0d5d`, `0e368cb`, `c2d42cf`, `5248ce4`.
- [x] **T10 — Regression, tests, iPhone deploy, and playtest record.**
  - Done: R3-001 via a new `transaction_aborted` signal (only an abort or `_exit_tree` cuts visuals; a normal dismount's 0.45s eases complete even with an early AWAKENED); R3-002 `_kill_beats()` at the peak; R3-005 `MIN_LIFE` 0.05 for sparks; R3-004 desk freed mid-celebration/mid-rest cases. Test split: runner `tests/stillness_desk_ritual_test.gd` + `tests/support/` (harness, suite base, recorder, flow/fx/trail cases): 32 single-purpose cases (longest function 18 lines), per-case `CHECKS` map summed for the expected total, watchdog, game-clock waits with worst-frame slack. PASS 259/259 twice sequentially and with 2 concurrent instances; an injected failure exits 1 and names the check. GGA `run --no-cache`: PASSED. Not covered: no deterministic test for R3-002.
  - Scope: T8 review findings (dismount ease vs clip length; kill `_beats` at the peak; frame/tween-time beat windows instead of wall clock; test freeing the desk mid-celebration/rest; clamp spark life), split the test into small single-purpose case functions (GGA), document/derive `EXPECTED_CHECKS`, full checks, iPhone deploy, record the playtest.

## Iteration 2 playtest (2026-09-30)

- The user tested iteration 2 on the iPhone 16 Pro: "si se ve bien, mejoraremos algunas cosas pero en general está bien". Accepted overall.
- **Pending: a future polish pass. The user explicitly said we will adjust things** (specifics not given yet; ask the user at the start of the next session). Carry into it:
  - The T9+T10 review follow-ups (post-peak no-refill assertion, per-case test timeout, AltarTrail editor probe, reconnecting the desk link on tree re-entry).
  - Codex root art once credits reset (then `show_roots` on level trails).
  - iPhone performance/overdraw measurement.
  - Repeat-rest halo snap, and vignette dimming the candelabras.

## Progress

- Current task: iteration 2 accepted by the user on device (2026-09-30); a polish pass is pending, with adjustments to be defined by the user. T10 committed `b2c43aa`; review of `e82307e..b2c43aa` (26 paths, 3244 lines incl. tests) GRANTED; lineage `review-d0461c1f43c1ff64` (review-reliability) APPROVED and acknowledged; boundary advances to `b2c43aa`. Follow-ups (non-blocking, small): R3-001 assert no halo refill or shaft re-swell after the peak; R3-002 a runtime error after a case's first await stalls until the 600s watchdog (add a per-case timeout); R3-003 `AltarTrail` @tool physics probe runs in the editor even with `snap_to_ground` false (disable physics process in the editor); R3-004 re-entering the tree doesn't reconnect the desk link (reconnect on enter). device playtest of iteration 2 pending.
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

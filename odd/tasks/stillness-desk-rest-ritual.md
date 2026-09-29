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
- Delivery strategy: `ask-on-risk`. Chain strategy: ask before the commit that crosses about 400 lines.
- Base: stacked on `feat/stillness-desk-checkpoint` at `d013cfb`. Initial reviewed boundary: `3a33a1b` (the T3+T4 range from the parent feature is still pending review).

## Tasks

- [x] **T0 — Design the ritual and record the feature contract**
  - Acceptance: design intent, scope, art decision, and verification are recorded.
  - Evidence: user approved the ritual direction and chose final layered altar art via Codex (2026-09-28).

- [x] **T1 — Luz rest clips spike (mount, sit loop, dismount)**
  - Generate with Codex image generation using the Luz identity reference, an existing in-game sheet, and the concept. Save the prompts under `tools/art_sources/luz/prompts/` and the raw sheets under `tools/art_sources/luz/raw/`. Process them into a runtime sheet and add manifest clips.
  - Acceptance: identity fidelity, consistent scale/baseline with the existing clips, a readable sitting silhouette on a desk-height surface, a backpack drop/pickup that reads, and no cell bleed.
  - Verification: raw + processed contact sheets and onion skins inspected; catalog smoke test; headless load clean.

- [ ] **T2 — Layered altar art**
  - Generate the desk body, pendulum, candle, inkwell, papers, floor protractor ring, paper roots, and backpack prop as separate transparent layers, sized so the T1 sitting Luz fits on the desk top. Save the processed layers under `assets/world/stillness_desk/`.
  - Acceptance: matches Luz's rendering and the concept palette; layers are cleanly separable for animation; the desk top height matches the sitting clip.
  - Verification: layer contact sheet plus a composite with the sitting Luz, inspected.

- [ ] **T3 — Rest ritual state machine and Luz integration**
  - Replace the `Visuals` placeholders with the T2 layers (keep node names stable where scripts reference them).
  - Phases: mount -> celebrate -> rest loop -> dismount on player input; first-vs-repeat ceremony; backpack prop handoff; Luz positioned on the desk top.
  - Acceptance: public API is stable; interruption (respawn/free) still unpauses and releases; touch and keyboard both release; deterministic repeats.
  - Verification: regression harness (extends the parent's 41 checks), headless load clean, screenshots per beat.

- [ ] **T4 — Altar life and celebration FX**
  - Fireflies (beacon idle, gather on celebrate, disperse on dismount), warm flickering lights, floor ring sweep, paper orbit, pendulum still/resume, breathing light synced to the sit loop, dust motes.
  - Acceptance: every effect maps to a ritual beat; Luz silhouette and UI are never obscured; particle budget is bounded.
  - Verification: screenshots per beat, harness checks for beat sequencing, device playtest by the user.

- [ ] **T5 — Regression, device playtest, and recovery record**
  - Run full checks, deploy to the iPhone, and record the playtest outcome, evidence, and the next delivery step.

## Progress

- Current task: T2 next (layered altar art).
- Next step: generate the altar layers sized to the 26.25-unit desk top.

## Verification evidence

- T1 first pass: Codex generated mount/sit/dismount (invocation: `codex exec -s workspace-write --skip-git-repo-check -i <identity ref> -i <locomotion sheet> -i <concept> -o <msg> "<prompt>"`). The sit and dismount sheets came back on opaque magenta, keyed out by the new `tools/process_luz_rest_ritual.py`. Processed into `assets/player/luz/luz_rest_sheet.png`; catalog smoke OK; headless load clean.
- T1 parent review (first pass): REJECTED pending fixes. mount frame 4 loses the ruler and floats in a "superman" pose; dismount frames 2-3 show the backpack on her back before the frame-4 pickup; dismount frame 1 drifts about 100px right. Targeted edit pass requested.
- T1 fix pass: mount frame 4 and dismount frames 2-3 edited per frame with Codex (pre-edit sheets kept in `tools/art_sources/luz/raw/edits/`); dismount frame 1 drift corrected with processor `dx`. Parent re-review: ACCEPTED. Mount frame 4 is a coil-and-reach with the ruler held; the backpack first returns at the dismount frame 4 pickup. Minor: dismount frame 3 jacket slightly bluer; edited frames marginally softer (not visible at 0.175). Re-verified: catalog smoke OK (8/4/8 frames, only `rest_sit` loops), headless import and `--quit-after 120` clean. A stray duplicate Codex edit process was stopped by the parent; processed sheet md5 `a8471eb5`.
- T1 clip speeds 8/2/10 fps are provisional; tune in T3 against the desk.
- T1 geometry for T2: desk top 150px above the feet row = 26.25 world units (hip height; Luz stands 58); seated head about 68 units; seated body centered on the player x. Backpack prop swaps: off at mount frame 3, pickup at dismount frame 4.

## Commit evidence

- Pending.

## Rollback boundaries

- T0: remove only this document and its Engram mirror.
- Later tasks record their own boundaries.

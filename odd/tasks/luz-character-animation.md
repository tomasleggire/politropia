# Feature: Luz character animation assets

## Objective
Replace Luz's placeholder/reused movement and combat poses with a cohesive, extensible pixel-art anime animation set that reflects her real movement and attack states while preserving all existing gameplay behavior.

## Problem / Why
Luz's moveset is already implemented, but the current player art only covers a small subset of it; unsupported actions reuse poses or squash effects. The visual gap makes movement and attacks harder to read and prevents the character from feeling complete.

## Scope
- Create character sprite assets and a state-to-animation catalog for existing player behavior.
- Integrate the assets into Godot without moving gameplay authority out of the player code or changing hitboxes, attack windows, state transitions, or movement timings.
- Verify project loading and animation behavior headlessly, in runtime, and on iPhone.
- Keep the asset layout and animation mapping extensible so future frames, states, and character variants can be added without redesigning the integration.

## Out of Scope
- New movement/combat mechanics, balance changes, hitbox or attack-timing changes.
- A double-jump animation or double-jump mechanic; both are future work.
- Enemy/hurtbox behavior, level/UI changes, and unrelated player refactors.

## Visual Constraints
- Preserve Luz's reference identity in faithful anime pixel art: blonde hair, dark-blue urban clothing, backpack, recognizable proportions and palette.
- The wooden ruler is her weapon in every applicable pose; preserve its flat rectangular ruler silhouette and measurement markings so it is never read as a baseball bat or sword.
- Draw the source sheet facing right and use horizontal flip (`flip_h`) for left-facing playback rather than duplicating left-facing art.
- Author frames around the feet origin so Godot's grounded position remains stable; preserve the existing player/collider alignment during import and integration.
- Use a consistent, documented frame grid and keep source/exported assets separable from animation mapping so more frames and states remain easy to add.

## Animation Catalog (Existing States Only)
- Idle: breathing loop.
- Run.
- Crouch.
- Jump ascent.
- Fall.
- Land.
- Ground dash and air dash.
- Wall cling and wall jump.
- Ledge hang and ledge climb.
- Ground attack combo hits 1, 2, and 3.
- Crouch attack, up attack, and air attack.
- Plunge and plunge-land impact.
- Drop-through reuses the crouch-to-fall transition; do not invent a separate gameplay state or required clip.
- Double jump is explicitly future work and excluded from this feature.

## Constraints / Assumptions
- The controller's real states and timing remain authoritative. Animation clips must not add method-call events that trigger gameplay attacks, alter physics, or change hitbox activation.
- Existing code uses a feet-origin player position; preserve it and verify anchoring through jump, landing, crouch, dash, ledge, and attacks.
- Existing attack/hitbox shapes, activation windows, combo buffering, and all player-state transitions remain unchanged.
- Animation playback speed is clip-local: reset `speed_scale` when switching clips so a prior action cannot affect later playback.
- Existing atlas/source art and canvas dimensions must be inspected during T0; do not assume dimensions from old asset guidance without checking the actual source.
- Do not hand-edit generated `.uid` files.

## TDD
- Mode: off.
- Source: inherited from `odd/tasks/blasphemous-movement.md` — no project/session TDD configuration or test framework is recorded in the repository task history. Reconfirm on resume only if configuration changes.
- Runner: Godot 4.7 headless project load; no automated unit-test runner is currently known.
- Exact headless check: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit` (must exit cleanly without script/scene parse errors).
- Exact device harness: `tools/ios/deploy.sh`, followed by the T2 iPhone gameplay/animation scenarios below. Device playtest is required; a successful export/install alone is not an animation check.

## Authorized Scope and Route
- Authorized branch: `feat/luz-character-animation`, created from `main@532bc8e`.
- Authorized changes: Luz character animation source/export assets and the narrowly required player animation integration/scene resources, plus verification fixes strictly required to make those assets load and play.
- No unrelated code or asset cleanup. Preserve gameplay code values and behavior.
- This substantial feature uses delegated direct implementation for asset generation/integration and delegated verification for native runtime/device checks; this task file is its recovery record.

## Delivery
- Strategy: `ask-on-risk`.
- Forecast: approximately 250–400 authored changed lines across integration and any supporting authored metadata; generated sprite pixels/assets are excluded from the authored-line forecast. Recalculate from work-unit commits. If forecast or running authored changes exceed about 400 lines, ask once for chain strategy before the next commit; do not shrink or omit necessary assets/tests to fit.
- Each implementation task closes as a reviewable work-unit commit with its relevant checks and assets/code together. Record exact commit hashes and authored-line count below.

## Tasks
- [x] T0 Generate extensible Luz animation assets (catalog above; right-facing frames, feet-origin, reference fidelity, wooden ruler; consistent frame grid and source/export organization). Route: delegated direct asset-generation work; trigger: multiple animation families and non-trivial frame production need cohesive visual consistency and broad state coverage. Checks: inspected all sheets visually; verified RGBA alpha, exact 1252×1252 dimensions, 4×4 equal 313×313 cells and row-major clip indices. Removed only exact saturated pure-red `(255,0,0)` fringe pixels with alpha 1–2 via deterministic RGBA cleanup; all other RGBA values, including warm/skin tones, were preserved. One directed air-combat edit corrected the duplicated plunge pose/anomalous splash. T0 commits: locomotion `5236d04dc66d8d022dec84a6c11819ce051ec3ce`; mobility `70f1a27a48c8ba96cc4927f608e44a9dd6868056`; ground combat `1f7bd4e2ad333cf6404c4d648754d7fa60e71864`; air combat `2d69c6897c78d3c1741a17712912e79e1cc01dbe`.
- [ ] T1 Integrate animations and state mapping in Godot, including left-facing `flip_h`, stable feet anchoring, safe clip/speed-scale changes, and drop-through crouch→fall reuse. Keep hitboxes, timings, and gameplay transitions unchanged; do not add a double-jump clip. Route: delegated direct writer; trigger: integration requires coordinated scene/resource and player-animation mapping changes, with asset inspection as preparation. Checks: exact headless command above; compare hitbox/timing/state code before and after; exercise all catalogued transitions. Commit: pending.
- [ ] T2 Verify headless/runtime/iPhone behavior; correct only animation/import/integration defects without changing gameplay. Route: delegated verifier after T0–T1; trigger: runtime and iPhone checks require independent environment/device execution and visual inspection. Checks: exact headless command above; run the Godot scene and inspect idle/run/jump/fall/land, crouch/drop-through, ground/air dash, wall cling/jump, ledge hang/climb, all listed attacks and plunge-land; deploy with `tools/ios/deploy.sh` and repeat representative movement/combat transitions on iPhone, confirming frame readability, facing, feet-origin stability, and unchanged hitbox/timing behavior. Record unavailable device checks as pending, never passed. Commit: pending.

## Acceptance Criteria
- Every existing catalogued movement/combat state has the intended readable animation, including distinct ground combo hits 1–3.
- Drop-through visibly transitions from crouch into falling without creating a separate state/clip requirement; double jump remains absent.
- Luz's hair, dark-blue outfit, backpack, and wooden ruler consistently match the reference direction; no bat-like or sword-like weapon pose appears.
- Source art faces right; left-facing playback uses horizontal flipping; feet remain anchored through all tested transitions.
- Headless load succeeds with no script/scene parse errors, Godot runtime transitions play the expected clips, and iPhone checks are completed and recorded.
- Existing movement, hitbox geometry/activation, attack timing, combo behavior, and state transitions are unchanged.
- Asset organization supports adding frames or states later without replacing the integration approach.

## Progress
- Branch `feat/luz-character-animation` created from `main@532bc8e`.
- T0 complete; T1–T2 pending.
- Document work-unit commit: `d592ffe` (`docs: plan Luz character animation assets`).
- T0 assets: `assets/player/luz/` contains four 1252×1252 RGBA sheets; `animation_manifest.json` records 4×4 row-major clips and 313×313 cells. The air-combat sheet uses the single edited output because it removes the duplicated plunge figure/splash. The other three edited outputs did not improve their appearance enough to replace the prior sheets; their fringe was removed through exact-color cleanup. Full-sheet visual readback confirmed right-facing identity, navy outfit, backpack, flat marked ruler, transparent background and no visible red fringe. No source atlas for Luz existed in `assets/player/`; existing player art under `assets/player/adventurer/` and `assets/player/gothic/` is unrelated and was not modified.
- Checks: `sips --cropToHeightWidth 1252 1252 assets/player/luz/*.png` center-cropped one pixel per edge; `sips -g pixelWidth -g pixelHeight -g hasAlpha assets/player/luz/*.png` reported 1252×1252 and alpha present for every PNG. Deterministic cleanup removed exact `(255,0,0)` pixels with alpha 1–2 only (air 9,525; ground 13,442; locomotion 10,602; mobility 10,500); the post-check found zero such pixels and retained the remaining warmer opaque pixels. `jq empty assets/player/luz/animation_manifest.json` and `git diff --check` pass. T0 functional/runtime checks are not applicable; no gameplay integration was performed.
- T0 work-unit commits: `5236d04dc66d8d022dec84a6c11819ce051ec3ce`, `70f1a27a48c8ba96cc4927f608e44a9dd6868056`, `1f7bd4e2ad333cf6404c4d648754d7fa60e71864`, `2d69c6897c78d3c1741a17712912e79e1cc01dbe`.
- Rollback boundary: revert those four commits or remove only `assets/player/luz/`; no gameplay files or generated `.uid` files were changed.

## Next Step
Begin T1: inspect the actual atlas/import settings and preserve these measured dimensions and the existing feet anchor. Do not change gameplay timing, hitboxes, or state transitions.

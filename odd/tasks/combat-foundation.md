# Feature: Combat foundation — damage, death and pip HUD

## Objective
Give Luz a Hollow Knight style damage loop:
- She takes a hit, flinches with knockback and is briefly invulnerable.
- When her health runs out she dies and wakes at the last Stillness Desk with full health, and resettable enemies reset.
- Health shows as pips (3 to start), not a bar with numbers.
- User correction (2026-10-01): the pips are NOT Hollow Knight masks. The final form is probably hearts, still undecided, and Codex makes it under the visual cohesion rule (`docs/ASSETS.md` section 0). Only the behavior is kept: lose a pip, the pip shakes, and the screen shakes slightly.

## Problem
The player has `max_health` (5), `health_changed` and `restore_full_health()`, but no way to take damage or die. No damage source contract exists for future enemies and hazards, and there is no HUD. The Greece playtest showed that without a cost of failure, level design reads as "platforms next to each other".

## Why
This is step 1 of the plan agreed with the user on 2026-10-01: combat foundation, then hazards and enemies, then the Greece v2 redesign, then camera and art polish. Enemies, spikes and the redesign all depend on it.

## Scope
- Player:
  - `max_health` 3.
  - `take_damage(amount, source_position)` with knockback away from the source, a short control lock, i-frames with a flicker, and an optional brief hit-stop.
  - Signals `damaged` and `died`.
  - A death sequence (input locked, short fade), then a respawn at the active checkpoint with full health and `CheckpointService.reset_resettable_enemies()`.
- A reusable damage source component (`ContactDamage` Area2D, `Kind { ENEMY, HAZARD }`):
  - ENEMY re-hits while overlapping.
  - HAZARD (spikes) never lets Luz stand in it: damage, then hit-stop and screen shake, then a brief dark fade back to the LAST SAFE GROUND (user correction, 2026-10-01). A lethal hit uses the death and checkpoint path instead.
- Last-safe-ground tracking in the player: `get_last_safe_ground()`, `return_to_safe_ground()`.
- Subtle screen shake on damage (`RoomCamera.shake`).
- A pip HUD (`HealthHud`):
  - 3 pips, top-left, inside the safe area.
  - Readable losing and refilling feedback.
  - Neutral placeholder drawn in code (a gem or dot, not a mask), swappable by `full_texture` and `empty_texture`. Codex makes the final art.
  - It sits above the vignette (CanvasLayer 30) and below or beside the touch controls.
  - It is in both Greece and level_01.
- One clearly marked placeholder damage source in Greece, so the loop can be felt on the device.
- Regression tests.

## Out of scope
- Real spike placement in levels, and enemies (step 2). The hazard mechanics land in C1.
- Healing by focus or soul.
- Hurt and death art (Codex).
- Greece v2 redesign, wings tuning, camera polish.

## Constraints
- Godot 4.7, typed GDScript, AGENTS.md rules. Commits use Conventional Commits with a body in neutral Spanish and no AI attribution (`GGA_PROVIDER=claude`).
- Must not break the Stillness Desk ritual (heal at peak), the double jump, the room camera or touch controls.
- Physics layers (project.godot): 1 solids, 2 one_way, 3 player_attack, 4 enemies. The player is on layer 1 with mask 3.
- Hit-stop must not fight the desk's `pause_world` or `Engine.time_scale` used by tests.

## Delivery
- TDD: off (no project TDD mode). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.
- Branch: `feat/greece-level`. It is part of completing the Greece zone, and the user chose one branch for everything (single-pr), 2026-10-01.
- RDD: on (default). Reviewed boundary is `9bbdc58` (docs commits since are passive).

## Tasks
- [x] C1 Player damage, i-frames, knockback, death and respawn, plus `ContactDamage` (ENEMY and HAZARD), safe-ground return, screen shake and a Greece placeholder hazard (route: delegated, writer trigger: player + component + camera + level + tests). The hazard, safe-ground and shake parts were added mid-task after user corrections.
  - Commits:
    - `dda2089` feat: add player damage, death and respawn.
    - `b0ccd6f` feat: return from hazards to the last safe ground.
  - Damage:
    - `max_health` 3. Knockback 320/-260, control lock 0.22 s, i-frames 1 s with an alpha flicker.
    - `State.HURT` and `State.DEAD`. A hit restores the air dash and air jump.
    - Hit-stop is a local 0.06 s freeze. `Engine.time_scale` is never touched.
  - Death: a 0.6 s fade, then the checkpoint, `respawn()`, and `reset_resettable_enemies()` once. 1 s of i-frames after waking (a test caught a re-hit). `set_max_health(n)` was added.
  - Hazards and shake:
    - `ContactDamage` `Kind { ENEMY, HAZARD }`. A HAZARD hit: damage, hit-stop, shake, 0.15 s fade out, move to the last safe ground, 0.2 s fade in. A lethal hit uses the death path.
    - Safe ground needs at least 0.1 s on a layer 1 or 2 floor, 24 px from edges and from hazards.
    - `RoomCamera.shake/cancel_shake` move only the offset (3 px for 0.2 s). It is zero after and during death.
  - The Greece placeholder hazard is at Rect2(1240,2704,96,16) on the B2 floor (`GreeceLayout.hazards()`).
  - Out-of-bounds still calls `respawn()` unchanged.
- [x] C2 Pip HUD with 3 neutral pips, lose and refill feedback, safe area, in Greece and level_01 (route: delegated, same writer)
  - Commit: `1e97b23` feat: add the health pip HUD.
  - Layer and placement: `HealthHud` is on CanvasLayer 40 (vignette 30, fade 35, touch controls 100), top-left. It maps `DisplayServer.get_display_safe_area()` on mobile, and `set_safe_area` is the override for tests.
  - Look: `HealthPip` is a neutral ivory gem when full and a dim ring when empty. Textures can replace it.
  - Feedback: a lost pip shakes, flashes and fades over 0.35 s. A refill pops 1.25 to 1 over 0.2 s, staggered 0.08 s.
  - Binding: the HUD rebuilds when max health changes. It binds to the `player` group and listens to `health_changed`.
  - Verification on the final tree `1e97b23`:
    - Import clean.
    - `combat_test` 67/67 and `health_hud_test` 25/25 (the parent re-ran both).
    - Ritual 259/259, double jump 30/30, room camera 38/38, `greece_layout` 70/70.
    - Boot clean.
    - The parent viewed `hud_one_lost.png`: 3 pips top-left, one empty, readable.
  - Review:
    - Range `9bbdc58..1e97b23`, 24 paths, 1589 lines. Assessed `medium`, `slice_budget_reached`. User GRANTED.
    - Lineage `review-3e7663c601c72bb1`: APPROVED, acknowledged. Boundary `1e97b23`.
  - Open:
    - Luz overlaps the hazard during the hit-stop and fade-out (about 0.2 s).
    - No hurt or death art: HURT reuses `fall` and DEAD uses `idle`.
    - No behavioural test that the B2 strip keeps the critical path open (placement only).
- [x] C3 Device playtest (2026-10-01, iPhone, build `3ea2ed7`)
  - User: "se siente bien, se ve bien".
  - Bug: after resting with missing pips, the HUD refills only when Luz stands up. The heal fires at the celebration peak, but `HealthHud` inherits the pause from the desk's `pause_world`, so its tweens freeze until the unpause. Fix in C4.
  - Change: falling out of the map must cost one pip.
- [x] C4 Playtest fixes (route: delegated, same writer as Greece T2b)
  - HUD keeps processing while the tree is paused (`PROCESS_MODE_ALWAYS`), so the refill shows at the peak right after Luz sits.
  - Out-of-bounds fall: 1 damage, then return to the last safe ground (the hazard path). A lethal fall uses the death path. Applies to Greece and level_01.
  - Commit: `0cc0ae9` fix: keep the HUD live while resting and hurt on falls.
  - HUD: `HealthHud` sets `PROCESS_MODE_ALWAYS`. A test asserts the pips are full while paused in RESTING, and it fails when the line is reverted.
  - Falls: `Player.fall_out_of_bounds()` costs a pip even during i-frames (Hollow Knight pits) and still returns her to safe ground. The camera re-snaps on `safe_ground_returned`.
  - Tests: combat 87/87, health_hud 31/31.
  - Review: range `1e97b23..2e268f6` (with T2b), 15 paths, 1233 lines, `medium`. User GRANTED. Lineage `review-6b866f555404910d`: APPROVED, acknowledged. Boundary `2e268f6`.

## Acceptance criteria
- A hit removes one pip, knocks Luz away from the source and gives about 1 s of i-frames with a visible flicker. Repeated contact during i-frames does nothing.
- At 0 pips, Luz dies and respawns at the last desk (or the level start without one) with 3 pips, and resettable enemies reset.
- Resting at the desk refills the pips, and the HUD shows it.
- The HUD is readable on the iPhone, inside the safe area, and never hidden by the touch controls.
- All existing tests still pass.

## Progress
- 2026-10-01: document created after the user approved the plan (3 pips to start).
- 2026-10-01: user corrections: neutral pips, not masks; screen shake on hit; hazards return Luz to the last safe ground. They were sent to the running writer.
- Acceptance addition: a hazard hit costs one pip and returns Luz to the last safe ground. She never stays standing in a hazard.

## Next step
Device check of C4 + T2b, then step 2 (enemies, pogo, soul focus). Decisions are in Engram: `design/enemy-persistence`, `design/enemy-roster`, `design/down-attack-pogo`, `design/soul-focus-heal`.

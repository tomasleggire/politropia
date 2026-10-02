# Feature: Greece enemies, pogo and soul focus

## Objective
Fill Greece with Hollow Knight style combat:
- Four enemy archetypes.
- Enemies that persist per room.
- A pogo down slash that replaces the plunge.
- A soul meter that Luz spends to heal.

Step 2 of the agreed roadmap (2026-10-01).

## Problem
Luz can take damage and die, but there is nothing to fight. The plunge does not support Hollow Knight style level design, and there is no way to heal outside the altar.

## Why
Enemies and pogo give jumps and rooms real pressure and options. The Greece v2 redesign (step 3) depends on this vocabulary.

## User decisions (2026-10-01, Engram `design/*`)
- **Persistence:**
  - Killed enemies stay dead until a desk rest or death. Their corpses stay visible where they died until then.
  - Living enemies reset to their spawn point at full health when Luz re-enters the room.
- **Roster:** Walker (Crawlid), Flyer (Vengefly), Shooter (Aspid), Charger (Husk). Codex designs the Greek look later.
- **Down attack:** a Hollow Knight pogo.
  - Hitting an enemy or a spike bounces Luz up and restores her air dash and double jump.
  - The PLUNGE is removed.
- **Healing:**
  - Hits fill a soul meter.
  - Holding a focus button spends soul to heal 1 pip. Luz stands still and is vulnerable for about 1 s.
- **Tuning:** close to Hollow Knight; adjusted after playtests.

## Scope
- Enemy base: health, hurt flash, recoil when hit, death into a corpse, contact damage via `ContactDamage` ENEMY, the `checkpoint_resettable` contract, and room persistence through `room_changed`.
- The four archetypes, with code placeholders only.
- Player:
  - Hit recoil on landing a hit.
  - The pogo.
  - Removal of PLUNGE and PLUNGE_LAND.
- Soul meter, focus heal, HUD meter, and a touch button.
- Placement of enemies and real spikes in the current Greece layout, so it can be tested on the device. The final placement comes in Greece v2.

## Out of scope
- Art and animation (Codex).
- The boss Artemis.
- Medals and doors.
- Saving to disk.
- The Greece v2 layout.

## Constraints
- Godot 4.7, typed GDScript, AGENTS.md. Commits use Conventional Commits with a body in neutral Spanish, no AI attribution, and `GGA_PROVIDER=claude`.
- Physics layers: 1 solids, 2 one_way, 3 player_attack, 4 enemies.
- Don't break any existing test suite: ritual, double jump, room camera, transitions, combat, HUD, Greece layout.
- Keep the mobile frame budget. Enemies should be cheap: simple raycasts and no per-frame allocations.

## Delivery
- TDD: off.
- Branch: `feat/greece-level` (single-pr).
- RDD: on. Boundary `2e268f6`.

## Tasks
- [x] E1 Enemy base, room persistence service with corpses, player hit recoil, and the Walker archetype (route: delegated)
  - Commit: `e74e0ae` (+1051/-4).
  - Hit seam: `AttackHitbox.attack_hit` goes to `Player._on_attack_hit`, which calls the deferred `target.receive_hit(damage, pos, attack_name)`. `attack_damage` is 1.
  - `EnemyRegistry` is an autoload. It holds the killed set, which survives reloads, and has an injectable `room_resolver`. The home room is `camera_room(room_for(spawn))`.
  - Rules:
    - Rule 2 runs on `room_changed`, via `enter_room(to)`.
    - Rule 3 runs through the existing `reset_resettable_enemies()` from the desk and the respawn, after the respawn move.
  - AI and gravity are paused for enemies off the current room. Luz is a collision exception, since she shares layer 1.
  - Enemy hit: 0.08 s flash, 0.04 s local hit-stop, 160 px/s recoil. Luz recoil: 120 px/s for 0.08 s, lateral only.
  - Walker: 2 HP, about 60 px/s, turns at ledges and walls.
  - Tests: `enemy_test` 62/62 (the parent re-ran it: 62/62).
- [x] E2 Pogo down slash that replaces the plunge (route: delegated, same writer as E1)
  - Commit: `ffe60f9` (+530/-81).
  - Down slash: 36x44 hitbox below the feet. `pogo_height` 130 (about -722 px/s), once per slash.
  - Hazard grace: 0.12 s, plus refusal while the slash covers the hazard.
  - New physics layer 5 `pogoable` (value 16), which HAZARDs join automatically. The attack mask changed from 8 to 24.
  - PLUNGE and PLUNGE_LAND were removed. Their clips stay unused for Codex. Touch uses pad-down + attack, or a down-swipe upgrade.
  - Tests: `pogo_test` 44/44 (the parent re-ran it: 44/44). All other suites pass (combat 87, HUD 31, transitions 49, camera 38, layout 70, double jump 30, ritual 259).
  - Review:
    - Range `2e268f6..ffe60f9`, 21 paths, 1739 lines, `medium`. User GRANTED.
    - Lineage `review-1b72dd716c08dce7`: APPROVED, acknowledged. Boundary `ffe60f9`.
  - Open:
    - Pogo off an enemy has no contact grace; landing back on it hurts.
    - The down slash has no VFX (Codex).
    - `walker.tscn` was written by hand without a uid.
- [x] E3 Flyer and Charger (route: delegated; the writer hit an API session limit mid-task and was resumed with its context)
  - Commit: `8ed2217` (+947).
  - Code structure: `FlyingEnemy` is the shared airborne base. `Charger` extends `Walker`.
  - Flyer: aggro 220 px, 420 px/s² up to 150 px/s, lateral 0.55 (overshoot). Gives up after 2.5 s or a 420 px leash and returns at 110 px/s. Knockback 340. 2 HP.
  - Charger: patrol 50, detect 260 px x ±60 px with sight, telegraph 0.45 s, charge 300 px/s for 1.1 s, recover 0.6 s. Telegraph hits don't stagger it; charge hits apply 0.25 recoil. 3 HP.
- [x] E4 Shooter and projectiles
  - Commit: `3defa7f` (+516/-5).
  - Shooter: aggro 300, holds 170 to 230 px with its centre 60 px above Luz. Fires every 1.6 s after a 0.35 s swell: 3 shots at ±15° and 210 px/s. Needs sight. 2 HP.
  - Projectile: 1 damage. Dies on solids, on Luz, after 3 s, or to a slash (no recoil or pogo). Pooled at 2 x volley.
  - Projectiles are cleared on `set_ai_active(false)` (room change), on `_reset_ai`, and on the shooter's corpse.
  - Sight checks: a single raycast against layer 1, throttled to 0.1 s.
  - Tests: `enemy_archetypes_test` 111/111, 3 runs (the parent re-ran it: 111/111). All other suites green.
  - Review: range `ffe60f9..3defa7f`, 18 paths, 1487 lines, `medium`. User GRANTED. Lineage `review-c70b1ea160950538`: APPROVED, acknowledged. Boundary `3defa7f`.
  - Open:
    - Tests use private members.
    - `charger.gd` hard-codes its sight offsets.
    - A flyer whose path home is walled off can get stuck.
    - Flyer and shooter spawn positions are origin-at-feet; account for this in E6 placement.
- [x] E5 Soul meter, focus heal, HUD meter, touch button (route: delegated)
  - Commit: `00ed923` (+802/-4).
  - Soul: `max_soul` 99, `soul_per_hit` 11, `focus_cost` 33, `focus_time` 0.9 s. Only hits that damage an `enemies` group member give soul. Death resets soul to 0.
  - Desk rest leaves soul unchanged (user decision 2026-10-01, matches Hollow Knight).
  - Focus: `State.FOCUS`, which chains while held. Release, damage, leaving the floor, an input lock, or movement, jump, attack or dash cancels it without spending soul.
  - Input: the `focus` action is F or joypad button 9.
  - UI:
    - `SoulMeter` is a 44 px vessel under the pips, with a pulsing cue at 33 or more. Textures can be exported for Codex.
    - The touch `FocusButton` sits left of Jump and shows only when focus is available.
  - Tests: `soul_focus_test` 52/52, 3 runs (the parent re-ran it: 52/52). All other suites green.
  - Review:
    - Range `3defa7f..00ed923`, 11 paths, 828 lines, `medium`. User GRANTED.
    - Lineage `review-7b96ddfc4a244354`: APPROVED, acknowledged. Boundary `00ed923`.
  - Open:
    - Focus uses the `idle` clip (Codex needs a focus clip and glow).
    - `HealthHud.bind_player` before `_ready` would fail.
    - The joypad button choice is arbitrary.
- [ ] E6 Place enemies and real spikes in the current Greece layout, then a device playtest (route: delegated)
  - Commit: `f62be82` feat: populate Greece with enemies and spikes (+455/-33).
  - Data: `GreeceLayout.enemies()` returns `{archetype, enemy_id, position, facing}`. `hazards()` returns 3 spike rows (group `greece_spikes`).
  - Placement:
    - B2 walker (1700,2720) and spikes (1320,2704,96,16).
    - Shaft flyers at (1680,1641) and (1680,911).
    - Alcove pit spikes (2040,1480,220,16).
    - T1 flyer (485,421) and pit spikes (380,628,210,16).
    - T2 charger (2260,544) and shooter (2290,204).
    - Exit shooter (2330,1754).
    - B3 walker (3300,2720) and charger (3440,2720).
    - Entrada, Altar and T3 are empty.
  - Fairness:
    - Every spawn is at least 220 px from arrivals, the spawn and the desk.
    - Reachability with spikes treated as non-standable still passes. The B3 side still needs the double jump.
    - A running jump over the B2 spikes takes no damage.
  - Extra changes:
    - The T1 camera view merges the pit (`T1_PIT_VIEW`).
    - The B2 spikes moved to x 1320 for runway.
    - `Probe.load_level(populated := false)` strips enemies and spikes for geometry probes.
  - Tests:
    - `greece_population_test` 33/33, 3 runs (the parent re-ran it: 33/33). `greece_layout_test` 70/70. All suites green.
    - The parent viewed the overview screenshot.
  - Review:
    - Range `00ed923..f62be82`, 8 paths, 510 lines, `medium`. User GRANTED.
    - Lineage `review-fcb291502e38d3be`: APPROVED, acknowledged. Boundary `f62be82`.
  - Open:
    - The B2 walker patrols up to the arrival points.
    - Alcove pit spikes cover its floor; the way out is the hazard return or a pogo.
  - Pending: device playtest.

## Acceptance criteria
- Each archetype behaves as described, damages Luz on contact, and dies to her attacks.
- Persistence follows the user's rules exactly, including visible corpses and the reset on desk rest or death.
- A pogo off an enemy or a spike bounces her and restores her air actions. The plunge no longer exists.
- Focus heals 1 pip for the soul cost and is cancelled by a hit.
- All suites pass, and the game runs smoothly on the iPhone.

## Progress
- 2026-10-01: document created. Decisions are recorded in Engram.

## Next step
E6 device playtest, then the next PR (E5 + E6), then Greece v2.

Delivery update (2026-10-02): staged PRs from `feat/greece-level` with merge commits. The user merges `e5c9159` now.

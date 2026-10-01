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
- [ ] E1 Enemy base, room persistence service with corpses, player hit recoil, and the Walker archetype (route: delegated)
- [ ] E2 Pogo down slash that replaces the plunge (route: delegated, same writer as E1)
- [ ] E3 Flyer and Charger
- [ ] E4 Shooter and projectiles
- [ ] E5 Soul meter, focus heal, HUD meter, touch button
- [ ] E6 Place enemies and real spikes in the current Greece layout, then a device playtest

## Acceptance criteria
- Each archetype behaves as described, damages Luz on contact, and dies to her attacks.
- Persistence follows the user's rules exactly, including visible corpses and the reset on desk rest or death.
- A pogo off an enemy or a spike bounces her and restores her air actions. The plunge no longer exists.
- Focus heals 1 pip for the soul cost and is cancelled by a hit.
- All suites pass, and the game runs smoothly on the iPhone.

## Progress
- 2026-10-01: document created. Decisions are recorded in Engram.

## Next step
E1 and E2.

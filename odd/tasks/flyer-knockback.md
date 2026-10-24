# Flyer knockback

## Objective
Flying enemies (Flyer, BookFlyer, ShadowOwl) are pushed back, away from Luz, when her attacks land.

## Problem
`Enemy.knockback_from_player_attacks` defaults to `false`, so `receive_hit` skips `_start_recoil` for every `attack_*` hit. Flyers inherit that gate, and `FlyingEnemy._start_recoil` zeroes `velocity.y`, so even the existing recoil is horizontal only.

## Why
Assigned team task: hitting a flyer must visibly shove it back, which gives the player breathing room in the air.

## Scope
- Enable player-attack knockback for flying enemies only. Walkers stay unaffected (`tests/enemy_test.gd` `case_player_recoil_on_hit` must keep passing).
- Push direction is 2D: away from Luz's body center, so `attack_up` knocks a flyer upward.
- ShadowOwl: a landed hit interrupts WINDUP/DIVE/CHARGE and sends it to RECOVER, so the push is not overridden by `velocity = _charge_direction * charge_speed`.
- Bosses are never knocked back (user requirement, 2026-10-24). Artemis extends `Enemy` directly and overrides `_start_recoil`; T1 adds a regression check.
- Out of scope: walkers, boss logic, the map work (next feature).

## Constraints
- Godot 4.7 GDScript conventions from AGENTS.md (typed, `@export_group`, no debug prints).
- Keep existing per-scene recoil overrides (flyer/book_flyer 340/0.18, shadow_owl 300/0.15) unless tuning is needed.

## Delivery
- Branch: `fix/player-missing-texture` (user decision: all current work on this branch).
- Strategy: ask-on-risk. Forecast: ~120 authored changed lines.
- TDD: off (source: project convention, same as previous features). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.

## Tasks
- [x] T1 — 2D knockback for flyers from player attacks, with tests in `tests/enemy_archetypes_test.gd`. Route: delegated direct (writer trigger: flying_enemy.gd + shadow_owl.gd + tests).
  - `Enemy._apply_recoil()` hook (walkers keep x-only); `FlyingEnemy._init` enables `knockback_from_player_attacks`, 2D `_recoil_vector` away from Luz's center; `ShadowOwl` hit in WINDUP/DIVE/CHARGE goes to RECOVER. Shooter inherits it.
  - `case_flyer_light_knockback_and_corpse` source moved from y=-100 to y=-71 (Luz's feet for a center at -100), otherwise the 2D push pointed down.
  - Evidence: enemy_archetypes FAIL 6/107 (base 6/100, same six cases; 3 new cases pass); enemy FAIL 5/62 (= base, `case_player_recoil_on_hit` passes); combat incomplete 147/153 (= base); boss suite via stillness_desk_ritual_test incomplete 452/702 with 13 failing cases (matches the 13 known base failures), new `case_never_knocked_back` passes; zone_1 boot clean.
- [x] T2 — Device check on iPhone: the push reads well, does not shove flyers through walls, ShadowOwl dive is interrupted.
  - Evidence: user played a5110c3 on the iPhone on 2026-10-24 and approved the flyer push ("Se ve bien el volador").

## Acceptance criteria
- A landed `attack_ground_*` hit moves a Flyer away from Luz horizontally; `attack_up` from below moves it up.
- A hit during ShadowOwl CHARGE stops the charge and pushes it back.
- Walker slash recoil stays off.
- `enemy_test.gd`, `enemy_archetypes_test.gd`, `combat_test.gd` pass (or match base failures).

## Checks
- `enemy_archetypes_test.gd`, `enemy_test.gd`, `combat_test.gd`.

## Progress
- Mapped: knockback gate at `scripts/enemies/enemy.gd:185`, recoil applied in `_physics_process` (`enemy.gd:130-134`, x only), `FlyingEnemy._start_recoil` (`flying_enemy.gd:119`).

## Next step
T1.

# La Hidra (optional Greece boss)

`scripts/enemies/bosses/hydra_boss.gd` (`class_name HydraBoss`, extends `BossEnemy`), the head part `scripts/enemies/bosses/hydra/hydra_head.gd` (`HydraHead`), two helpers (`hydra_tiers.gd`, `hydra_venom.gd`), the scene `scenes/enemies/bosses/hydra.tscn` and the one-drag prefab `scenes/enemies/bosses/hydra_boss_arena.tscn`. Try it in `scenes/levels/test/hydra_arena.tscn`. Base docs: `BOSS_ENEMY.md`, `BOSS_ARENA.md`.

A target-priority and platforming fight. A static body at the right wall has three heads at three heights. Luz climbs the platforms to reach them and must kill all three. A killed head stays as a stump and the others get fiercer, so the order Luz picks changes the fight.

## Placing the prefab

1. Drag `hydra_boss_arena.tscn` into the level (the origin is the floor line, the default `arena_rect` is `(-468, -480, 936, 480)`).
2. `boss_name` is "La Hidra", the boss `enemy_id` is `greece_hydra` (unique per run), `reward_enabled` is off. Nothing else to wire.
3. The body places itself `right_wall_margin` (68 px) from the right wall of whatever `arena_rect` you give it, and the sweep runs to the left wall. The floor is the y of the boss at spawn.
4. Only `ArtemisBoss` ends the game; the Hydra opens the arena and the level music returns.

## Layout and platform rules

- The root body is not hittable (`_root_layer()` is 0) and hurts on touch. The heads (`Heads/LowHead`, `MidHead`, `HighHead`) are `Area2D` hurtboxes on layer 8.
- The heads rest at the lowest level, the middle level and the highest level read from the platforms, 190 px left of the body and 34 px above their level.
- Platforms live in `Platforms` (a child of the arena root, not of the boss): one-way `StaticBody2D`s on collision layer 2 in the group `hydra_platform`, each with a `CollisionShape2D` rectangle. The boss reads them when the fight starts (and on reset), so **you can move, add or remove platforms freely**; the heads, the sweep bands and the venom spots follow. Keep three rules: steps of about 56 px between levels (one jump is 120 px), a standing place near each head, and every platform reachable from another surface by one jump.
- Shipped layout (arena-local, surface y; floor 0): `PlatformLowLeft` (-280, -56), `PlatformLowRight` (-80, -56), `PlatformMid` (100, -112), `PlatformUpper` (-40, -168), `PlatformTop` (130, -224); each 160 px wide. Levels: 0, -56, -112, -168, -224. Low head at 0, mid head at -112, high head at -224.

## Heads

| Head | Level | Colour | Attack |
|---|---|---|---|
| Biter | low | red | `BITE_LUNGE` |
| Sweeper | mid | violet | `NECK_SWEEP` |
| Spitter | high | green | `VENOM_VOLLEY` |

Each head has 12 health; the boss pool (36) always equals the sum of the heads. A hit on a head is clamped to what it has left and runs the base `receive_hit`, so the bar, the engage gate and the final blow are the base's. Soul: heads are not in the `enemies` group (tests and probes cast that whole group to `Enemy`), so the boss gives Luz her `soul_per_hit` itself on every landed hit.

## Attacks

| Attack | Telegraph | How to avoid it |
|---|---|---|
| `BITE_LUNGE` (biter) | 0.9 s red aim line that tracks Luz and locks for the last 0.15 s | Leave the locked point before the neck arrives (about 0.3 s). The head then sits stuck for 0.8 s: hit it. |
| `VENOM_VOLLEY` (spitter) | 0.8 s amber markers on the floor and platforms (the first under Luz, the rest fanned out), kept until each glob lands | Step off the marked spots. Each puddle hurts for 3.5 s, so it also denies ground. |
| `NECK_SWEEP` (sweeper) | 0.95 s red band on the tier Luz stands on (floor, mid or high), locked at the start | Change tier. The band is 56 px tall: a stair between two tiers is safe. |

Every telegraph is at least 0.35 s. A hit never cancels an attack (super armor on, stagger off).

## Pacing and what changes per dead head

- Three heads (phase 1): one head attacks at a time, drawn among the living heads with no immediate repeat.
- Two heads (phase 2): the living heads attack as a duo; the second starts `duo_offset` (0.7 s) after the first, so attacks overlap.
- One head (phase 3): frenzy. The head draws any of the three attacks (its own counts `frenzy_native_weight` times more); the other two are weaker versions (2 globs, 0.8x speed, slower telegraph). Recoveries and pauses shrink to 0.6x; its own attacks are 1.2x faster. The stuck window of the bite is never shortened.
- Per dead head: telegraphs x0.85 (never under 0.35 s), one more venom glob, sweeps 25% faster. Each death triggers the base phase beat (roar) and cancels what the dead head was doing.
- Phases (3, 2, 1 heads) are driven by head deaths; `phase_thresholds` only feeds the bar notches.

## Death, reload and reset

- The last head's death takes the pool to 0: the base final blow runs and the body slumps; all heads are severed and no hazard remains.
- A reload after defeat (`make_corpse_at`) shows the body dead with all three heads severed.
- A desk rest or Luz's death (`reset_to_spawn`) restores three full heads, clears every hazard and leaves the boss fresh.

## Tunables worth knowing

All are exported and grouped on `HydraBoss`: Layout (`right_wall_margin`, `head_rest_height`), Biter (`bite_telegraph`, `bite_lock_time`, `bite_speed`, `bite_reach`, `bite_stuck_time`), Spitter (`venom_count`, `venom_spacing`, `venom_interval`, `venom_flight_time`, `venom_pool_time`, `venom_pool_width`), Sweeper (`sweep_telegraph`, `sweep_speed`, `sweep_band_height`), Enrage, Weak Versions, Duo and Testing (`auto_attack` off keeps the boss passive so you can call `start_attack`). Head health, rest offset, shoulder and colour are exports of `HydraHead`.

## Tests

`tests/hydra_boss_test.gd`.

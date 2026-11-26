# BossEnemy: the shared boss base

`scripts/enemies/bosses/boss_enemy.gd` (`class_name BossEnemy`, extends `Enemy`) plus the inheritable scene `scenes/enemies/bosses/boss_enemy.tscn`. Arena side: `docs/bosses/BOSS_ARENA.md`. Artemis predates it and keeps its own script.

## What the base gives you

- The duck-typed contract `BossArena` calls: `set_manual_engage`, `engage`, `set_arena_limits`, `play_intro`, `is_fresh`, the signals `phase_changed`, `defeated`, `corpse_settled`, `sfx_cue`, and a boss that refuses hits until the arena engages it.
- A state machine: IDLE (awaiting the arena), FIGHT (movement), ATTACK (TELEGRAPH, ACTIVE, RECOVER), FLINCH, STAGGER, STUN, TRANSITION, DEFEATED. Timers run in physics time inside `_think`, so hit-stop pauses them. No telegraph is shorter than `MIN_TELEGRAPH` (0.35 s).
- Phases from `phase_thresholds` (descending health ratios, `[0.66, 0.33]` is three phases), with a transition beat (`phase_transition_time`) during which the boss does not attack but can be hit.
- Optional hit-count stagger (`stagger_hits`, off at 0), a public `stun(duration)`, optional interruptible telegraphs (`super_armor`, on by default).
- The Artemis final blow, defeat slump, corpse settle and `corpse_settled`; reset to a fresh state; no knockback; the `Sfx/<Cue>` system; a projectile pool; hitbox and Luz helpers.

## Hooks to override

All are virtual with safe defaults; none requires overriding `_think`.

| Hook | When |
|---|---|
| `_choose_next_action() -> int` | The fight delay elapsed: return an attack id or `NO_ATTACK` |
| `_update_fight(delta)` | Every frame between attacks (movement) |
| `_tick(delta)` | Every frame in every state (beat clock, noise meter) |
| `_fight_delay()` | Seconds of movement before the next choice |
| `_telegraph_time / _active_time / _recover_time(attack)` | Durations of an attack |
| `_begin_attack_phase / _update_attack_phase / _end_attack_phase(attack, phase)` | Run the attack. `_end_attack_phase` also runs when it is cut short, so cleanup lives there |
| `_on_phase_entered(phase)`, `_on_transition_started(phase)` | A phase was reached, then its beat starts |
| `_on_stunned(duration)`, `_on_stun_ended()` | Punish windows |
| `_clear_hazards()` | Defeat, reset, AI off. May run during the base `_ready`: touch only existing nodes |
| `_accepts_hit(damage, source)` | Return false to refuse a hit |
| `_update_facing()` | Override to keep a facing |
| `_root_layer()` | Collision layer of the root while hittable (default 8) |

Helpers: `_draw_attack(weights)` (weighted, skips the last attack, seeded through `rng_seed`), `_set_hittable(on)`, `_set_hitbox(area, on)`, `_hurt_luz_once(area, damage)`, `_launch_projectile(scene, from, dir, speed)`, `_arena_bounds()`, `_clamp_to_arena(x)`, `_aim_at_luz(from)`, `_dir_to_luz()`, `play_cue(cue)`.

## Attacks

Declare your own `enum Attack`; the base only sees `int` ids. Give the weights array one entry per id, in enum order. A hitbox is an `Area2D` armed with `_set_hitbox` (deferred) and polled with `_hurt_luz_once`, which hurts Luz once per activation.

## Phases driven by events

Set `phases_from_health = false` and call `_advance_phase()` (or `_enter_phase(n)`) from your own event, for example a head dying. It does exactly what a threshold crossing does. `phase_thresholds` may still be filled for the bar notches.

## Temporarily untargetable

`_set_hittable(false)` (as Artemis does in her dive) clears the root collision layer and makes `receive_hit` refuse every hit, from the body or from a part. `_set_hittable(true)` restores `_root_layer()`.

## Multi-part bosses

Make each part an `Area2D` on layer 8 whose `receive_hit(damage, source, attack_name) -> bool` forwards to the boss's `receive_hit`. The shared health pool, the `hit` signal (bar), phases, engage gate and final blow all run in the base. If the root must not be hit directly, return 0 from `_root_layer()`: reset restores that value, not a fixed 8.

## Prefab recipe

1. New scene inheriting `boss_enemy.tscn`, script `extends BossEnemy`.
2. Wrap it in a scene inheriting `boss_arena.tscn`; set `boss_name`, a unique `enemy_id`, `reward_enabled = false`.
3. Only `ArtemisBoss` ends the game; other bosses open the arena and the level music returns.
4. Notches: `phase_two_threshold` is the first threshold; every further threshold gets its own notch.

## Tests

`tests/boss_enemy_test.gd` with `tests/support/dummy_boss.gd` / `.tscn` as a minimal example subclass.

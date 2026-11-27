# El Topo (the Blind Beast)

Audience: level designers and the boss team. An optional library boss, a **perception fight**: the blind old man of the side quest is a giant mole. He cannot see Luz. He hears and feels her. The right answer is to slow down.

- Script: `scripts/enemies/bosses/blind_beast_boss.gd` (`BlindBeastBoss`, extends `BossEnemy`). Code names are creature-neutral: another creature is only a re-skin.
- Scenes: `scenes/enemies/bosses/blind_beast.tscn` (the boss), `scenes/enemies/bosses/blind_beast_boss_arena.tscn` (the one-drag prefab), `scenes/levels/test/blind_beast_arena.tscn` (test room).
- `enemy_id`: `library_blind_beast`. Arena `boss_name`: "El Topo". `reward_enabled` is off. 30 health, phases at 0.66 and 0.33, `super_armor` on, stagger off. He never triggers `GameCompletion`.
- Tests: `tests/blind_beast_boss_test.gd`.

## The noise rules

The beast polls Luz's public API. Nothing in `player.gd` changes.

| | What counts | How it is read |
|---|---|---|
| LOUD | Landing after being airborne for `landing_min_air_time` (0.15 s) | `is_on_floor()` edge |
| LOUD | A dash starting | `is_dash_invulnerable()` edge (needs `dash_invulnerable` on, the default) |
| LOUD | An attack swing starting (ground, air, up, crouch) | `is_attack_starting()` edge |
| LOUD | Hyperfocus | `open_eyes_activated` |
| QUIET | Walking, standing, the jump take-off | nothing |
| STILL | Grounded, slower than `still_speed`, and `still_grace` seconds since the last loud action | `is_luz_still()` |

Each loud event stores a **noise spot** (Luz's x on the floor line) and draws a **ripple**: the newest is the brightest. He remembers the last `noise_memory` (3) spots. A hurt knockback that ends in a landing is also a landing. A noise beyond the wall is clamped to the arena.

## The loop

1. **Burrowed** (default): untargetable (`_set_hittable(false)`), body hidden, a small moving dirt mound shows where he is (`show_mound`, on by default, for fairness).
2. He tunnels (`tunnel_speed`, 220 px/s) to the newest noise spot he has not answered.
3. **Cracks** open there (red, `crack_time` 0.5 s), then a column (56 x 90 px) bursts and hurts once.
4. He is **exposed** above ground and hittable: `exposed_hit_time` (0.8 s) if the column hit Luz, a disoriented `stun` of `missed_stun_time` (1.8 s) if it missed. Then he digs in (`dig_in_time`, untargetable at once).
5. **Anti-stall:** if he heard nothing for `patience_time` (4 s) he probes: three evenly spaced, telegraphed eruptions sweeping the arena, then he surfaces for `probe_exposed_time` (1.2 s).

6. **Never stuck:** if the tunnel makes no headway toward the noise for `stuck_tunnel_time` (3 s: a wall, a step in the floor, no arena limits, `tunnel_speed` 0), he erupts where he is, at the closest point he could reach, and the noise counts as answered. A normal tunnel keeps closing in, so crossing the whole arena never trips it. If the weighted draw comes back empty (every weight zeroed), the plain ERUPTION answers the noise instead. Either way he surfaces and can be hit: Luz is never left with an untargetable boss that does nothing.

Contact damage stays off for the whole fight: every hurt comes from a telegraphed hazard.

## Attacks

Telegraph colours follow `BossTelegraph`: red melee, amber ranged. No telegraph is under 0.35 s.

| Attack | Phase | Telegraph | How to avoid it |
|---|---|---|---|
| ERUPTION | 1 | Red cracks and a column outline at the newest noise spot, 0.5 s | Do not stand at the spot you made noise at. Walk away quietly |
| PROBE | 1 | Three red cracks at once, 0.5 s for the first, 0.4 s longer for each next | Stand between the cracks; bursts go one after another |
| CLAW_COUNTER | 1 | Red zone (120 x 60 px) at where the swing came from, 0.45 s, while he is exposed and not stunned | Leave the spot you swung from. It never follows you |
| BRAILLE_RIDGE | 2 | A bump on every floor slot, raised ones bright red and taller, 0.8 s | Stand on a flat slot. Spikes rise left to right and retract |
| DEBRIS_TOSS | 2 | An eruption plus three rocks with amber floor markers, 0.8 s of flight | Stay off the markers and out of the column |
| TREMOR_PULSE | 3 | He surfaces and glows red, 0.7 s, then slams: a pulse travels both ways at 260 px/s | **Stand still** or be airborne as it passes. A moving grounded Luz is felt: three fast eruptions (0.4 s cracks) track her real position |
| CHAIN_ERUPTION | 3 | Cracks on every remembered noise spot, 0.55 s | Be away from all your recent noise spots; bursts go oldest to newest, 0.45 s apart |

A missed pulse leaves him surfaced and confused (`tremor_confused_time`, 1.2 s). In phase 3 an optional dark overlay dims the light (`dim_light_in_final_phase`, a CanvasLayer on layer 30, under the HUD at 40 and the boss bar at 41). It is cosmetic only: no mechanic depends on it.

### Hyperfocus is a bonus

If the player has the `open_eyes_activated` signal and it fires while he is burrowed and the bonus is off its 8 s cooldown (`hyperfocus_cooldown`), he is forced up where he is, dazed for `hyperfocus_stun_time` (1.2 s). It always counts as noise. The fight is fully winnable without it, and the boss works when the signal does not exist.

## Tunables worth knowing

Everything is `@export`, grouped on the `BlindBeast` node: `Noise`, `Burrow`, `Eruption`, `Probe`, `Claw Counter`, `Braille Ridge`, `Debris Toss`, `Tremor Pulse`, `Chain Eruption`, `Hyperfocus`, `Light`, `Attack Weights` (one weight per attack in enum order for each phase) plus the base groups.

- Make it kinder: raise `patience_time`, `crack_time`, `exposed_hit_time`; lower `tunnel_speed`.
- Fight length: Luz deals 1 per hit, so the 30 health come from exposed windows (about 3 hits in a 1.8 s one, 2 in a 0.8 s one). Tune `missed_stun_time` first.
- The ridge words (`ridge_words`) use the letters L U Z O J; `BRAILLE_LETTERS` holds the six-dot cells. Empty words, or words with none of those letters, are skipped; with no valid word the ridge is skipped for a plain ERUPTION.
- The ridge always fits between the arena limits: a slot is never narrower than 20 px (`MIN_SLOT_WIDTH`), so it picks a word that fits, or cuts the pattern to the slots that fit. An arena too narrow for a single slot skips the ridge.
- `stuck_tunnel_time` (Burrow, 3 s): how long the tunnel may make no headway before he erupts where he is. Raise it only if you slow `tunnel_speed` a lot on purpose.
- Sound slots under `Sfx`: the base cues plus `Heard`, `Dig`, `Erupt`, `Claw`, `Ridge`, `Debris`, `Pulse` (empty streams; each fires `sfx_cue`).

## Place the prefab

1. Drag `scenes/enemies/bosses/blind_beast_boss_arena.tscn` into the level, origin on the **floor line** at the **centre of the room** (936 px wide like Artemis's room).
2. The arena feeds the boss its walls: the ridge, the probe and the pulse adapt to any `arena_rect` (a narrower one makes a smaller, or shorter, ridge that never leaves the walls). Resize the arena rects in the inspector; do not scale or rotate the node.
3. Keep the floor flat: noise spots, cracks and slots sit on the floor line of the boss. Platforms are fine for Luz, but a column (90 px) cannot reach them.
4. Put a Stillness Desk before the arena. See `docs/bosses/BOSS_ARENA.md`.
5. The boss instance sits at the centre of the arena (x 0) on purpose: his intro clip (the old man turning into the beast) plays there, and the centre is inside the 640 px view from either entrance. He starts burrowed and untargetable, so moving him only changes where his first tunnel begins; keep him where the camera can see the intro.

Test it: open `scenes/levels/test/blind_beast_arena.tscn` and run the scene. Headless: `godot --headless --path . --script res://tests/blind_beast_boss_test.gd`.

## Wiring to the blind NPC quest (not implemented)

Nothing in `blind_npc.gd` or `blind_quest_progress.gd` is touched. The cleanest hook is the **delivery end**:

- `BlindNPC.has_required_book()` (`scripts/world/blind_npc.gd`) gates the final dialogue's `_give_reward()`. It currently returns `true`. Returning `BossProgress.is_defeated(&"library_blind_beast")` instead would make the ruby owl wait for the fight.
- For listeners (a door, a toast, the NPC itself), `BlindQuestProgress.changed` already fires on `accept()`, `complete()` and `grant_reward()`. The boss side needs nothing more: `BossProgress` already records the defeat under the `enemy_id`.

What the swap would need beyond that one line: a place to put the arena (a `Library` room reachable after `BlindQuestProgress.is_accepted()`), a decision on what the old man says between the quest start and the fight (`final_dialogue`), and, if the NPC should turn into the beast on screen, hiding him once the arena is armed and not restoring him after the defeat. `BlindQuestProgress` is memory-only on purpose, so the defeat (saved by `BossProgress`) is the durable fact to read.

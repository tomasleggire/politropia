# El Profesor (Boombox Teacher): library main boss

Audience: level designers and whoever tunes the fight. A teacher with a boombox for a head. It is a **rhythm** fight: he never dodges, never jumps, and every strike lands on a beat that speeds up per phase. Luz wins by learning the tempo.

- Script: `scripts/enemies/bosses/boombox_teacher_boss.gd` (`BoomboxTeacherBoss`, extends `BossEnemy`), hazards in `scripts/enemies/bosses/boombox_teacher/boombox_hazard.gd`.
- Boss scene: `scenes/enemies/bosses/boombox_teacher.tscn` (`enemy_id` `library_boombox_teacher`).
- One-drag prefab: `scenes/enemies/bosses/boombox_teacher_boss_arena.tscn`.
- Test room: `scenes/levels/test/boombox_teacher_arena.tscn`. Run it from the editor (F6).
- Numbers: 36 HP, three phases (66 % and 33 %), super armor, no knockback, no stagger. Luz deals 1 damage per hit.

## Place it

1. Drag `boombox_teacher_boss_arena.tscn` into a level. Put its origin on the **floor line**, at the horizontal **centre** of the room.
2. It is sized for a 936x480 room (same as Artemis). Resize `arena_rect`, `trigger_rect` and the doors on the arena node; the boss adapts to whatever walls the arena gives it (waves, notes and the dictation columns are computed from them, nothing is hardcoded in world coordinates).
3. The arena already has `boss_name` "El Profesor", the unique `enemy_id` and `reward_enabled = false`. Beating him opens the doors and restores the level music; he does **not** trigger the game completion (only Artemis does). The defeat is remembered through `BossProgress`.
4. Put a Stillness Desk before the arena, as for every boss. A desk rest or Luz's death returns him to a fresh state with no hazard left.

## The beat clock

- Starts at `engage()` and runs until the fight resets or he falls. 90 bpm in phase one, 110 in phase two, 132 in phase three (`bpm_by_phase`). A phase change never changes the tempo in the middle of an attack: the new tempo starts at the **transition beat**, which waits for an active strike to end and cuts a wind-up (nothing of that attack fires). Every event of a strike keeps exactly the beat it was telegraphed with.
- Every beat emits `beat(index)`, plays the cue `Beat` and pulses a **metronome**: the boombox head swells and a ring grows and fades at his feet. Every fourth beat is the accent (a bigger, brighter ring). The tempo is readable with no audio.
- **Quantisation**: a telegraph lasts a whole number of beats and the strike (the ACTIVE phase) starts on a beat. The telegraph time is the time left to the Nth next beat; when that is under 0.35 s (a high `bpm_by_phase`) one more beat is added, so no telegraph is ever shorter than 0.35 s. Each recovery also ends on a beat, so the next telegraph starts on the grid.

## Phrases, rest and finale

- He plays **phrases**: two to four attacks back to back, drawn from a weighted per-phase table (`PHRASES` in the script), never the same phrase twice in a row. A later phase adds attacks to the table and never removes the earlier ones; an attack never shows up before its phase.
- After a phrase he **rests one bar** (`rest_beats`, 4 beats) walking at `walk_speed` (70 px/s) to a mid-range spot (`mid_range`, 105 px) facing Luz. If Luz is hugging him (closer than `kick_range`, 50 px) at the end of the rest he kicks first, then plays his phrase.
- **Every third phrase is the phase finale** (`finale_every`). Right after a finale he **overheats**: a stun of 2.2 s in phase one, 2.0 s in phase two, 1.8 s in phase three (`overheat_times`), with steam and the cue `Overheat`. It is the main punish window; he can be hit the rest of the time too, and his telegraphs never flinch (super armor).

| Phase | Finale | Plays |
|---|---|---|
| 1 "La clase" | Lección | triple thrust chain, then the briefcase |
| 2 "Listening" | Listening | one eight-beat wave sequence |
| 3 "Examen oral" | Encore | dictation, eight beats of alternating waves, bass drop |

## Attacks

Beats are at the phase tempo. "Jump" means being airborne (feet more than about 35 px up); a dash passes through a hazard while Luz's i-frames last (see "What a dash can pass" below).

| Attack | Phase | Telegraph | How to avoid it |
|---|---|---|---|
| Pointer thrust (chain of 1 to 3, one per beat) | 1+ | 1 beat, red glow plus a red line at the height of the thrust. The height of the next thrust is shown during the beat before it. | 120 px reach. **High** thrust (standing height): crouch under it. **Low** thrust (feet): jump it. Heights alternate. |
| Briefcase boomerang | 1+ | 2 beats, amber glow plus an amber line at torso height. | Flies out 2 beats, comes back 2 beats (also from behind). Torso height: crouching does not help. Jump it or dash through it (the outward pass; the return trip is a new overlap). |
| Kick | 1+ (only when Luz hugs him) | 1 beat, red glow plus a red floor marker in front of him. | 64 px reach. Step back, jump or dash. |
| Sound waves | 2+ | 4 beats (the bar). Pips over his head show the pattern: low pips sit low (amber), high pips sit high (cyan), dots are rests. The next wave lights one beat before it leaves. | One wave per beat for 4 to 8 beats, both directions along the floor across the arena. **Low** wave (amber): jump it. **High** wave (cyan, 50 to 80 px above the floor): stay on the ground, standing or crouching. Patterns never put three lows in a row and never a high straight after a low (a rest lets Luz land). |
| Note bounce | 2+ | 2 beats, amber glow plus a line along the floor. | 2 or 3 notes hop toward Luz's side and despawn at the walls. Stand under the apex of a hop or jump the bounce. |
| Blackboard dictation | 3+ | 4 beats. A blackboard reading `in English please!` appears above the arena centre and every floor column shows a dim marker. | One letter per beat falls on the columns from left to right, in reading order; its marker brightens when it is released, and every letter takes 0.45 s to land. Stand between two columns. |
| Bass drop | 3+ | 2 beats. He lifts the boombox and the whole floor flashes amber. | On the beat a ground shock covers the whole arena, 34 px high. Be airborne at that instant, or dash so that the i-frames are running when the shock starts. |

## What a dash can pass

The dash i-frames last the whole dash: about 0.51 s for a ground dash from rest (0.08 s lean-back plus 0.43 s slide), 0.30 s for an air dash, with a 0.35 s cooldown (`Dash` and `Dash Invulnerability` in `player.gd`; no grace after it).

- A hazard that touches Luz while the i-frames run is **dodged**: it cannot hurt her until it has stopped overlapping her. So a dash that is running when a wave, the briefcase or the bass shock reaches her passes it, even if the i-frames end while she is still inside the same hazard (the 0.22 s shock, for instance).
- A hazard that reaches her only **after** the dash ended hurts as usual, and so does a second overlap with the same hazard (the briefcase coming back).
- A dash started more than about 0.5 s before the strike does not protect her: time it to the beat, not to the telegraph.

## Tunables worth knowing

Everything is an `@export` on the boss node, in groups:

- `Beat`: `bpm_by_phase`, `pulse_time`, `head_pulse`.
- `Structure`: `rest_beats`, `opening_beats`, `finale_every`, `overheat_times`, `walk_speed`, `mid_range`, `kick_range`, `auto_phrases` (off: the loop never attacks by itself, tests drive it).
- `Telegraphs`: the whole beats each wind-up lasts (a floor of 0.35 s always applies).
- `Pointer Thrust`, `Briefcase`, `Kick`, `Sound Waves`, `Notes`, `Dictation`, `Bass Drop`: reaches, bands (feet-relative y ranges), speeds, counts, the board text.
- `Hazards`: `hazard_damage`, `max_clear_beats` (how long he waits for notes to clear; at least 1). The wait for waves to leave is capped at 12 beats whatever the arena size, so he never sits in his recovery.
- Degenerate values are guarded: `finale_every` 0 or less means no finales (and no overheat), empty `bpm_by_phase` / `overheat_times` fall back to 90, 110, 132 and 2.2, 2.0, 1.8, bpm is clamped to 30..300, and the wave length, note count, telegraph beats, rest and opening beats, column spacing and note physics are raised to valid minimums.
- Base groups from `BossEnemy`: `Phases`, `Defeat`, `Final Blow`, `Camera Shakes`, `Randomness` (`rng_seed` for deterministic fights).

Difficulty is mostly the tempo and the phrase table. To make the fight easier lower `bpm_by_phase`, lengthen `overheat_times` or trim `PHRASES`.

## Audio cues

Empty `AudioStreamPlayer2D` slots under `Sfx`, each also emitted as `sfx_cue`: `Beat`, `Overheat`, `Thrust`, `Throw`, `Kick`, `Wave`, `Note`, `Letter`, `BassDrop`, plus the base ones (`Intro`, `PhaseChange`, `Stun`, `Flinch`, `Stagger`, `Defeat`). A `Beat` stream gives the music its metronome.

## Tests

`tests/boombox_teacher_boss_test.gd` (headless): the prefab, the clock and its tempo per phase, strikes on a beat, the minimum telegraph, the avoidance of each attack, the wave pattern rules, dictation, phrases and finales per phase, the overheat, the arena limits, the tempo holding through phase changes in the middle of an attack, degenerate tunables, a boss with no arena limits, real dashes through a wave, the briefcase and the bass drop, the reset and the defeat. Run:

`godot --headless --path . --script res://tests/boombox_teacher_boss_test.gd`

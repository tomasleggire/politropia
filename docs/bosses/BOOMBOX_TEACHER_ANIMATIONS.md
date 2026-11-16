# Boombox Teacher animation contract

Audience: Codex (art agent) and whoever runs the processing script. Goal: replace El Profesor's `Polygon2D` placeholders with final art **without touching gameplay**.
Numbers come from `scripts/enemies/bosses/boombox_teacher_boss.gd`, `boombox_teacher/boombox_hazard.gd` and `scenes/enemies/bosses/boombox_teacher.tscn`. The fight itself is described in `docs/bosses/BOOMBOX_TEACHER.md`. The format mirrors `docs/bosses/ARTEMIS_ANIMATIONS.md`.

---

## 1. Character brief

Same style as Luz and Artemis: thick dark outline `#1A1410`, cel shading in 2-3 steps, flat shapes, one palette. He keeps a TALL, lanky build.

| Aspect | Direction |
|---|---|
| Who | The library's English teacher with a boombox for a head. Theatrical, grounded, never jumps or dodges. |
| References | `tools/art_sources/boombox_teacher/concept/` (approved: `teacher_concept_v1.png`). |
| Outfit | Warm cream shirt, sleeves rolled, dark red tie, dark navy trousers, black shoes and gloves. |
| Props | Pointer stick (right hand, strikes), black briefcase (thrown, comes back), the boombox itself (lifted for the bass drop). |
| Mood | Stern and showy, never gory. The corpse is a collapsed teacher with the boombox on the floor. |

---

## 2. Technical contract

### 2.1 Nodes

| Path (under `BoomboxTeacher`, a `CharacterBody2D`) | Contract |
|---|---|
| `Visual` (`Node2D`) | Code owns it: `scale.x = facing`, `position.x` (flinch shake), `modulate` (stun and corpse tints), tilt and squash of the placeholder corpse. Art never animates these. |
| `Visual/AnimatedSprite2D` | The final art, first child of `Visual` (so the flash and glow clones draw above it). `texture_filter = 4`, `scale = 0.2896`, `offset = (0, -192)`. |
| `Visual/Body`, `Tie`, `Pointer`, `Head/*` | Placeholders. Visible only when no art exists. With art they are hidden. The white hit flash and the telegraph glow are clones with their own visibility and use `ART_SILHOUETTE` (a tall torso + head polygon in the script) so they cover the sprite. |
| `CollisionShape2D` | 28 x 84 at `(0, -42)` on this scene only (the base boss is 26 x 56) so Luz's hits connect with the drawn torso and head. |
| Hazards (`BoomboxHazard`) | Boxes polled against Luz. Their size and timing do not change. |

### 2.2 Origin, facing and scale

- **Origin = feet, horizontally centred** (the feet centre of each cell sits on the cell centre).
- **Art faces RIGHT (+x).** `Visual.scale.x = facing` flips it. Asymmetric props (pointer in the right hand) are correct for the right-facing frame.
- The drawn clips already carry the lean, crouch and slump: the sprite undoes `Visual`'s corpse tilt and squash and keeps only the facing flip.
- **On-screen size:** about **92 px** from sole to the top of the boombox (Luz 48, Artemis 56). The antenna is thin and extra: it does not count. Same on-screen pixel scale as Artemis: `sprite_scale` **0.2896** (= 0.1448 x 512 / 256).
- **Processed cell: 448 x 448 px, feet row 416** (`animation_manifest.json`: `cell`, `feet_row`). Standing height in the cell = 92 / 0.2896 = 318 px. The cell leaves 416 px (120 screen px) above the feet for the antenna and the bass lift (about 1.3x his height), and 448 px (130 screen px) of width for the lunge and the lying corpse. `offset.y = -(416 - 224) = -192`.
- All frames of all clips share the cell size and the feet row. No per-frame offset in code.

### 2.3 Raw sheets and the pipeline

Codex draws raw magenta sheets of **1536 x 1024**: `thrust` is **3 columns x 2 rows** (512 x 512 cells, the lunge is wide), every other sheet is **4 x 2** (384 x 512 cells). Codex does not keep exact geometry: the script splits by connected components per grid cell.
Raw file: `tools/art_sources/boombox_teacher/raw/boombox_teacher_<sheet>_raw.png`. Output: `assets/enemies/boombox_teacher/boombox_teacher_<sheet>_sheet.png` + `animation_manifest.json` (`cell`, `feet_row`, `sprite_scale`, `sheets {file: {grid, clips, events}}`, `props {sheet, sprite_scale, grid, clips}`).

Scale rules (script `tools/process_boombox_teacher_sheets.py`, helpers in `tools/boss_sheet_pipeline.py`):

- The loco idle frames set the base: median height sole to top of the boombox, antenna excluded (the first row whose solid run is at least 30% of the widest row, so a thin antenna is skipped), scaled to 318 px.
- Codex draws each sheet at a slightly different size, so each other sheet is scaled to match the **boombox size** of loco (`block_size`: the topmost grey block, sqrt of its area, median over the sheet; the boombox exists in every pose). `size_cells` limits the measured cells (defeat: 0-4) and `scale_mult` tunes by hand.
- Props have no boombox: the briefcase of cell 0 is scaled to 30 px on screen (the hazard is 30 wide) and every prop uses that factor.
- Unused cells are dropped; clip indices in the manifest are for the compacted sheet.

Run (Pillow, numpy and scipy are not in the system Python; use a venv, nothing global):

```
python3 -m venv /tmp/politropia-art-venv && /tmp/politropia-art-venv/bin/pip install pillow numpy scipy
/tmp/politropia-art-venv/bin/python tools/process_boombox_teacher_sheets.py --preview <dir>
```

Missing raw sheets are skipped with a message; sheets already processed stay in the manifest. `--preview DIR` writes each sheet with the feet row and reference lines for Luz (48 px), Artemis (56 px) and the Profesor (92 px), and the measured boombox size.

### 2.4 Sheet plan (raw cells in reading order)

| Sheet | Cells -> clips |
|---|---|
| `loco` | `idle` 0-3, `walk` 4-7 |
| `thrust` (3 x 2) | `thrust_high_windup` 0, `thrust_high_strike` 1, `thrust_high_recover` 2, `thrust_low_windup` 3, `thrust_low_strike` 4, `thrust_low_recover` 5 |
| `throw` | `throw_windup` 0-1, `throw_release` 2, `throw_wait` 3 (empty-handed), `throw_catch` 4, `kick_windup` 5, `kick_strike` 6, `kick_recover` 7 |
| `conduct` | `conduct` 0-3 (waves), `lecture` 4-5 (dictation), `notes` 6-7 |
| `bass` | `bass_lift` 0-1 (boombox over the shoulders, about 1.3x height), `bass_slam` 2-3, `overheat` 4-7 (loop) |
| `trans` | `phase_change` 0-3, `intro` 4-7 |
| `defeat` | `defeat` 0-7 (6-7 are the corpse) |
| `props` (no figure) | `briefcase_spin` 0-3 (front, edge, back, edge), `note` 4, `note_pair` 5, `steam` 6, `spark` 7 |

---

## 3. Clip table

The boss asks for clips by these names. A clip that is not drawn resolves through the fallbacks (script `FALLBACKS`) and then to `idle`. A **strike** is a one-frame clip that shows when ACTIVE starts, which is on a beat: every telegraph ends on a beat. Playback speed is derived at play time (`frames / fps / duration`); a clip never decides when a state ends: the state machine ends it and the clip is cut or holds its last frame. `bpm` 90 / 110 / 132 gives a beat of 0.667 / 0.545 / 0.455 s.

| Clip | Trigger in code | Duration source | Loop | Fallback |
|---|---|---|---|---|
| `idle` | `IDLE`, `FIGHT` with `velocity.x` under 1, ATTACK recovers without their own pose, flinch, stagger | open-ended | loop | none (default) |
| `walk` | `FIGHT` walking to mid range (`walk_speed` 70) | open-ended | loop | `idle` |
| `intro` | `play_intro(duration)` while `IDLE` | the intro duration given by the arena | one-shot | `idle` |
| `phase_change` | `TRANSITION` | `phase_transition_time` | one-shot | `idle` |
| `overheat` | `STUN` (overheat after a finale) | open-ended (2.2 / 2.0 / 1.8 s) | loop | `idle` |
| `defeat` | `DEFEATED` | `defeat_time`; a restored corpse shows the last frame | one-shot | `idle` |
| `thrust_<h>_windup` | THRUST TELEGRAPH, `h` = height of the first thrust (`high` / `low`) | the telegraph (`thrust_telegraph_beats` whole beats) | hold | `thrust_<h>_strike`, other height |
| `thrust_<h>_strike` | THRUST ACTIVE, the `thrust_strike_time` (0.18 s) after each strike event; event k fires on beat `anchor + k` | 0.18 s | hold | `thrust_<h>_windup` |
| `thrust_<h>_windup` (again) | ACTIVE after a strike with another thrust coming in the chain, height of the next one | until the next beat | hold | as above |
| `thrust_<h>_recover` | ACTIVE after the last strike of the chain, and RECOVER | rest of the phase | hold | `thrust_<h>_strike` |
| `throw_windup` | BRIEFCASE TELEGRAPH | the telegraph (`briefcase_telegraph_beats`, 2 beats) | hold | `idle` |
| `throw_release` | BRIEFCASE ACTIVE start (the briefcase leaves; strike frame) | 0.15 s | hold | `throw_windup` |
| `throw_wait` | BRIEFCASE ACTIVE while the briefcase flies (out 2 beats, back 2 beats) | until the catch | hold | `idle` |
| `throw_catch` | BRIEFCASE ACTIVE during the last 0.3 s, when it comes home | 0.3 s | hold | `throw_wait` |
| `kick_windup` | KICK TELEGRAPH (`kick_telegraph_beats`) | the telegraph | hold | `idle` |
| `kick_strike` | KICK ACTIVE (strike frame) | `kick_active_time` 0.2 s | hold | `kick_windup` |
| `kick_recover` | KICK RECOVER | rest of the phase | hold | `kick_strike` |
| `conduct` | SOUND_WAVE TELEGRAPH and ACTIVE (one wave pattern per beat) | one cycle per beat | loop | `idle` |
| `notes` | NOTE_BOUNCE TELEGRAPH and ACTIVE | one cycle per beat | loop | `conduct` |
| `lecture` | DICTATION TELEGRAPH and ACTIVE | one cycle per beat | loop | `conduct` |
| `bass_lift` | BASS_DROP TELEGRAPH (`bass_telegraph_beats`) | the telegraph | hold | `idle` |
| `bass_slam` | BASS_DROP ACTIVE and RECOVER (slam frame at ACTIVE start, held in recover) | `shock_time` + 0.08 s | hold | `bass_lift` |

**Events** (manifest `events`: clip -> frame index of the strike inside the clip): `thrust_high_strike`, `thrust_low_strike`, `throw_release`, `kick_strike`, `bass_slam` all at frame 0, because the clip starts when ACTIVE starts.

Gameplay overlays stay code-driven: telegraph aim lines and floor markers, the pips over his head, the blackboard, the hit flash (white clone of `ART_SILHOUETTE`), the telegraph glow, the stun and corpse tints.

**Metronome head swell.** The head cannot be isolated from a baked sprite, so with art the swell is dropped and only the floor ring pulses on the beat (the placeholder `Head` still swells when there is no art). If the art later needs a pulse, a 2-3% sprite scale pulse is the option.

## 4. Props

| Prop | Used by | Note |
|---|---|---|
| `briefcase_spin` | BRIEFCASE hazard (30 x 22 box), spinning while it flies | scaled so the front view is 30 px wide |
| `note`, `note_pair` | NOTE_BOUNCE disc hazard (radius 10), the `note_pair` for accents over `conduct` / `notes` | same factor as the briefcase |
| `steam` | overheat puffs (`_draw_steam`) | |
| `spark` | bass drop shock and hit accents | |

Props are integrated in a later task (T5); until then the polygons the hazards draw stay.

## 5. Integration checklist

1. Raw sheets in `tools/art_sources/boombox_teacher/raw/`.
2. Run the script, check the previews: feet on the line, 92 px red line at the top of the boombox, no size jumps between sheets.
3. `godot --headless --path . --import`, then `tests/boombox_teacher_boss_test.gd` and `tests/boss_animation_catalog_test.gd`.
4. Look at the real fight: strikes land on the beat, the corpse shows the last defeat frame, flash and glow cover the sprite, Luz's hits connect on the torso and head.

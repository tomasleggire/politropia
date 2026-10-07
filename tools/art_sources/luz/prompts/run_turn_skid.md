# M5 - Codex art request: Luz run, turn, skid

Status: approved 2026-10-07. Rim light is NOT part of this request: it is applied in-engine by a shader on every Luz animation (see `odd/tasks/luz-final.md`).
Reference: `~/Desktop/Caminar.mov` (60 fps, VFR ~59). Video frame numbers `n` below are 0-based ffmpeg frame indices.
The video was horizontally flipped for analysis so the Penitent runs RIGHT like Luz. Ruler direction below is therefore already "Luz facing right".

Measured vs assumed: poses, lean, leg/ruler positions and frame numbers were read from cropped frames at about 1:1 to 1.5x (measured by eye, +-1 video frame, angles +-10 deg). Timings come from the already-measured spec in `odd/tasks/luz-final.md`.

## 1. Spec table

Shared geometry (matches the pipeline in `tools/process_luz_rest_ritual.py`): raw cells are 384x512, facing RIGHT, lowest sole of the lowest shoe on y=472 in every cell, standing-equivalent body height 340 px (top of hair to sole, same scale as the idle frame), 16 px minimum padding to the cell edges. The processor rescales to the 512x512 output cell, feet row 413, anchor x=256 (alpha centroid aligned to the idle frame).

| Clip | Frames | Timing | Loop | Raw sheet | Notes |
|---|---|---|---|---|---|
| `run` | 8 | 28 fps = 0.0357 s/frame, cycle 0.286 s (~17 video frames, measured 17-18) | loop | `luz_run_raw.png`, 1536x1024, 4x2 cells | replaces the 4-frame `run`. 9 poses would need a 4x3 sheet (see open decisions) |
| `turn` | 4 | 4 / `turn_time`; recommended `turn_time` 0.12 s (30-35 fps), now 0.06 s | no loop, holds the last frame | `luz_turn_skid_raw.png`, 1536x1536, 4x3 cells, slots 0-3 | no translation while it plays |
| `skid` | 6 | brake 0.14 s + hold 0.17 s = 0.31 s, uniform 0.052 s/frame (frames 0-2 brake, 3-5 hold) | no loop, holds the last frame | same sheet, slots 4-9 | current player.gd durations are kept |

### run (facing right, ruler trails behind to the LEFT, held in the right hand at hip height)
Body leans forward 20-30 deg, head forward, arms bent and swinging. One foot is always near the ground. The ruler stays at hip height, tip behind her, between horizontal and 30 deg below horizontal. Silhouette height is about 92% of standing.

| # | Video ref | Pose |
|---|---|---|
| R1 | n36 | Compression: weight on the front leg (vertical under the hips), rear leg bent with the shin trailing, foot at about knee height. Lean ~20 deg. Ruler ~30 deg below horizontal. |
| R2 | n38 | As R1, rear foot lifting, rear arm swinging back. |
| R3 | n40 | Rear leg kicks back and up (foot at about hip height behind), front leg straight. Ruler ~15 deg below horizontal. |
| R4 | n42 | Push-off: rear leg fully extended behind, toe near the ground, front leg planted. Lean ~25 deg. Ruler ~horizontal. |
| R5 | n44 | Widest stride: front leg reaching forward with the toe pointing down, rear leg bent back and off the ground. Maximum lean ~30 deg. Ruler horizontal, tip slightly up. |
| R6 | n46 | Front foot touches down ahead, rear leg trails straight behind. Ruler horizontal. |
| R7 | n48 | Front leg takes the weight, rear knee starts to cock. Lean ~20 deg. Ruler tip dips ~20 deg. |
| R8 | n50 | Rear knee drives, heel up near the glute, front leg vertical. Ruler ~25 deg below horizontal. R8 must flow into R1 (n52 ~ n36). |

Height rule: R1/R8 (compression) are about 3 px lower in the head than R4/R5; keep the bob subtle (<= 4% of body height).

### turn (the clip plays already facing the NEW direction, no movement)
Reference: idle -> crouch -> run, n22-n33 and n120-n135. The ruler goes from low in front to trailing behind.

| # | Video ref | Pose |
|---|---|---|
| T1 | n22-23 | Feet widen, knees start to bend, torso upright, ruler still low in front of the body (idle position). |
| T2 | n24 | Wide stance, knees bent, torso upright, ruler flipped to trail behind, ~35 deg below horizontal. |
| T3 | n25 | Deepest crouch (1 frame only): torso hunched forward, head at about 75-80% of standing height, ruler horizontal behind her, arms low. |
| T4 | n26-27 | Rising from the crouch, wide stance, torso upright, ruler trailing ~30 deg below horizontal. Must chain into R1. |

### skid (stop from full run, facing right, ruler behind-left)
Reference: n84-n122. Snap to a wide low pose, then hold, then it relaxes to idle. Dust is a separate VFX (M2/M6), do not draw it.

| # | Video ref | Phase | Pose |
|---|---|---|---|
| S1 | n84 | brake | Snap: legs very wide (front foot far ahead, rear foot far behind), knees bent, torso upright (no forward lean), both arms thrown out for balance, ruler horizontal at shoulder height behind. About 90-95% of standing height. |
| S2 | n86-88 | brake | Same width, arms still out, ruler starts to drop. |
| S3 | n90-92 | brake | Stance narrows slightly, arms come in, ruler ~25 deg below horizontal. |
| S4 | n96 | hold | Upright, legs about shoulder width plus 30%, knees slightly bent, ruler resting low behind (~25-30 deg below horizontal). |
| S5 | n104 | hold | S4 with a tiny breath/sway (1-2 px). |
| S6 | n116 | hold | S5 with the ruler hand a few px lower. |

## 2. Global style block (paste at the top of every Codex prompt)

- Same character and same rendering as `luz_identity_ref.png` and the attached `luz_locomotion_sheet.png`: blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack, light-brown wooden ruler with dark tick marks. Same illustrated "pixel-styled" look, same density (~6-7 texture px per world unit, standing body ~340 px tall), same dark outline weight, same cel shading and palette. No rim light or edge glow (the engine adds it). Do not redraw her in true pixel art and do not change proportions.
- Ruler: same length and width as in the idle frame of `luz_locomotion_sheet.png` (about 36% of standing height), identical length in every frame, never a bat or a sword.
- Transparent background (real alpha). If real alpha is impossible, flat pure magenta #FF00FF with no gradients, no shadow, no antialiasing halo. No ground, no shadow, no glow, no dust, no motion lines, no text, no numbers, no grid lines.
- Right-facing side view in every frame. Lowest sole on y=472 of its cell in every frame. 16 px minimum padding to each cell edge. The ruler may stretch to the left, leave room: body centre near x=210 for run and skid, x=190 for turn.
- Output files go in `tools/art_sources/luz/raw/` (gitignored); reply with the path and image size. Do not edit any other file.

## 3. Codex prompts

Attachments for both: 1 `tools/art_sources/luz/refs/luz_identity_ref.png`, 2 `assets/player/luz/luz_locomotion_sheet.png` (in-game style/scale), 3 the pose reference contact sheet from the video: `tools/art_sources/luz/refs/penitent_run_ref.png` for 3a, `penitent_turn_ref.png` and `penitent_skid_ref.png` for 3b (local, gitignored; pose reference only, do not copy the character, armor or red sash, only the body mechanics).

### 3a. run -> `tools/art_sources/luz/raw/luz_run_raw.png`

> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. [paste the global style block]. Generate ONE 1536x1024 PNG, 4 columns x 2 rows of invisible 384x512 cells, row-major, eight frames of a seamless looping RUN cycle of Luz facing right (frame 8 flows into frame 1). Standing-equivalent body height 340 px, lowest sole on y=472 in every cell, body centre near x=210, 16 px padding. She leans forward 20-30 degrees, head forward, arms bent and swinging, the wooden ruler held in her right hand at hip height trailing behind her to the left (between horizontal and 30 degrees below horizontal, tip pointing back-left), same ruler size in all frames. Frames: 1 compression, weight on the front leg under the hips, rear leg bent with the shin trailing, ruler ~30 deg below horizontal; 2 same, rear foot lifting; 3 rear leg kicks back and up, ruler ~15 deg below horizontal; 4 push-off, rear leg fully extended behind with the toe near the ground, ruler horizontal; 5 widest stride, front leg reaching forward toe down, rear leg bent back off the ground, maximum lean, ruler horizontal; 6 front foot touches down ahead, rear leg trails straight; 7 front leg takes the weight, rear knee begins to cock, ruler tip dips 20 deg; 8 rear knee drives, heel near the glute, ruler 25 deg below horizontal. Keep the body height, outline and palette identical in all frames. Fast, weighty, fluid like the attached pose reference; each frame is a distinct pose (no duplicates).

### 3b. turn + skid -> `tools/art_sources/luz/raw/luz_turn_skid_raw.png`

> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. [paste the global style block]. Generate ONE 1536x1536 PNG, 4 columns x 3 rows of invisible 384x512 cells, row-major, twelve slots (slots 11-12 stay empty/transparent). Right-facing Luz, standing-equivalent body height 340 px, lowest sole on y=472 in every cell, 16 px padding. Row 1 (slots 1-4) = TURN crouch: 1 feet widen, knees start to bend, torso upright, ruler held low in front of her; 2 wide stance, knees bent, torso upright, ruler now trailing behind her to the left about 35 deg below horizontal; 3 deepest crouch, torso hunched forward, head at about 75-80% of her standing height, ruler horizontal behind her, arms low; 4 rising from the crouch, wide stance, torso upright, ruler trailing about 30 deg below horizontal. Rows 2-3, slots 5-10 = SKID (hard stop from a run, wide and low, no forward lean): 5 snap, legs very wide with the front foot far ahead and the rear foot far behind, knees bent, torso upright, both arms thrown out for balance, ruler horizontal at shoulder height behind her; 6 same width, ruler starting to drop; 7 stance narrows slightly, arms come in, ruler about 25 deg below horizontal; 8 hold, upright, legs shoulder-width plus 30%, knees slightly bent, ruler resting low behind her about 25-30 deg below horizontal; 9 same as 8 with a tiny sway; 10 same as 9, ruler hand a few px lower. Same body scale in all slots.

## 4. Integration notes (for Claude, after the raw files exist)

Pipeline facts: `scripts/player/luz_animation_catalog.gd` reads `assets/player/luz/animation_manifest.json`; each sheet has a `grid` (columns, rows, 512x512 cells, asserted against the PNG size at catalog L192-198) and `clips` (name -> cell indices, row-major). Frames are already repacked so the sole sits on row 413 and the sprite uses `offset (0,-157)` and `scale = body_height/331.5` (`player.gd` L437-442), so new frames must keep the idle standing scale (processor scale ~0.97 from the 340 px raw).

1. New processor `tools/process_luz_run_turn_skid.py`, cloned from `tools/process_luz_rest_ritual.py` (magenta key, component ownership per 384x512 cell, `place()` with lift 0, centroid anchored to the idle frame). It must accept the 4x2 run sheet and the 4x3 turn/skid sheet (the rest script hard-codes 1536x1024 and 8 cells). Outputs `assets/player/luz/luz_run_sheet.png` (2048x1024) and `assets/player/luz/luz_turn_skid_sheet.png` (2048x1536), plus preview timelines/onion skins.
2. Manifest (the script writes it like the rest script): `luz_run_sheet.png` grid 4x2, clips `run: [0..7]`; `luz_turn_skid_sheet.png` grid 4x3, clips `turn: [0,1,2,3]`, `skid: [4..9]`. Do NOT run `tools/process_luz_sheet.py` (it would regenerate the old locomotion sheet).
3. Remove `"run": [4,5,6,7]` from the `luz_locomotion_sheet.png` clips. Otherwise the catalog maps both sheets' `run` clips to `walk` and appends 4 stale frames (catalog L107-130, `_animation_name_for` L213-217). Leave the other locomotion clips (idle, jump, fall, crouch, land) untouched; the `crouch` frames stay for the real crouch.
4. Catalog: set `CLIP_SPEEDS["walk"]` from 9.0 to 28.0 (L20). `turn` and `skid` need no catalog change: `PLACEHOLDER_CLIPS` (L52-55) is ignored as soon as the manifest provides clips named `turn` and `skid` (`_fill_placeholder_clips` L138-142). Both are non-looping (not in `LOOPING_CLIPS`).
5. Timing in `player.gd`: `turn`/`skid` fps are derived from `turn_time` (L113, now 0.06 s) and `skid_brake_time + skid_hold_time` (L119-121, 0.31 s) passed to the catalog (L310-311). With 4 turn frames, 0.06 s is 67 fps; raise `turn_time` to ~0.12 s (user feel decision; it also lengthens the no-movement window). Run playback uses `_play_animation(&"walk", clamp(speed/run_max_speed, 0.7, 1.8))` (L2479), so 28 fps at full 150 px/s.
6. Checks: regenerate previews and review the onion skins, `--check-only` on the catalog, headless boot, `tests/locomotion_test.gd` (turn/skid state coverage), then the iPhone feel check. Update `odd/tasks/luz-final.md` M5 afterward.

## 5. Decisions (user, 2026-10-07)

1. Run: 8 poses at 28 fps (fits the 4x2 pipeline).
2. `turn_time`: not decided by the art; the art has 4 frames either way. Measurements disagree (3-4 video frames = 0.06 s vs ~6 frames = 0.1 s); tune the exported value on the iPhone.
3. No `skid_relax` clip: the video shows none; the skid ends into `idle`.
4. Rim light: in-engine shader on every Luz animation, not drawn by Codex.

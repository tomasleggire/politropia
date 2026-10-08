# P9 - Codex art request: Luz jump, fall, landing, double jump and crouch

Status: draft 2026-10-08. Reference: `tools/art_sources/luz/reference/penitent_jump_dash_reference.md` (60 fps video; pose timelines in section 1.5, curve in 1.2). Pose sheets (local, gitignored): `refs/penitent_jump_ref.png` (video frames 29-80: takeoff, rise, apex, fall), `refs/penitent_jump_land_ref.png` (frames 22-109: takeoff and landing), `refs/penitent_land_ref.png` (a running landing), `refs/penitent_crouch_ref.png` (crouch attack, posture only).
Codex draws ONLY the character and her ruler (sword); dust, afterimages and effects are VFX.

## 1. Timeline and decisions

Physics today: rise 0.45 s, fall ~0.41 s, hard standing landing 0.35 s, jump-cancel from 0.18 s. Penitent has no takeoff anticipation: the idle pose is followed at once by the airborne pose.

| Clip (catalog name) | Penitent timeline (60 fps frames) | Luz frames | Playback |
|---|---|---|---|
| `jump` (source `jump_ascent`) | launch 0-2: body stretched, feet leaving; rise ~20 f legs tucked, sword down | 5 | plays once over the rise (0.45 s), holds the last pose |
| `fall` | apex transition ~5 f (arms open, sword swings horizontal); fall ~25 f arms spread, legs straight down, hair up | 5 + 1 spare | apex 2 frames, fall 3 frames, holds the last pose until touchdown |
| `land` | 21 f in 5 pose steps: crouch 0-4, crouch 5-9, rising 10-14, half crouch 15-17, stance 18-20 | 5 | one pose per step over 0.35 s (0.07 s each) |
| `double_jump` (new, Luz only, boss reward) | none in the Penitent | 6 | once over the second rise, then `fall` takes over |
| `crouch` | crouch attack stance (`penitent_crouch_ref.png`), posture only | 3 enter + 2 hold | enter plays once, last frame held while crouching |
| `crouch_exit` (new) | mirror of the enter | 3 | plays once on standing up |

Double jump design (justified): a forward tuck-somersault. At ~48 px she must read as clearly different from the first jump (tucked-and-open pose): a curled ball rotating one full turn is a distinct silhouette, it tells "second jump, boss power" without effects, and it keeps the ruler close to the body (blade along her back, grip near the hip) so the long ruler never sweeps a huge circle. Rotation is forward (clockwise for a right-facing figure: head goes forward then down): tuck, ~90, ~180, ~270, open (~330), upright stretch (rise pose, hands out) so the fall clip continues without a pop.

Ruler angles below are measured from the grip, degrees above (+) or below (-) horizontal, B = pointing back (left), F = forward (right), +-10 deg; the long ruler is normalised to 215 texels at integration by `tools/luz_ruler_length.py`.

## 2. Global style block (paste at the top of every prompt)

- Same character and same rendering as `luz_identity_ref.png` and the attached `luz_idle_raw_v3.png`: blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack. Same illustrated "pixel-styled" look, density, dark outline weight, cel shading and palette. Do not redraw her in true pixel art, do not change proportions, no rim light or edge glow.
- Ruler (her sword): the long light-brown wooden ruler with dark tick marks, as long as in the attached idle (about 65% of her standing height), identical length and width in every frame, held like a sword by its end (the hand grips the last ~15%). Never a bat, never a real sword. Keep its full length visible (tilt it 20-30 degrees if it would point at the camera).
- Head and body scale identical in every frame and the same as the attached idle (standing body height 360 px top of hair to sole; crouched poses are lower, never smaller).
- Background ONE flat pure magenta #FF00FF everywhere outside the character, no gradient, no glow, no shadow, no halo. No ground, no dust, no motion lines, no text, no numbers, no grid lines.
- Right-facing side view. 1536x1536 PNG, 3 columns x 3 rows of invisible 512x512 cells, row-major, slot 1 top-left, unused slots stay magenta. Nothing crosses a cell edge, 16 px padding. Output to `tools/art_sources/luz/raw/` (gitignored), reply with the path and size, edit nothing else.

Attachments for every job: 1 `tools/art_sources/luz/refs/luz_identity_ref.png`, 2 `tools/art_sources/luz/raw/luz_idle_raw_v3.png` (style, scale, sword grip), 3 the Penitent sheet named per job (pose reference only: do not copy his armor, helmet, red sash or sword, nor the backgrounds).

## 3. Frame tables

### 3.1 jump -> `luz_jump_ascent_raw.png` (5 frames), Penitent `penitent_jump_ref.png` frames 29-47
Airborne in every frame, no ground. Body centre x=210, vertical centre of the body near y=300.

| # | Penitent | Pose | Ruler |
|---|---|---|---|
| 1 | 29-32 | TAKEOFF: body stretched upward, legs still extending down with toes pointing, free arm swinging up, head up | 40 below, B |
| 2 | 32-35 | RISE: knees pulled up, feet tucked under the hips, torso upright, free arm raised | 45 below, B |
| 3 | 38-41 | RISE: knees tucked high, shins back, hair streaming down | 50 below, B |
| 4 | 41-44 | RISE: same tuck, slightly looser, hair streaming | 45 below, B |
| 5 | 44-47 | LATE RISE: legs beginning to lower, body slowing, chin level | 40 below, B |

### 3.2 fall -> `luz_jump_fall_raw.png` (5 frames + 1 spare), `penitent_jump_ref.png` frames 47-80
Airborne, body centre x=210, vertical centre near y=300.

| # | Penitent | Pose | Ruler |
|---|---|---|---|
| 1 | 47-50 | APEX A: legs releasing and lowering, arms starting to open | 30 below, B |
| 2 | 50-53 | APEX B: arms spread to the sides, legs hanging slightly bent, hair floating up | 15 below, B |
| 3 | 56-62 | FALL A: arms spread out, legs straight down, torso upright, hair lifted | 30 below, B |
| 4 | 65-71 | FALL B: same, hair streaming up more | 40 below, B |
| 5 | 74-80 | FALL C: stretched, legs straight, arms out, hair high | 35 below, B |
| 6 | spare | PRE-LAND: knees starting to bend, feet reaching down | 35 below, B |

### 3.3 land -> `luz_jump_land_raw.png` (5 frames), `penitent_jump_land_ref.png` frames 82-109 and `penitent_land_ref.png`
Grounded: lowest sole on y=472 of its row (472, 984, 1496), body centre x=210. Heights are fractions of the standing head height (head top at 100%).

| # | Penitent | Pose | Ruler |
|---|---|---|---|
| 1 | 82-85 | IMPACT: knees bent, torso dropping, head at 85%, arms out for balance | 30 below, B |
| 2 | 88-94 | DEEP CROUCH: head at 65%, torso forward, hands low | 25 below, B |
| 3 | 97-100 | CROUCH rising: head at 72%, weight forward | 25 below, B |
| 4 | 103-106 | HALF CROUCH: head at 85%, knees bent | 30 below, B |
| 5 | 109 | STANCE: back to the idle stance of the attached idle | 35 below, B |

### 3.4 double_jump -> `luz_jump_double_raw.png` (6 frames), no Penitent reference (attach `penitent_jump_ref.png` for the tuck only)
Airborne, body centre of each frame near (210, 300), the figure rotates about its centre.

| # | Pose | Ruler |
|---|---|---|
| 1 | TUCK-IN: knees pulled to the chest, chin down, torso pitched forward 20 deg, free arm hugging the knees | held close along her back, tip behind the hip, 50 below, B |
| 2 | ROLL 90: curled ball, head forward and down, back facing up | along her back, pointing back |
| 3 | ROLL 180: upside down, feet at the top, head at the bottom, tightly curled | along her back |
| 4 | ROLL 270: head back and down, feet forward, still curled | along her back |
| 5 | OPEN ~330: body unfolding, nearly upright, legs extending | swinging out, 40 below, B |
| 6 | STRETCH: upright, arms out, legs hanging, like the late rise pose | 40 below, B |

### 3.5 crouch -> `luz_crouch_raw.png` (8 frames), `penitent_crouch_ref.png` (posture)
Grounded, sole on y=472 of its row, body centre x=210. Head and body scale the SAME as the idle (only the posture lowers); full crouch head at 65% of the standing head height, torso pitched forward 25 deg, knees deeply bent, feet a little wider than the shoulders.

| # | Pose | Ruler |
|---|---|---|
| 1 | ENTER A: knees start to bend, torso upright, head at 88% | 35 below, B |
| 2 | ENTER B: head at 76%, torso leaning forward | 35 below, B |
| 3 | ENTER C: full crouch, head at 65% | 30 below, B |
| 4 | HOLD A: full crouch, chest slightly raised (breathing in) | 30 below, B |
| 5 | HOLD B: same, shoulders 3-4 px lower (breathing out) | 30 below, B |
| 6 | EXIT A: rising, head at 76% | 35 below, B |
| 7 | EXIT B: head at 88%, torso almost upright | 35 below, B |
| 8 | EXIT C: back to the idle stance of the attached idle | 35 below, B |

## 4. Codex prompts

Each prompt = global style block (section 2) + the text below.

### 4.1 jump
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Five frames (slots 1-5) of Luz's JUMP, takeoff and rise, a fast fluid jump like the attached Penitent reference (body mechanics only; no anticipation crouch). She is airborne in every frame, no ground. Frames: 1 takeoff, body stretched upward, legs still extending down with toes pointing, free arm swinging up, ruler trailing back-left 40 degrees below horizontal; 2 knees pulled up and feet tucked under the hips, torso upright, free arm raised, ruler back 45 degrees below horizontal; 3 knees tucked high, shins back, hair streaming down, ruler 50 degrees below horizontal pointing back; 4 same tuck, slightly looser, ruler 45 below; 5 late rise, legs starting to lower, ruler 40 below. Every frame a distinct pose, same body scale and ruler length.

### 4.2 fall
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Six frames (slots 1-6) of Luz at the APEX and FALLING, like the attached Penitent reference (body mechanics only). Airborne in every frame, no ground. Frames: 1 apex, legs releasing and lowering, arms starting to open, ruler back 30 degrees below horizontal; 2 arms spread to the sides, legs hanging slightly bent, hair floating up, ruler back 15 degrees below horizontal; 3 falling, arms spread, legs straight down, torso upright, hair lifted, ruler back 30 below; 4 same, hair streaming up more, ruler 40 below; 5 stretched, legs straight, arms out, hair high, ruler 35 below; 6 pre-landing, knees starting to bend and feet reaching down, ruler 35 below. Same body scale and ruler length, distinct poses.

### 4.3 land
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Five frames (slots 1-5) of Luz's HARD LANDING recovery, like the attached Penitent reference (body mechanics only). Feet on the ground, lowest sole on y=472 of its row, body centre x=210. Frames: 1 impact, knees bent, torso dropping, head at 85% of her standing head height, arms out for balance, ruler back 30 degrees below horizontal; 2 deep crouch, head at 65%, torso forward, hands low, ruler back 25 below; 3 still crouched but rising, head at 72%, weight forward, ruler 25 below; 4 half crouch, head at 85%, ruler 30 below; 5 back to the idle stance of the attached idle, ruler 35 below. Crouched poses are lower, not smaller: head size identical to the idle.

### 4.4 double jump
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Six frames (slots 1-6) of Luz's DOUBLE JUMP, a forward tuck-somersault that rotates once clockwise (right-facing: head goes forward then down), with the ruler held close along her back, grip near her hip. Airborne, no ground, the body centre of each frame near (210, 300). Frames: 1 tuck-in, knees pulled to the chest, chin down, torso pitched forward 20 degrees, free arm hugging the knees, ruler along her back with the tip behind the hip; 2 rolled 90 degrees, curled ball, head forward and down, back facing up; 3 rolled 180 degrees, upside down, feet at the top, tightly curled; 4 rolled 270 degrees, head back and down, feet forward, curled; 5 unfolding at about 330 degrees, nearly upright, legs extending, ruler swinging out back-left 40 degrees below horizontal; 6 upright stretch, arms out, legs hanging, ruler 40 below. Same body scale and ruler length in all frames (the ruler stays fully visible).

### 4.5 crouch
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Eight frames (slots 1-8) of Luz CROUCHING: enter, hold, exit, posture like the attached Penitent crouch reference (body mechanics only; ignore the slashes). Feet planted, lowest sole on y=472 of its row, body centre x=210. HEAD AND BODY SCALE IDENTICAL to the attached idle (she is only lower, never smaller). Frames: 1 knees start to bend, torso upright, head at 88% of her standing head height, ruler back 35 degrees below horizontal; 2 head at 76%, torso leaning forward, ruler 35 below; 3 full crouch, head at 65%, torso pitched forward 25 degrees, knees deeply bent, ruler 30 below; 4 same full crouch, chest slightly raised (breathing in); 5 same, shoulders a little lower (breathing out); 6 rising, head at 76%, ruler 35 below; 7 head at 88%, torso almost upright; 8 back to the idle stance of the attached idle, ruler 35 below.

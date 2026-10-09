# P10 - Codex art request: Luz ground dash, air dash, wall cling and wall jump

Status: draft 2026-10-08. Reference: `tools/art_sources/luz/reference/penitent_jump_dash_reference.md` section 2 (60 fps video). Pose sheet (local, gitignored): `refs/penitent_dash_ref.png` (video frames 0-116 every 4th: lean-back 4-12, drop 12-16, full slide 20-36 with purple afterimages, stand-up 38+). Codex draws ONLY the character and her ruler (sword); dust, afterimages and effects are VFX.

## 1. Timeline and decisions

| Clip (catalog name) | Source | Frames | Playback |
|---|---|---|---|
| `ground_dash` | Penitent dash: lean back, drop, long low slide (sash 45 -> 38, body about 0.5 of standing), ease-out | 8 | `dash_duration` 0.43 s after the 0.08 s lean-back (frame 1 is held frozen during the lean-back when dashing from rest) |
| `air_dash` | none (Luz design) | 6 | 0.30 s, horizontal, gravity off, standing collider |
| `wall_cling` | none (Luz design) | 4 | loop while sliding down the wall |
| `wall_jump` | none (Luz design) | 4 | 0.12 s kick-off, then the jump clip takes over |

Ruler angles: degrees above (+) or below (-) horizontal, measured from the grip, B = pointing back (left), F = forward (right), +-10 deg. The long ruler is normalised to 215 texels at integration by `tools/luz_ruler_length.py`; draw it as long as in the idle.

## 2. Global style block (paste at the top of every prompt)

- Same character and same rendering as `luz_identity_ref.png` and the attached `luz_idle_raw_v3.png`: blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack. Same illustrated "pixel-styled" look, density, dark outline weight, cel shading and palette. Do not redraw her in true pixel art, do not change proportions, no rim light or edge glow.
- Ruler (her sword): the long light-brown wooden ruler with dark tick marks, as long as in the attached idle (about 65% of her standing height), identical length and width in every frame, held like a sword by its end (the hand grips the last ~15%). Never a bat, never a real sword. Keep its full length visible.
- HEAD SIZE and body scale identical in every frame and the same as the attached idle (standing body height 360 px top of hair to sole). Low poses are lower, never smaller: the head stays the same size as in the idle.
- Background ONE flat pure magenta #FF00FF everywhere outside the character, no gradient, no glow, no shadow, no halo. No ground, no wall, no dust, no motion lines, no afterimages, no text, no numbers, no grid lines.
- Right-facing side view. 1536x1536 PNG, 3 columns x 3 rows of invisible 512x512 cells, row-major, slot 1 top-left, unused slots stay magenta. Nothing crosses a cell edge, 16 px padding. Body centre x=210, lowest sole on y=472 of its row (472, 984, 1496) for grounded poses. Output to `tools/art_sources/luz/raw/` (gitignored), reply with the path and size, edit nothing else.

Attachments: 1 `tools/art_sources/luz/refs/luz_identity_ref.png`, 2 `tools/art_sources/luz/raw/luz_idle_raw_v3.png`, 3 (ground dash only) `tools/art_sources/luz/refs/penitent_dash_ref.png` as pose reference only: do not copy his armor, helmet, red sash, sword or the purple afterimages or the cream dust.

## 3. Frame tables

### 3.1 ground_dash -> `luz_mobility_ground_dash_raw.png` (8 frames)
| # | Penitent | Pose | Ruler |
|---|---|---|---|
| 1 | 4-12 | LEAN-BACK startup: standing, weight shifted back onto the rear leg, torso leaning back about 10 deg, knees slightly bent, free hand low, sneakers planted | 35 below, B |
| 2 | 12-14 | DROP: knees bending hard, torso pitching forward, centre of gravity falling, head at 80% of standing | 20 below, B |
| 3 | 16-18 | LUNGE: very low and forward, front knee bent, rear leg thrust back, torso leaning forward about 45 deg, head at 62% | 10 below, B |
| 4 | 20-24 | SLIDE A: low slide, torso nearly horizontal (about 70 deg forward of vertical), head at 50% of standing, legs spread wide (front knee bent forward, rear leg stretched back), free arm forward-down for balance, hair streaming back | 5 above, B (blade trailing behind at hip height, clear of the floor) |
| 5 | 26-30 | SLIDE B: same low slide, rear leg slightly different, hair streaming | 5 above, B |
| 6 | 30-34 | SLIDE C: same low slide, weight a little lower, hair streaming | 0, B |
| 7 | 34-36 | SLIDE D (ease-out): still low, torso starting to lift, head at 56%, front foot braking | 10 below, B |
| 8 | 38 | RISING: half-crouch coming up out of the slide, torso lifting to about 30 deg forward, head at 75% | 25 below, B |
Feet: the lowest sole of every frame sits on y=472 of its row. Only 4-6 are really low; all slide frames keep the silhouette low and long (about 1.1 x standing height wide, ruler excluded).

### 3.2 air_dash -> `luz_mobility_air_dash_raw.png` (6 frames)
Airborne, no ground, body centre of each frame near (210, 300). A horizontal dash through the air, sword held back.
| # | Pose | Ruler |
|---|---|---|
| 1 | STARTUP: body tucks and pitches forward 20 deg, knees bent up, free arm pulled back, ready to burst | 40 below, B |
| 2 | BURST: body pitched forward about 60 deg, legs trailing back, free arm thrust forward | held back along the body, 10 below, B |
| 3 | DASH A: body almost horizontal, face forward, legs straight back together, free arm forward, hair streaming straight back | along the body, 5 below, B |
| 4 | DASH B: same horizontal streak, slightly different leg and hair shape | along the body, 5 below, B |
| 5 | DASH C: same horizontal streak, torso starting to rise | 15 below, B |
| 6 | END: body unfolding upright again, legs lowering, arm out for balance | 35 below, B |

### 3.3 wall -> `luz_mobility_wall_raw.png` (8 frames: wall_cling 1-4, wall_jump 5-8)
An invisible vertical wall stands to the RIGHT of her: its surface is the line x = 300 of her cell (body centre x=210). Do not draw it.
| # | Clip | Pose | Ruler |
|---|---|---|---|
| 1 | cling | GRAB: body just caught the wall, front arm reaching forward with the palm flat on the invisible wall at x=300 and elbow bent, torso upright, knees bent, feet low and close to the wall, eyes toward the wall | held in the back hand, tip pointing down-back, 60 below, B |
| 2 | cling | HOLD A: sliding down the wall, front palm flat on the wall above her head height, other hand holding the ruler, legs hanging, hair lifted upward (she is falling slowly), sneakers brushing the wall | 60 below, B |
| 3 | cling | HOLD B: same slide, hair settling, jacket hem lifted, front arm slightly bent | 65 below, B |
| 4 | cling | HOLD C: same slide, hair rising again, one knee slightly bent | 60 below, B |
| 5 | wall_jump | CROUCH ON WALL: both feet pressed on the invisible wall (feet at x about 285-300, soles toward the wall), knees bent, body coiled, front hand just letting go | 45 below, B |
| 6 | wall_jump | KICK: legs extending hard, launching up and away from the wall (to the left), torso twisting back toward the wall while she still faces right | 35 below, B |
| 7 | wall_jump | LAUNCH: fully extended diagonal stretch up and left (away from the wall), arms out, hair streaming down | 30 below, B |
| 8 | wall_jump | RISE: legs tucking, body upright again, like the late jump rise | 40 below, B |

## 4. Codex prompts
Each prompt = global style block (section 2) + the text below.

### 4.1 ground dash
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Eight frames (slots 1-8) of Luz's GROUND DASH like the attached Penitent reference (body mechanics only): lean-back startup, a hard drop, a very low slide with the torso nearly horizontal and legs spread wide, ease-out and a rising half-crouch. Frames: 1 standing lean-back, weight on the rear leg, ruler trailing back 35 degrees below horizontal; 2 knees bending, torso pitching forward, head at 80% of standing; 3 very low lunge, rear leg thrust back, head at 62%; 4-6 the slide, torso nearly horizontal, head at about 50% of her standing head height, front knee bent, rear leg stretched back, hair streaming back, ruler trailing behind at hip height pointing back, three similar frames with small differences in leg and hair; 7 slide easing, torso starting to lift, front foot braking; 8 rising half-crouch, ruler 25 degrees below. Head size identical to the idle in every frame, only lower. Grounded: lowest sole on y=472 of its row.

### 4.2 air dash
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Six frames (slots 1-6) of Luz's AIR DASH, a fast horizontal burst through the air, sword held back. Airborne, no ground, body centre near (210, 300) in each cell. Frames: 1 tuck, body pitched forward 20 degrees, knees up, free arm pulled back, ruler back 40 degrees below horizontal; 2 burst, body pitched about 60 degrees, legs trailing, free arm forward, ruler held back along the body; 3-4 body almost horizontal, face forward, legs straight back together, free arm forward, hair streaming straight back, ruler along the body pointing back (two similar frames with small differences in legs and hair); 5 same streak, torso starting to rise; 6 body unfolding upright, legs lowering, arm out, ruler 35 degrees below. Same body scale and ruler length in all frames.

### 4.3 wall
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Eight frames (slots 1-8) of Luz on a WALL. An invisible vertical wall stands to her RIGHT at x=300 of her cell (body centre x=210): do not draw it. Slots 1-4 WALL CLING sliding down: front arm reaching to the right with the palm flat on the invisible wall, torso upright, knees bent, the other hand holding the ruler pointing down and back, hair lifted upward as she slides, sneakers close to the wall; slot 1 is the grab (arm just landing), slots 2-4 the slide with small differences in hair, jacket and knees. Slots 5-8 WALL JUMP, kicking off the wall and away from it (up and to the left): 5 crouched on the wall with both feet pressed on it and knees bent, 6 legs extending hard and launching, 7 fully extended diagonal stretch up and away from the wall with arms out and hair streaming down, 8 legs tucking and body upright like the late rise of a jump. She keeps facing right in every frame. Same body scale and head size as the idle; ruler as in the table.

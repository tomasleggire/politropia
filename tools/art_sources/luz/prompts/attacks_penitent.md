# P8 - Codex art request: Luz attacks matched to the Penitent

Status: draft 2026-10-08. Reference measurements: Engram / `penitent_attack_reference.md` (Ataque.mov and "Atacar enemigos y morir.mov", 60 fps video, frame numbers below are 1-based video frames; 1 Luz world px = 3.08 video px; standing Luz = 331.5 output texels = 48 world px, so 1 world px = 6.9 texels).
Slash crescents and smears are VFX (separate, `tools/generate_luz_slash_smears.py` style). Codex draws ONLY the character and her ruler (sword).

## 1. Canvas and ruler decision

Problem. The long ruler is ~215 output texels (0.65 x 331.5, ~31 world px). The output cell is 512x512 with the sprite anchor at x 273 and the feet row at 413, so there are 239 texels to the right of the anchor and 413 above the feet. The old 384x512 raw cell (scale ~0.87 to output) has body centre ~190 and only ~178 raw px to the right: a forward-pointing long ruler (hand at +60 raw plus ~208 raw ruler = ~270 raw) does not fit. The old attack sheets avoided this by drawing a ~125-130 px ruler and, later, by `paint_luz_ruler.py` repainting a long ruler per frame; the Penitent's visual reach (+77..+81 world px) was always carried by the slash VFX, not by the sword.

Decision.
1. Raw cells for the attack sheets are 512x512 (not 384x512), 3 columns x 3 rows = 1536x1536 per sheet (a size Codex already delivered for run/turn/skid), body centre x=210, lowest sole y=472. Forward room is 512-210-16 = 286 raw px: a horizontal ruler pointing forward from an extended hand (60 + ~208 raw) fits (268). Backward room is 194 raw px, enough for the idle-style trailing ruler (extent ~180) and for a horizontal-back ruler only if the hand is near the body, so back-pointing poses must point 20-35 degrees below horizontal, never horizontal to the cell edge.
2. Codex draws the ruler itself, copying length from the idle v3 reference (about 0.62-0.65 of standing height; it ignores text lengths). The ruler is NOT painted from scratch by default. At integration, `tools/luz_ruler_length.py` normalizes every frame to `RULER_TARGET_LENGTH` 215 (same as run/idle/turn/skid). This is the proven P7 path.
3. Fallback per frame: if the drawn ruler is foreshortened, hidden by the arm, or the normalized ruler would leave the 512 output cell, `paint_luz_ruler.py`-style erase and repaint at the measured grip and angle from the table below (angles are in section 3, +- 10 deg). The existing 40 degree swing about the grip (`MAX_TILT`) absorbs small overflows.
4. Headroom: output has 413 texels above the feet. A ruler raised overhead must therefore be angled (<= 35 degrees above horizontal when the grip is at head height, tip no higher than 1.15 x standing height). The Penitent never points the sword vertically either (up attack: sword at his right side pointing up-right, tip y ~45 of 48).
5. Lunge in hit 3: the sprite shows the lunging pose but the sprite stays centred in its cell; the +40 world px translation is done by `player.gd` (hit 3 lunge), not by the art.
6. No cell-size change is needed at integration (grid stays 512x512 output cells). Frame count per sheet is <= 9 slots. Slow holds (hit-stop) are repeated frames at integration, not new art.

Playback rule. The Penitent art steps irregularly (1-5 video frames per pose, roughly 15 fps art). Plan the clips at 30 fps ticks (1 tick = 2 video frames = 33 ms); the "ticks" column is how long each pose is held, so the integration can either duplicate frames or set per-frame durations. Sheets contain distinct poses only.

## 2. Global style block (paste at the top of every Codex prompt)

- Same character and same rendering as `luz_identity_ref.png` and the attached `luz_idle_raw_v3.png`: blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack. Same illustrated "pixel-styled" look, same density, same dark outline weight, same cel shading and palette. Do not redraw her in true pixel art and do not change proportions. No rim light or edge glow (the engine adds it).
- Ruler (her sword): a long light-brown wooden ruler with dark tick marks, as long as in the attached idle (about 65% of her standing height), identical length and width in every frame, held like a sword by its end: the hand grips the last ~15% of the ruler, the rest is the blade. Never a bat, never a real sword. Keep the full length visible in every frame (do not shorten it for foreshortening; when it points at or away from the camera tilt it 20-30 degrees so its length stays readable).
- Standing body height 340-380 px in the cell (same scale as the attached idle, top of hair to sole), identical body scale in every frame; crouched poses are lower, not smaller.
- Background: ONE flat pure magenta #FF00FF everywhere outside the character, no gradient, no glow, no vignette, no shadow, no antialiasing halo into other colours. No ground, no shadow, no slash smear, no crescent, no motion lines, no sparks, no dust, no text, no numbers, no grid lines. Only the character and her ruler.
- Right-facing side view in every frame. Lowest sole on y=472 of its cell (in every row, so y=472, 984, 1496). Body centre near x=210 of its 512x512 cell, at least 16 px of padding to every cell edge, nothing crosses into a neighbouring cell.
- Penitent attachments are POSE references only (body mechanics, weight, timing): do not copy his armor, helmet, red sash, or his sword; do not draw the cream crescent VFX that appears in them.
- Output files go in `tools/art_sources/luz/raw/` (gitignored); reply with the path and image size. Do not edit any other file.

## 3. Sheets

Common: 1536x1536, 3 columns x 3 rows of invisible 512x512 cells, row-major, slot 1 top-left. Empty slots stay magenta. Ruler angles: degrees above (+) or below (-) horizontal, measured from the grip, pointing F (forward/right) or B (back/left), +-10 deg. Heights are in fractions of standing height H.

Attachments for every job: 1 `tools/art_sources/luz/refs/luz_identity_ref.png`, 2 `tools/art_sources/luz/raw/luz_idle_raw_v3.png` (style, scale, sword grip, ruler length), 3 the Penitent pose sheet named per sheet.

### 3.1 hit1 -> `luz_attack_hit1_raw.png` (9 frames) - Penitent `sheet_ground.png`, frames 624-652

Ground hit 1: windup (7 video frames from idle), slash A flat at waist (4 f), slash B high backhand (5 f), hold, recover. Feet never move (same x), only the torso leans forward ~+5 world px (~35 texels at output scale). Chains into hit 2 from the "raise" pose.

| # | Video ref | Ticks @30 fps | Pose | Ruler |
|---|---|---|---|---|
| 1 | 624-626 | 1 | Idle stance (as the idle v3), sword low behind, hand starts to open | 35 below, B |
| 2 | 627-629 | 2 | WINDUP: feet planted and a little wider, sword hand raised slightly, blade back-left; leading fist forward at chest height | 20 below, B |
| 3 | 630-631 | 1 | CHARGE: body drops and leans forward, blade held short and horizontal across the chest in front | 0, pointing F, ruler held in front at chest height (tilt 15 below so length reads) |
| 4 | 632 | 1 | RAISE: blade swings up and back, tip high behind the head (this is the chained-combo hold pose) | 30 above, B |
| 5 | 633-634 | 2 | SLASH A: arm fully extended forward at waist height, torso leans forward, blade straight forward | 5 below, F |
| 6 | 635-636 | 2 | A follow: same, arm fully extended, blade still forward, slight overshoot, front knee bent | 5 above, F |
| 7 | 637-639 | 3 | SLASH B: backhand, blade swept overhead to head height, pointing back-left, torso twisted back, arm across the chest | 25 above, B |
| 8 | 642-647 | 3 | HOLD: blade horizontal at head height pointing back-left, weight settling | 15 above, B |
| 9 | 648 | 2 | RECOVER: back to the idle stance, sword low behind (same as slot 1) | 35 below, B |

### 3.2 hit2 -> `luz_attack_hit2_raw.png` (8 frames) - Penitent `sheet_combo3.png` row HIT2, frames 399-420

Hit 2 follows hit 1 after a 4 f windup. A' is slightly lower than A. B' is a LOW long backhand: the blade sweeps from behind at waist height down to knee height and forward. No lunge.

| # | Video ref | Ticks | Pose | Ruler |
|---|---|---|---|---|
| 1 | 399 | 1 | Chained windup: weight slightly forward, sword hand back, blade back-left and low | 20 below, B |
| 2 | 402-405 | 3 | RAISE HOLD: blade up and back, tip behind the head, torso coiled | 30 above, B |
| 3 | 409-410 | 2 | SLASH A': arm extended forward, torso slightly lower than hit 1 (knees bent a little more), blade straight forward below waist | 10 below, F |
| 4 | 411 | 1 | A' follow: blade forward, shoulders open | 0, F |
| 5 | 412-413 | 2 | SLASH B': backhand low: torso rotates back and bends, arm swung down and behind, blade at knee height pointing back-left and slightly down | 25 below, B |
| 6 | 414-416 | 2 | B' follow: blade swept low and forward at knee height, torso low, weight on front leg | 15 below, F |
| 7 | 417-420 | 2 | HOLD: blade low in front-left, torso rising | 35 below, B |
| 8 | 424 | 1 | RECOVER: back to idle (same as hit 1 slot 9) | 35 below, B |

### 3.3 hit3 -> `luz_attack_hit3_raw.png` (9 frames) - Penitent `sheet_combo3.png` row HIT3, frames 424-462 and G2/G3 stills

Finisher: long windup (9-13 video frames, ~0.19 s) with the sword raised above the head and the torso leaning back, then a lunge (+35..+50 world px, done in code) with the body low and the sword trailing low behind, then the huge rising crescent (VFX) while the pose is frozen (hit-stop 12 f), then a slow recover.

| # | Video ref | Ticks | Pose | Ruler |
|---|---|---|---|---|
| 1 | 424 | 2 | Prep: weight shifts back, sword hand pulled back and up, free fist forward | 10 above, B |
| 2 | 427 | 2 | Windup: sword pulled up and behind above the head, torso leaning back, back knee bent, chest open | 30 above, B |
| 3 | 430 | 2 | MAX WINDUP: ruler raised above the head angled back (tip no higher than 1.15 H), arm bent behind the head, deep lean back, feet planted wider | 35 above, B |
| 4 | 431 | 1 | SNAP: body whips forward, arm swings down and forward past the head, ruler passes through the vertical-ish front | 40 below, F |
| 5 | 432-433 | 2 | LUNGE: body low and stretched far forward, head at ~65% H, front leg bent deeply, back leg extended, free arm forward, ruler trailing low behind-left at knee height | 20 below, B |
| 6 | 434 | 6 | LUNGE HOLD (hit-stop pose): the same as 5 with the sword hand thrust forward, ruler pointing behind | 15 below, B |
| 7 | 446-449 | 2 | STOP: weight over the front foot, torso rising, sword hand low | 30 below, B |
| 8 | 455-462 | 3 | Rising: back to a wide stance, blade low behind | 35 below, B |
| 9 | 648 | 2 | RECOVER: idle stance (same as hit 1 slot 9) | 35 below, B |

### 3.4 crouch -> `luz_attack_crouch_raw.png` (8 frames) - Penitent `sheet_crouch.png`, frames 745-790

Crouched: head top ~0.75 H (36 world px tall body ~ 0.75 of standing), feet fixed. Windup 4 f from the crouch hold, sweep 1 diagonal descending (4 f), sweep 2 low backhand (3 f), return.

| # | Video ref | Ticks | Pose | Ruler |
|---|---|---|---|---|
| 1 | 747-756 | 3 | Crouch hold: deep squat, torso forward, weight low, sword low behind | 25 below, B |
| 2 | 757 | 1 | Lunge down: body drops a little more, blade back | 30 below, B |
| 3 | 758-759 | 1 | RAISE: arm raised, blade up at head height behind | 30 above, B |
| 4 | 760 | 1 | Raise 2: blade over the shoulder, ready to cut | 40 above, B |
| 5 | 761-764 | 2 | SWEEP 1: the cut: torso rotates forward, arm extended forward and DOWN, ruler diagonal pointing forward-down toward the ground in front (tip clearly above the sole row) | 35 below, F |
| 6 | 765-767 | 2 | SWEEP 2: backhand low: arm swung back along the ground behind the legs, torso twisted, ruler low and pointing back-left | 25 below, B |
| 7 | 768-770 | 2 | Arm return: ruler comes back, torso straightening to the crouch | 30 below, B |
| 8 | 774-779 | 2 | Recover crouch: same as slot 1 | 25 below, B |

### 3.5 air -> `luz_attack_air_raw.png` (8 frames) - Penitent `sheet_air.png`, frames 993-1012

Airborne near the apex, knees tucked, feet off the ground (still place the lowest sole at y=472 in the cell for the pipeline). Windup 3 f, slash A (5 f, big diagonal in front), slash B (5 f, low horizontal at knee/hip height), post pose falling stretched.

| # | Video ref | Ticks | Pose | Ruler |
|---|---|---|---|---|
| 1 | 993-996 | 1 | Tuck: knees pulled up, sword hand behind the hip, free arm in front | 30 below, B |
| 2 | 997-999 | 1 | WINDUP: sword drawn back and up behind the head, arm forward for balance, legs tucked | 30 above, B |
| 3 | 1000-1001 | 1 | A start: torso opens, arm starts forward and down, ruler overhead behind | 20 above, B |
| 4 | 1002-1004 | 2 | SLASH A: arm extended forward and down in front, torso leaning forward, ruler diagonal forward-down | 30 below, F |
| 5 | 1005-1006 | 2 | SLASH B start: legs tucked, arm swung back around at hip height, ruler horizontal low pointing back-left | 15 below, B |
| 6 | 1007-1009 | 3 | SLASH B: low backhand through knee height, ruler pointing forward and slightly down | 10 below, F |
| 7 | 1010 | 1 | Post pose: arms spread, body stretching, ruler low behind | 30 below, B |
| 8 | 1011-1012 | 2 | Falling stretch: legs extending, ruler low behind (like the fall pose) | 35 below, B |

### 3.6 up -> `luz_attack_up_raw.png` (8 frames) - Penitent `sheet_up.png`, frames 340-362

The up attack is mostly a held pose: arm and sword go up and to the right side while the overhead arc (VFX, 125 world px high) draws. Feet never move.

| # | Video ref | Ticks | Pose | Ruler |
|---|---|---|---|---|
| 1 | 340-341 | 1 | Idle stance, sword low behind | 35 below, B |
| 2 | 342-343 | 1 | WINDUP: slight crouch, free arm raised over the head, sword hand back | 25 below, B |
| 3 | 344-345 | 1 | Arm sweeping up and back over the head, torso leaning back a little | 5 above, B |
| 4 | 346-347 | 1 | Arm out to the right, torso rotating forward, free hand open | 10 above, F |
| 5 | 348 | 1 | READY: stance wide, sword hand at the right shoulder, ruler held up-right in a reverse-ish grip (tip no higher than 1.05 H) | 60 above, F |
| 6 | 349-352 | 4 | ARC (hold): same as 5, slight lean back, chin up | 60 above, F |
| 7 | 353-358 | 4 | ARC fade (hold): same, arm eases, ruler tilts forward | 50 above, F |
| 8 | 359-360 | 2 | RECOVER: sword comes down, back to the idle stance | 35 below, B |

## 4. Codex prompts

Each prompt is ready to paste after the global style block (section 2). The Penitent attachment is the third `-i`.

### 4.1 hit1
> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. [global style block]. Generate ONE 1536x1536 PNG, 3 columns x 3 rows of invisible 512x512 cells, row-major, nine frames of Luz's GROUND ATTACK HIT 1, a fast, weighty, fluid forehand horizontal sword slash at waist height followed by a high backhand, like the attached Penitent reference `sheet_ground.png` (body mechanics only). Her sword is the long ruler held by its end in her right hand. Right-facing, feet planted and never moving, standing body height 360 px, lowest sole at y=472 of each row, body centre near x=210. Frames: 1 idle stance, ruler trailing low behind (35 deg below horizontal); 2 windup, feet slightly wider, sword hand raised, ruler back-left 20 deg below horizontal, free fist forward at chest height; 3 charge, body drops and leans forward, ruler held across the front of the chest tilted 15 deg down; 4 raise, ruler swung up and back 30 deg above horizontal, tip behind her head; 5 slash A, arm fully extended forward at waist height, torso leaning forward, ruler pointing forward 5 deg below horizontal; 6 same as 5, slight overshoot, front knee bent, ruler 5 deg above horizontal pointing forward; 7 slash B, backhand: ruler swept up to head height pointing back-left 25 deg above horizontal, torso twisted back, arm across the chest; 8 hold, ruler 15 deg above horizontal pointing back-left, weight settling; 9 recover to the idle stance of frame 1. Same ruler length and body scale in every frame, every frame a distinct pose, no slash effects drawn.

### 4.2 hit2
> [same header] ... nine-cell sheet with EIGHT frames (slots 9 empty magenta) of GROUND ATTACK HIT 2 (second hit of the combo), attached Penitent reference `sheet_combo3.png` (use the HIT2 row; ignore the enemy, the wheel, the blood and every glowing slash). Frames: 1 chained windup, weight slightly forward, sword hand back, ruler back-left 20 deg below horizontal; 2 raised, ruler up and back 30 deg above horizontal with the tip behind her head, torso coiled; 3 slash A', arm forward, torso a little lower than hit 1 (knees bent more), ruler pointing forward 10 deg below horizontal; 4 follow, ruler forward horizontal, shoulders open; 5 slash B' = LOW backhand: torso rotates back and bends, arm swung down and behind, ruler at knee height pointing back-left 25 deg below horizontal; 6 B' follow, ruler swept low and forward at knee height 15 deg below horizontal, torso low, weight on the front leg; 7 hold, ruler low in front-left 35 deg below, torso rising; 8 recover to idle (ruler trailing low behind, 35 deg below horizontal). [rules as in hit1]

### 4.3 hit3
> [same header] ... NINE frames of GROUND ATTACK HIT 3, the lunging finisher, attached Penitent reference `sheet_combo3.png` (HIT3 row; ignore enemies, blood and the big glowing crescent). Frames: 1 weight shifts back, sword hand pulled back and up, ruler 10 deg above horizontal pointing back-left; 2 windup, ruler raised and pulled behind the head 30 deg above horizontal, torso leaning back, back knee bent; 3 MAX WINDUP, ruler raised above her head angled back 35 deg above horizontal (tip no higher than 1.15 x her standing height), arm bent behind the head, deep lean back, feet wide; 4 snap, body whips forward, arm swinging down and forward past the head, ruler 40 deg below horizontal pointing forward; 5 LUNGE, body low and stretched far forward, head at 65% of standing height, front knee deeply bent, back leg extended, free arm forward, ruler trailing low behind her at knee height 20 deg below horizontal; 6 lunge peak held, same as 5 with the sword hand thrust forward; 7 stop, weight over the front foot, torso rising, ruler low behind 30 deg below horizontal; 8 rising to a wide stance, ruler low behind; 9 recover to the idle stance. Sole row y=472 in every frame (crouched poses are lower, not smaller). [rules as in hit1]

### 4.4 crouch
> [same header] ... EIGHT frames of CROUCH ATTACK, attached Penitent reference `sheet_crouch.png`. She is crouched with her head at about 75% of her standing height throughout and her feet planted; sole row y=472. Frames: 1 deep crouch hold, torso forward, ruler low behind 25 deg below horizontal; 2 body drops lower, ruler back 30 deg below; 3 arm raised, ruler up behind at head height 30 deg above horizontal; 4 ruler over the shoulder 40 deg above, ready to cut; 5 SWEEP 1, torso rotates forward, arm extended forward and down, ruler diagonal pointing forward-down 35 deg below horizontal (tip stays above the sole row); 6 SWEEP 2, low backhand, arm swung back behind the legs, torso twisted, ruler low pointing back-left 25 deg below horizontal; 7 arm returns, torso straightening; 8 recover to the crouch of frame 1. [rules as in hit1]

### 4.5 air
> [same header] ... EIGHT frames of AIR HORIZONTAL ATTACK near the apex of a jump, attached Penitent reference `sheet_air.png` (ignore backgrounds and slashes). She is airborne in every frame with knees tucked; draw no ground; put the lowest sole at y=472. Frames: 1 tuck, knees up, sword hand behind the hip, free arm forward, ruler 30 deg below behind; 2 windup, ruler drawn back and up behind her head 30 deg above horizontal, legs tucked; 3 torso opens, ruler overhead behind; 4 SLASH A, arm extended forward and down in front, torso leaning forward, ruler diagonal pointing forward-down 30 deg below horizontal; 5 SLASH B start, arm swung back around at hip height, ruler horizontal-low pointing back-left; 6 SLASH B, low backhand through knee height, ruler pointing forward and slightly down; 7 post pose, arms spread, body stretching, ruler low behind; 8 falling stretch, legs extending, ruler low behind. [rules as in hit1]

### 4.6 up
> [same header] ... EIGHT frames of UP ATTACK, attached Penitent reference `sheet_up.png` (ignore backgrounds, the big cream arc and the red cloth), feet planted and never moving. Frames: 1 idle stance, ruler low behind 35 deg below horizontal; 2 windup, slight crouch, free arm raised over her head, sword hand back; 3 arm sweeps up and back over the head, torso leaning back a little, ruler near horizontal behind; 4 arm out to the right, torso rotating forward, free hand open; 5 READY: wide stance, sword hand at her right shoulder, ruler held up and forward-right at 60 deg above horizontal (tip no higher than 1.05 x standing height); 6 same as 5, slight lean back, chin up; 7 same, arm eases, ruler tilts to 50 deg; 8 recover, ruler comes down behind her to the idle stance. [rules as in hit1]

## 5. Integration notes (after the raws are reviewed)
- New processor cloned from `process_luz_run_turn_skid.py` (raw cell 512x512, `RAW_CELL_W` configurable), magenta key (`clean_key`), `place()` with fixed scale (standing 331.5 / raw standing, measured per sheet), anchor at the idle centroid x 273, feet row 413, `luz_ruler_length.normalize_ruler` as the last step of every frame.
- Per-frame ruler overflow (forward at x > 512) is relaxed by the swing up to `MAX_TILT`, reported if it fails; the paint fallback applies to those frames.
- Hit holds (hit-stop) and tick durations come from the tables, not from the art; hit 3 lunge translation and the combo-advances-on-hit rule belong to `player.gd`.

### Integration result (2026-10-08, `tools/process_luz_attacks.py`)
- Sheets: `luz_ground_combat_sheet.png` (ground_attack_1 0-8, ground_attack_2 9-16, ground_attack_3 17-25, crouch_attack 26-33) and `luz_air_combat_sheet.png` (up_attack 0-7, air_horizontal_attack 8-15, plunge 16-23 unchanged).
- Anchor: front foot on the idle's front foot (ground and up), body centroid on the idle's (air). Scales per sheet: hit1 0.77, hit2 0.67, hit3 0.90, crouch 0.72, air 0.74, up 0.79.
- Ruler: 215 texels wherever it fits the 512 cell; forward-thrown frames carry the longest ruler that fits (110-160 texels), re-aimed at the angles of section 3 (see the P8a entry in `odd/tasks/luz-final.md`). The manifest sheet entries hold `contact_frames`, `phases` and `frame_ticks_30fps` per clip for the combat timing.

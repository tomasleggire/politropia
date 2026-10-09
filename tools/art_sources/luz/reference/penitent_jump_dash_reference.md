# Blasphemous Penitent: jump and dash reference for Luz

Source: 60 fps screen recordings (static camera in Salto/Dash/Caminar/Ataque; the camera scrolls in "Atacar enemigos y morir", so that clip was used only qualitatively).
Scale check: FFT of the edge profile gives an art pixel of 3.00 video px in all 5 videos. Units below are Luz px with 1 Luz px = 3.08 video px (body 148 video px = 48 px). To get Penitent art px, multiply by 1.027.
Tracking: red sash centroid (torso reference) + background-model mask (feet). Time resolution is 1 frame (16.7 ms). The captures contain duplicated frames (capture stutter), so single-frame timings are +-1 frame.
Tags: [M] measured, [E] estimated/derived, [V] visual only. Confidence: H/M/L.
Plots and contact sheets: `penitent/f/` (salto_overview.png, jump_overlay.png, dash_aligned.png, dash_overview.png, sheet_salto1.png, air_poses.png, run_jump.png, ataque_jump.png, ataque_land2.png, dash_close.png, dash_vfx.png). Per-frame curve: `penitent/jump_curve.csv`.

## 0. Reference-point warning (important)

"Height" depends on what you track. The sash (torso) rises the same in every jump: 86-89 px. The visible feet rise less in the standing jump (about 75, legs hang down) and about 85 in the running jump (legs tucked). The torso trajectory is the physics trajectory; the feet are pose. Luz's `jump_height` is the collider travel, so use the torso number (about 87), not the 77 from the previous estimate. [M, M-H]

## 1. Jump

### 1.1 Measured jumps (Salto.mov, 9 usable instances; torso = sash height above ground pose)

| # | frame takeoff | type | torso height | rise (frames) | fall (frames) | airtime (frames) | x speed in air |
|---|---|---|---|---|---|---|---|
| 1 | 30 | stand, held | 85.6 | 27 | 23-24 | 51 | 0 |
| 2 | 107 | stand, held | 85.7 | 22-26 | 27 | 50 | 0 |
| 3 | 186 | stand, tap | 74.7 | 21 | 23 | 45 | 0 |
| 4 | 266 | stand, tap | 73.7 | 20 | 23 | 44 | 0 |
| 5 | 432 | run left | 86.7 | 25 | 23 | 49 | -158 |
| 6 | 532 | run right | 88.6 | 26 | 24 | 51 | +164 |
| 7 | 627 | run left | 89 | ~25 | 23 | 50 | -166 |
| 8 | 710 | run right | 88.6 | 25 | 24 | 50 | +158 |
| 9 | 777 | run left | 89 | 29 | 24 | 54 | -161 |

Ataque.mov (7 jump + air-attack instances, in place): torso height 82-85, airtime 48-49 frames every time (gravity is not changed by attacking). [M, H]

Summary (full jump): height 87 (86-89) px; rise to apex 26-27 frames = 0.44-0.45 s; fall 24-25 frames = 0.40-0.42 s; airtime 50 frames (0.83-0.87 s); apex hang (within 3 px of the top) 5-8 frames (about 0.1 s). [M, H]
Summary (tap): height 74 (0.85 of full); airtime 44-45 frames (0.74 s). [M, M] Only two heights appear in all clips (0.85 and 1.0).

### 1.2 Curve (median of the 5 clean full jumps and the 2 taps, torso px, k = frames since first airborne frame minus 1)

| k | t (s) | full | tap |
|---|---|---|---|
| 0 | 0.000 | 3 | 0 |
| 2 | 0.033 | 22 | 22 |
| 4 | 0.067 | 31 | 32 |
| 8 | 0.133 | 47 | 48 |
| 12 | 0.200 | 62 | 61 |
| 16 | 0.267 | 73 | 69 |
| 20 | 0.333 | 82 | 73 |
| 24 | 0.400 | 85 | 73 |
| 26-28 | 0.45 | 86 | 71-69 |
| 32 | 0.533 | 85 | 61 |
| 36 | 0.600 | 77 | 49 |
| 40 | 0.667 | 60 | 32 |
| 44 | 0.733 | 44 | 14 |
| 48 | 0.800 | 25 | 0 |
| 52 | 0.867 | 3 | - |

Features: [M, H]
- No anticipation: the idle pose (k=-1) is followed immediately by the airborne pose. The sprite rises about 20 px in the first 2 frames (launch-pose offset plus about 300 px/s), then decelerates smoothly.
- After the first 2 frames, rise is a parabola: apex at k about 28, g_rise about 680 px/s^2 (fit), initial v about 300 px/s. Fall is a parabola with g_fall about 1100 px/s^2 (ratio about 1.6 versus the fit; the whole-curve equivalent ratio in section 1.6 is 1.15).
- Landing speed about 380 px/s at touchdown (no terminal-velocity clamp reached; the fall curve is still accelerating).
- Taps follow exactly the same curve as full jumps until k about 15-18 (0.25-0.30 s, about 70 px), then the rise is cut: the apex is reached within about 3 frames at 73-75 and the descent starts early. Both taps cut at the same moment, which suggests a game-defined minimum jump (min hold about 0.25-0.3 s, min height about 0.85). We do not know what a much shorter tap does. [M cut shape, L whether a lower minimum exists]

### 1.3 Horizontal motion
- Air speed = run speed: 161 +-4 px/s (fits: 158.4, 164.2, 166.3, 157.8, 161.1). Ground run speed measured in Caminar: 145-169 (mean about 157). [M, H]
- Takeoff keeps the running speed instantly (no ramp, no speed bump). Speed is constant through the air (the +-30 px/s ripple in the tracker is pose jitter). Standing jumps have 0 px/s. [M, H]
- Running jump distance: about 130-135 px over 0.83 s (measured dx 128-131 for 49-51 frame jumps). [M]
- Mid-air direction reversal and air acceleration: not observed in any clip (no input visible). [unknown]
- Run start: full speed in 1-3 frames; stop from full speed: 5-6 frames (Caminar). Effectively instant accel; accel/decel not critical. [M, M]

### 1.4 Takeoff / landing behaviour
- Standing landing (Salto, jump 1): touch frame 81 jumps straight to a deep crouch pose, then poses step at frames 81, 86, 91, 95, 99 (holds of 4-5 frames, the landing animation is about 13 fps), idle again at 102. Recovery 21 frames (0.35 s). [M, H]
- Running landing: no stop. The character lands in a low run-lunge pose and keeps running (about 160 px/s in the first 2 frames after touchdown, 4-6 px low in the torso). Landing lock about 0-2 frames. [M, M-H]
- Jump out of landing: in Ataque the next jump started 11-17 frames after touchdown (gaps 17, 14, 12, 11, 11, 25; the user pressed progressively sooner). It launches straight out of the deep crouch pose (no extra anticipation). So the landing recovery is cancellable by jump after about 10-11 frames (0.17-0.18 s). Whether this is a buffered press or a free cancel cannot be told. [M the gaps, L the mechanism]
- Locked movement during the landing animation: not testable here. [unknown]
- Coyote time and jump buffering: no evidence in the clips. Ledge: dashing off a ledge ends the slide and the character falls normally (Morir frames 253-300, camera scrolls). [V]

### 1.5 Pose timeline (standing jump, frames relative to the first airborne frame k=0 at clip frame 30; 60 fps)

| frames (k) | pose | notes |
|---|---|---|
| -1 | idle | no anticipation |
| 0-19 | ascent: body vertical, legs together trailing, sword held low vertical on the left, red sash hanging | continuous motion, no discrete hold |
| 20-35 | apex: arms spread, sword swung horizontal to the left, hair/ribbon visible | hold about 16 frames |
| 36-50 | fall: arms out, legs straight down, sword angled | until touchdown (frame 81 in the clip) |
| land 0-4 | deep crouch, sword low, torso very low | shown 5 frames |
| land 5-9 | crouch step 2 | 5 frames |
| land 10-14 | crouch step 3 (rising) | 5 frames |
| land 15-17 | half-crouch | 4 frames |
| land 18-20 | stance recover | 4 frames; idle at 21 |

Running jump uses a different air pose: knees tucked, arms/sword trailing behind (see run_jump.png). The running jump has a short turn/lean frame before takeoff when reversing direction (frame 429). [V]

### 1.6 VFX (jump)
- Takeoff dust: a tiny cream "M"-shaped puff (about 8 px wide, 5 px high) appears on the ground 2 frames after takeoff at the takeoff spot and stays static about 15 frames while fading. [V, M]
- Landing dust: small cream flecks (2-3 px) spray sideways from both feet, spreading to about +-25 px, over about 12-15 frames, starting at the touch frame. [V, M]
- No jump afterimages.

### 1.7 Jump parameters for Luz (derived)
Luz derives gravity as 2h/T^2 (player.gd line 444). To reproduce the measured whole-curve timing (apex 0.45 s, fall 0.42 s, height 87):
- jump_height 87, time_to_apex 0.45 -> rise gravity 859 px/s^2, v0 = 387 px/s
- fall multiplier (0.45/0.42)^2 = 1.15 -> fall gravity 988 px/s^2 (fall about 0.42 s, airtime 0.87 s, touchdown speed about 415 px/s)
- The first 2 frames in the real game are about 9 px higher than this parabola; handle that in the art offset of the first jump frame, not in physics.

## 2. Dash

### 2.1 Measured dashes (Dash.mov, 6 clean dashes; slide = sash height below 48; time zero = first slide frame s)

| # | start frame | direction | start speed | slide pose frames | x travelled in 25 frames |
|---|---|---|---|---|---|
| 1 | 13 | right | rest | 26 | 119.5 |
| 2 | 84 | left | running (about 140) | 28 | 137.7 |
| 3 | 153 | right | running | 28 | 137.7 |
| 4 | 216 | left | running | 28 | 139.9 |
| 5 | 286 | right | running | 25 | 127.6 |
| 6 | 349 | left | running | 27 | 138.0 |

Slide pose lasts 25-28 frames (0.43-0.47 s). A 7th dash exists in Morir (frames 253-280, 27 frames, slides to a ledge and falls off). [M, H]

### 2.2 Velocity profile (px/s, aligned on s, mean of 6, 3-frame smoothing)
- From rest (dash 1): 4-8 frames before s the character leans back about 10 px (anticipation in x, about -80 px/s, pose crouches at frame 12-14). From s: speed 60 (s+1), 180 (s+2), 240 (s+3), 300 (s+4), 400 (s+5).
- Mean over all 6 (smoothed): ramp s to s+4: about 120 -> 380 px/s; plateau s+4 to s+18 about 395 px/s (range 380-460), duration 15-16 frames = 0.25-0.27 s; ease-out s+19 to s+22: 330 -> 150 px/s; then ordinary run (150-170) if the direction is held. From rest the ease-out goes down to about 90-100 px/s for 4-5 frames before the character stands. [M, M-H; the tracker has +-40 px/s jitter]
- Peak instantaneous values seen: 430-490 px/s (single-frame jitter, do not use). Use 395-400 as the plateau.
- Distance: from rest 120 px (dash) + about 15 px (brake) = about 135; started from a run, 138 px over the same window. [M, H]
- Startup before movement: from rest, the slide pose starts at s with 1-2 near-zero frames, and the lean-back wind-up is 4-8 frames (frames 4-12 in the clip). In running dashes there is no visible wind-up. [M, M]
- Recovery: sprite stands up at s+25..27 (sash height 38 -> 52 in 2 frames); movement resumes at run speed (150-170) immediately if held (about 0-3 frames lockout). [M, M]
- Cooldown: shortest gap between the end of one dash and the start of the next was 35 frames (0.58 s) (user limited). So cooldown <= 0.58 s; the real value is unknown. [M bound, unknown value]
- Slide silhouette: sash drops 16-22 px (54-60 -> 38); full silhouette about 23-24 px tall including the helmet spike versus about 52 standing, i.e. about 0.45-0.5. Collider 0.5 is right. [M, M-L]
- Ledge: the dash is ground-only; at a ledge it ends and the character falls with ordinary gravity in the stand pose (Morir 271-300). [V]
- Air dash, i-frames, chaining into jump/attack: not observable in these clips. [unknown]

### 2.3 Pose timeline (dash from rest, frames from the clip, s = 13)

| frames | pose | notes |
|---|---|---|
| 0-11 | idle, sword forward-low | |
| 4-12 | slight lean back (x -10 px) | wind-up |
| 12-14 (s-1..s+1) | crouch start, dust puff behind the feet at 14 | sash drops 8 px |
| 16-18 | low lunge, sword trailing behind | ramp |
| 20-36 (s+7..s+23) | full slide: torso horizontal and low, legs spread, sword trailing horizontally behind at ground level | plateau and ease; sash 40 -> 38 |
| 38 | stand-up / recovery, sword forward | s+25 |
| 40-46 | upright braking/run pose, cream skid fan in front of the feet | 6-8 frames |

### 2.4 VFX (dash)
- Afterimage: translucent purple copies of the full slide pose trailing behind. Purple pixel count: starts at frame 14 (s+1), saturates at about 4500 by s+9, stays until s+22, falls to nothing by s+31 (about 6 frames after the dash ends). Trail length about 55-60 px behind the body, consistent with ghost lifetime of about 8-9 frames (0.13-0.15 s) at 400 px/s; spawn interval about 2 frames (4-5 ghosts alive). This replaces the previous "0.43 s lifetime"; 0.43 s is the dash total, not the ghost life. [M for timing, V for count/alpha]
- Alpha: first ghost about 0.6-0.7 fading to about 0.1 over its life (visual). [E, L]
- Start dust: one cream puff behind the feet at s+1, about 12 px wide by 8 high. [V, L]
- End dust: cream skid fan in front of the feet at s+25..s+33, about 18 px wide by 14 high, plus a second small puff. [V, L]

### 2.5 Dash parameters for Luz
Luz profile: full speed for `dash_full_speed_ratio * dash_duration`, then ease to run speed. No ramp.
- dash_speed 395-400
- dash_duration 0.43 (keep equal to the slide pose length 26 frames)
- dash_full_speed_ratio 0.50 (full for 0.215 s; real plateau 0.25 s but real ramp costs 0.07 s)
- Resulting distance: 0.215*395 = 85 + 0.215*(395+150)/2 = 58 -> about 143 px. This matches the measured 138 from a run and 135 from rest (with brake). Current Luz values (480, 0.45, 0.70) give about 193 px, about 40% too far.
- If you want a pure rest dash of 120: dash_duration 0.40 and ratio 0.45.
- dash_cooldown: keep 0.35 (observed <= 0.58). Air dash left as is (no data).
- Add a 4-5 frame (0.07-0.08 s) lean/crouch wind-up in the art when starting from rest (visual only; can overlap the first frames with movement to avoid input lag).

## 3. Open points

- Minimum jump height for a very short tap (only 0.85 and 1.0 observed). Test: shortest possible tap.
- Is the landing lock a hard lock (about 0.35 s, jump-cancellable at 0.18 s) or does movement allow steering during it? Not testable without input visibility.
- Coyote time and jump buffer window.
- Mid-air direction change and air acceleration.
- Dash cooldown, dash chaining (dash -> jump, dash -> attack), air dash, invulnerability.
- First-frame art offset of the launch pose (about 9 px above physics in frames 0-2).

## 4. Godot parameters to set (player.gd export groups)

| Group | Export | Current | Set | Basis |
|---|---|---|---|---|
| Jump | jump_height | 130 | 87 | torso travel [M, H] |
| Jump | jump_time_to_apex | 0.36 | 0.45 | 27 frames [M, H] |
| Jump | fall_gravity_multiplier | 1.2 | 1.15 | fall 25 vs rise 27 frames [M, M] |
| Jump | max_fall_speed | 900 | >= 450 (900 is fine) | landing about 415 [E] |
| Jump | jump_release_multiplier | 0.45 | keep, but add min jump (hold about 0.28 s or min height 0.85*87 = 74) | taps all 74 [M, M] |
| Jump | coyote_time / jump_buffer_time | 0.08 / 0.10 | keep | no data |
| Double Jump | can_double_jump / air_jumps | false / 1 | keep false | Penitent has none in the clips |
| Air Control | air_max_speed | 250 | 160 (= run speed) | 161 +-4 [M, H] |
| Air Control | air_acceleration / air_deceleration | 2600 | keep; no data | |
| Run | run_max_speed | 150 | 155-160 | 145-169, mean 157 [M, M] |
| Landing | landing_squash_time | 0.08 | 0.35 standing hard landing, 0.0 (no pause) when landing at run speed; allow jump from 0.18 s | [M, M-H] |
| Landing | landing_impact_speed | 150 | keep; it only gates the animation | |
| Dash | dash_speed | 480 | 395-400 | [M, M-H] |
| Dash | dash_duration | 0.45 | 0.43 | [M, H] |
| Dash | dash_full_speed_ratio | 0.70 | 0.50 | gives about 143 px [E] |
| Dash | dash_cooldown | 0.35 | keep | bound <= 0.58 |
| Dash | air_dash_duration | 0.30 | keep | no data |
| Crouch | crouch_collider_scale | 0.5 | keep (slide about 0.45-0.5) | [M, M-L] |

Largest differences versus current Luz: jump is 1.5x too high (130 versus 87) and 20% too fast to apex; air speed 250 versus 160; dash about 40% too long.

## 5. Differences versus the previous rough estimates

| Item | Previous | Now |
|---|---|---|
| Jump height | 77 (feet, standing) | 87 torso (75 feet standing, 85 feet running) |
| Apex time | 0.417 s | 0.45 s (26-27 frames) |
| Symmetric fall | yes | no, fall 0.40-0.42 s (about 8% shorter); airtime 0.87 s |
| Gravity | 873 constant | 859 rise, 988 fall (whole-curve equivalent) |
| v0 | -364 | -387 |
| Air x speed | 152-155 | 161 +-4 (= run 157) |
| Variable height | min 0.88 | 0.85, cut at 0.25-0.3 s |
| Landing | 21 frames standing | confirmed 21; running about 0-2; jump-cancel at about 11 frames |
| Dash plateau | 400 for 0.25 s | 395 for 0.25-0.27 s, ramp 5 frames (confirmed) |
| Dash distance | 119 + 10 | 120 + 15 from rest, 138 from run |
| Dash startup | 4 frames still crouch | lean-back x -10 px over 4-8 frames before slide, slide begins moving within 1-2 frames |
| Slide height | 0.53 | about 0.45-0.5 |
| Ghost lifetime | 0.43 s | 0.13-0.15 s (trail lasts about 0.4-0.5 s total) |

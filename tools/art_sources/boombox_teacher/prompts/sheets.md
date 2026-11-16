# El Profesor - animation sheets (run)

Contract: `docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md`. Approved design: `concept/teacher_concept_v1.png` (variant b of the concept run; `teacher_concept_v1_alt.png` is the discarded variant a). Rule 0: same style as Luz and Artemis, tall build kept.

Eight Codex runs, one per raw sheet, in parallel, with the approved concept and `luz_identity_ref.png` as `-i`. Raw sheets go to `../raw/boombox_teacher_<sheet>_raw.png`; `tools/process_boombox_teacher_sheets.py` keys the magenta, splits frames by connected components per grid cell, applies one scale, aligns the lowest sole on the feet row and writes `assets/enemies/boombox_teacher/`.

All sheets are 1536x1024: 4 columns x 2 rows of 384x512 cells, except `thrust` (3 x 2 cells of 512x512). Every character sheet asks for the same standing height (about 360 raw px, sole to the top of the boombox), but Codex does not keep it (about 370 to 445 px in practice), so the processing script scales each sheet by the size of the boombox head (see ).

| Raw sheet | Grid | Clips (raw cell indices) |
|---|---|---|
| `boombox_teacher_loco_raw.png` | 4x2 | `idle` 0-3, `walk` 4-7 |
| `boombox_teacher_thrust_raw.png` | 3x2 | `thrust_high_windup` 0, `thrust_high_strike` 1, `thrust_high_recover` 2, `thrust_low_windup` 3, `thrust_low_strike` 4, `thrust_low_recover` 5 |
| `boombox_teacher_throw_raw.png` | 4x2 | `throw_windup` 0-1, `throw_release` 2, `throw_wait` 3, `throw_catch` 4, `kick_windup` 5, `kick_strike` 6, `kick_recover` 7 |
| `boombox_teacher_conduct_raw.png` | 4x2 | `conduct` 0-3, `lecture` 4-5, `notes` 6-7 |
| `boombox_teacher_bass_raw.png` | 4x2 | `bass_lift` 0-1, `bass_slam` 2-3, `overheat` 4-7 |
| `boombox_teacher_trans_raw.png` | 4x2 | `phase_change` 0-3, `intro` 4-7 |
| `boombox_teacher_defeat_raw.png` | 4x2 | `defeat` 0-7 (6-7 = corpse) |
| `boombox_teacher_props_raw.png` | 4x2 | `briefcase_spin` 0-3, `note` 4, `note_pair` 5, `steam` 6, `spark` 7 |

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/boombox_teacher/concept/teacher_concept_v1.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -- "<common block + sheet block>" < /dev/null > <log> 2>&1 &
```

Run from a scratch directory, never from the repository. Generated PNGs land in `~/.codex/generated_images/<session>/`; copy the chosen one to `../raw/`.

## Common block (character sheets)

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Animation sprite sheet of EL PROFESOR, the boombox-headed teacher boss of a 2D side-scrolling metroidvania. The FIRST attached image is his approved character design: use it as the exact character (same boombox head with carry handle, antenna, two round speakers and cassette window; cream shirt with rolled sleeves, dark red tie, black belt, charcoal trousers, black gloves, black dress shoes, black briefcase, thin wooden pointer) and keep his TALL lanky proportions. The SECOND attached image is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps per material, big flat colour shapes.
> Rules for EVERY frame: character facing RIGHT, side view, identical character, identical body scale in all frames: his standing body, from the sole to the top of the boombox (antenna excluded), is about 360 px tall. Image 1536x1024, landscape. Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no text, no labels, no grid lines, no frames, no glow, no rim light, no motion lines, no dust, no music notes, no sparks, no steam, no speech marks. Cells are equal and arranged in a strict regular grid; each pose stays fully inside its own cell with at least 16 px padding (pointer, briefcase, raised arms, raised boombox and legs included); in every grounded frame the lowest sole sits on the same row near the bottom of its cell, feet horizontally near the cell center. Poses must be clearly distinct from each other at silhouette level, chunky and readable at small size.

## Sheet block: Locomotion (`loco`)

> Sheet LOCOMOTION: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> Cells 1-4 = IDLE loop (4 frames): stiff upright teacher posture, briefcase in one hand, pointer held down in the other, a slight bob of the boombox head on the beat: 1 neutral, 2 head dipped a few pixels with knees softening, 3 neutral, 4 head raised slightly. Very small differences between frames; frame 4 flows back into frame 1.
> Cells 5-8 = WALK loop (4 frames): a slow, stiff, measured stride to the right, upright, long legs, briefcase swinging slightly; contact poses in cells 5 and 7, passing poses in cells 6 and 8; seamless loop.

## Sheet block: Pointer thrust (`thrust`)

> Sheet POINTER THRUST: grid of 3 columns x 2 rows (6 square cells of 512x512, reading order left-to-right, top-to-bottom). The pointer tip must stay inside its cell.
> Cell 1 = HIGH WIND-UP: side-on fencing guard, the pointer pulled back beside the boombox, front knee bent, briefcase held back.
> Cell 2 = HIGH STRIKE: a deep fencing lunge, front leg far forward, the pointer arm fully extended straight forward and level, arm and pointer one long horizontal line at about 45 percent of his standing height (the lunge lowers him).
> Cell 3 = HIGH RECOVER: pulling back out of the lunge, pointer lowered, slightly off balance, torso open.
> Cell 4 = LOW WIND-UP: crouching low, the pointer held low and back near his knee, ready to sweep.
> Cell 5 = LOW STRIKE: a low crouched lunge, body bent forward, the pointer extended straight forward just above the floor, at ankle height.
> Cell 6 = LOW RECOVER: rising from the crouch, the pointer dragging, torso open.

## Sheet block: Briefcase and kick (`throw`)

> Sheet BRIEFCASE AND KICK: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> Cells 1-2 = BRIEFCASE WIND-UP: 1 turning the torso back, the briefcase swung behind him at torso height; 2 maximum wind-up, briefcase far back, the other hand reaching forward.
> Cell 3 = RELEASE: the throwing arm whipped forward and extended, hand open, the briefcase is GONE (not drawn anywhere).
> Cell 4 = WAIT: empty-handed guarded stance, NO briefcase anywhere, pointer in the other hand, watching forward.
> Cell 5 = CATCH: catching the returning briefcase with the free hand raised at torso height, the briefcase drawn in that hand.
> Cell 6 = KICK WIND-UP: front knee chambered up high, the pointer arm out for balance.
> Cell 7 = KICK STRIKE: a straight side kick forward at shin-to-knee height, leg fully extended, sole forward, torso leaning back.
> Cell 8 = KICK RECOVER: the leg coming back down, stance resetting.

## Sheet block: Conducting (`conduct`)

> Sheet CONDUCTING: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom). The briefcase hangs from the free hand in every cell.
> Cells 1-4 = CONDUCTING loop (4 frames), like an orchestra conductor using the pointer as a baton: 1 pointer hand raised high, 2 downbeat, the baton hand dropping sharply, 3 rebound outward, 4 lifting again; the boombox head nods with the beat; seamless loop.
> Cells 5-6 = LECTURE: 5 raising the pointer toward a blackboard above and in front of him, 6 the pointer fully extended up and forward, as when explaining a lesson, body upright and stiff.
> Cells 7-8 = PLAY NOTES: 7 the free hand (holding the briefcase handle) raised to the side of his boombox head, 8 knocking the side of the boombox with the back of that hand, the body bouncing slightly.

## Sheet block: Bass drop and overheat (`bass`)

> Sheet BASS DROP AND OVERHEAT: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom). In this sheet his hands are empty: no pointer, no briefcase.
> Cells 1-2 = LIFT: 1 gripping his own boombox head with both hands; 2 lifting the boombox high above his shoulders, detached from his neck (the empty shirt collar shows), knees bent. The raised boombox must stay inside the cell.
> Cells 3-4 = SLAM: 3 bringing the boombox crashing back down onto his shoulders while stomping, knees deeply bent; 4 the boombox back in place, crouched, recoiling from the stomp.
> Cells 5-8 = OVERHEAT loop (4 frames): exhausted and dazed, hunched forward, hands on his knees, the boombox head drooping and tilted, swaying slightly between frames; seamless loop.

## Sheet block: Phase change and intro (`trans`)

> Sheet PHASE CHANGE AND INTRO: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> Cells 1-4 = PHASE CHANGE: a furious outburst. 1 recoiling, 2 arms flung up and wide, fists clenched, boombox tilted back as if shouting, 3 shaking with arms still up, 4 settling back into a stiff guard, one hand tugging the tie straight. Pointer and briefcase stay in his hands.
> Cells 5-8 = INTRO: 5 standing stiff, straightening his tie, 6 tapping the boombox head once with a finger, 7 sliding the pointer up, 8 pointing the pointer straight forward to the right at full arm's length, accusing, the other hand holding the briefcase.

## Sheet block: Defeat (`defeat`)

> Sheet DEFEAT: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> A final sequence of the teacher being defeated: 1 struck by the final blow, boombox knocked back; 2 staggering, the boombox head tilting, the pointer slipping from his hand; 3 knees buckling, the briefcase dropping to the floor; 4 on his knees, the boombox drooping forward; 5 collapsing forward onto his hands; 6 lying face down flat on the floor, the boombox head lying on its side, antenna bent; 7-8 practically identical: the permanent corpse lying flat on the floor line, clearly defeated (it cannot be mistaken for a pose he could get up from), briefcase and pointer lying beside him. Lying frames rest on the ground row of the cell.

## Common block (props sheet)

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Prop and effect sprite sheet for EL PROFESOR, the boombox-headed teacher boss of a 2D side-scrolling metroidvania. The FIRST attached image is his approved character design (use its briefcase exactly); the SECOND is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps, big flat colour shapes. Draw every object at the same pixel scale as a 360 px tall version of the teacher. Image 1536x1024, landscape, grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom); each object alone and centred in its cell, fully inside it. Flat opaque magenta #FF00FF background everywhere, no character, no text, no labels, no grid lines, no frames, no glow, no motion lines.

## Sheet block: Props (`props`)

> Cells 1-4 = BRIEFCASE SPIN: the black briefcase from the design, about 70 px wide, rotated 0, 90, 180 and 270 degrees clockwise around its centre.
> Cell 5 = a single eighth note, chunky, black with a warm amber highlight, about 70 px tall.
> Cell 6 = two beamed sixteenth notes, same style, about 80 px tall.
> Cell 7 = a small puff of steam: three soft round cel-shaded lobes, light grey and white, about 90 px wide.
> Cell 8 = a spark burst: a small jagged six-point star, amber and white, about 70 px wide.

## Batch 2: hazards and effects

Two more Codex runs with the same  images, after the first in-game capture showed the hazards still drawn as placeholder boxes. Raw files:  (one blank blackboard; the game writes the dictation text on it) and  (4x2 cells of 384x512:  0,  1,  2,  3,  4-7).

### Blackboard prompt

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Prop sprite for EL PROFESOR, the boombox-headed English teacher boss of a 2D side-scrolling metroidvania. The FIRST attached image is his approved character design, the SECOND is the player character Luz: draw the prop in exactly their rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps, big flat colour shapes, slightly painterly texture. No glow, no rim light.
> Object: one classroom BLACKBOARD seen straight from the front, wide landscape shape about 3.4 times wider than tall, filling most of the image width: a dark green slate (#1F3A2E with a slightly lighter worn area #2C4A3B and faint old chalk smudges), a light warm wooden frame (#B98A55 with shadow #7E5A35) about one twentieth of the board height thick, a narrow wooden chalk tray along the bottom edge with two short white chalk sticks and a small felt eraser. The slate is BLANK: no writing, no letters, no drawings. Centered in the image, nothing else.
> Image 1536x1024, landscape. Flat opaque magenta #FF00FF background everywhere around the board, no shadow, no text, no labels, no frame around the image.

### Effects prompt

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Effect sprite sheet for EL PROFESOR, the boombox-headed teacher boss of a 2D side-scrolling metroidvania whose attacks follow a musical beat. The FIRST attached image is his approved character design, the SECOND is the player character Luz: draw every effect in exactly their rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps, big flat colour shapes. No soft glow, no blur, no gradients beyond the cel steps.
> Image 1536x1024, landscape, grid of 4 columns x 2 rows (8 equal cells of 384x512, reading order left-to-right, top-to-bottom). Each effect alone and centred in its cell, fully inside it with at least 24 px padding. Flat opaque magenta #FF00FF background everywhere, no character, no text, no labels, no grid lines, no frames.
> Cell 1 = LOW SOUND WAVE: three nested curved arcs like ")))" travelling to the right, warm AMBER (#F2A33A, light #FFD27A, shadow #B4651E), each arc thick and chunky, about 120 px tall and 110 px wide in total.
> Cell 2 = HIGH SOUND WAVE: the same three nested arcs ")))" but cool CYAN (#4FC3E8, light #A8ECFF, shadow #2479A0), same size.
> Cell 3 = BASS SHOCK CREST: a wide, low ground shockwave crest seen from the side, an amber wave of cracked energy hugging the floor line, about 300 px wide and 90 px tall, flat bottom edge.
> Cell 4 = CHALK DUST PUFF: a small burst of white chalk dust, three or four round cel-shaded lobes, white and pale grey, about 110 px wide.
> Cells 5-8 = STEAM LOOP (4 frames): a puff of grey-white steam rising and dissolving: 5 a small round puff, 6 bigger and rising, 7 biggest with lobes separating, 8 thin wisps breaking apart; about 100 to 150 px wide, round cel-shaded lobes, light grey #D9D6D2 and white with grey shadow #9C9893.

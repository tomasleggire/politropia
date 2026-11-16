# El Topo - animation sheets (run)

Contract: `docs/bosses/BLIND_BEAST_ANIMATIONS.md`. Approved design: `concept/topo_concept_v1.png`. Rule 0: same style as Luz, Artemis and El Profesor.

Eight Codex runs, one per raw sheet, in parallel, with the approved concept and `luz_identity_ref.png` as `-i` (the `intro` sheet also gets the old man reference). Raw sheets go to `../raw/blind_beast_<sheet>_raw.png`; `tools/process_blind_beast_sheets.py` keys the magenta, splits frames by connected components per grid cell, scales each sheet by the size of the pink star nose, aligns the lowest point on the feet row and writes `assets/enemies/blind_beast/`.

All sheets are 1536x1024: 4 columns x 2 rows of 384x512 cells, except `claw` (3 x 2 cells of 512x512). Every character sheet asks for the same standing height (about 330 raw px, sole to the top of the head); Codex does not keep it exactly, hence the per-sheet scale.

| Raw sheet | Grid | Clips (raw cell indices) |
|---|---|---|
| `blind_beast_exposed_raw.png` | 4x2 | `exposed_idle` 0-3, `dazed` 4-7 |
| `blind_beast_burrow_raw.png` | 4x2 | `emerge` 0-3, `dig_in` 4-7 |
| `blind_beast_claw_raw.png` | 3x2 | `claw_windup` 0-1, `claw_strike` 2-3, `claw_recover` 4-5 |
| `blind_beast_slam_raw.png` | 4x2 | `slam_windup` 0-1, `slam_strike` 2-3, `phase_change` 4-7 |
| `blind_beast_intro_raw.png` | 4x2 | `intro` 0-7 |
| `blind_beast_defeat_raw.png` | 4x2 | `defeat` 0-7 (6-7 = corpse) |
| `blind_beast_props_raw.png` | 4x2 | `mound` 0-3, `rock` 4, `rock_alt` 5, `crack` 6, `spike` 7 |
| `blind_beast_fx_raw.png` | 4x2 | `erupt_column` 0-2, `pulse_wave` 3-4, `dust_puff` 5, `rock_impact` 6, `dig_dirt` 7 |

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/blind_beast/concept/topo_concept_v1.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -- "<common block + sheet block>" < /dev/null > <log> 2>&1 &
```

For `intro`, add `-i tools/art_sources/blind_beast/concept/old_man_npc_ref.jpg` as the third image. Run from a scratch directory, never from the repository. Generated PNGs land in `~/.codex/generated_images/<session>/`; copy the chosen one to `../raw/`.

## Common block (character sheets)

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Animation sprite sheet of EL TOPO, a boss of a 2D side-scrolling metroidvania: a giant blind star-nosed mole who used to be a blind old man. The FIRST attached image is his approved character design: use it as the exact character (grey-white hair tuft, small milky blind eyes, fleshy pink star nose, enormous pale shovel claws, torn charcoal suit jacket, loosened dark red tie, wooden cane, warm grey-brown fur) and keep his stocky, hunched, upright build. The SECOND attached image is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps per material, big flat colour shapes.
> Rules for EVERY frame: character facing RIGHT, side view, identical character, identical body scale in all frames: standing hunched, from the sole to the top of the head, he is about 330 px tall. Image 1536x1024, landscape. Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no text, no labels, no grid lines, no frames, no glow, no rim light, no motion lines, no dust clouds, no flying debris (effects are drawn separately). Cells are equal and arranged in a strict regular grid; each pose stays fully inside its own cell with at least 16 px padding (claws, cane and raised arms included); in every grounded frame the lowest point of the feet sits on the same row near the bottom of its cell, feet horizontally near the cell center. Poses must be clearly distinct from each other at silhouette level, chunky and readable at small size.

## Sheet block: Exposed (`exposed`)

> Sheet EXPOSED: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> Cells 1-4 = EXPOSED IDLE loop (4 frames): standing hunched, leaning on the cane with one claw, the other claw held ready, the star nose sniffing forward: 1 tentacles spread, 2 tentacles closed, 3 spread again, 4 the nose turned slightly up; small breathing movement; frame 4 flows back into frame 1.
> Cells 5-8 = DAZED loop (4 frames): disoriented and vulnerable, swaying, head drooping, claws hanging low, the cane slipping, the star nose limp, tilting left, centre, right, centre; seamless loop.

## Sheet block: Burrow (`burrow`)

> Sheet BURROW: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom). In the cells that say so, his lower body is hidden below a flat horizontal ground line near the bottom of the cell: the figure is cut flat along that line, with a small rim of broken earth clods along the cut and nothing drawn below it. That ground line is the same row where his feet stand in the other cells.
> Cells 1-4 = EMERGE: bursting up out of the ground. 1 only the claws and the star nose breaking through the ground line (cut); 2 head and shoulders out (cut); 3 upper body out to the waist, claws raised wide (cut); 4 fully out, standing in the hunched pose, feet on the row.
> Cells 5-8 = DIG IN: 5 crouching and raising both claws (feet on the row); 6 diving head-first, claws already in the ground (cut); 7 only the back, the hind legs and the short tail above the ground line (cut); 8 only the tail tip and a heap of earth clods remain (cut).

## Sheet block: Claw (`claw`)

> Sheet CLAW: grid of 3 columns x 2 rows (6 square cells of 512x512, reading order left-to-right, top-to-bottom). The claw tip must stay inside its cell.
> Cells 1-2 = WIND-UP: 1 turning toward a sound, one claw drawn far back at shoulder height; 2 maximum wind-up, body coiled, star nose pointing forward.
> Cells 3-4 = STRIKE: 3 a wide horizontal swipe, the claw sweeping forward at chest height, fully extended; 4 the follow-through past the front, body twisted.
> Cells 5-6 = RECOVER: 5 the claw coming back, off balance; 6 back in the hunched stance.

## Sheet block: Slam and phase change (`slam`)

> Sheet SLAM AND PHASE CHANGE: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> Cells 1-2 = SLAM WIND-UP: rearing up tall on the hind legs, both claws raised high above the head, the star nose pointing up (the tallest pose; the claws stay inside the cell).
> Cells 3-4 = SLAM STRIKE: 3 both claws smashing down onto the ground in front of him, body bent forward; 4 crouched low after the impact, claws flat on the ground.
> Cells 5-8 = PHASE CHANGE: an anguished roar. 5 recoiling; 6 head thrown back, roaring, claws spread wide, the jacket tearing more; 7 shaking with rage; 8 settling into a lower, more beast-like hunched stance.

## Sheet block: Intro (`intro`)

> Sheet INTRO, the transformation: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom). The THIRD attached image is the blind old man before the transformation (he is seated there; draw him standing). Every figure has about the same height as the beast standing hunched.
> 1 the blind old man exactly as in the third image (swept grey hair, milky eyes, charcoal suit with waistcoat, dark red tie), standing hunched on his wooden cane, facing right; 2 he doubles over, clutching his chest, the cane bending; 3 his back swells and grey-brown fur bursts through the suit, his hands start growing into claws; 4 his face stretches into a snout and the pink star nose appears; 5 the full beast, the jacket torn open, still hunched over the cane; 6 rising and sniffing the air; 7 roaring with the claws raised; 8 settling in the standing hunched pose of the design.

## Sheet block: Defeat (`defeat`)

> Sheet DEFEAT: grid of 4 columns x 2 rows (8 cells of 384x512, reading order left-to-right, top-to-bottom).
> 1 struck by the final blow, head knocked back, star nose flaring; 2 staggering backwards, the cane falling; 3 dropping to his knees, claws on the ground; 4 collapsing onto his side; 5 lying on his side, a last twitch of the star nose; 6 lying still, the cane and a torn piece of the jacket beside him; 7-8 practically identical: the permanent corpse lying flat on the floor line, clearly defeated (it cannot be mistaken for a pose he could get up from). Lying frames rest on the ground row of the cell.

## Common block (props and effects sheets)

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt:
>
> Prop and effect sprite sheet for EL TOPO, a giant blind mole boss of a 2D side-scrolling metroidvania who tunnels under the floor of a haunted library. The FIRST attached image is his approved character design and the SECOND is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps, big flat colour shapes. No soft glow, no blur. Draw every object at the same pixel scale as a 330 px tall version of the mole. Earth colours: dark brown #4A3A30, mid #6E5644, light #9A7F63; stone grey #7C7A80 and #A9A6AB; dust #B9AC9C. Image 1536x1024, landscape, grid of 4 columns x 2 rows (8 equal cells of 384x512, reading order left-to-right, top-to-bottom); each object alone and centred in its cell, fully inside it with at least 24 px padding. Flat opaque magenta #FF00FF background everywhere, no character, no text, no labels, no grid lines, no frames.

## Sheet block: Props (`props`)

> Cells 1-4 = MOUND loop (4 frames): a low mound of loose dark earth with a few clods and a small root, about 110 px wide and 45 px tall, flat bottom edge; the earth shifts as something tunnels beneath it (clods popping up and settling between frames); seamless loop.
> Cell 5 = ROCK: a chunky rock, grey stone with a little earth stuck to it, about 60 px.
> Cell 6 = ROCK ALT: a different chunky rock, about 55 px.
> Cell 7 = CRACKS: the floor seen from the side, a wide thin strip of broken ground with earth pushing up through the cracks, about 180 px wide and 30 px tall, flat bottom edge.
> Cell 8 = SPIKE: an earthen stone spike rising from the ground, a tall narrow cone with a few round braille-like bumps on it, about 45 px wide and 110 px tall, flat bottom edge.

## Sheet block: Effects (`fx`)

> Cells 1-3 = ERUPTION COLUMN (3 frames): a vertical burst of earth, rocks and dust shooting up from the ground, tall and narrow (about 1.6 times taller than wide), flat bottom edge: 1 the burst starting, 2 the full column, 3 collapsing with clods falling.
> Cells 4-5 = PULSE WAVE (2 frames): a low, wide ripple of earth and dust travelling along the ground to the right, about three times wider than tall, flat bottom edge.
> Cell 6 = DUST PUFF: a puff of brown-grey dust, round cel-shaded lobes, about 110 px wide.
> Cell 7 = ROCK IMPACT: a small burst of rock fragments and dust where a rock hits the floor, flat bottom edge, about 120 px wide.
> Cell 8 = DIG DIRT: a spray of dirt clods flung upward and backward, about 120 px wide.

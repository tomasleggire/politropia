# Rest Ritual Sprite Prompts (Stillness Desk)

Generated with Codex's built-in image generation tool (`codex exec -i ...`). Raw
sheets are kept in `tools/art_sources/luz/raw/` (gitignored);
`tools/process_luz_rest_ritual.py` turns them into `assets/player/luz/luz_rest_sheet.png`.

Attached references for every sheet: image 1 = `refs/luz_identity_ref.png`
(identity/outfit), image 2 = `assets/player/luz/luz_locomotion_sheet.png`
(in-game style/scale), image 3 = concept art (seated pose only; do not copy
the desk, background or lighting).

## Fixed geometry contract (shared by all three sheets)

- Raw sheet 1536x1024, 4 columns x 2 rows of invisible 384x512 cells, row-major.
- Right-facing side view. Floor baseline (lowest shoe when standing) is y=472 in every cell.
- Standing body height (top of hair to sole) about 340 px. Body centre near x=150 in the cell.
- Invisible seat surface: **y=302, i.e. 170 px above the floor baseline** (about hip height,
  half of standing height). The desk itself is NOT drawn.
- 16 px minimum transparent padding to every cell edge. Transparent alpha only.

## Common style clause

> Attached image 1 gives Luz's exact identity/outfit; image 2 the current in-game rendering, palette and scale; image 3 is a concept for the seated pose only. Luz: blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack, light-brown wooden school ruler with dark tick marks. Clean outlined anime pixel-art game rendering, same proportions, palette and line weight as image 2. Right-facing side view. Transparent background only; absolutely no desk, furniture, floor, ground line, shadow, glow, haze, vignette, particles, text, frame numbers, labels, borders or grid lines. The sheet is cut mechanically: every pixel of a frame stays at least 16 px inside its own 384x512 cell.

## rest_mount — generation prompt

> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Generate ONE 1536x1024 PNG with real transparent alpha, exactly 4 columns x 2 rows of invisible 384x512 cells, row-major, eight sequential frames of Luz mounting a waist-high desk that is NOT drawn (empty space). The desk is to her RIGHT; its top surface is an invisible horizontal line at y=302 in each cell (170 px above the floor baseline y=472). Standing body height about 340 px, body centre near x=150, floor baseline y=472 while grounded. Frames: 0 standing relaxed beside the desk, backpack on, ruler held low in her right hand; 1 shrugs the backpack straps off her shoulders, leaning slightly forward; 2 LAST frame with the backpack: she lowers the whole backpack to the floor behind/left of her, backpack bottom touching baseline y=472 at x about 60-110, still drawn as a distinct object; 3 standing upright and empty-backed, NO BACKPACK anywhere in this frame or any later frame, ruler in hand, knees bending to spring; 4 hopping up, feet off the floor, hands reaching forward to grip the invisible desk edge at y=302, body rising; 5 knee up on the invisible surface, hips at about y=302, torso upright; 6 sitting down onto the invisible surface, legs folding into a cross-legged pose, ruler being laid across her knees; 7 settled cross-legged seat exactly on the line y=302 (the lowest point of her legs is y=302), ruler flat and horizontal across both knees held by both hands, eyes closed, calm, no backpack. Do not draw the surface, the desk, or the backpack after frame 2. Keep the same character scale in all frames.

## rest_sit — generation prompt

> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Generate ONE 1536x1024 PNG with real transparent alpha, 4 columns x 2 rows of invisible 384x512 cells, row-major, eight frames of a seamless looping breathing cycle of Luz meditating cross-legged, matching the seated pose of attached image 3. The seat is an invisible surface at y=302 in each cell (NOT drawn); the lowest point of the crossed legs sits exactly on y=302 in every frame. Standing-equivalent scale: a standing Luz would be 340 px tall; body centre near x=150. Eyes closed, calm face, wooden ruler flat and horizontal across both knees held loosely by both hands, NO BACKPACK. Subtle breathing only: frames 0-3 chest and shoulders rise about 3 px and head lifts about 2 px, ponytail and hair strands sway slightly to the back; frames 4-7 return gently to the start pose. Legs, ruler and hands stay essentially identical in all frames. Frame 7 must flow back into frame 0. Nothing else changes: no desk, no floor, no glow.

## rest_dismount — generation prompt

> Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Generate ONE 1536x1024 PNG with real transparent alpha, 4 columns x 2 rows of invisible 384x512 cells, row-major, eight sequential frames of Luz dismounting a waist-high desk that is NOT drawn. The desk is to her RIGHT and its top is an invisible line at y=302 (170 px above the floor baseline y=472). Standing height about 340 px, body centre near x=150. Frames: 0 seated cross-legged exactly on the invisible line y=302, eyes closed, ruler across knees, NO BACKPACK; 1 eyes open, uncrossing her legs, ruler in right hand, legs swinging forward/down over the edge; 2 pushing off with her hands and dropping, mid-air; 3 landing on the floor in a compact crouch, feet on baseline y=472, still no backpack; 4 crouching to pick up her dark navy backpack which lies on the floor to her left with its bottom on y=472 at x about 60-110; 5 lifting the backpack by its strap, swinging it up toward her shoulder; 6 sliding the second strap on, backpack now on her back, straightening; 7 standing ready, backpack on, ruler held low in her right hand, close to the idle stance of image 1 and 2. Keep character scale identical in all frames; feet on y=472 for frames 3-7.

## Refinement prompt template (one pass per sheet, only if a frame is broken)

> Use case: precise-object-edit. Edit the supplied sheet as raw source art. Preserve the 4x2 layout of 384x512 cells, transparent alpha, identity, outfit, scale, feet baseline and every frame that is not named. Fix only the named frames: <describe defect>. No new limbs, props, effects, desk or floor.

## Records

Filled in after generation; see the bottom of this file.

### Generation record (2026-09-28)

- Invoked as `codex exec -s workspace-write --skip-git-repo-check -i <identity ref> -i <locomotion sheet> -i <concept> -o <last-message file> "<instruction + prompt above>"`, one run per sheet; the tool saved to `tools/art_sources/luz/raw/rest_{mount,sit,dismount}_raw.png`.
- Codex could not emit real alpha for `sit` and `dismount` (opaque magenta `#FF00FF` fallback); the processor keys magenta. `mount` came back with alpha.
- No refinement pass was needed; each sheet is a single generation.
- The generator did not honour the numeric geometry (standing 340 px, seat at y=302): standing height came out 377-410 px, seated poses sat far lower, and the `sit` sheet was drawn ~1.3x larger than `mount`/`dismount`. The processor therefore rescales per clip (mount 0.81, sit 0.64, dismount 0.85) and re-places each frame at an authored `lift` above the feet row; the seat surface is 150 output px above the feet row.
- `rest_sit` uses raw frames [7, 6, 4, 5] (row 2); row-1 frames stretch the torso too much to loop.

### Targeted frame edits (2026-09-29)

Parent review found three continuity defects. Each defective frame was edited alone: the 384x512 cell was cropped from the raw sheet onto magenta, edited with Codex (`codex exec -s workspace-write -i <refs...>`, output a 3:4 portrait on magenta), resized to 384x512 and pasted back into the raw sheet (pre-edit sheets kept as `raw/edits/*_v1.png`). Other frames are unchanged.

#### rest_mount frame 4 (refs: identity ref, mount frame 3, mount frame 5)

> Use case: precise-object-edit / animation in-between. Asset type: single frame of a 2D pixel-art game sprite sheet. Image 1 is Luz's identity reference. Image 2 is the frame BEFORE (standing, no backpack, wooden school ruler held low in her right hand). Image 3 is the frame AFTER (sitting on the edge of an invisible desk, right hand planted on its top). Draw ONE new in-between frame, right-facing side view, same character, outfit, hair, art style, line weight, palette and character scale as images 2 and 3: a crouched spring / climb beat. Knees bent deeply, weight loaded, the feet just barely leaving or still touching the floor, torso leaning forward, both arms reaching up and forward toward an invisible desk-top edge at about chest-to-head height in front of her. The SAME light-brown wooden ruler with dark tick marks must remain clearly visible, held in her RIGHT hand (the reaching hand may hold it against the edge), fully drawn, same size as in image 2 and 3. No backpack, no desk, no floor, no shadow, no glow, no text. Flat magenta background. Keep the figure centred with at least 16 px margin at 384x512 proportions, feet/lowest point near 92% of the image height. 

#### rest_dismount frame 2 (ref: that frame)

> Use case: precise-object-edit. Edit image 1 (a single sprite frame of Luz mid-air, dropping from a seat, right-facing). Remove the dark navy backpack entirely: no bag mass, straps or bulk behind her shoulders or back; show only her jacket and hood/collar and hair as they would look without a backpack. Change nothing else: same pose, legs, arms, ruler in her hand, face, hair, scale, colours, outlines, position in the frame. Flat magenta background, no shadow, glow or text. 

#### rest_dismount frame 3 (ref: that frame)

> Use case: precise-object-edit. Edit image 1 (a single sprite frame of Luz landing in a compact crouch, right-facing). Remove the dark navy backpack entirely: no bag mass, straps or bulk behind her shoulders or back; show only her jacket and hood/collar and hair as they would look without a backpack. Change nothing else: same pose, legs, arms, ruler in her hand, face, hair, scale, colours, outlines, position in the frame. Flat magenta background, no shadow, glow or text. 

Rest_dismount frame 1 drift was corrected in the processor, not by regeneration: per-frame `dx` [0, -35, -20, 0, 0, 0, 0, 0]. Mount frame 4 lift is now 20.

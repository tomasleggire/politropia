# La Hidra - animation sheets (run)

Contract: `docs/bosses/HYDRA_ANIMATIONS.md`. Approved design: `concept/hydra_concept_v1.png`. Rule 0: same style as Luz, Artemis, El Profesor and El Topo.

Six Codex runs, one per raw sheet, in parallel, with the approved concept and `luz_identity_ref.png` as `-i`. Raw sheets go to `../raw/hydra_<sheet>_raw.png`; `tools/process_hydra_sheets.py` keys the magenta, splits the frames per grid cell, scales each sheet on its first idle cell and writes `assets/enemies/hydra/`.

The Hydra is a multi-part boss: the body is one sprite, each head is its own sprite and the necks are drawn by the engine with the tiled `neck` texture. So the body sheets have NO heads and NO necks, and the head sheets have NO neck.

All sheets are 1536x1024. Body sheets: 3 columns x 2 rows of 512x512 cells. Head and props sheets: 4 columns x 2 rows of 384x512 cells.

| Raw sheet | Grid | Clips (raw cell indices) |
|---|---|---|
| `hydra_body_raw.png` | 3x2 | `idle` 0-3, `roar` 4-5 |
| `hydra_defeat_raw.png` | 3x2 | `defeat` 0-5 (4-5 = corpse) |
| `hydra_head_biter_raw.png` | 4x2 | `idle` 0-2, `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `hydra_head_sweeper_raw.png` | 4x2 | `idle` 0-2, `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `hydra_head_spitter_raw.png` | 4x2 | `idle` 0-2, `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `hydra_props_raw.png` | 4x2 | `neck` 0, `stump` 1, `venom_glob` 2, `venom_pool` 3-4, `venom_splash` 5, `platform` 6, `platform_alt` 7 |

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/hydra/concept/hydra_concept_v1.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -- "<wrapper + common block + sheet block>" < /dev/null > <log> 2>&1 &
```

Run from a scratch directory, never from the repository. Generated PNGs land in `~/.codex/generated_images/<session>/`; copy the chosen one to `../raw/`.

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt: <common block> <sheet block>

## Common block (body sheets)

> Animation sprite sheet of the BODY of LA HIDRA, a boss of a 2D side-scrolling metroidvania set among ancient Greek ruins: the Lernaean Hydra, a massive three-headed serpent. The FIRST attached image is the approved character design: use its exact body (dark teal-green scales with large readable scale shapes, pale ochre plated belly, the upright trunk rising from heavy coils resting on the ground, the short tail curling behind). The SECOND attached image is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps per material, big flat colour shapes.
> IMPORTANT: this sheet shows the body WITHOUT its heads and WITHOUT its long necks, because the game draws the necks and the heads separately on top of it.
> Rules for EVERY frame: the body facing RIGHT, side view, identical creature and identical scale in all frames: from the ground to the top of the trunk it is about 430 px tall and about 330 px wide, the coils resting on the same ground row near the bottom of each cell, horizontally centred in the cell. Image 1536x1024, landscape, strict regular grid of 3 columns x 2 rows (6 equal square cells of 512x512, reading order left-to-right, top-to-bottom); each pose stays fully inside its own cell with at least 20 px padding. Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no water, no text, no labels, no grid lines, no frames, no glow, no rim light, no motion lines, no dust.

## Sheet block: Body (`body`)

> Sheet BODY. In every cell, where the three necks would grow there are only three short, thick, rounded neck bases covered in teal scales: one at the top of the trunk curving forward (to the right), one bulging from the front of the trunk at mid height, and one low near the coils; each is just a short stub pointing right that ends in a smooth rounded scaly end (no cut, no flesh), the same in every frame.
> Cells 1-4 = IDLE loop (4 frames): slow heavy breathing: 1 neutral; 2 the trunk swelling slightly and leaning a little back, the tail tip curling up; 3 neutral with the coils shifted a little; 4 the trunk leaning slightly forward, the tail tip down; frame 4 flows back into frame 1. Small movements only.
> Cells 5-6 = ROAR (2 frames): 5 the trunk rearing up taller and arching back, the scales bristling, the tail raised; 6 the trunk thrust forward and tensed, the coils tightening, the tail lashing.

## Sheet block: Defeat (`defeat`)

> Sheet DEFEAT. In this sheet the Hydra has lost its three heads: each of the three necks is cut short into a limp severed stump about as long as the trunk is thick, with a dark flat cut end (no blood, no gore).
> 1 struck by the final blow, the trunk recoiling backwards, the three stumps flailing; 2 the trunk swaying, the stumps drooping; 3 the trunk buckling and falling forward (to the right); 4 slumped over its own coils; 5-6 practically identical: the permanent corpse, a limp heap of coils with the trunk and the three stumps lying flat along the ground, clearly dead (it cannot be mistaken for a pose it could rise from). Lying frames rest on the ground row of the cell and stay inside the cell.

## Common block (head sheets)

> Animation sprite sheet of ONE HEAD of LA HIDRA, a boss of a 2D side-scrolling metroidvania set among ancient Greek ruins: the Lernaean Hydra, a massive three-headed serpent. The FIRST attached image is the approved character design: on its right side it shows the three heads as close-up studies; use the exact design of the head named below (same shapes, same crest, same colours, dark teal scales, pale yellow slit eye, bone-coloured teeth, ochre lower jaw). The SECOND attached image is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps per material, big flat colour shapes.
> Rules for EVERY frame: ONLY the head, cut off cleanly right behind the skull with a short rounded scaly end, NO neck (the game draws the neck separately); side view facing RIGHT; identical head and identical scale in all frames: about 290 px long from the back of the skull to the tip of the snout when the mouth is closed; the back of the skull sits at the same place in every cell and the head is centred in its cell. Image 1536x1024, landscape, strict regular grid of 4 columns x 2 rows (8 equal cells of 384x512, reading order left-to-right, top-to-bottom); each head stays fully inside its own cell with at least 20 px padding, crest, fangs and tongue included. Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no text, no labels, no grid lines, no frames, no glow, no rim light, no motion lines, no spit streams, no particles.

## Sheet block: Biter head (`head_biter`)

> Sheet BITER HEAD: the head with the crimson red crest fins and red markings, a short heavy crocodile-like skull with a massive jaw and big fangs.
> Cells 1-3 = IDLE loop: 1 jaws slightly open, fangs showing; 2 jaws a little more open, breathing; 3 jaws almost closed, the eye narrowed.
> Cell 4 = TELEGRAPH: about to strike: the head drawn back, lips curled, all teeth bared in a snarl, the eye wide, the crest raised.
> Cells 5-6 = ATTACK: 5 the jaws open at their maximum, a huge gape, lunging forward; 6 the jaws snapped shut hard, the fangs interlocked, the head stretched forward.
> Cell 7 = ROAR: jaws wide open, roaring upward and forward, tongue out, crest fully raised.
> Cell 8 = DAZED: stunned after biting the ground: the eye half closed, the tongue lolling out of a slack jaw, the crest drooping.

## Sheet block: Sweeper head (`head_sweeper`)

> Sheet SWEEPER HEAD: the head with the violet blade-shaped horn crest and violet markings, a long flat blade-like snout.
> Cells 1-3 = IDLE loop: 1 mouth closed, calm; 2 mouth slightly open, a thin forked tongue flicking out; 3 mouth closed, the eye narrowed, the crest slightly lowered.
> Cell 4 = TELEGRAPH: about to sweep: the head lowered and flattened like a drawn blade, the crest blades raised and spread, the jaw clenched, the eye fierce.
> Cells 5-6 = ATTACK: rushing head-first like a blade: 5 the snout thrust straight forward, the mouth open in a hiss, the crest swept back flat by the speed; 6 the same rushing pose with the jaws closed and the eye squinting.
> Cell 7 = ROAR: jaws wide open, roaring, tongue out, crest fully spread.
> Cell 8 = DAZED: stunned: the eye half closed, the tongue hanging out of a slack jaw, the crest drooping.

## Sheet block: Spitter head (`head_spitter`)

> Sheet SPITTER HEAD: the cobra-like head with the wide acid green hood and the swollen venom sacs under the jaw.
> Cells 1-3 = IDLE loop: 1 mouth slightly open, a drop of green venom on a fang, the hood half open; 2 mouth closed, the venom sacs pulsing a little larger; 3 mouth slightly open, the hood a little wider.
> Cell 4 = TELEGRAPH: about to spit: the hood fully flared, the venom sacs swollen to their largest, the mouth closed tight, the head tilted up and back.
> Cells 5-6 = ATTACK: 5 the mouth wide open, spitting, the sacs squeezed small, a few thick green venom drops right at the lips; 6 the mouth still open, recoiling after the spit, the sacs deflated, the hood shaking.
> Cell 7 = ROAR: jaws wide open, roaring, tongue out, the hood fully flared.
> Cell 8 = DAZED: stunned: the eye half closed, the tongue hanging out of a slack jaw, the hood folded and drooping.

## Common block (props sheet)

> Prop and effect sprite sheet for LA HIDRA, a massive three-headed serpent boss of a 2D side-scrolling metroidvania set among ancient Greek ruins. The FIRST attached image is its approved character design and the SECOND is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410, cel shading with 2-3 value steps, big flat colour shapes. No soft glow, no blur. Colours: Hydra scales dark teal-green #33574A with shadows #1F3A36 and a lighter edge #5E8F7A, belly plates ochre-bone #D8C79A; venom bright green #A6F06A, mid #66CC4D, dark #3D8A3A; marble #E8E4DA with shadows #B9B4C2 and #7C7A8A. Image 1536x1024, landscape, strict regular grid of 4 columns x 2 rows (8 equal cells of 384x512, reading order left-to-right, top-to-bottom); each object alone and centred in its cell, fully inside it with at least 24 px padding. Flat opaque magenta #FF00FF background everywhere, no character, no text, no labels, no grid lines, no frames.

## Sheet block: Props (`props`)

> Cell 1 = NECK SECTION: one perfectly straight horizontal section of the Hydra's neck, like a pipe seen from the side: teal scales on the upper two thirds, ochre belly plates along the lower third, constant thickness, about 320 px long and 90 px thick, both ends cut perfectly flat and vertical (it will be repeated end to end to build a long neck, so the left end and the right end must match).
> Cell 2 = STUMP: a short severed neck stump of the same neck, about 150 px long and 90 px thick: the left end is cut flat and vertical (it attaches to the body), the right end is the severed end, ragged and dark, drooping slightly, no blood.
> Cell 3 = VENOM GLOB: a thick round blob of bright green venom flying, with a short tail, about 80 px.
> Cells 4-5 = VENOM POOL loop (2 frames): a flat puddle of bubbling green venom seen from the side, very wide and low, about 320 px wide and 55 px tall, flat bottom edge; frame 2 is the same puddle with the bubbles in other places.
> Cell 6 = VENOM SPLASH: a low crown-shaped splash of green venom hitting the ground, about 200 px wide and 110 px tall, flat bottom edge.
> Cell 7 = PLATFORM: a ledge of ancient Greek white marble seen from the side: one wide flat slab with a perfectly flat horizontal top edge, a carved Greek key (meander) band along its front face, a few cracks and chips and a little ivy hanging from one end; about 340 px wide and 60 px tall.
> Cell 8 = PLATFORM ALT: a different marble ledge of the same size and the same flat top edge, more broken, with other cracks and a missing corner, no ivy.

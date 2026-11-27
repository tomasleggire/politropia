# El Profesor (Boombox Teacher) - character concept (step A)

Contract: `docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md`. Design source: `concept/design_sheet_ref.jpeg` (the team's design sheet), plus the two pose refs next to it. Style anchors: `tools/art_sources/luz/refs/luz_identity_ref.png` (Luz) and `tools/art_sources/artemis/concept/artemis_concept_v2_keyed.png` (Artemis, the first boss). Rule 0: one cohesive style with Luz and Artemis. Same workflow as `tools/art_sources/artemis/prompts/character_concept.md`.

Size decision: he is TALL. The library's regular teacher enemies are about 85 px on screen; the boss is about 92 px to the top of the boombox (Luz 48 px, Artemis 56 px), so about 1.9 times Luz.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/boombox_teacher/concept/design_sheet_ref.jpeg \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -i tools/art_sources/artemis/concept/artemis_concept_v2_keyed.png \
  -- "<instruction wrapper + prompt below>" < /dev/null > <log> 2>&1 &
```

Run it from a scratch directory, never from the repository. Generated PNGs are picked up from `~/.codex/generated_images/<session>/`.

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt: <prompt>

## Prompt

Character reference sheet of EL PROFESOR, a boss for a 2D side-scrolling metroidvania: a tall, lanky English teacher whose head is a retro boombox. The FIRST attached image is the team's design sheet: use it for the character design (boombox head with carry handle, antenna, two round speakers and a cassette deck; cream long-sleeve dress shirt with rolled cuffs, dark red tie, black belt, charcoal dress trousers, black gloves, black dress shoes, black briefcase, thin wooden pointer). The SECOND attached image is the player character Luz and the THIRD is Artemis, the first boss: draw him in EXACTLY their rendering style: illustrated "pixel-styled" look, same rendering density, thick uniform dark outline (near-black warm brown #1A1410, as heavy as Luz's) around the whole silhouette and around every major shape, cel shading with 2-3 value steps per material, big flat colour shapes, slightly painterly texture. Do not redraw in true low-res pixel art, no smooth vector gradients, no rim light, no glow (the engine adds it).

Proportions: keep the design's TALL lanky adult build (long legs, narrow torso, long arms), NOT the stocky 4-head build of Luz and Artemis: he must look clearly taller and more imposing, about 1.9 times Luz's height. But simplify like a game sprite: large readable hands (gloves) and shoes, few shirt folds, the boombox head big and clean (about one fifth of his height), so the figure still reads when shrunk to about 92 px tall.

Layout: one large full-body idle pose on the left, facing RIGHT, side/three-quarter view, standing upright with a stiff teacher posture, briefcase in his left hand (the hand away from the viewer), pointer in his right hand held down along the leg, feet on a common ground line, the figure filling most of the image height. On the right, three smaller pose thumbnails of the same character at one shared smaller scale: (1) a deep fencing lunge with the pointer thrust straight forward, arm and pointer forming one long horizontal line; (2) winding up to throw the briefcase, briefcase pulled far back behind him at torso height; (3) both hands lifting his own boombox head above his shoulders, about to slam it down. Flat solid magenta background #FF00FF everywhere, no ground, no shadow, no text, no labels, no UI, no frame, no motion lines, no music notes.

Palette (restrained, within about 16-24 colours): shirt warm off-white #E8DCCB with shadows #B9A893 and #8E7F6E; tie crimson #8E1F2A with shadow #5E1520; trousers charcoal #2E2D38 and #403F4D; gloves and shoes near-black #17151C with a cool highlight #4A4858 so they never vanish on a dark background; boombox light grey #C2BFB8 and #8C8A86, speaker cones dark #24232A with a grey ring, a small amber accent on the cassette window. Keep a light value on the body edge (shirt, boombox) so the silhouette reads against the dark navy and violet library backgrounds. Mood: strict, comic, a little menacing, no gore.

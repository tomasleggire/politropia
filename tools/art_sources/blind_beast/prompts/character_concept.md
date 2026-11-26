# El Topo (Blind Beast) - character concept (step A)

Contract: `docs/bosses/BLIND_BEAST_ANIMATIONS.md`. Design source: the blind old man of the library side quest (`concept/old_man_npc_ref.jpg`, copied from `assets/world/blind_npc.jpg`): the beast is that old man transformed, so he must stay recognisable. Style anchors: `tools/art_sources/luz/refs/luz_identity_ref.png` (Luz), `tools/art_sources/artemis/concept/artemis_concept_v2_keyed.png` (Artemis) and `tools/art_sources/boombox_teacher/concept/teacher_concept_v1.png` (El Profesor). Rule 0: one cohesive style. Same workflow as the Artemis and Profesor concepts.

Design decision: a giant STAR-NOSED MOLE (the star nose is the organ that feels vibrations, which is how he hunts Luz), standing upright and hunched like an old man, keeping the old man's grey hair as a tuft, his milky blind eyes, the torn remains of his charcoal suit jacket and dark red tie, and his wooden cane. Size: about 70 px on screen to the top of the head when standing (Luz 48, Artemis 56, Profesor 92); his eruption column is 56 x 90 px.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/blind_beast/concept/old_man_npc_ref.jpg \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -i tools/art_sources/boombox_teacher/concept/teacher_concept_v1.png \
  -- "<instruction wrapper + prompt below>" < /dev/null > <log> 2>&1 &
```

Run it from a scratch directory, never from the repository. Generated PNGs are picked up from `~/.codex/generated_images/<session>/`.

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt: <prompt>

## Prompt

Character reference sheet of EL TOPO, an optional boss for a 2D side-scrolling metroidvania set in a haunted library: the blind old man from the FIRST attached image has transformed into a giant blind STAR-NOSED MOLE. He must stay recognisable as that old man: a tuft of swept-back grey-white hair on top of the head, small milky pale-blue blind eyes half hidden in the fur, the torn remains of his charcoal suit jacket over the shoulders and a loosened dark red tie, and his wooden walking cane held in one claw. Mole anatomy: a heavy pear-shaped body covered in short dense fur, a long snout ending in a fleshy pink STAR NOSE with a ring of short tentacles, enormous pale shovel-shaped front claws (each hand as big as his head), short hind legs. He stands upright on his hind legs, hunched forward like an old man leaning on his cane. The SECOND attached image is the player character Luz and the THIRD is El Profesor, another boss of the same game: draw him in EXACTLY their rendering style: illustrated "pixel-styled" look, same rendering density, thick uniform dark outline (near-black warm brown #1A1410, as heavy as Luz's) around the whole silhouette and around every major shape, cel shading with 2-3 value steps per material, big flat colour shapes, slightly painterly texture. Do not redraw in true low-res pixel art, no smooth vector gradients, no rim light, no glow (the engine adds it).

Proportions: stocky and heavy, wider than Luz, about 1.45 times her height when standing hunched. Simplify like a game sprite: big readable claws, few fur strands, the star nose large and clear, so the figure still reads when shrunk to about 70 px tall.

Layout: one large full-body pose on the left, facing RIGHT, side/three-quarter view, standing hunched and leaning on the cane, the star nose sniffing forward, feet on a common ground line, the figure filling most of the image height. On the right, three smaller pose thumbnails of the same character at one shared smaller scale: (1) bursting up out of the ground, only the upper body above a ring of broken earth, claws raised; (2) a wide horizontal claw swipe to the right, one claw fully extended; (3) rearing up tall on the hind legs with both claws raised high, about to slam the ground. Flat solid magenta background #FF00FF everywhere, no ground line, no shadow, no text, no labels, no UI, no frame, no motion lines.

Palette (restrained, within about 16-24 colours): fur warm grey-brown #6B5E5A with shadows #463C3E and #2E2729 and a lighter edge #8F817A so the silhouette reads against the dark navy and violet library backgrounds; head tuft grey-white #C9C4CC; star nose pink #E07A8F with shadow #A8485E; claws pale bone #E3D6BC with shadow #A99878; eyes milky pale blue #C9D6DE; jacket charcoal #2E2D38 and #403F4D; tie dark red #7A1F2A; cane warm wood #8A5A33 and #B07A45. Mood: sad, eerie, a little grotesque, no gore.

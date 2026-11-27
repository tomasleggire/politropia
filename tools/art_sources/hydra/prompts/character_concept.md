# La Hidra (Hydra) - character concept (step A)

Contract: `docs/bosses/HYDRA_ANIMATIONS.md`. Style anchors: `tools/art_sources/luz/refs/luz_identity_ref.png` (Luz) and `tools/art_sources/boombox_teacher/concept/teacher_concept_v1.png` (El Profesor); the other approved bosses are `tools/art_sources/artemis/concept/artemis_concept_v2_keyed.png` and `tools/art_sources/blind_beast/concept/topo_concept_v1.png`. Rule 0: one cohesive style. Same workflow as the Artemis, Profesor and Topo concepts.

Design decision: the Lernaean Hydra as a massive coiled serpent with three heads on long necks at three heights. The heads keep their gameplay colours so the player can still choose a target at a glance: the BITER (low, crimson, heavy jaw and big fangs), the SWEEPER (middle, violet, long flat blade-like snout with a blade crest) and the SPITTER (high, acid green, cobra hood and venom sacs). In the game the body is one sprite (about 112 x 152 px on screen, Luz is 48 px tall), each head is its own sprite (about 56 x 42 px) and the necks are drawn by the engine with a tiled texture, so the concept must show the body, the three heads and the neck surface clearly.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check -C <scratch dir> \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -i tools/art_sources/boombox_teacher/concept/teacher_concept_v1.png \
  -- "<instruction wrapper + prompt below>" < /dev/null > <log> 2>&1 &
```

Run it from a scratch directory, never from the repository. Generated PNGs are picked up from `~/.codex/generated_images/<session>/`.

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt. Do not create or modify any file. Prompt: <prompt>

## Prompt

Character reference sheet of LA HIDRA, an optional boss for a 2D side-scrolling metroidvania set among ancient Greek ruins: the Lernaean Hydra, a massive three-headed water serpent. Body: a huge, heavy serpent trunk rising upright from thick coils resting on the ground, taller than it is wide, with a short thick tail curling behind it; dark teal-green scales with large readable scale shapes and a pale ochre plated belly. Three long, thick, smooth necks grow from the FRONT of the trunk at three different heights (one low near the ground, one at mid height, one near the top) and reach far forward, each ending in a clearly different head. The LOW head is the BITER: a short, heavy, crocodile-like skull with a massive jaw and big bone fangs, crimson red crest fins and red markings. The MIDDLE head is the SWEEPER: a long, flat, blade-like snout with a sharp blade-shaped horn crest sweeping back, violet crest and violet markings. The HIGH head is the SPITTER: a cobra-like head with a wide flared hood and swollen venom sacs under the jaw, acid green hood and green markings, a drop of bright green venom on its fangs. All three heads share the same teal scales, pale yellow slit eyes and bone-coloured teeth, so they read as one creature; the crest colour is what tells them apart. The FIRST attached image is the player character Luz and the SECOND is El Profesor, another boss of the same game: draw the Hydra in EXACTLY their rendering style: illustrated "pixel-styled" look, same rendering density, thick uniform dark outline (near-black warm brown #1A1410, as heavy as Luz's) around the whole silhouette and around every major shape, cel shading with 2-3 value steps per material, big flat colour shapes, slightly painterly texture. Do not redraw in true low-res pixel art, no smooth vector gradients, no rim light, no glow (the engine adds it).

Proportions: the trunk is about 3.2 times Luz's height; each head is about as long as Luz is tall. Simplify like a game sprite: few large scales, chunky readable heads, each head silhouette must still read when shrunk to about 56 px wide.

Layout: on the left, one large full-body view of the whole Hydra facing RIGHT, side view, the trunk and coils at the left and the three necks reaching to the right at three heights with gentle S-curves, jaws slightly open, the coils resting on a common ground line, the figure filling most of the image height. On the right, three close-up studies at one shared scale, each one a single head alone, side view facing RIGHT, cut off cleanly right behind the skull with no neck: (1) the BITER with its jaws wide open, (2) the SWEEPER with its jaws closed, (3) the SPITTER with its hood flared and its mouth open. Flat solid magenta background #FF00FF everywhere, no ground line, no shadow, no water, no text, no labels, no UI, no frame, no motion lines.

Palette (restrained, within about 16-24 colours): scales deep teal-green #33574A with shadows #1F3A36 and #14262A and a lighter edge #5E8F7A so the silhouette reads against dark navy night backgrounds and also against bright Greek sky blue and white marble; belly plates ochre-bone #D8C79A with shadow #A08E62; biter crest crimson #D94540 with shadow #8F2A30; sweeper crest violet #9466E6 with shadow #5A3D9E; spitter hood acid green #66CC4D with shadow #3D8A3A and venom #A6F06A; eyes pale yellow #FFF280; teeth bone #EDE3C8. Mood: ancient, menacing, mythic, no gore.

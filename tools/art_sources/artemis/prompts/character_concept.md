# Artemis - character concept (step A)

Contract: `docs/bosses/ARTEMIS_ANIMATIONS.md`. Style anchor: `tools/art_sources/luz/refs/luz_identity_ref.png` (Luz). Rule 0: one cohesive style.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  "<instruction wrapper + prompt below>" < /dev/null > <log> 2>&1 &
```

Generated PNGs are picked up from `~/.codex/generated_images/<session>/` (sandbox cannot copy into the repo).

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt. Do not modify any file in the repository. Prompt: <prompt>

## Prompt

Character reference sheet of ARTEMIS, a Greek huntress goddess boss for a 2D side-scrolling metroidvania, drawn in EXACTLY the same style as the attached reference of the player character Luz: illustrated "pixel-styled" look, same rendering density, same dark outline weight (near-black warm brown #1A1410, about 2-3 px at this scale), same cel shading with 2-3 value steps per material, same slightly painterly texture, same anime-influenced face with a simple eye. Do not redraw in true low-res pixel art, do not use smooth vector gradients, do not add rim light or glow (the engine adds it).

Layout: one large full-body idle pose, facing RIGHT, side/three-quarter view, feet on a common ground line, standing about 1.15 times Luz's height (Luz = 340 px; Artemis about 390 px tall in the same pixel scale). On the right, three small pose thumbnails of the same character at the same scale as the main figure's pixel grid: (1) bow at full draw, arrow nocked, side-on, one long horizontal line of arm, arrow and bow; (2) quick backstep hop, torso leaning back, bow forward; (3) bow raised vertically skyward, body arched back. Flat solid magenta background #FF00FF everywhere, no ground, no shadow, no text, no labels, no UI, no frame.

Character: slim, tall, upright, calm, controlled, never brutish. Long dark hair pulled back, with a long trailing veil or hair tail that reads motion. Pale silver-white Greek chiton tunic, short, belted, with a cobalt-blue short cape or cloth sash; leather bracers and sandals/boots. A recurve bow in her right hand in front, dominant and chunky (at least 3 px thick), warm wood (#D8792E / #F0AE4C) with crescent-moon tips in pale silver. Quiver of arrows on her back (on the left side of the sprite when facing right). Short dagger sheathed at the belt. A small crescent-moon circlet or clasp. Torso narrow (about 26 px wide in a 56 px body), bow, hair and cloth may overhang.

Palette (restrained, cool, within about 16-24 colours): dark navy shadows #090D1D and #101A33, cobalt edge light #24558A and #4C79A8, pale cloth #B8C9DC and white, warm accent only on bow wood and belt, silver moon accents. Keep a light value on the body edge so the silhouette reads against dark navy backgrounds; it must also sit well against bright Greek sky blue and white marble. Mood: cold, elegant, dangerous, no gore. Silhouette must read clearly when shrunk to about 56 px tall.

## Revision v2 (appended after the v1 comparison with Luz)

v1 matched the rendering family but not the proportions or line weight: Artemis came out as a realistic 7-head figure with hairline outlines and fine detail, next to Luz's chunky 3-head figure with a heavy dark outline. Appended to the prompt for v2:

> Match Luz's proportions and chunkiness: a stylised, stocky game-sprite figure of about 4 heads tall (large head, big simple eyes like Luz, short torso, sturdy limbs, bigger hands and feet), NOT a realistic fashion-illustration body. Thick, uniform dark outline (#1A1410) around the whole silhouette and around every major shape, as heavy as Luz's. Simplify detail: fewer straps, fewer folds, large flat colour shapes with 2-3 shading steps, so it still reads at 56 px tall. Keep the hair, veil, cape, chunky bow and quiver as big readable masses. Fully clothed, legs not bare above the knee: short trousers or a longer tunic with leggings.

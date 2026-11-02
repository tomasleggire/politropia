# Artemis - batch 3 (remaining art)

Contract: `docs/bosses/ARTEMIS_ANIMATIONS.md`. Same pipeline and invocation as `minimal_set.md`: one Codex run per raw sheet, in parallel, outputs copied to `../raw/`, then `python tools/process_artemis_sheets.py`.

| Raw sheet | Grid | Content | Extra `-i` reference |
|---|---|---|---|
| `artemis_intro_raw.png` | 4x2 | `intro` 0-7 (ends in the idle pose) | - |
| `artemis_walkback_raw.png` | 4x2 | `walk_back` 0-7 (loop) | `../raw/artemis_loco_raw.png` |
| `artemis_stagvanish_raw.png` | 4x2 | `stag_vanish` 0-7 | `../raw/artemis_stag_raw.png` |
| `artemis_impact_raw.png` | 4x2 | arrow impact: amber 0-3, moon 4-7 | `../raw/artemis_vfx_raw.png`, `../raw/artemis_arrow_raw.png` |
| `artemis_glyphs_raw.png` | 4x2 | telegraph glyphs (white, tinted in code) | `../raw/artemis_vfx_raw.png` |

Body sheets (intro, walk back) use the Common block of `minimal_set.md` verbatim, with the concept v2 and `luz_identity_ref.png` as the first two `-i`. The stag, impact and glyph sheets use their own block below, with `luz_identity_ref.png` as the first `-i` (style only) and the listed raw sheet as the second.

## Sheet block: Intro

> Sheet INTRO: grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2. Artemis is revealed as the boss and gets ready to fight, in about 0.8 seconds.
> Cells 1-2 = kneeling on one knee, head bowed, the bow held upright in front of her like a vow, eyes closed, veil and cape at rest.
> Cells 3-4 = rising to her feet, head lifting, eyes open and fixed on the opponent to the right.
> Cells 5-6 = a confident flourish: she spins the bow once in the right hand (cell 5 bow horizontal mid-spin, cell 6 bow caught), cape and ponytail swinging.
> Cells 7-8 = settling into the exact IDLE stance of the locomotion sheet (bow held lowered but ready in the right hand in front, weight on the back foot). Cell 8 must be identical to that idle pose so the clip flows into idle.
> Grounded frames share the sole row; the kneeling frames also rest on that row.

## Sheet block: Walk back

> Sheet WALK BACK: grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2. The THIRD attached image is her existing locomotion sheet: match its walk exactly in scale, bow position and costume.
> Cells 1-8 = WALK BACKWARDS loop (8 frames): she retreats to the LEFT while still FACING RIGHT toward the opponent, bow held ready in front, wary and controlled, torso slightly leaning back, short careful steps where the back foot reaches behind first; contact poses at cells 1 and 5; hair, veil and cape drift forward a little because she moves backward; cell 8 flows back into cell 1.

## Sheet block: Stag vanish

> Generate an image with your built-in image generation tool from the following prompt. Do not modify any file in the repository. Prompt:
>
> Animation sprite sheet of the SPECTRAL STAG summoned by the huntress Artemis in a 2D side-scrolling metroidvania. The FIRST attached image is only for rendering style: illustrated pixel-styled look, thick uniform dark outline, cel shading with 2-3 value steps, big flat shapes. The SECOND attached image is the existing spectral stag sheet: use it as the exact creature (same silver-white body, antlers, proportions, palette and size).
> Grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2. The stag faces RIGHT, side view, same size in every cell as in the reference.
> Cells 1-8 = VANISH: at the end of its charge the stag dissolves into moonlight. Cell 1 = mid-gallop pose from the reference, intact. Cells 2-4 = the body starts to break apart from the hind legs and tail forward into large chunky silver shards and crescent-shaped wisps (each shard at least the size of a hoof, no tiny dust), antlers last to go. Cells 5-7 = only a loose cloud of large silver shards and wisps keeping the stag's rough outline, drifting up and fading toward a pale silver. Cell 8 = a few last large wisps, almost gone.
> Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no text, no labels, no grid lines, no frames, no outer glow halo. Each frame stays fully inside its own cell with at least 16 px padding; the lowest hoof or shard sits on the same row of each cell.

## Sheet block: Arrow impact

> Generate an image with your built-in image generation tool from the following prompt. Do not modify any file in the repository. Prompt:
>
> Effect sprite sheet for a 2D side-scrolling metroidvania boss fight: ARROW IMPACT bursts. The FIRST attached image is only for rendering style (illustrated pixel-styled look, thick uniform dark outline, cel shading, big flat shapes). The SECOND attached image is the existing Artemis effects sheet: match its style, line weight and palette. The THIRD attached image shows the two arrows (normal amber-fletched arrow, and silver moon arrow).
> Grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2. The arrow flew from LEFT to RIGHT and struck a surface on the right side of the cell; the burst opens back toward the left.
> Cells 1-4 = AMBER IMPACT (normal arrow): 1 the arrowhead hits, a small hard flash; 2 a chunky starburst of amber and warm-white sparks with 2-3 wood splinters; 3 the burst expands and breaks into larger pieces; 4 a few fading amber embers. Amber #FFB840 and warm white, dark outline.
> Cells 5-8 = MOON IMPACT (moon arrow): the same timing but silver-white and pale blue (#CCE6FF), with a small crescent-shaped shard flying off in cells 6-7.
> Every piece is chunky (no tiny dust, no thin lines), readable when shrunk to about 24 px. Flat opaque magenta #FF00FF background everywhere, no text, no labels, no grid lines, no frames, no outer glow halo. Each burst stays fully inside its own cell with at least 16 px padding, centred vertically in the cell.

## Sheet block: Telegraph glyphs

> Generate an image with your built-in image generation tool from the following prompt. Do not modify any file in the repository. Prompt:
>
> Sprite sheet of TELEGRAPH GLYPHS for a 2D side-scrolling metroidvania boss fight against Artemis, goddess of the hunt and the moon. These mark where attacks will land. The FIRST attached image is only for rendering style (illustrated pixel-styled look, chunky shapes, dark outline). The SECOND attached image is the existing Artemis effects sheet: match its line weight.
> Draw every glyph in PURE WHITE and LIGHT GREY only (no other colours: the game tints them amber, silver or red in code), with a dark outline #1A1410. The OUTER EDGES of each glyph must be brighter (pure white) than its inner fill (light grey), so the edges read first.
> Grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2; each glyph centred in its cell with at least 16 px padding.
> Cell 1 = FLOOR GLYPH A, a flat wide strip seen from the side (about 7 times wider than tall), a row of small downward arrowheads inside a bright rim: marks where an arrow rain will fall.
> Cell 2 = FLOOR GLYPH B, a flat wide strip (about 7 times wider than tall) with a crescent moon in the middle and short radiating ticks: marks where the moon dive will land.
> Cell 3 = WALL GLYPH, a tall rectangle (about 5 wide by 4 tall) holding a stylised stag head with antlers: marks the wall the spectral stag will charge from.
> Cell 4 = AIM DOT, a small diamond-shaped bead with a bright rim, used repeated along a dotted aim line.
> Cells 5-8 = the same four glyphs in the same order, in a brighter "about to strike" state: thicker bright rim and slightly larger inner shapes.
> Flat opaque magenta #FF00FF background everywhere, no text, no labels, no grid lines, no frames, no glow halo, no perspective (strictly flat side view).

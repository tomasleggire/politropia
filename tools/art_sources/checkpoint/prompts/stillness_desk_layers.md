# Stillness Desk Layer Prompts

Generated with Codex's built-in image generation (`codex exec`). Raw sheets live in
`tools/art_sources/checkpoint/raw/` (gitignored); `tools/process_stillness_desk_art.py`
turns them into `assets/world/stillness_desk/*.png` + `layout.json`.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check \
  -i tools/art_sources/checkpoint/concept/stillness_desk_concept_v1.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  [-i <scratch crop of rest-sheet mount frame 2 + dismount frame 4, on magenta>  # props sheet only, backpack ref] \
  -o <last-message file> "<instruction + prompt>"
```

Four runs in parallel, one per sheet. The sandbox refused the copy into the repo
(`Operation not permitted`), so the generated PNGs were taken from
`~/.codex/generated_images/<session>/` and copied to `raw/stillness_{desk,roots,props,misc}_raw.png`.
Each run emitted two images; the final one (opaque magenta) is used, the earlier
(alpha, discarded draft) is kept as `*_alt.png` for reference only.

Codex ignored numeric proportions, so the processor rescales every layer to the
target texel density (1 px = 0.175 world units). No edit pass was needed.

## Instruction wrapper

> Generate an image with your built-in image generation tool from the following prompt, and save the final PNG to <raw path> (opaque magenta background is acceptable). Do not modify any other file. Prompt: <sheet prompt>

## Sheet prompts

### desk

> Image 1 is the concept art (art direction: gothic school-desk lectern with carved arch panels, brass corners, paper ribbons, cobalt inkwell with quill, candle in a small glass jar, open wooden box, pendulum with brass bob, amber-marked floor ring; use its palette: near-black navy, deep blue, steel blue, pale sky blue, amber orange and warm yellow). Image 2 is Luz, the in-game character (clean outlined anime pixel art, crisp 1-2 px dark outlines, limited palette, soft cel shading); every asset must look like it belongs in the same game as Luz. Produce production 2D game sprite assets: chunky readable pixel art with clean dark outlines, no painterly blur, no photo texture. Views are strictly FRONTAL (straight-on side-scroller elevation, camera at object mid height) unless stated otherwise. Each asset is a separate isolated item on a perfectly flat solid magenta #FF00FF background (no gradients, no shadows, no glow, no ground line, no text, no labels, no borders, no frame numbers), with at least 100 px of empty magenta between items and around the sheet edge. Never use magenta or pink inside the art. Generate ONE landscape PNG. Items, arranged in one row left to right: (A) DESK BODY: a waist-high gothic school-desk lectern seen frontally, a wide flat wooden top slab with brass corner caps and slightly overhanging edge, below it a stone-and-dark-wood front with three carved gothic arch panels (centre panel taller, with brass handle plate), small ornate brass ornaments, short stubby base. Total proportion about 1.25 wide : 1 tall, top slab thickness about 12 percent of the height. The top surface is seen as a thin front edge only (flat elevation), nothing on the top, no paper, no ribbons, no roots, no props. (B) ARCH FRAME: a restrained gothic pointed-arch stone doorway/niche frame seen frontally, dark blue stone bricks with subtle lighter blue edge highlights, two thick side pillars with simple capitals and a pointed arch on top, a small stone keystone at the apex, the inside of the arch left as flat magenta (transparent) so it is just a frame, about 1 wide : 1.4 tall. Low contrast, subtle, must not compete with a character standing in front of it.

### roots

> Image 1 is the concept art (art direction: gothic school-desk lectern with carved arch panels, brass corners, paper ribbons, cobalt inkwell with quill, candle in a small glass jar, open wooden box, pendulum with brass bob, amber-marked floor ring; use its palette: near-black navy, deep blue, steel blue, pale sky blue, amber orange and warm yellow). Image 2 is Luz, the in-game character (clean outlined anime pixel art, crisp 1-2 px dark outlines, limited palette, soft cel shading); every asset must look like it belongs in the same game as Luz. Produce production 2D game sprite assets: chunky readable pixel art with clean dark outlines, no painterly blur, no photo texture. Views are strictly FRONTAL (straight-on side-scroller elevation, camera at object mid height) unless stated otherwise. Each asset is a separate isolated item on a perfectly flat solid magenta #FF00FF background (no gradients, no shadows, no glow, no ground line, no text, no labels, no borders, no frame numbers), with at least 100 px of empty magenta between items and around the sheet edge. Never use magenta or pink inside the art. Generate ONE landscape PNG. Items, arranged top to bottom: (A) PAPER ROOTS: a wide horizontal cluster of pale cream paper-ribbon roots with faint handwritten ink lines and slightly curled frayed ends, as if paper strips grew like tree roots; they spread left and right along a flat floor line in frontal side view, a thick central tangle in the middle where they attach (the attach edge is a flat top-centre area), thinning into long curling tendrils toward both ends, some tendrils lifting slightly. Wide, about 4 wide : 1 tall. Cream, tan and pale grey-blue shading with dark outlines. (B) FLOOR RING: a circular clock-protractor ring engraved on stone floor seen at a shallow angle so it is a flat wide ellipse (about 5 wide : 1 tall), a thin band of dark blue stone with a thin dim bronze-brown outline on both edges and short radial tick marks around the band (like a clock or protractor scale), the inside of the ellipse and the outside left magenta so only the band exists. Ticks are dull bronze and unlit.

### props

> Image 1 is the concept art (art direction: gothic school-desk lectern with carved arch panels, brass corners, paper ribbons, cobalt inkwell with quill, candle in a small glass jar, open wooden box, pendulum with brass bob, amber-marked floor ring; use its palette: near-black navy, deep blue, steel blue, pale sky blue, amber orange and warm yellow). Image 2 is Luz, the in-game character (clean outlined anime pixel art, crisp 1-2 px dark outlines, limited palette, soft cel shading); every asset must look like it belongs in the same game as Luz. Produce production 2D game sprite assets: chunky readable pixel art with clean dark outlines, no painterly blur, no photo texture. Views are strictly FRONTAL (straight-on side-scroller elevation, camera at object mid height) unless stated otherwise. Each asset is a separate isolated item on a perfectly flat solid magenta #FF00FF background (no gradients, no shadows, no glow, no ground line, no text, no labels, no borders, no frame numbers), with at least 100 px of empty magenta between items and around the sheet edge. Never use magenta or pink inside the art. Generate ONE landscape PNG. Items, arranged in a grid, left to right, top row then bottom row: TOP ROW: (1) CANDLE JAR WITHOUT FLAME: a short cream candle in a small round glass jar, no flame at all, unlit black wick, small, about 1 wide : 1.2 tall. (2) FLAME FRAME 1, (3) FLAME FRAME 2, (4) FLAME FRAME 3, (5) FLAME FRAME 4: four separate small candle flames of a looping flicker animation, each drawn upright, warm yellow core, orange outer edge, dark-orange tip, each about 0.5 wide : 1 tall, consistent size, gentle sway differences between frames, bases all aligned at the bottom, no candle, no glow halo. BOTTOM ROW: (6) INKWELL: a cobalt-blue glass square inkwell with a bright highlight and a white feather quill sticking out to the upper right, about 1 wide : 1.6 tall. (7) INK BOX: a small open wooden box seen frontally with its lid raised open behind it, brass hinges and clasp, dark brown wood, empty interior in shadow, about 1.3 wide : 1 tall. (8) BACKPACK: Luz's dark navy school backpack resting upright on the floor seen from the side, rounded top, front pocket with zipper, shoulder strap loop, slightly slouched, dark navy fabric with lighter blue highlights and dark outlines, about 1 wide : 1.1 tall.

### misc

> Image 1 is the concept art (art direction: gothic school-desk lectern with carved arch panels, brass corners, paper ribbons, cobalt inkwell with quill, candle in a small glass jar, open wooden box, pendulum with brass bob, amber-marked floor ring; use its palette: near-black navy, deep blue, steel blue, pale sky blue, amber orange and warm yellow). Image 2 is Luz, the in-game character (clean outlined anime pixel art, crisp 1-2 px dark outlines, limited palette, soft cel shading); every asset must look like it belongs in the same game as Luz. Produce production 2D game sprite assets: chunky readable pixel art with clean dark outlines, no painterly blur, no photo texture. Views are strictly FRONTAL (straight-on side-scroller elevation, camera at object mid height) unless stated otherwise. Each asset is a separate isolated item on a perfectly flat solid magenta #FF00FF background (no gradients, no shadows, no glow, no ground line, no text, no labels, no borders, no frame numbers), with at least 100 px of empty magenta between items and around the sheet edge. Never use magenta or pink inside the art. Generate ONE landscape PNG. Items, arranged in one row left to right: (1-4) FOUR LOOSE PAPER SHEETS, each a different design: a flat rectangular sheet of cream paper with handwritten ink lines, seen slightly rotated, with curled corners; sheet 1 flat and slightly tilted, sheet 2 with a folded corner, sheet 3 curled like a scroll end, sheet 4 crumpled slightly with a tear. Each about 1 wide : 1.3 tall, similar size, pale cream with tan shading and dark outline. (5) PENDULUM: a vertical thin brass rod with small ornamental collars hanging straight down, ending in a large round brass bob (sphere with a highlight, ring bands and a small finial at the top of the rod), the whole piece straight vertical and perfectly symmetric about its vertical axis, about 1 wide : 9 tall, pivot loop at the very top centre. (6) PENDULUM BRACKET: a small ornate gothic brass and dark stone ceiling bracket / keystone, a compact decorative mount that a pendulum hangs from, symmetric, with a small hole ring at the bottom centre, about 1.5 wide : 1 tall.

## Post-processing decisions (not generated)

- `floor_ring_unlit` and `floor_ring_lit` are derived from the single generated ring in the processor (amber pixels dimmed vs brightened + soft glow) so their geometry is identical; a second Codex ring would not match pixel for pixel.
- `arch_frame` is darkened to 62% brightness so it recedes behind Luz.
- `desk_body` is stretched 1.2x horizontally to reach ~324 px width at the required 150 px height.

## Roots: interim derivation and pending Codex redo

The first roots sheet read as a soft, painterly noodle pile covering the desk's centre panel. Codex regeneration failed (workspace out of credits), so as an interim fix `process_stillness_desk_art.py` cuts the existing roots: the centre 130 px (about 40% of the desk width) is masked with an 8 px alpha falloff, orphan specks under 60 px are dropped, and each half is shifted so its inner edge sits at a desk leg (x = -140 / +140). Exported as `roots_left.png` and `roots_right.png`. Style is still the softer original render.

### Pending redo (run after credits are refilled)

Invocation (stdin MUST be closed and the run backgrounded, or codex hangs):

```
nohup codex exec -s workspace-write --skip-git-repo-check \
  -i tools/art_sources/checkpoint/concept/stillness_desk_concept_v1.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -i tools/art_sources/checkpoint/raw/stillness_desk_raw.png \
  -o <last-message file> "<wrapper with raw path stillness_roots2_raw.png + prompt below>" > log.txt 2>&1 < /dev/null &
```

Prompt:

> 
Image 1 is the concept art (art direction: gothic school-desk lectern with carved arch panels, brass corners, paper ribbons, cobalt inkwell with quill, candle in a small glass jar, open wooden box, pendulum with brass bob, amber-marked floor ring; use its palette: near-black navy, deep blue, steel blue, pale sky blue, amber orange and warm yellow). Image 2 is Luz, the in-game character (clean outlined anime pixel art, crisp 1-2 px dark outlines, limited palette, soft cel shading); every asset must look like it belongs in the same game as Luz. Produce production 2D game sprite assets: chunky readable pixel art with clean dark outlines, no painterly blur, no photo texture. Views are strictly FRONTAL (straight-on side-scroller elevation, camera at object mid height) unless stated otherwise. Each asset is a separate isolated item on a perfectly flat solid magenta #FF00FF background (no gradients, no shadows, no glow, no ground line, no text, no labels, no borders, no frame numbers), with at least 100 px of empty magenta between items and around the sheet edge. Never use magenta or pink inside the art. Generate ONE landscape PNG. Items: TWO separate paper-root clusters side by side with at least 200 px of empty magenta between them: (LEFT) a low, wide cluster of unrolled paper scrolls and ribbons in frontal side view, whose thick attachment point is at its RIGHT end (the end nearest the centre of the sheet, where it would emerge from a desk leg corner), flowing outward to the LEFT and down along a flat floor line, the ribbons lying and curling on the floor, ends curling up into small spirals, a few thin strands trailing far out to the left; (RIGHT) the exact mirror-style counterpart with its attachment at its LEFT end flowing outward to the RIGHT (similar but not a pixel-identical copy). Each cluster is about 3 wide : 1 tall, low profile, flat bottom edge sitting on the floor line, tallest at the attachment end. Rendering: crisp clean chunky pixel art with a solid 1-2 px DARK NAVY outline around every shape, flat cel shading with only 3-4 tones per material, warm off-white paper with cool blue-grey shadow tones, faint dark blue ink handwriting lines on the ribbons. NO green or olive tones anywhere, no soft painterly texture, no blur, no anti-aliased gradients. Same pixel-art quality as a retro game sprite.

After generation: add a `stillness_roots2_raw.png` sheet spec (items `roots_left`, `roots_right`, left to right) to `SHEETS` and replace `split_roots` with direct scaling.

Use your image generation tool to create ONE sprite sheet image, then save the final PNG to
`tools/art_sources/luz/raw/ground_attack_2_raw.png` (create folders if needed). Do not edit any other file.
Reply with the saved path and the image pixel size.

Attached references:
1. `luz_identity_ref.png` — the character "Luz" (existing sprites). Match her identity exactly: blonde messy
   ponytail, blue eyes, oversized dark navy hoodie jacket over a white shirt with a thin dark blue tie, wide
   dark navy baggy pants, grey/white sneakers, dark navy backpack. Same anime pixel-art rendering, same outline
   weight, same palette, same proportions.
2. `blasphemous_slash_ref.png` — quality/feel reference only (Blasphemous, The Penitent One): a fast, weighty,
   fluid horizontal sword slash. Do NOT copy that character; copy the motion quality.

Her weapon is a flat, straight, light-brown WOODEN RULER with dark measurement tick marks along one edge,
rectangular with square ends, about as long as her arm plus her torso (roughly 55% of her standing height).
It must read as a ruler, never a bat, stick or sword. Keep the ruler the same length and width in every frame.

Animation: GROUND COMBO HIT 2 — a fast BACKHAND horizontal slash at waist height, chaining from hit 1.
It must be a clearly curved sweep, NOT a straight poke. Hit 1 ended with the ruler low in front of her; hit 2
whips the ruler back and around, then cuts forward horizontally at WAIST height (lower than hit 1's chest-height
cut) with a strong hip twist. Facing RIGHT in every frame. 8 frames, in order:
1. Start pose: weight on the front foot, ruler low in front of her pointing down-right (like hit 1's end).
2. Wind-back: she pulls the ruler back across her body to her LEFT hip, ruler roughly horizontal pointing LEFT
   behind her at waist height, torso twisted away, back foot planted.
3. Swing: hips snap forward, ruler sweeping around her side, diagonal in front of her with the tip pointing
   right and slightly DOWN (about 20 degrees below horizontal).
4. Contact: right arm fully extended forward at WAIST height, ruler perfectly HORIZONTAL pointing right,
   maximum reach, low wide stance. This is the widest frame.
5. Follow-through: the sweep continues UP and across; ruler angled up-right (about 40 degrees above
   horizontal), arm still extended.
6. Follow-through settle: ruler raised in front of her at shoulder height, pointing up-right.
7. Recovery: bringing the ruler down toward a guard.
8. Guard: ruler held in front at chest height pointing up-forward, ready to chain into the finisher.

RULER SIZE (critical): the ruler is LONG — about 130 px long in every frame (a bit more than half of her
240 px standing height) and about 14 px wide. Measure it: it must be the same length in every frame where it
is fully visible. Do not shrink it when it points sideways.

STRICT OUTPUT RULES (the previous attempt failed these):
- The background must be 100% transparent: alpha = 0 on every pixel outside the character. NO glow, NO haze,
  NO vignette, NO colored backdrop, NO soft shadow.
- Standing height exactly 240 px, same pixel scale as the attached HIT 1 sheet. Feet baseline at y = 472 px
  inside EVERY cell of BOTH rows (i.e. y = 472 in the top row and y = 984 in the bottom row of the canvas).
- Every pixel at least 12 px inside its own 384x512 cell.

NO slash smear, NO trail effects, NO sparks, NO text, NO frame numbers, NO grid lines — only the character.

Layout (critical, it will be cut by a program):
- Canvas 1536x1024, fully TRANSPARENT background (real alpha). If transparency is impossible, use a flat
  pure #00FF00 background with no gradients or shadows.
- 4 columns x 2 rows of invisible 384x512 cells, row-major order (frames 1–4 top row, 5–8 bottom row).
- The character is the SAME SIZE in every frame (standing height about 240 px), feet on the same baseline
  about 40 px above the bottom of each cell, and the body center is about 140 px from the LEFT edge of its
  cell (leaving room in front for the extended ruler).
- Every pixel of each frame, including the fully extended ruler, stays at least 12 px inside its own cell.
  Nothing may touch or cross into a neighboring cell.
- Crisp pixel art edges, no blur, no drop shadow, no ground.

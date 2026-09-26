Use your image generation tool to create ONE sprite sheet image, then save the final PNG to
`tools/art_sources/luz/raw/ground_attack_3_raw.png` (create folders if needed). Do not edit any other file.
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

Animation: GROUND COMBO HIT 3 (FINISHER) — a heavy RISING-TO-HORIZONTAL two-handed sweep with a big forward
lunge. It must look clearly DIFFERENT from hit 1 (hit 1 winds up OVERHEAD; this one winds up LOW behind her hip)
and reach FARTHER than hits 1 and 2. Clearly curved arc, NOT a poke. Facing RIGHT in every frame. 8 frames:
1. Guard: ruler held in front at chest height pointing up-forward (like hit 2's end).
2. Low wind-up: she crouches and pulls the ruler down and BACK with both hands behind her right hip, ruler
   pointing diagonally DOWN and BEHIND her (tip toward the lower left, about 30 degrees below horizontal),
   torso coiled, weight on the back foot.
3. Explosive step-in: big forward step, ruler sweeping forward and upward past her front knee, tip pointing
   right and slightly down (about 15 degrees below horizontal).
4. Contact: deepest lunge of the whole combo, back leg almost straight, torso leaning forward, both arms fully
   extended at chest height, ruler perfectly HORIZONTAL pointing right. The ruler tip must be FARTHER right than
   in hit 1's contact frame (tip about 350 px from the cell's left edge). This is the widest frame.
5. Follow-through: the arc keeps rising; ruler angled up-right (about 45 degrees above horizontal), arms extended.
6. Heavy follow-through: ruler high above her front shoulder pointing up, hair swinging forward, body still low.
7. Recovery: pushing back up, bringing the ruler down to her side.
8. Back to ready stance: knees bent, ruler held low in the right hand pointing down-forward (so the combo can
   loop back to hit 1).

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
  about 40 px above the bottom of each cell, and the body center is about 130 px from the LEFT edge of its
  cell (leaving room in front for the extended ruler).
- Every pixel of each frame, including the fully extended ruler, stays at least 12 px inside its own cell.
  Nothing may touch or cross into a neighboring cell.
- Crisp pixel art edges, no blur, no drop shadow, no ground.

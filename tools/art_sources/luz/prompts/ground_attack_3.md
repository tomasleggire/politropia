Use your image generation tool to create ONE sprite sheet image, then save the final PNG to
`tools/art_sources/luz/raw/ground_attack_3_raw.png` (create folders if needed). Do not edit any other file.
Reply with the saved path and the image pixel size.

Attached references:
1. `luz_identity_ref.png` — the character "Luz" (existing sprites). Match her identity exactly: blonde messy
   ponytail, blue eyes, oversized dark navy hoodie jacket over a white shirt with a thin dark blue tie, wide
   dark navy baggy pants, grey/white sneakers, dark navy backpack. Same anime pixel-art rendering, same outline
   weight, same palette, same proportions.
2. `blasphemous_slash_ref.png` — quality/feel reference only (Blasphemous, The Penitent One): a fast, weighty,
   fluid horizontal sword slash (the sideways, flat cut shown is exactly the motion to replicate). Do NOT copy that character; copy the motion quality.

Her weapon is a flat, straight, light-brown WOODEN RULER with dark measurement tick marks along one edge,
rectangular with square ends, about as long as her arm plus her torso (roughly 55% of her standing height).
It must read as a ruler, never a bat, stick or sword. Keep the ruler the same length and width in every frame.

STYLE OF THE CUT (critical, the previous version was rejected): this is a HORIZONTAL, SIDEWAYS sword swing,
like the main attack of The Penitent One in Blasphemous (attached reference) — the blade travels in a flat
horizontal plane around her body at chest height, NOT from top to bottom. NEVER raise the ruler above her head.
Because the swing is horizontal and the camera is a side view, the ruler is FORESHORTENED (looks shorter) in the
frames where it points toward or away from the camera, and fully long when it points left or right.
She grips the ruler like a sword and puts her whole body into it (hips and shoulders rotate).

Animation: GROUND COMBO HIT 3 (FINISHER) — a heavy TWO-HANDED horizontal sweep with a big forward step, reaching
FARTHER than hits 1 and 2. Facing RIGHT in every frame. 8 frames:
1. Guard: ruler held in front at chest height pointing forward-up (like hit 2's end).
2. Big wind-back: she steps back onto the rear foot and pulls the ruler back with BOTH hands behind her right
   shoulder, ruler perfectly HORIZONTAL pointing LEFT behind her at chest height, torso fully coiled away.
3. Step-in swing: big forward step, body lunging; the ruler sweeps around horizontally, FORESHORTENED (pointing
   toward the camera) at chest height beside her.
4. Contact: deepest lunge of the whole combo, back leg almost straight, torso leaning forward, both arms fully
   extended at chest height, ruler perfectly HORIZONTAL pointing RIGHT, full length. The ruler tip must be FARTHER
   right than in hit 1's contact frame (tip about 350 px from the cell's left edge). Widest frame.
5. Follow-through: momentum carries the swing around in the same horizontal plane; ruler FORESHORTENED (pointing
   away from the camera), arms crossing in front of her.
6. Heavy follow-through: ruler horizontal across the front of her body pointing LEFT, body still low and rotated,
   hair swinging forward.
7. Recovery: pushing back up, bringing the ruler down to her right side.
8. Ready stance: knees bent, ruler held low in the right hand pointing down-forward (so the combo loops to hit 1).

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

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

Animation: GROUND COMBO HIT 3 (FINISHER) — a heavy, committed two-handed horizontal sweep with a big
forward step. It must feel heavier and reach farther than hits 1 and 2, with a clearly curved arc, NOT a poke.
Facing RIGHT in every frame. 8 frames, in order:
1. Guard: ruler held in front at chest height pointing up-forward (like hit 2's end).
2. Big wind-up: she steps back onto the rear foot and raises the ruler with BOTH hands high over her right
   shoulder, ruler pointing diagonally up and BEHIND her (about 50 degrees above horizontal, tip toward the left).
3. Step-in swing: big forward step, body lunging, ruler coming down diagonally in front of her with the tip
   pointing up-right (about 30 degrees above horizontal).
4. Contact: deepest lunge of the whole combo, both arms fully extended forward at chest height, ruler
   perfectly HORIZONTAL pointing right, maximum reach — farther forward than any other frame. This is the widest frame.
5. Follow-through: momentum carries the ruler down and across; ruler angled down-right (about 40 degrees
   below horizontal), body still low and forward.
6. Heavy follow-through: ruler tip near the ground in front of her, knees deeply bent, hair swinging forward.
7. Recovery: pushing back up, pulling the ruler back toward her side.
8. Back to ready stance: knees bent, ruler held low in the right hand pointing down-forward (so the combo can
   loop back to hit 1).

RULER SIZE (critical): the ruler is LONG — about 130 px long in every frame (a bit more than half of her
240 px standing height) and about 14 px wide. Measure it: it must be the same length in every frame where it
is fully visible. Do not shrink it when it points sideways.

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

Use your image generation tool to create ONE sprite sheet image, then save the final PNG to
`tools/art_sources/luz/raw/ground_attack_1_raw.png` (create folders if needed). Do not edit any other file.
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

Animation: GROUND COMBO HIT 1 — a big, fast ARCING slash, like a sword cut, NOT a straight poke or thrust.
The ruler tip must travel along a wide curved arc from high behind her, over her shoulder, down to chest
height in front of her. Facing RIGHT in every frame. 8 frames, in order:
1. Ready stance, knees bent, ruler held low in the right hand, pointing down-forward.
2. Anticipation: torso twists back to the left, both hands raise the ruler up and back over her right
   shoulder; the ruler points diagonally UP and BEHIND her (about 45 degrees above horizontal, tip toward the left).
3. Swing: body rotating forward, arm coming over the top; the ruler is diagonal IN FRONT of her, tip pointing
   up-right (about 45 degrees above horizontal).
4. Contact: right arm fully extended forward at chest height, ruler perfectly HORIZONTAL pointing right,
   maximum reach, front knee bent in a deep lunge. This is the widest frame.
5. Follow-through: the arc continues downward; ruler angled down-right (about 35 degrees below horizontal),
   still extended in front of her.
6. Follow-through settle: weight on the front foot, ruler low in front, tip near knee height.
7. Recovery: pulling back toward the ready stance.
8. Back to ready stance (close to frame 1 so the clip can chain into the next hit).

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

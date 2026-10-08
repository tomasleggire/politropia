# P10 - Codex art request: Luz heal (focus) and Stillness Desk rest v2

Status: draft 2026-10-08. Codex draws ONLY the character and her ruler; all glow, particles, dust and the desk are VFX/world art. Raw sheets are local and gitignored in `tools/art_sources/luz/raw/`.

## 1. Design rationale

### 1.1 Heal (focus)
Today (`scripts/player/player.gd`, `tests/soul_focus_test.gd`): holding `focus` on the floor, with no horizontal input, enough soul (`focus_cost` 33) and a missing pip enters `State.FOCUS`. Each channel lasts `focus_time` 0.9 s; at the end one pip heals and the soul is spent, and if focus is still held and available the channel chains (`_focus_left` and `_state_time` reset), otherwise the state returns to IDLE. Releasing, running out of soul, leaving the floor, jump, attack, dash or horizontal input cancels at once back to IDLE (or FALL). There is no animation today; a Polygon2D glow is a placeholder.

Design: Luz plants the point of the long ruler on the ground and rests both hands on the grip, head bowed, eyes closed (knight leaning on his sword). It reuses the sword grip, keeps the 215-texel ruler at its natural upright length (about 0.65 of her height, grip at chest height), reads at 48 px and needs no extra props. The ruler tip touches the ground at x about 290 (front of her feet).

| Clip | Frames | Playback |
|---|---|---|
| `heal_start` | 3 (slots 1-3) | plays once on entering FOCUS, 0.07 s per frame (0.21 s); leaves the loop pose on its last frame |
| `heal_loop` | 4 (slots 4-7) | loops while FOCUS lasts; one cycle = `focus_time` 0.9 s (0.225 s per frame) so the cycle wrap coincides with the heal pip. Because chaining resets `_state_time`, restart the loop (not the start) on chain |
| `heal_end` | 2 (slots 8-9) | plays once ONLY after a completed heal that does not chain (0.1 s per frame); any cancel (release, action, damage) skips it and goes straight to idle |

Interruptions: all cancels are immediate in `player.gd`, so the clips must tolerate being cut at any frame; `heal_end` is cosmetic and never delays control.

VFX (procedural, not in the frames): a soft pulsing warm-white halo around the chest that grows with channel progress (replace the current Polygon2D with a shader/GPUParticles2D), small motes rising towards her head, and a bright flash plus a ring burst at the heal pip (the loop wrap), HUD pip refilling. Tint matches the existing `_update_focus_glow` colour (1.0, 0.95, 0.75).

### 1.2 Rest at the Stillness Desk
Choreography today (`scripts/world/stillness_desk.gd`, `tools/process_luz_rest_ritual.py`, manifest `rest_ritual`): `rest_mount` 8 frames, `rest_sit` 4-frame breathing loop (the desk script syncs `breath_cycle_started` to frame 0 and reads its length for `breath_period`), `rest_dismount` 8 frames. Backpack prop appears from mount frame index 3 (`BACKPACK_DROP_FRAME`) and disappears from dismount frame index 4 (`BACKPACK_PICKUP_FRAME`). Seat surface is 150 output px above the feet row (413); per-frame `lift_px` and `dx_px` are authored in the processor.

New art keeps exactly the same frame counts, the same beats on the same indices (backpack off at mount frame 4 (index 3), backpack on again at dismount frame 5 (index 4)) and the same lifts, so the state machine and backpack prop work unchanged. Differences: long ruler (sword grip while standing) and the new scale (sole y=472, standing height 360 px).

Ruler while sitting: laid flat and horizontal across both thighs, held near its middle by both hands, ends sticking out evenly past the knees. It stays visible, matches the old composition (ruler across the knees), does not collide with the desk (the desk is below the seat line) and at 215 texels (about 1.4x the seat width) reads as long without sweeping. Sit frames keep its position identical in every frame.

Raw geometry: row-major 3x3 cells of 512x512; seat line at y=307 of each row (165 raw px above the sole line y=472, = 150 output px / 0.92 scale) so the processor can keep `lift` 150.

| Sheet | Frames | Notes |
|---|---|---|
| `luz_rest_mount_v2_raw.png` | 8 (slots 1-8) | backpack leaves her in frame 3, absent from frame 4 on; sits in frame 8 |
| `luz_rest_sit_v2_raw.png` | 6 (slots 1-6) | loop; the processor may pick 4 (frames 1,2,3,5) to keep the 4-frame loop and `breath_period`, or all 6 with the catalog changing the sit length (the desk reads it) |
| `luz_rest_dismount_v2_raw.png` | 8 (slots 1-8) | backpack on the floor frames 5-6; picked up by frame 8 |

## 2. Global style block and prompts

Attachments for every job: image 1 `tools/art_sources/luz/refs/luz_identity_ref.png`, image 2 `tools/art_sources/luz/raw/luz_idle_raw_v3.png`; rest jobs also image 3 `assets/player/luz/luz_rest_sheet.png` (choreography only).

```
GLOBAL STYLE BLOCK
- Same character and same rendering as image 1 (luz_identity_ref.png) and image 2 (luz_idle_raw_v3.png): blonde messy ponytail, blue eyes, oversized dark navy school jacket over white shirt and thin dark blue tie, loose navy pants, gray/white sneakers, dark navy backpack (only where stated). Same illustrated pixel-styled look, density, dark outline weight, cel shading and palette. Do not redraw her in true pixel art, do not change proportions, no rim light or edge glow.
- Ruler (her sword): the long light-brown wooden ruler with dark tick marks, as long as in image 2 (about 65% of her standing height), identical length and width in every frame, held like a sword by its end (the hand grips the last ~15%). Never a bat, never a real sword. Keep its full length visible.
- Head and body scale identical in every frame and the same as image 2 (standing body height 360 px, top of hair to sole).
- Background ONE flat pure magenta #FF00FF everywhere outside the character: no gradient, no glow, no shadow, no halo, no vignette. No ground, no desk, no dust, no particles, no light effects, no motion lines, no text, no numbers, no grid lines.
- Right-facing side view. Output ONE 1536x1536 PNG, 3 columns x 3 rows of invisible 512x512 cells, row-major, slot 1 top-left, unused slots stay magenta. Nothing crosses a cell edge, 16 px padding. Save to the path given below (tools/art_sources/luz/raw/, gitignored), reply with the path and size, edit nothing else.
```

### heal -> `luz_heal_raw.png`

```
Attachments: 1 luz_identity_ref.png, 2 luz_idle_raw_v3.png.

Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Nine frames (slots 1-9) of Luz's HEAL / FOCUS (Hollow Knight style: she stands still, concentrates and mends herself). Feet on the ground, lowest sole on y=472 of its row (472, 984, 1496), body centre x=210. NO glow or particles are drawn (added later in code). Core pose: she plants the point of the long ruler on the ground in front of her, ruler upright (tilted at most 8 degrees toward her), both hands stacked on the grip at the top, like a knight leaning on a sword, head bowed, eyes closed, feet together-ish. The ruler tip touches the ground at x about 290 on y=472. Frames: 1 START A: from the idle stance she steps feet together and brings the ruler in front of her, tilted 35 degrees, one hand still on the grip, free hand rising; 2 START B: ruler nearly upright, tip about to touch the ground, both hands reaching the grip, head starting to bow; 3 START C: ruler planted upright, both hands on the grip, head bowed, eyes closing; 4 LOOP A: full focus pose, eyes closed, chest low (breath out), hair and jacket hem settled; 5 LOOP B: chest and shoulders rise 3 px, head lifts 2 px, ponytail and a few hair strands lift slightly; 6 LOOP C: peak, shoulders 4 px up, hair strands floating a little higher, hands pressing on the grip; 7 LOOP D: settling back, shoulders 2 px up, hair falling (frame 7 must flow into frame 4); 8 END A: head lifts, eyes open (blue), a small relieved exhale, ruler still planted, one hand lifting off; 9 END B: she lifts the ruler off the ground and back to the idle sword grip, stance close to image 2. Loop frames 4-7 differ only by subtle breathing and hair, same hands, same ruler, same feet.
```

### mount -> `luz_rest_mount_v2_raw.png`

```
Attachments: 1 luz_identity_ref.png, 2 luz_idle_raw_v3.png, 3 assets/player/luz/luz_rest_sheet.png (choreography reference only: reproduce the mount sequence of its first 8 frames, but with the LONG ruler of image 2 and the scale of image 2; ignore its transparent background and old short ruler).

Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Eight frames (slots 1-8, the 9th slot stays magenta) of Luz MOUNTING a waist-high desk that is NOT drawn. The desk is to her RIGHT; its top is an invisible horizontal line at y=307 of each row (165 px above the floor baseline y=472; rows are 0-511, 512-1023, 1024-1535 so the line is at y=307, 819, 1331). Body centre x=210, floor baseline y=472 of each row while grounded. Frames: 1 standing relaxed beside the desk, backpack on, long ruler held low in her right hand in the sword grip, tip pointing back-down; 2 shrugging the backpack straps off her shoulders, leaning slightly forward, ruler still held; 3 LAST frame with the backpack: she lowers the whole backpack to the floor behind her to the left, backpack bottom touching y=472 at x about 60-110, drawn as a distinct object, ruler held in the other hand; 4 standing upright, NO BACKPACK anywhere in this frame or any later frame, ruler in hand, knees bending to spring; 5 hopping up, feet barely off the floor, hands reaching forward to the invisible desk edge, deeply bent knees, ruler held against the edge in her right hand, fully visible; 6 knee up on the invisible surface, hips near the surface line, torso upright, ruler held low; 7 sitting down onto the invisible surface, legs folding into cross-legged, ruler being laid across her knees; 8 settled cross-legged seat exactly on the line (lowest point of the legs on y=307 of its row), the long ruler laid flat and horizontal across both thighs, held by both hands near its middle, both ends sticking out evenly past her knees, eyes closed, calm, no backpack. Do not draw the surface, desk or backpack after frame 3. Same character scale in all frames, long ruler of identical length in all frames.
```

### sit -> `luz_rest_sit_v2_raw.png`

```
Attachments: 1 luz_identity_ref.png, 2 luz_idle_raw_v3.png, 3 assets/player/luz/luz_rest_sheet.png (reference of the seated pose in its frames 8-11: copy the pose and framing, but with the LONG ruler of image 2 and the scale of image 2).

Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Six frames (slots 1-6) forming a seamless looping BREATHING cycle of Luz meditating cross-legged on an invisible seat surface at y=307 of each row (y=307, 819, 1331; NOT drawn): the lowest point of the crossed legs sits exactly on that line in every frame, body centre x=210, scale of image 2 (a standing Luz would be 360 px tall). Eyes closed, calm face, NO BACKPACK. The long ruler lies flat and horizontal across both thighs, held loosely by both hands near its middle, both ends sticking out evenly past her knees, identical position and length in all frames. Subtle breathing only: frames 1-3 chest and shoulders rise about 3 px, head lifts 2 px, ponytail and hair strands sway slightly back; frames 4-6 return gently so that frame 6 flows into frame 1. Legs, ruler, hands stay essentially identical.
```

### dismount -> `luz_rest_dismount_v2_raw.png`

```
Attachments: 1 luz_identity_ref.png, 2 luz_idle_raw_v3.png, 3 assets/player/luz/luz_rest_sheet.png (choreography reference only: reproduce the dismount sequence of its last 8 frames, but with the LONG ruler of image 2 and the scale of image 2; ignore its transparent background and old short ruler).

Use case: stylized-concept. Asset type: production 2D game animation sprite sheet. Eight frames (slots 1-8, the 9th slot stays magenta) of Luz DISMOUNTING a waist-high desk that is NOT drawn. The desk is to her RIGHT, its top is an invisible line at y=307 of each row (rows 0-511, 512-1023, 1024-1535: y=307, 819, 1331); floor baseline y=472 of each row; body centre x=210. Frames: 1 seated cross-legged exactly on the invisible line, eyes closed, the long ruler laid flat across her thighs held by both hands, NO BACKPACK; 2 eyes open, uncrossing her legs, ruler gripped in her right hand, legs swinging forward/down over the edge; 3 pushing off with her hands and dropping, mid-air, ruler in hand; 4 landing on the floor in a compact crouch, feet on y=472, ruler in hand, no backpack; 5 crouching to pick up her dark navy backpack lying on the floor to her left, bottom on y=472 at x about 60-110, ruler in the other hand; 6 lifting the backpack by its strap, swinging it up toward her shoulder; 7 sliding the second strap on, backpack on her back, straightening; 8 standing ready, backpack on, long ruler in the sword grip, tip pointing back-down, close to the idle stance of image 2. Same character scale in all frames; backpack absent in frames 1-4 (not drawn in the air or the crouch), feet on y=472 for frames 4-8.
```

## 3. Phase 2 integration notes

- New processor (copy of `process_luz_rest_ritual.py` for the 3x3/512 raws, then `tools/luz_ruler_length.py` to 215 texels, `hair_match`); new `luz_heal_sheet.png` + manifest clips `heal_start`, `heal_loop`, `heal_end` and catalog timings; rest sheet rebuilt with the same lifts and clip names.
- `player.gd`: FOCUS state plays `heal_start` then `heal_loop`, re-enters the loop on chain, plays `heal_end` only on a completed non-chained heal; replace the Polygon2D glow with the VFX in 1.1.
- Desk: no change if counts and beat indices stay (mount 8, sit 4, dismount 8); if sit gets 6 frames only `breath_period` changes automatically.

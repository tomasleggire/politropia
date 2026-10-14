# Artemis - minimal demo set (run)

Contract: `docs/bosses/ARTEMIS_ANIMATIONS.md`. Approved design: `concept/artemis_concept_v2.png`. Rule 0: same style as Luz.

Six Codex runs (one per raw sheet, run in parallel, concept v2 and `luz_identity_ref.png` as `-i`), raw sheets in `../raw/`. The raw cells are regular grids but Codex ignores exact geometry, so `tools/process_artemis_sheets.py` keys the magenta, splits frames by connected components per grid cell, applies ONE scale, aligns the lowest sole on the feet row and writes `assets/enemies/artemis/`.

The contract defines no `hurt` clip (the white flash is code-driven); for the demo "hurt" is `interrupt_flinch` + `stagger_in`/`stagger_loop`, "death" is `defeat`. Clips not drawn yet fall back through `ArtemisAnimationCatalog.FALLBACKS`.

| Raw sheet | Grid | Clips (raw cell indices) |
|---|---|---|
| `artemis_loco_raw.png` | 4x3 | `idle` 0-5, `walk_fwd` 6-11 (`walk_back` = reversed `walk_fwd`) |
| `artemis_shot_raw.png` | 4x3 | `shot_draw` 0-4, `shot_hold` 5, `shot_release` 6-7, `shot_recover` 8-11 |
| `artemis_move_raw.png` | 4x3 | `backstep` 0-4, `interrupt_flinch` 5-9, `dodge` 10-11 |
| `artemis_down_raw.png` | 4x2 | `stagger_loop` 0-5, `stagger_in` 6-7 |
| `artemis_vault_raw.png` | 4x2 | `vault_crouch` 0-1, `vault_air` 2-5, `vault_land` 6-7 |
| `artemis_defeat_raw.png` | 4x3 | `defeat` 0-11 (last frames = corpse) |

Applied adjustments to the concept (user approved): heavier outline like Luz, simplified boots and bracers, cape desaturated toward `#24558A` / `#4C79A8`.

## Invocation

```
codex exec -s workspace-write --skip-git-repo-check \
  -i tools/art_sources/artemis/concept/artemis_concept_v2.png \
  -i tools/art_sources/luz/refs/luz_identity_ref.png \
  -- "<common block + sheet block>" < /dev/null > <log> 2>&1 &
```

Generated PNGs land in `~/.codex/generated_images/<session>/`; copy them to `tools/art_sources/artemis/raw/artemis_<sheet>_raw.png`, then run `python tools/process_artemis_sheets.py`.

## Common block (start of every prompt)

> Generate an image with your built-in image generation tool from the following prompt. Do not modify any file in the repository. Prompt:
> 
> Animation sprite sheet of ARTEMIS, the huntress boss of a 2D side-scrolling metroidvania. The FIRST attached image is the approved character design of Artemis (use it as the exact character: same face, hair, costume, bow, proportions). The SECOND attached image is the player character Luz, only for rendering style: illustrated pixel-styled look, thick uniform dark outline #1A1410 (as heavy as Luz's; a bit heavier than the concept sheet), cel shading with 2-3 value steps per material, big flat colour shapes, stocky ~4-head game-sprite proportions.
> Adjustments to the approved design: SIMPLIFIED boots and bracers (large plain shapes, NO fine lacing or small straps that would turn to mush when the sprite is shrunk to 56 px tall); cape desaturated and a bit darker, steel blue (#24558A shadows, #4C79A8 lights), not saturated royal blue. Everything else identical to the concept: long dark ponytail, trailing white veil, pale silver-white short chiton with leggings, brown bracers and sandals/boots, warm wood recurve bow with silver crescent-moon tips, quiver on the back (on the left side of the sprite when she faces right), dagger at the belt, crescent circlet.
> Rules for EVERY frame: character facing RIGHT, side view, identical character, identical bow length and body scale in all frames (standing body about 390 px tall in a 384x512 cell). Flat opaque magenta #FF00FF background everywhere, no ground, no shadow, no text, no labels, no grid lines, no frames, no glow, no rim light, no motion lines, no dust. Cells are equal and arranged in a strict regular grid; each pose stays fully inside its own cell with at least 16 px padding; in every grounded frame the lowest sole sits on the same row of its cell (the cell's bottom area), feet horizontally near the cell center. Poses must be clearly distinct from each other at silhouette level, chunky and readable at small size.

## Sheet block: Locomotion

> Sheet LOCOMOTION: grid of 4 columns x 3 rows (12 cells, reading order left-to-right, top-to-bottom), aspect 4:3.
> Cells 1-6 = IDLE loop (6 frames): poised, bow held lowered but ready in the right hand in front, weight on the back foot, subtle breathing, hair/veil/cape sway slightly between frames; very small differences between frames, last frame flows back into the first.
> Cells 7-12 = WALK loop (6 frames): calm stalking forward to the right, bow held ready in front, short stride, upright, contact poses at frames 1 and 4 (cells 7 and 10), hair/cape trailing behind; a seamless loop.

## Sheet block: Aimed shot

> Sheet AIMED SHOT: grid of 4 columns x 3 rows (12 cells, reading order left-to-right, top-to-bottom), aspect 4:3.
> Cells 1-5 = DRAW: from ready stance, feet planted wide and side-on, nocking the arrow and pulling the string back; frame 5 = full draw, string at the cheek. One long horizontal line of back arm, arrow and bow.
> Cell 6 = FULL DRAW HOLD: exactly the full-draw pose, absolutely still, arrow tip and bow hand on the same horizontal.
> Cell 7 = RELEASE: the string has snapped forward, the arrow is GONE (not drawn), the draw arm recoils back.
> Cell 8 = FOLLOW-THROUGH: arm sweeping back, bow vibrating, cape surging.
> Cells 9-12 = RECOVER: lowering the bow, exhaling, slightly off balance, torso open and visibly vulnerable, ending in the relaxed idle stance with bow lowered.
> The arrow must be drawn only in cells 1-6 (in cells 1-4 it appears as soon as it is nocked).

## Sheet block: Moves

> Sheet MOVES: grid of 4 columns x 3 rows (12 cells, reading order left-to-right, top-to-bottom), aspect 4:3. Unlike other sheets, airborne poses are OFF the ground (that is intended), grounded frames share the sole row.
> Cells 1-5 = BACKSTEP: quick light hop BACKWARDS (she moves to the left while still FACING RIGHT): 1 crouch take-off, 2 leaving ground, 3 apex with legs gathered and torso leaning back, bow forward, 4 descending, 5 landing absorbed.
> Cells 6-10 = FLINCH (an attack of hers was cancelled by a hit): 6 the hit lands, shoulders jerk and the bow snaps off the string, eyes narrowed; 7-8 recoil leaning back, bow arm flung out; 9-10 recovering to a guarded stance. Lighter than a collapse.
> Cells 11-12 = DODGE: a sharp low sideways twist-sidestep away (2 frames: lowest point of the twist, then landing in a guarded stance).

## Sheet block: Stagger

> Sheet STAGGER: grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2.
> Cells 1-6 = STAGGER loop (6 frames): dazed and vulnerable, knocked off balance, bow arm hanging low (bow tip near the ground), head bowed, knees slightly bent, swaying left-right-left between frames, hair and veil drooping; seamless loop (frame 6 flows into frame 1).
> Cells 7-8 = STAGGER ENTRY (2 frames): recoiling back from a heavy hit, head thrown back, arms flung out; frame 8 settles into the dazed pose.

## Sheet block: Vault

> Sheet VAULT: grid of 4 columns x 2 rows (8 cells, reading order left-to-right, top-to-bottom), aspect 3:2.
> Cells 1-2 = CROUCH: tight low crouch gathering to jump, body compressed, bow tucked against the body (NO weapon raised or aimed), nothing in front.
> Cells 3-6 = AIR: a high arc leaping forward OVER an opponent: 3 take-off stretching upward, 4 apex tucked in a ball with trailing hair and cape, bow clear of the body, 5-6 descending with legs reaching down. These frames are airborne, off the ground.
> Cells 7-8 = LAND: soft landing absorbing impact (knees bent, cape settling), then rising to a ready stance. Feet on the ground row.

## Sheet block: Defeat

> Sheet DEFEAT: grid of 4 columns x 3 rows (12 cells, reading order left-to-right, top-to-bottom), aspect 4:3.
> A final sequence of Artemis being defeated: 1 struck by a mortal blow, head back; 2-3 staggering, bow slipping from her hand; 4-5 sinking to her knees, the bow dropping to the ground; 6-8 collapsing forward onto her hands, then onto her side; 9-12 lying fully prone on the ground, motionless, bow lying beside her, cape and veil settling over her; frames 10-12 are practically identical (the permanent corpse lying flat on the floor line, clearly defeated, cannot be mistaken for a pose she could get up from). Lying frames rest on the ground row of the cell.

## Not drawn yet (full set)

Fan, rain (vertical draw), dagger windup/slash/flip, dive (leap, fall, stuck), stag cast/summon, feint, phase transition, phase 2 skin (silver accents), spectral stag, arrow and VFX art. Each falls back to a drawn clip until its sheet exists.

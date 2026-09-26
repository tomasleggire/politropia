# Feature: Luz Blasphemous-grade animation

## Objective
Bring Luz's animation set to near-final quality using Blasphemous (The Penitent One) as the reference: a fluid three-hit horizontal ruler combo with crescent slash smears, readable crouch/up/air attacks, longer attack reach, and smoother locomotion/mobility clips with more frames.

## Problem / Why
- Current combat clips are 4-frame AI-generated thrusts, not cuts; the "cut" only comes from a thin code-drawn white line the user rejected ("queda muy mal").
- The shared `safe_cuts` grid slices extended ruler tips into neighboring cells (ground combat frames 5→6, 6→7, 9→10, 10→11, 13→14, 14→15; air combat 11→15), which shows as a floating ruler fragment behind Luz and truncates the striking ruler.
- Attack hit 1 activates its hitbox while the sprite still shows the overhead windup frame.
- Attack reach is short and the up attack does not reach as far as the lateral attack.
- Locomotion/mobility clips use 2–4 frames, so movement reads as choppy compared to the reference.

## Reference
- User-supplied Blasphemous screenshot: wide pale mint/white crescent smear sweeping horizontally in front of the character, thick at the leading edge and tapering to a thin tail, drawn over a clearly swung weapon.
- Luz's weapon stays the flat wooden ruler with markings (never a bat or sword); the smear is the "cut".

## Scope
- New combat art with more frames per clip: ground combo hits 1–3 (distinct horizontal cuts, loops back to hit 1), crouch attack (single, left/right via flip), up attack (single, vertical, same reach as lateral), air lateral attack (single); air up reuses the up attack.
- Replace the code-drawn line VFX with pre-rendered pixel-art crescent smear frames, one variant per attack kind/combo hit.
- Deterministic sprite-sheet processing tool that segments raw generated sheets by connected components, aligns feet to a baseline, and repacks frames into uniform, gutter-safe cells — eliminating hand-tuned `safe_cuts`/`frame_overrides`/`foot_offsets` bleed.
- Catalog support for per-sheet grids and variable frame counts.
- Attack reach (hitbox size/offset tunables) enlarged to match the new ruler + smear reach; up reach matches lateral reach.
- Locomotion and mobility clips re-animated with more frames (idle, run, jump/fall, land, crouch, dash, wall, ledge, plunge) after combat is accepted.
- Verification headlessly and on iPhone after each visible milestone.

## Out of Scope
- New mechanics (double jump, new attack types), damage/balance, enemy behavior, level/UI.
- Changing attack windows/combo buffering unless a clip cannot be synchronized otherwise (record the reason if it happens).

## Constraints
- Right-facing source art, `flip_h` for left; feet-origin anchoring preserved.
- Gameplay authority stays in `player.gd`; animations and VFX never trigger hits.
- Art generation uses the Codex CLI image generation (same tool family that produced the current sheets); raw outputs live under `tools/art_sources/luz/` (gdignored), processed sheets under `assets/player/luz/`.
- Do not hand-edit generated `.uid` files.
- Commits: Conventional Commits, neutral Spanish body, no AI attribution; `GGA_PROVIDER=claude` for the pre-commit hook, never `--no-verify`.

## TDD
- Mode: off (inherited from `odd/tasks/luz-character-animation.md`; no test framework configured).
- Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 300 2>&1 | rg -i "error|warning"` must print nothing.
- Visual checks: contact sheets and onion-skin renders from the processing tool, inspected per clip; iPhone deploy + playtest by the user.

## Delivery
- Strategy: `ask-on-risk`. Forecast: ~450–700 authored lines (processing tool, catalog changes, VFX rewrite, hitbox tunables, docs); generated PNGs excluded. Ask once for chain strategy before the commit that crosses ~400 lines.
- Base: `feat/luz-attack-polish@11a7592`.

## Tasks
- [ ] T1 Spike: generate one ground-combo hit with Codex image generation and process it; confirm identity fidelity, frame consistency, and horizontal-cut readability before committing to the full pipeline. Route: inline orchestration of a Codex CLI generation + local processing. Checks: visual inspection of raw + processed contact sheet. Status: BLOCKED — `codex exec` returned "Your workspace is out of credits" (2026-09-26); Gemini CLI has no image-generation extension. Prompt kept at `tools/art_sources/luz/prompts/ground_attack_1.md`; refs (incl. the Blasphemous screenshot) are gitignored under `tools/art_sources/luz/refs/`. T2/T3 proceed independently; T4–T7 new art waits for credits.
- [x] T2 Sprite processing tool (`tools/process_luz_sheet.py`): connected-component segmentation, detached-fragment ownership, feet baseline alignment, horizontal anchor, uniform gutter-safe repack, contact-sheet + onion-skin output; catalog/manifest support for per-sheet grids. Route: delegated direct writer (2+ non-trivial files; trigger: manifest + catalog + tool script all non-trivial). Checks: reprocessed all 4 sheets with zero segmentation failures, no bleed fragments (visually confirmed in contact sheets/onion skins); headless import + runtime clean. Commit: (recorded below after commit).
- [ ] T3 Crescent smear VFX (also: hitbox reach enlarged, up reach == lateral, and per-clip `contact_frame` timing so the striking frame shows at the active window): deterministic pixel-art smear frame generator + `SlashVfx` rewrite to play smear frames per attack kind/hit, removing the line drawing. Route: delegated direct writer. Checks: rendered smear contact sheet; headless runner clean.
- [ ] T4 Ground combo art (hits 1–3) generated, processed, integrated, synchronized with active windows; hitbox reach enlarged. Route: delegated direct. Checks: onion-skin per hit; frame-at-active-window check; headless runner; iPhone deploy.
- [ ] T5 Crouch, up, and air attack art + smear sync + reach parity (up == lateral). Route: delegated direct. Checks: as T4.
- [ ] T6 Locomotion re-animation (idle, run, jump, fall, land, crouch). Route: delegated direct. Checks: onion-skin, feet stability, iPhone.
- [ ] T7 Mobility + plunge re-animation (dash, wall cling/jump, ledge hang/climb, plunge, plunge land). Route: delegated direct. Checks: as T6.
- [ ] T8 Final verification pass on iPhone; record every pending/failed check honestly.

## Progress
- 2026-09-26: Analysis of `feat/luz-attack-polish@201866e` done; current state deployed to iPhone. Pending Codex docs/uid committed as `11a7592`. Feature document created; next is the T1 generation spike.
- 2026-09-26: T2 done. Wrote `tools/process_luz_sheet.py` (pure Python 3 + Pillow, no numpy/scipy available in this environment): 8-connected flood fill over the full sheet's alpha channel (threshold 8), per-cell "body" = component with most pixels inside that cell's old safe_cuts seed rect, every other component (fragment) assigned to the nearest body's cell via min squared distance between border-adjacent pixels (components within `BORDER_MARGIN`=60px of any seed cut); a component that is the body of two cells raises `SegmentationError` instead of merging. All 4 sheets (`luz_ground_combat_sheet.png` 170 components, `luz_air_combat_sheet.png` 80, `luz_locomotion_sheet.png` 127, `luz_mobility_sheet.png` 240) processed with zero segmentation failures. Repacked sheets written to `assets/player/luz/*.png` at 2048x2048 (4x4 512x512 cells); raw generated sheets moved to `tools/art_sources/luz/source/` via `git mv`, their old `.import` files removed (Godot regenerated new ones on `--import`). Contact sheets + onion skins written to `tools/art_sources/luz/preview/` (gitignored) and visually inspected: all 6 previously-documented bleed pairs (ground combat 5-6/6-7/9-10/10-11/13-14/14-15, air combat 11/15) show zero floating fragments and full, untruncated ruler tips in both the contact sheets and per-clip onion skins; feet sit exactly on the marked row-413 line in every frame of every clip. Placement fidelity verified analytically (the new `leading_x = 100 + (bbox_x0 - col*313)` / `leading_y = 413 - (bbox_h - 1)` formulas are algebraically identical to the old region-position/foot_offset formulas for frames without bleed or overrides) and spot-checked in Python against the old per-frame math for locomotion frames 0/1/4/7 (unaffected by bleed): alpha bounding boxes match within 1px. Frames 12/15 (crouch/land) differ by 4-6px from the old reconstruction because the old raw crop *included* undocumented minor bleed fringe that the new segmentation correctly excludes -- expected, not a defect (feet still exactly on row 413 in the new output). Manifest replaced per-sheet `safe_cuts`/`frame_overrides`/`foot_offsets` with a uniform `"grid": {"columns":4,"rows":4,"cell_width":512,"cell_height":512}` per sheet; `luz_animation_catalog.gd` simplified to plain grid-region `AtlasTexture`s (no margin/offset math); `AnimatedSprite2D` offset/scale in player.gd/player.tscn unchanged (canvas stays 512x512 by construction). Checks: `--import` clean, `--quit-after 300` clean, `git diff --check` clean. Route: delegated direct writer, trigger = 2+ non-trivial files (manifest, catalog, new tool). Commit: `fix: repack Luz sheets to remove ruler bleed` (hash recorded after commit, see below).

## Next Step
T3 (crescent smear VFX, reach, contact-frame sync) via the same delegated writer.

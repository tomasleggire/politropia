# Artemis polish

## Objective
Fix the two most visible art issues in the Artemis fight without new art: the spectral stag's size and gallop, and the dive shaft covering Artemis.

## Problem
- The SpectralStag sprite reads wider than its 60 px hitbox, so hits and misses look unfair.
- The stag gallop has no vertical bob, because the sheet frames were aligned by the lowest hoof.
- The `dive_shaft` VFX (`artemis_boss.gd` ~1812) draws over Artemis' sprite during the moon dive.

## Why
Pending items from `odd/tasks/demo-polish.md` (D19 known nits), chosen by the user on 2026-10-24 as the next Artemis work.

## Scope
- Scale the stag visual to match its hitbox (art style stays; the painterly look needs new art and is out of scope).
- Add a gallop bob in code (no sheet reprocessing).
- Make the dive shaft read behind/around Artemis instead of over her (draw order, offset or size).
- Scope extended on 2026-10-24 (user: "genera el arte primero y luego pruebo todo junto"): the remaining art (intro, `stag_vanish`, arrow impact, telegraph/floor markers, `walk_back`) with the minimal code hooks each needs. Boss timings stay unchanged.
- Pipeline risk: `tools/process_artemis_sheets.py` rebuilds the whole manifest; its stag constants (0.2) must match the scene/manifest (0.245, T1) before rerunning.

## Constraints
- Godot 4.7 GDScript conventions from AGENTS.md. Hitboxes and timings stay unchanged.

## Delivery
- Branch: `feat/artemis-polish` from main `663b188`.
- Strategy: ask-on-risk. Forecast: ~80 authored changed lines.
- TDD: off (source: project convention). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.

## Tasks
- [x] T1 — Spectral stag: visual scaled to its 60 px hitbox, gallop bob. Route: delegated direct (preparation trigger: stag script + scene + manifest + boss spawn code).
  - The premise was inverted: measured stag_run body ~245 px wide × 0.2 = ~49 px, narrower than the 60 px hitbox. Scaled up to 0.245 (~60 px wide, ~42 px tall) in `artemis.tscn` (the real source) and the manifest `sprite_scale` (unused by code, kept consistent). Feet stay put (`offset` is in texture pixels).
  - Gallop bob: `bob_amplitude` export (3 px), `-abs(sin(TAU * phase))` over `stag_run`, sprite only. The two-arcs-per-loop cadence needs a device check.
  - Evidence: boss suite incomplete 452/702 with exactly the 13 known failures; case_spectral_stag 8/8, case_interrupt_stag_cast 5/5. zone_1 boot clean.
- [x] T2 — Dive shaft no longer covers Artemis. Route: delegated direct (preparation trigger: boss VFX code + scene).
  - `DiveHitbox/ImpactArt` z_index 2 → -1, behind `Visual/AnimatedSprite2D` and above the arena background (-10). Alpha and width unchanged. Risk to check on device: in `zone_artemis` a tilemap drawn after Artemis could hide the floor part of the shaft.
  - Evidence: boss suite same 13 known failures; case_moon_dive 6/6.
- [ ] T3 — iPhone device check of T1-T9 with the user (user asked to test everything together after the art, 2026-10-24).
- [x] T4 — Batch 3 art generation with Codex: 5 raw sheets (intro, walk back, stag vanish, arrow impact, telegraph glyphs). Prompts in `tools/art_sources/artemis/prompts/batch_3.md`. Route: inline (parent runs Codex).
  - All 5 runs exited 0 and were reviewed visually by the parent. Raw sheets are 1536x1024, 4x2 cells, magenta background.
  - Intro deviates from the prompt: cells 5-6 are a warning aim (arrow drawn, then released pose) instead of a bow spin; cell 4 jumps from kneeling to standing. Accepted: it still reads as a boss reveal and cell 8 is the idle pose.
  - Stag vanish breaks into shards and crescents; some small shards will fall under the processor's 40 px component threshold (acceptable).
- [x] T5 — `walk_back` clip: process the sheet, add it to the locomotion clips (replaces the reversed `walk_fwd`). Route: delegated direct. Commit `0d023eb` (also carries the processor changes and the manifest regenerated for all five sheets; existing sheet PNGs byte-identical; processor stag `sprite_scale` now 0.245 with `STAG_RENDER_SCALE` 0.2 for pixels).
- [x] T6 — `intro` clip plus code hook: a one-shot INTRO played on arena entry, inside `engage_delay`, reset on fight reset. Route: delegated direct. Commit `e9af143`: `ArtemisBoss.play_intro(duration)`, called from `BossArena._start_fight` behind `has_method`; skipped for a corpse; cleared by `engage()`, `_reset_ai` and leaving IDLE. `case_intro_clip` 5/5.
- [x] T7 — `stag_vanish`: deferred hide in `SpectralStag.deactivate()` (hitbox off at once, visual plays the clip), update `tests/artemis_boss_test.gd:1015`. Route: delegated direct. Commit `75a9b93`: `deactivate(instant := false)`, `VANISH_TIME` 0.4 s, resets pass `true`; vanish frames scaled 0.8 to match `stag_run`. `case_spectral_stag` 9/9.
- [x] T8 — Arrow impact VFX: pooled impact sprite spawned when an arrow hits Luz or a surface (not on lifetime expiry or reset). Route: delegated direct. Commit `180b973`: `EnemyProjectile.impacted(point, direction)` signal, 8-sprite pool in ArtemisBoss. No moon arrows are fired anywhere, so impacts are amber; `arrow_impact_moon` is built but unused. `case_arrow_impact` 5/5.
- [x] T9 — Telegraph glyph art: floor markers (rain, dive), stag wall marker and dotted aim line use the white glyphs tinted by the existing colours; `BossTelegraph` API unchanged, edges brighter than fill, accelerating pulse kept. Route: delegated direct. Commit `1229958`: `show_floor_marker(..., glyph := &"", hot := false)` (optional params), hot at 70% progress; strips capped at 2x rect height (dive ~16 px); aim lines dotted, width 6 instead of 3. `case_telegraph_glyphs` 6/6.
  - Evidence T5-T9 (parent re-ran the boss suite): incomplete 469/719 (base 452/702; +17 new checks), the same 13 known failing cases; zone_1 and zone_artemis boot clean.
  - Device checks: walk back and intro scale (matched by eye), first vanish frame slightly taller, heavier dotted aim line, slightly stretched rain strips.
- RDD: assess `663b188..1229958` = high (`process_boundary`), review due. Preflight STATUS asks for an intended-untracked selection JSON whose exact schema is undocumented; blocked until `tools/art_sources/checkpoint/concept/` is resolved (ignore or commit) so no untracked file remains.

## Acceptance criteria
- The stag's drawn body width roughly matches its hitbox; it bobs while galloping.
- During the dive, Artemis stays readable over or beside the shaft.
- No new test failures vs base (see Engram `bug/test-debt-main`).

## Checks
- Boss suite through `tests/stillness_desk_ritual_test.gd` (base: incomplete 452/702, 13 known failing cases).
- Broken on main `663b188` before this feature (not caused here):
  - `tests/artemis_room_test.gd` does not parse: it uses `DoorID.ID.ZONE_1_TO_ARTEMIS`/`ARTEMIS_TO_ZONE_1`, renamed to `ZONE_5_*` in `083d5c3`.
  - `tests/door_links_test.gd` FAIL 4/349 on clean HEAD (`zone_teacher.tscn` key missing, `zone_1.tscn:10506` thorns texture `5_ns67n` parse error in test context).

## Next step
T1.

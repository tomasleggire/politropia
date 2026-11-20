# Hydra art (La Hidra)

Locator: `odd/tasks/hydra-art.md`. Engram mirror: `odd/hydra-art/tasks` (project `politropia`), pending: `mem_save` is refused in auto mode because a hook rewrites the call.
Branch: `feat/new-bosses` (single branch by user preference; no stacked art branch).

## Objective

Give La Hidra (`HydraBoss`) final art in the same style as Luz, Artemis, El Profesor and El Topo, with the same workflow (Codex concept, Codex raw sheets, `tools/boss_sheet_pipeline.py`, `BossAnimationCatalog`, `BossSpriteFx`). Gameplay (timings, hitboxes, hurtboxes, head positions, hazards, platform rules) does not change.

## Problem

The Hydra is drawn with placeholder polygons: one body polygon, three heads drawn in `HydraHead._draw` (head and jaw polygons, a straight 16 px line as the neck, a stump line when severed), venom drawn in `HydraVenom` and five grey platform slabs. It is the only one of the three new bosses with no art plan.

## Why

Requested by the user on 2026-11-19: resume the Codex art of the three new bosses and advance as far as possible.

## Decisions

- Design: the Lernaean Hydra as a massive coiled serpent, dark teal scales with a pale ochre belly. The three heads keep their gameplay colours so target priority still reads: the biter (low) is crimson with a heavy jaw and big fangs, the sweeper (mid) is violet with a long flat blade-like snout and crest, the spitter (high) is acid green with a cobra hood and venom sacs. Prompt: `tools/art_sources/hydra/prompts/character_concept.md`.
- Multi-part boss: one body sprite under `Visual`, one sprite per head inside each `HydraHead`, and a procedural neck (a textured `Line2D` with a seamless neck tile from the fixed shoulder to the moving head). Heads never rotate. The art is drawn facing RIGHT; `Visual` is mirrored already and the head sprites are flipped in code.
- On-screen sizes stay those of the placeholders: body about 112 x 152 px, each head about 56 x 42 px (crests and fangs may overhang a little), platforms 160 px wide. Shoulder points are visual only and may move to match the neck roots of the art; head rest positions do not move.
- With art on, the defeat clip of the body shows the severed necks itself and the `Heads` node is hidden from the start of the defeat; without art everything behaves as today.
- Per-sheet scale reference: the content height of the first idle cell (body) and the content width of the first idle cell (each head). No colour block is needed because every cell holds one isolated object.
- Code-driven and unchanged: telegraph markers (aim line, sweep band, venom markers), hurt flash (moved to a per-head sprite shader), the stuck mark.

## Sheet plan (raw cells, reading order)

All raw sheets are 1536x1024.

| Sheet | Grid | Clips |
|---|---|---|
| `body` | 3x2 (512x512) | `idle` 0-3 (loop), `roar` 4-5 (phase change and intro) |
| `defeat` | 3x2 (512x512) | `defeat` 0-5 (4-5 = corpse) |
| `head_biter` | 4x2 (384x512) | `idle` 0-2 (loop), `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 (stuck) |
| `head_sweeper` | 4x2 | `idle` 0-2 (loop), `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `head_spitter` | 4x2 | `idle` 0-2 (loop), `telegraph` 3, `attack` 4-5, `roar` 6, `dazed` 7 |
| `props` | 4x2 | `neck` 0, `stump` 1, `venom_glob` 2, `venom_pool` 3-4 (loop), `venom_splash` 5, `platform` 6, `platform_alt` 7 |

## Constraints

- AGENTS.md conventions; no hand-edited `.uid` files; node names referenced by scripts and tests stay stable (the platform collision child stays `CollisionShape2D`).
- No asset on disk means the placeholders stay exactly as today (same fallback rule as El Profesor and El Topo).
- Artemis, Profesor and Topo assets and behaviour stay unchanged.

## Delivery

- Strategy: ask-on-risk. Forecast: about 1500 authored lines (contract, processing script, integration, tests) plus binary art, above the 400-line budget. Chain strategy: pending, asked before any pull request together with the rest of `feat/new-bosses`.
- TDD: off (source: project convention, `odd/tasks/artemis-polish.md:27`). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd` (one Godot process at a time).
- Receipt-driven development: on by default; consent `granted` by standing user instruction. Last reviewed boundary when this document was created: `6255adb`; after T2: `b35bfb4`.

## Tasks

- [x] T1 Concept in the game style (route: inline, two Codex runs by the parent). Commit `7d11749`: `tools/art_sources/hydra/concept/hydra_concept_v1.png` (chosen: thicker outline and bigger flat shapes, reads better at 56 px per head) and `hydra_concept_v1_alt.png`.
- [x] T2 Contract `docs/bosses/HYDRA_ANIMATIONS.md`, `tools/process_hydra_sheets.py`, integration with fallbacks (body sprite, head sprites, textured neck, stump, venom, platforms), tests (route: delegated writer in an isolated worktree; trigger: 2+ non-trivial files). Commit `400a669` (cherry-pick of the writer's `5bcf8f2`). Writer decisions: body cell 640 with feet row 608, head cell 256, both at scale 0.2896; head frames anchored on the top and back of the skull; neck tile 18 px thick, a textured `Line2D` behind the head that sags up to 12 px at rest and is flat in a sweep; platforms dressed by `HydraBoss._dress_platforms()` at `_ready` and on every rescan through the new `HydraTiers.platform_nodes()`; new `HydraArt` (extends `BoomboxEffectArt`); `Heads` is hidden only when the body has the `defeat` clip; the suite pins the old cases to a missing manifest so they keep running without art. No shared file was touched.
- [x] T3 Raw sheets (route: inline, six parallel Codex runs by the parent). Prompts in `tools/art_sources/hydra/prompts/sheets.md` (commit `7d11749`). Commit `dc89068`: the six sheets in `tools/art_sources/hydra/raw/`. The runs of 2026-11-19 failed with "Your workspace is out of credits"; the runs of 2026-11-20 all returned one usable 1536x1024 image on the first try, with the requested grid and poses, each checked by eye.
- [ ] T4 Process the sheets and tune the integration on the real art (route: delegated writer).
- [ ] T5 Visual check in the real game (route: inline): movie maker capture, video for the user.

## Acceptance criteria

- With the processed assets present, the Hydra shows the body, the three heads, textured necks, stumps, venom and platforms as sprites, each head plays the clip of its state, and no placeholder polygon is visible.
- With the assets absent, the fight looks and plays exactly as before.
- `tests/hydra_boss_test.gd` stays green (228 before this feature) with new art cases; `tests/boss_animation_catalog_test.gd`, `tests/boss_enemy_test.gd` and `tests/boss_test_hub_test.gd` stay green.

## Checks

- The suites above, plus `Godot --headless --path . --import` with no script or parse errors.
- Artemis, Profesor and Topo assets unchanged after re-running their processing scripts.

## Progress and evidence

- 2026-11-19: Codex has credits again. Hydra visual inventory mapped (read-only mapper). Feature document created with 5 tasks.
- 2026-11-19, T1: both concept runs produced an image (Codex sessions `01a1f459-84a6-79e0-87e5-3a128ff730f8`, chosen, and `01a1f459-84a6-76c0-bed2-5c89414dd5f7`, alternative). T2 writer launched in an isolated worktree (it does not need the art).
- 2026-11-19, T3: six sheet runs launched right after the eight Topo sheets; all six failed with "ERROR: Your workspace is out of credits. Ask your workspace owner to refill in order to continue." The Codex credits lasted for 2 Topo concepts, 8 Topo sheets and 2 Hydra concepts.

- 2026-11-19, T2 (writer run plus parent spot check on the integrated branch): `hydra_boss_test` `PASS 314/314` (228 before, 86 new art checks), `blind_beast_boss_test` `PASS 349/349`, `boss_animation_catalog_test` `PASS 41/41`, `boss_enemy_test` `PASS 178/178`, all exit 0; import with no script errors; `tools/process_hydra_sheets.py` with no raw sheets prints the skips and exits 0; smoke load of `scenes/levels/test/hydra_arena.tscn` exit 0. The writer also reported `boss_test_hub_test` `PASS 213/213`, `boombox_teacher_boss_test` `PASS 412/412` and an end-to-end run on synthetic sheets. Untested without the real art: the head anchor, the neck tile seam, the platform proportions, whether the 525 px body needs a slight upscale from the 512 px raw cell, and the rendered flash and glow.
- 2026-11-19, native review of `34cc8dd..b35bfb4` (assessed high: `process_boundary` on `tools/process_hydra_sheets.py`; 14 paths, 1553 lines): consent `granted` (standing user instruction), four lenses, approved, acknowledged (lineage `review-c016520fea489c4e`, authority burned). The reviewed boundary is `b35bfb4`. Non-blocking follow-ups to take in T4, when the script runs on real sheets: `load_frames` drops empty cells and the builders then index by raw cell number, correct only while every cell is used (`tools/process_hydra_sheets.py:94-95`, two lenses); sheets are saved one by one and the manifest only at the end, so an error mid-run leaves new textures beside an old manifest (`:283-291`, two lenses); no automated test for the script, and a reference cell emptied by `drop_specks` would divide by zero (`:100-103`); `NECK_PAD` is 2 but the docstrings and section 2.3 of the contract say one row (`:65`); `roar(duration, clip)` also carries the spitter's attack (`hydra_head.gd:226-228`); `_ready` dresses the platforms twice without a comment (`hydra_boss.gd:174`); a stale comment on `GLOB_ART_SIZE` (`hydra_venom.gd:33`); the moved-platform check cannot fail and some art checks read private members (`tests/hydra_boss_test.gd:1631`, `:1352`).

- 2026-11-20, T3: Codex has credits again (a text-only probe answered). Six sheet runs, Codex sessions `01a1f6e8-a343-7d90-9aaa-6eabe9607e5b` (body), `01a1f6e8-a344-7ad0-9c53-2149ec2c619e` (defeat), `01a1f6e8-a342-7ae1-829b-cd47c98bb6fe` (biter), `01a1f6e8-a36b-77a0-ab23-7232f512fbf7` (sweeper), `01a1f6e8-a36f-7303-a419-668dac445d2d` (spitter), `01a1f6e8-a371-7323-a382-af12158ee325` (props). First run of `tools/process_hydra_sheets.py --preview` on the real sheets exits 0 (body scale 1.2467, defeat 1.1191, heads 0.5755 to 0.5895). Seen in the previews, to fix in T4: the magenta key removes the violet of the sweeper crest (it comes out dark navy); the defeat sheet is a lighter, greyer green than the body sheet; the neck section and the stump have a dark outline on their flat ends.

## Next step

T4: process the sheets and tune the integration on the real art (delegated writer), then T5 (capture).

# Bosses polish (Profesor, Topo, Hidra)

Locator: `odd/tasks/bosses-polish.md`. Engram mirror: `odd/bosses-polish/tasks` (project `politropia`), pending while `mem_save` is refused in this session.
Branch: `feat/blind-beast-art` (the top of the stack: `feat/new-bosses` <- `feat/boombox-teacher-art` <- `feat/blind-beast-art`).

## Objective

While the Codex workspace is out of credits (El Topo's art is blocked), close the open, low-risk follow-ups recorded for the three new bosses, then leave everything on a single branch ready to push.

## Scope (from `odd/tasks/new-bosses.md`, `odd/tasks/boombox-teacher-art.md`, `odd/tasks/blind-beast-art.md`)

- El Topo: spike placeholder/art predicate drift (`blind_beast_boss.gd:1439-1440`, two review lenses); `_emerging` lifecycle on every exit path (`blind_beast_boss.gd:1650-1655`); Topo script error handling (`tools/process_blind_beast_sheets.py:131-133`, `:254-264`); the test at `tests/blind_beast_boss_test.gd:1366`; `BlindBeastHazardArt` extends the Profesor-named `BoomboxEffectArt` (rename the generic base so La Hidra can use it too); loop fps literals; the teacher `clip_contents` shim.
- El Profesor: the empty-phrase guard refills the phrase without clearing the finale flag; the 12-beat cap on wave recovery can open the overheat with waves in flight in a very wide arena; no case proves a dodged hazard hurts again on a second overlap (the briefcase's return after a dash through its outward pass); whether the outline shader samples into neighbouring atlas cells (`shaders/sprite_glow.gdshader:22-29`); small test readability items.
- La Hidra: the tier scan ignores platforms nested below `Platforms` and takes the first ancestor with a child of that name.
- Shared: `boss_enemy_test` prints an engine error from `CheckpointService.restore_pending_player` at teardown.
- Out of scope: the blind NPC quest link to El Topo (a product decision), the Hydra difficulty (user: "dejémoslo así"), El Topo's art (blocked on Codex credits).

## Delivery

- One branch at the end: `feat/new-bosses` fast-forwarded to the top of the stack (it is already on the remote, so the push is a fast-forward); the two intermediate local branches deleted once merged. Push only with the user's go-ahead.
- TDD: off (project convention). Runner: Godot headless, one process at a time.

## Tasks

- [ ] T1 Polish follow-ups: CANCELLED by the user on 2026-11-16 ("dejemos los jefes jugables y listo"; art when Codex has credits again). The writer was stopped mid-way; its uncommitted, untested changes were not kept in the branch (saved outside the repo as a patch). The scope list above stays as the open follow-up list.
- [x] T2 Single-branch consolidation (route: inline): `feat/new-bosses` fast-forwarded to the top of the stack, intermediate branches deleted, pushed with the user's go-ahead.

## Checks

All boss suites green: `boss_enemy_test`, `boombox_teacher_boss_test`, `blind_beast_boss_test`, `hydra_boss_test`, `boss_animation_catalog_test`, `boss_test_hub_test`, `game_completion_test`; Artemis and Profesor assets unchanged after re-running their scripts; ritual runner case lines unchanged if shared boss code changes.

## Progress and evidence

- 2026-11-16: document created; T1 writer launched.

## Next step

Wait for T1, spot check, review, consolidate the branch.

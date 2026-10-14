# Feature: Demo polish (presentation 2026-10-15 night)

## Objective
Make the current main playable end to end as a presentable Hollow Knight / Blasphemous style demo: working soul/heal loop, coherent room navigation, player guidance, HUD/UI quality, a map, ambience (light, particles, parallax), secrets, and a reachable Artemis room plus a healing room.

## Problem
- The energy bar never fills and the heal button never appears in real play (user playtest 2026-10-14: killed several snakes and a book flyer, no heal button).
- Leaving and re-entering rooms often spawns Luz at the zone start instead of the door she used.
- No guidance (controls, pickups), no pause, no map, flat static backgrounds with no lighting.
- Artemis is only reachable from a test scene; there are no secret rooms.

## Why
Demo presentation the night of 2026-10-15. The professors flagged visual cohesion as the weakest point; ambience and UI quality matter.

## User decisions (2026-10-14)
- No sound work in this feature.
- Main menu buttons stay as they are (Continue disabled, Collectables) even if they do nothing; they must never break or print.
- Soul: hits on ANY enemy fill the energy bar; the heal button appears when a heal is possible; heal becomes a single TAP (no hold); the heal animation keeps today's duration (`focus_time` 0.9 s) and the player regains control only after it ends.
- Room transitions must return Luz to the door she came through, never to the zone start.
- Map edits use the TileMapLayer tiles (no Polygon2D greybox).
- Parallax: quality but not final. Provisional layers from existing art now; Codex may supply final layers later (art = Codex, per project rule).
- Everything teammates use must be a drag-and-drop prefab (`.tscn`) configured through grouped `@export`s, with a short usage note.
- Wall cling exists (`player.gd` `_try_start_wall_cling`); tune it so it engages reliably.

## Scope
See tasks. Placement work covers the real play path: `scenes/levels/library/zone_*` and `scenes/levels/greece/zone_*`.

## Out of scope
- Sound/music.
- New character/enemy art (Codex). Artemis stays Polygon2D.
- Save to disk, Collectables screen.
- Multi-layer final parallax art.

## Constraints
- Godot 4.7, typed GDScript, AGENTS.md. Conventional Commits, body in neutral Spanish, no AI attribution, `GGA_PROVIDER=claude`.
- Do not hand-edit `.uid` files; keep node names referenced by scripts stable.
- Do not break existing suites under `tests/`.
- Mobile frame budget: lights and particles cheap (few PointLight2D, no shadows unless cheap).
- Teammates have open branches (`feature/dialogue-system`, `feature/spikes-dmg`, `feature/library_zone_transitions`, `feature/enemy_snake_lancet_scene_transition`); keep zone `.tscn` edits minimal and additive to reduce merge conflicts.

## Delivery
- TDD: off (source: project convention, same as previous features). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.
- Other checks: headless boot (`--headless --path . --quit-after 120`), iPhone deploy and user playtest.
- Branch: `feat/demo-polish`, from main `38b9d3f`.
- Delivery strategy: single-pr (same choice the user made for Artemis); forecast well above 400 authored lines.
- RDD: on (default). Boundary: `38b9d3f`.

## Tasks
- [x] D1 Soul loop fix: every enemy hit (snake, lancet, owl, book flyer, base enemies, Artemis) grants soul; HUD energy bar reflects soul; heal button appears; heal = tap with fixed 0.9 s lock (route: delegated)
  - Commit: `019d84c` (+148/-94).
  - Root cause:
    - Soul granting worked; every enemy gives +11.
    - The `TouchControls` autoload bound the player once at boot, on the menu, and never rebound. Fix: `_process` rebinds.
    - `HUD.gd` EnergyBar followed the unused `energy_changed`. Fix: it now follows `soul_changed`.
  - Tap heal: `request_focus(true)` runs a 0.9 s channel with input locked. Damage cancels it at no cost.
  - Tests: `soul_focus_test` 64/64 (the parent re-ran it: 64/64).
  - Pre-existing failures on the base, unchanged: combat, double_jump, enemy_archetypes, enemy, greece_layout, greece_population, health_hud, jump_dash, room_camera_bounds, room_transition. artemis_boss, boss_arena and stillness_desk_ritual hang.
  - Headless boot: exits 0. `library/zone_1.tscn:10501` reports a pre-existing parse error.
  - RDD: medium, under_budget (the slice stays pending from boundary `38b9d3f`). Assessments need `--untracked-scope=exclude`.
  - Device test:
    - The energy bar rises with hits.
    - The heal button shows at 33 or more soul when not at full health.
    - One tap heals.
    - The button still binds after a zone change and after a respawn.
- [x] D2 Room transitions: every zone exit/entry pair uses door ids so Luz returns to the door she used, library and Greece (route: delegated)
  - Commit: `3cf80a8` (+505/-70).
  - What changed:
    - Every door is now paired.
    - Arrival lands inside the room on the floor, facing in. Floor and ceiling holes land Luz on the ledge beside them.
    - The arrival door sets the respawn point, but an active checkpoint wins.
    - A missing target door logs `push_warning`.
    - Fixed: the swapped and wrong ids, Greece zone_healing (which was a softlock), and the zone_6 null script.
  - Greece zone_4's bottom exit now goes to zone_2. This needs a device check.
  - New `tests/door_links_test.gd`: 279/279 (the parent re-ran it: 279/279, about 110 s). The other suites match the base.
  - Device test:
    - Walk every door both ways.
    - Check the floor and ceiling holes.
    - Death respawn: at the arrival door without a desk, at the desk with one.
- [x] D3 Content fixes: duplicate fragment 2 in library zone_4, library zone_6 exit (route: delegated, with D2)
  - Commit: `cdc96e9` (+7/-4).
  - The `zone_1.tscn:10501` parse error is not a defect. `--quit-after 120` kills the menu's threaded load; with `--quit-after 3000` the boot is clean.
  - The library fragments are now 1 (zone_3), 2 (zone_4), 3 (zone_5) and 4 (zone_6), once each. The copy in zone_2 was removed.
  - Zone_6 got an exit to zone_4.
  - BLOCKED, moved to D10: library zone_6 has no way in, so fragment 4 cannot be collected. Zone_4 needs an entry door `ZONE_4_TO_ZONE_6`, tracked in `PENDING_ARRIVAL_DOORS`.
  - Finding: fragments are decorative. Nothing collects them, and Greece has no fragment 2. This feeds D4 and D5.
  - Pre-existing warning: duplicate `enemy_id 'book_flyer'` in a library zone.
- RDD slice from `38b9d3f` to `cdc96e9`:
  - Medium, `slice_budget_reached` (909 lines), so a review is due.
  - Deferred to the morning: the user is asleep, and the consent needs the human. Run the preflight STATUS with `--base-ref=38b9d3f --committed-only` then.
- [x] D4 Guidance prefabs: `TutorialSign` (world sign with text, shows near player) and pickup toast ("Fragmento 2/4"), placed in library zone_1 and on fragments/double jump (route: delegated)
  - Commit: `65ba227` (+660/-0).
  - `scenes/world/tutorial_sign.tscn` is a polygon signpost whose panel fades in on proximity. It has `show_once`, and New Game resets it.
  - `PickupToast` is an autoload: call `PickupToast.show_toast(title, subtitle)`. It reacts to `fragment_collected` and to `ability_unlocked`.
  - `assets/ui/gothic_theme.tres` is a shared theme (Cinzel and the menu palette).
  - Five signs in library zone_1: move, jump, attack, dash, heal. There is no wall-jump sign, because no early wall exists.
  - Tests: `guidance_test` 15/15 (the parent re-ran it: 15/15).
- [x] D5 HUD and UI: fragment counter, touch pause button with pause menu (Reanudar / Menu principal), menu buttons never break (route: delegated)
  - Commit: `90691ac` (+763/-17).
  - Fragments:
    - The `FragmentProgress` autoload provides `collect`, `count`, `fragment_collected`, and the to/from dict methods.
    - Each fragment has `fragment_id` 1-4 and collects on touch. A collected fragment stays gone when the room reloads.
    - The pedestal has `require_all_fragments := false`.
  - The HUD shows an "n/4" counter.
  - The `PauseMenu` autoload adds an "II" touch button in the safe area plus Escape. It offers Reanudar, Mapa (disabled; `map_enabled` and `map_requested` hook it up for D6) and Menú principal. It blocks and releases touch input.
  - Collectables shows a "Próximamente" toast.
  - Fragment ids are shared between library and Greece. Greece has no fragment 2.
  - Tests: `fragment_progress` 22/22 and `pause_menu` 20/20 (the parent re-ran both). The rest match the base.
  - Device test:
    - The signs are readable.
    - Pause opens and closes, input does not leak, and nothing stays stuck after resume.
    - The fragment toast and counter work, and a collected fragment stays gone.
- [ ] D6 Map screen: static map with "you are here" marker per zone, opened from pause/touch (route: delegated)
- [ ] D7 Ambience prefabs: `ZoneAmbience` (CanvasModulate tint), light prefab for candles/desk/pedestal, place dust/firefly/candle particles per zone (route: delegated)
- [ ] D8 Parallax prefab with provisional layers per zone (far, mid, fog) and a Codex request for final layers (route: delegated)
- [ ] D9 Secret rooms: `BreakableWall` prefab (breaks on hits, hides a room) with a reward, placed in at least one library and one Greece zone (route: delegated)
- [ ] D10 Map connection with tiles: reach an Artemis arena room and a healing room from the Greece chain (route: delegated)
- [ ] D11 Wall cling tuning so it engages reliably when touching a wall in the air (route: delegated)
- [ ] D12 iPhone deploy and user playtest; fixes from feedback (route: inline/delegated)

## Progress
- 2026-10-14: feature document created; branch `feat/demo-polish`.

## Next step
D1.

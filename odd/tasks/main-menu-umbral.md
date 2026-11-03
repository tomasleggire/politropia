# Main menu "El Umbral"

## Objective
Replace the basic main menu (static background, logo, four boxy buttons) with a cinematic, immersive title screen in the spirit of Hollow Knight / Blasphemous, based on the approved concept "El Umbral".

## Problem
`scenes/ui/main_menu.tscn` looks plain: one static `TextureRect` background, the logo and four `StyleBoxFlat` buttons. It does not sell the game.

## Why
User request on 2026-11-03: the menu must be more spectacular, beautiful, immersive, professional and polished. The user picked concept B "El Umbral" and required that the character is the real Luz and that she moves.

## Approved concept
- Reference: `tools/art_sources/main_menu/concept/umbral_concept.png` (Codex, 2026-11-03).
- A monumental gothic arch inside the dark candlelit library opens onto sunlit Greek ruins and the sea at dusk; god rays and dust pour in.
- Luz stands in the threshold facing the light (side view, real in-game sprite, animated).
- Left third is dark library holding the UI: logo top-left, a left-aligned text menu with a thin vertical gold line; the selected item has a glowing four-point star and a gold underline sweep; CONTINUAR dimmed while there is no save.

## Scope
- New layered art: far vista layer (Greece at dusk) and an architecture layer with the arch opening keyed to alpha, so they parallax.
- Ambient life in engine: slow parallax drift, god rays, golden dust particles, candle flicker, vignette.
- Luz via `LuzAnimationCatalog.build_sprite_frames()` playing `idle`.
- Text-only menu with animated selector, working with touch, mouse, keyboard and gamepad focus.
- New game transition: Luz walks into the light while the screen fades to warm gold, then the intro scene loads.
- Keep behaviour of the four options: NUEVA PARTIDA (reset progress + intro), CONTINUAR (disabled), COLECCIONABLES (gallery), LOGROS ("Coming soon" toast). Keep `%NewGame`, `%Continue`, `%Collectables`, `%Achievements` unique names.

## Constraints
- Godot 4.7 GDScript conventions from AGENTS.md. Viewport 640x360, stretch `canvas_items` / `expand` (phones wider than 16:9 must not show gaps).
- Mobile performance: CPUParticles2D or light GPU particles, no heavy full-screen shaders.
- No sound changes (menu music stays as is).

## Delivery
- Branch: `feat/main-menu-umbral` from main `4ed92c5`.
- Strategy: ask-on-risk. Forecast: ~350 authored changed lines (binary art excluded).
- TDD: off (source: project convention). Runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_test.gd`.
- Engram mirror `odd/main-menu-umbral/tasks`: pending (auto mode blocked `mem_save` on 2026-11-03 because a hook rewrites the call).

## Tasks
- [x] T1 — Layered art with Codex: architecture layer (arch opening as magenta key → alpha) and far vista layer; prompts and raw outputs in `tools/art_sources/main_menu/`, final PNGs in `assets/ui/main_menu/`. Route: inline (parent runs Codex + one keying script).
  - `assets/ui/main_menu/umbral_architecture.png` (1672x941, 20.6% transparent arch opening, 0 residual magenta pixels) keyed by `tools/key_magenta_layer.py` (run with `python3.13`, the Homebrew interpreter that has Pillow).
  - `assets/ui/main_menu/umbral_vista.png` (1672x941): sun at ~66% width, main temple at ~73-87%, framed by the arch opening (~52-88% width, ~6-82% height).
  - Visual composite check reviewed by the parent; Godot `--import` exit 0.
- [x] T2 — Rebuild `main_menu` scene: layers, parallax drift, god rays, dust, candle flicker, vignette, animated Luz, text menu with star selector; preserve option behaviour; headless test. Route: delegated direct writer (writer trigger: scene + script + selector + test, 2+ non-trivial files).
  - Stage works in the 1672x941 art space scaled to cover the viewport, so Luz, glows and particles stay glued to the art on wider phones.
  - Files: `scenes/ui/main_menu.tscn`, `scripts/ui/main_menu.gd` (flow, focus chain, opening, cinematic), `scripts/ui/main_menu_stage.gd` (`MainMenuStage`: cover math, parallax, Luz, rays, candles, dust), `scripts/ui/menu_selector.gd` (`MenuSelector`: gold line, star, underline sweep), `scripts/ui/menu_shade.gd` (`MenuShade`: left gradient + vignette), `tests/main_menu_test.gd`.
  - Tunables to adjust on device: beam alpha 0.5, Luz tint (0.52, 0.52, 0.74). Optional falling leaves skipped.
  - Evidence: `tests/main_menu_test.gd` PASS 26/26 (writer and parent re-run). Boot smoke prints only `6 ObjectDB instances were leaked` + `1 resources still in use` at exit, identical with the old menu (pre-existing). Loading `zone_1.tscn` from a `--script` harness prints `zone_1.tscn:28 Parse Error` (test-harness only, not in boot). Movie Maker frames at 640x360 and 780x360 reviewed by the parent; an auto-start of NUEVA PARTIDA seen once by the writer did not reproduce in two 8 s parent runs (brightness stable, no gold flash).
- [x] T3 — Folded into T2 on 2026-11-03: the same writer builds the new game cinematic (Luz walks into the light + gold fade before the intro), since it lives in the same scene and script.
- T1 review: RDD assessed `high` (process boundary signal on `tools/key_magenta_layer.py`); user granted; lineage `review-99f37ee38a891939` approved by 4 lenses and acknowledged (authority burned). Reviewed boundary: `fbe82ed`. Non-blocking follow-ups: despill also touches opaque near-magenta pixels; the 3x3 opening can erase 1-2 px detail (vine tendrils); no automated check for the keying script.
- [ ] T4 — Visual check with the user (desktop run + iPhone if requested).

## Acceptance criteria
- The menu matches the approved concept's composition and mood at 640x360 and on wider phone aspect ratios.
- Luz is the real in-game sprite and is visibly animated; the scene has visible ambient motion.
- All four options keep their current behaviour; focus/selection works with touch and keyboard/gamepad.
- Headless test for the menu passes; the project boots to the menu without errors.

## Progress
- 2026-11-03: three Codex concepts generated (Gran Salón, Umbral, Vigilia); user chose Umbral with the real Luz animated.

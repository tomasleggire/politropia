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
- [ ] T2 — Rebuild `main_menu` scene: layers, parallax drift, god rays, dust, candle flicker, vignette, animated Luz, text menu with star selector; preserve option behaviour; headless test. Route: delegated direct writer (scene + script + test, 2+ non-trivial files).
- [ ] T3 — New game cinematic: Luz walks into the light + gold fade before the intro. Route: decided after T2.
- [ ] T4 — Visual check with the user (desktop run + iPhone if requested).

## Acceptance criteria
- The menu matches the approved concept's composition and mood at 640x360 and on wider phone aspect ratios.
- Luz is the real in-game sprite and is visibly animated; the scene has visible ambient motion.
- All four options keep their current behaviour; focus/selection works with touch and keyboard/gamepad.
- Headless test for the menu passes; the project boots to the menu without errors.

## Progress
- 2026-11-03: three Codex concepts generated (Gran Salón, Umbral, Vigilia); user chose Umbral with the real Luz animated.

# Tests

Headless regression tests run as Godot scripts. They exit with code 0 on
success and 1 on failure, printing `PASS n/n` or `FAIL k/n` plus the failing
check names.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
```

## Layout

- `stillness_desk_ritual_test.gd`: the single entrypoint (runner and reporter).
- `door_links_test.gd`: every library and Greece door points at a door that exists in
  its target scene and leads back, Luz arrives standing on the floor just inside the
  room (never on a trigger), and a real fade transition, respawn and checkpoint run.
  Slow (about two minutes): it loads every zone.
- `artemis_room_test.gd`: the real Artemis room (greece/zone_artemis): arena and boss
  present, tiles close the arena, the door pairs with the healing room, beating Artemis
  grants the double jump once, and a reload or a zone change keeps it
  (`AbilityProgress`). About ten seconds.
- `ambience_test.gd`: every library and Greece zone has one `ZoneAmbience` and one
  `ParallaxBackdrop`, the tint never reaches the HUD layers, a zone holds at most
  8 lights, and the far parallax layer covers the view at the corners of the camera
  area for a 640x360 and an 800x500 view. Slow (about three minutes).
- `greece_layout_test.gd`: Greece layout data, reachability model and physics
  probes (including the medal alcove); helpers in `support/greece_*.gd`.
- `double_jump_test.gd`: the gated double jump (off by default, air jump count,
  resets, jump buffer, unlock signal) on a synthetic floor.
- `jump_dash_test.gd`: the Penitent-matched jump (height, apex, tap minimum, air
  speed), the standing landing recovery and its jump cancel, the ground and air
  dash profile, ledge, afterimages and dust.
- `room_camera_bounds_test.gd`: per-room camera clamp and blend, room selection
  and the real camera in the Greece level.
- `combat_test.gd`: damage, i-frames, knockback, control lock, hit-stop, death,
  respawn, the `ContactDamage` component on a synthetic floor, the absence of
  the pogo and ledge states, and the attacks (combo advances only on a landed
  hit, whiff cadence, hitbox rectangles per phase, hit-stop, finisher lunge,
  no recoil, camera kick) plus the dash i-frames.
- `enemy_test.gd`: the enemy base and the walker (patrol, ledges and walls,
  contact damage, hits, corpses), the three room persistence rules, off-room
  pausing and the player's hit recoil.
- `enemy_archetypes_test.gd`: the airborne and charging archetypes (flyer,
  charger, shooter) plus their persistence rules.
- `artemis_boss_test.gd`: the Artemis boss (health and defeat, phase threshold,
  aimed shot telegraph and arrow, dash i-frames, backstep, dodge, feint, kiting,
  walls and ledges, stagger, checkpoint reset). Unlike the standalone suites it is
  a ritual-style suite chained into the single runner, ahead of the level cases
  (the boss targets the first Luz in the tree). It also covers the phase-two
  chain and transition advisories (a plain hop never starts a string; a
  threshold crossed during a stagger or a vault fires the beat exactly once).
- `boss_arena_test.gd`: the BossArena (trigger, doors, camera lock for a plain
  Camera2D and a RoomCamera, boss health bar and phase notch, reset when Luz
  dies with and without the checkpoint contract, defeat, the double jump reward
  and its options, permanent defeat across desk rests and re-instantiation, and
  arena limits fed to the boss). Chained right after the Artemis suite.
- `health_hud_test.gd`: the mask HUD (pips, loss and refill feedback, rebuild,
  safe area, presence in both levels).
- `support/ritual_harness.gd`: shared state, game-clock waits, event recording.
- `support/ritual_celebration_recorder.gd`: per-frame beat recorder.
- `support/ritual_flow_cases.gd`, `ritual_fx_cases.gd`, `ritual_trail_cases.gd`:
  one `case_*` function per scenario, each small and single-purpose.

## Adding or changing a check

Each suite lists its cases in a `CHECKS` map (case name to number of checks).
The runner sums those maps into the expected total and also compares every
case's own count, so a case cut short by a script error is reported by name
and the run fails as incomplete. After adding a check, bump that case's number;
a mismatch prints the count actually observed. A watchdog fails a run that
never finishes.

## Timing

Waits and measured durations use the game clock (accumulated process deltas),
the same time base as the desk's tweens and the FX, never wall-clock time.
Duration tolerances widen by the worst frame seen in the measured window
(`Harness.slack`), so a frame hitch cannot make a check flaky.

The `tests/` folder is excluded from exports (see `export_presets.cfg`).

# Tests

Headless regression tests run as Godot scripts. They exit with code 0 on
success and 1 on failure, printing `PASS n/n` or `FAIL k/n` plus the failing
check names.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
```

## Layout

- `stillness_desk_ritual_test.gd`: the single entrypoint (runner and reporter).
- `greece_layout_test.gd`: Greece layout data, reachability model and physics
  probes (including the medal alcove); helpers in `support/greece_*.gd`.
- `double_jump_test.gd`: the gated double jump (off by default, air jump count,
  resets, jump buffer, unlock signal) on a synthetic floor.
- `room_camera_bounds_test.gd`: per-room camera clamp and blend, room selection
  and the real camera in the Greece level.
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

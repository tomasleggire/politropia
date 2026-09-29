# Tests

Headless regression tests run as Godot scripts. They exit with code 0 on
success and 1 on failure, printing `PASS n/n` or `FAIL k/n` plus the failing
check names.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
```

The `tests/` folder is excluded from exports (see `export_presets.cfg`).

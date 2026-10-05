extends RefCounted
## Base of every ritual test suite: a suite is a set of `case_*` coroutines that
## share one harness. `expected_checks()` maps each case name to the number of
## checks it performs; the runner runs the cases in that order and flags any
## case whose count differs (a script error aborts a case silently).

const Harness := preload("res://tests/support/ritual_harness.gd")

var h: Harness


func _init(harness: Harness) -> void:
	h = harness


func expected_checks() -> Dictionary:
	return {}

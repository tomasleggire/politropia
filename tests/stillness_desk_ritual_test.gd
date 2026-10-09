extends SceneTree
## Regression test for the Stillness Desk rest ritual (flow, fallbacks, FX, trails).
## Run: godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Cases live in tests/support/ritual_*_cases.gd. Each suite lists its cases in a
## `CHECKS` map (case name -> number of checks it performs). The runner sums the
## maps into the expected total and compares every case's own count, so a case
## cut short by a script error is named. Adding a check to a case means bumping
## that case's number in its suite; a mismatch prints the observed count.

const Harness := preload("res://tests/support/ritual_harness.gd")
const RitualSuite := preload("res://tests/support/ritual_suite.gd")
const FlowCases := preload("res://tests/support/ritual_flow_cases.gd")
const FxCases := preload("res://tests/support/ritual_fx_cases.gd")
const TrailCases := preload("res://tests/support/ritual_trail_cases.gd")
const DESK_SCENE := "res://scenes/world/stillness_desk.tscn"
## Real seconds before a stuck run (an aborted coroutine never resumes) fails.
const WATCHDOG_SECONDS := 600.0

var _harness: Harness
var _expected_total := 0
var _problems: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_harness = Harness.new(self)
	_expected_total += 4
	await _case_desk_scene_is_reusable()
	var suites: Array[RitualSuite] = [FlowCases.new(_harness), FxCases.new(_harness), TrailCases.new(_harness)]
	for suite: RitualSuite in suites:
		await _run_suite(suite)
	_harness.cps.clear()
	finish()


func _run_suite(suite: RitualSuite) -> void:
	var expected := suite.expected_checks()
	for case_name: String in expected:
		var wanted: int = expected[case_name]
		_expected_total += wanted
		await _run_case(suite, case_name, wanted)


func _case_desk_scene_is_reusable() -> void:
	var packed := load(DESK_SCENE) as PackedScene
	var desk := packed.instantiate()
	desk.set("checkpoint_id", &"standalone_validation")
	root.add_child(desk)
	await process_frame
	_harness.check(desk.is_in_group(&"interactable"), "a standalone desk registers as interactable")
	_harness.check(desk.get_node_or_null("InteractionArea") != null and desk.get_node_or_null("SpawnAnchor") != null, "the desk scene contains its interaction and spawn anchors")
	var background := desk.get_node_or_null("Visuals/Background") as CanvasItem
	_harness.check(background != null and background.is_visible_in_tree(), "the desk scene loads its altar visuals")
	_harness.check(desk.get("checkpoint_id") == &"standalone_validation", "a teammate can configure a unique checkpoint id")
	desk.queue_free()
	await process_frame


func _run_case(suite: RitualSuite, case_name: String, wanted: int) -> void:
	var before := _harness.checks
	var failed_before := _harness.failed.size()
	await suite.call(case_name)
	var ran := _harness.checks - before
	var new_failures := _harness.failed.size() - failed_before
	print("case %s: %d checks, %d failed" % [case_name, ran, new_failures])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])


func _on_watchdog() -> void:
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


func finish() -> void:
	# A script error inside a case aborts that coroutine silently, so a clean
	# `failed` list alone proves nothing: every case must run its full count.
	var failed := _harness.failed
	var complete := _problems.is_empty() and _harness.checks == _expected_total
	if complete and failed.is_empty():
		print("PASS %d/%d" % [_harness.checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("FAIL incomplete run (%d of %d checks ran)" % [_harness.checks, _expected_total])
	else:
		print("FAIL %d/%d" % [failed.size(), _harness.checks])
	_print_lines(_problems)
	_print_lines(failed)
	quit(1)


func _print_lines(lines: Array[String]) -> void:
	for line: String in lines:
		print("  - " + line)

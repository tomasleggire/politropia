extends SceneTree
## Regression test for the health pip HUD: pips built from max health, loss
## and refill feedback, rebuilds, rapid hits, the safe area and its presence
## in both levels.
## Run: godot --headless --path . --script res://tests/health_hud_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HUD_SCENE := "res://scenes/ui/health_hud.tscn"
const LEVELS := {
	"level_01": "res://scenes/levels/level_01.tscn",
	"greece": "res://scenes/levels/greece_level.tscn",
}
const WATCHDOG_SECONDS := 120.0
const LAYOUT_FRAMES := 3
## Longer than the loss tween and a staggered refill of three pips.
const LOSS_DONE := 0.6
const REFILL_DONE := 0.9
const SAFE_AREA := Rect2(30.0, 20.0, 550.0, 300.0)

const CHECKS := {
	"case_pips_built": 8,
	"case_damage_empties_one_pip": 3,
	"case_heal_refills_all": 3,
	"case_max_health_rebuilds": 4,
	"case_rapid_double_damage": 3,
	"case_safe_area": 3,
	"case_levels_bind_hud": 4,
	"case_refill_shows_while_resting": 6,
}
const DESK_LEVEL := "res://scenes/levels/level_01.tscn"
const DESK_ID := &"level_01_desk_a"
## StillnessDesk.Phase.RESTING; the class does not compile in a --script run.
const DESK_PHASE_RESTING := 4

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _hud: HealthHud


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	process_frame.connect(_tick)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _tick() -> void:
	_clock += root.get_process_delta_time()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	_free_rig()
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func _on_watchdog() -> void:
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


func finish() -> void:
	var complete := _problems.is_empty() and checks == _expected_total
	if complete and failed.is_empty():
		print("PASS %d/%d" % [checks, _expected_total])
		quit(0)
		return
	if not complete:
		print("FAIL incomplete run (%d of %d checks ran)" % [checks, _expected_total])
	else:
		print("FAIL %d/%d" % [failed.size(), checks])
	for line: String in _problems + failed:
		print("  - " + line)
	quit(1)


# -- Rig and helpers -----------------------------------------------------------------

## A player and a HUD bound to her, laid out and ready.
func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_rig.add_child(_player)
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as HealthHud
	_rig.add_child(_hud)
	_hud.bind_player(_player)
	await _frames(LAYOUT_FRAMES)


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_hud = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _hit() -> void:
	_player._invuln_left = 0.0
	_player.take_damage(1, Vector2(-100.0, 0.0))


func _full_count() -> int:
	var count := 0
	for pip: HealthPip in _hud.get_pips():
		if pip.is_full():
			count += 1
	return count


func _settled() -> bool:
	for pip: HealthPip in _hud.get_pips():
		var final_fill := 1.0 if pip.is_full() else 0.0
		if pip.is_animating() or pip.fill != final_fill or pip.scale != Vector2.ONE or pip.shake != 0.0:
			return false
	return true


# -- Cases -----------------------------------------------------------------------

func case_pips_built() -> void:
	await _build_rig()
	check(_hud.get_pips().size() == 3, "one pip per max health (%d)" % _hud.get_pips().size())
	check(_full_count() == 3, "every pip starts full")
	check(_hud.layer > 30 and _hud.layer < 100, "the HUD sits above the vignette and below the touch controls (%d)" % _hud.layer)
	check(_hud.is_bound(), "the HUD is bound to the player")
	check(_hud.visible, "the health HUD layer is visible")
	check(_hud.get_meter().is_visible_in_tree(), "the soul vessel is visible in the scene tree")
	check(_hud.get_pips()[0].is_visible_in_tree(), "the health pips are visible in the scene tree")
	var art := PlaceholderTexture2D.new()
	_hud.full_texture = art
	_player.set_max_health(4)
	check(_hud.get_pips()[0].full_texture == art, "pips built later take the HUD's swappable art")


func case_damage_empties_one_pip() -> void:
	await _build_rig()
	_hit()
	await _secs(LOSS_DONE)
	check(_full_count() == 2, "one hit leaves two full pips (%d)" % _full_count())
	check(not _hud.get_pips()[2].is_full() and _hud.get_pips()[0].is_full(), "the rightmost pip is the one that emptied")
	check(_settled(), "no pip is stuck mid-tween")


func case_heal_refills_all() -> void:
	await _build_rig()
	_hit()
	await _secs(LOSS_DONE)
	_player.restore_full_health()
	await _secs(REFILL_DONE)
	check(_full_count() == 3, "healing refills every pip")
	check(_settled(), "the refill ends settled")
	_hit()
	_player.restore_full_health()
	await _secs(REFILL_DONE)
	check(_full_count() == 3 and _settled(), "a heal right after a hit still ends full")


func case_max_health_rebuilds() -> void:
	await _build_rig()
	_player.set_max_health(5)
	await _frames(LAYOUT_FRAMES)
	check(_hud.get_pips().size() == 5, "raising max health builds five pips (%d)" % _hud.get_pips().size())
	check(_full_count() == 3, "health is not raised, so only three are full (%d)" % _full_count())
	_player.set_max_health(2)
	await _frames(LAYOUT_FRAMES)
	check(_hud.get_pips().size() == 2, "lowering max health drops to two pips")
	check(_full_count() == 2 and _hud.get_child(0).get_child(0).get_child_count() == 2, "no leftover pips remain in the row")


func case_rapid_double_damage() -> void:
	await _build_rig()
	_hit()
	_hit()
	await _secs(LOSS_DONE)
	check(_player.get_health() == 1, "two quick hits leave one pip")
	check(_full_count() == 1 and _hud.get_pips()[0].is_full(), "the HUD shows exactly one full pip, the leftmost")
	check(_settled(), "no pip is stuck mid-tween after rapid hits")


func case_safe_area() -> void:
	await _build_rig()
	_hud.set_safe_area(SAFE_AREA)
	await _frames(LAYOUT_FRAMES)
	var inside := true
	for pip: HealthPip in _hud.get_pips():
		inside = inside and SAFE_AREA.encloses(pip.get_global_rect())
	check(inside, "every pip sits inside the pinned safe area")
	check(_hud.get_pips()[0].get_global_rect().position.x > SAFE_AREA.position.x, "the first pip is inset from the safe edge")
	var viewport_rect := _hud.get_viewport().get_visible_rect()
	_hud.set_safe_area(Rect2())
	await _frames(LAYOUT_FRAMES)
	check(viewport_rect.encloses(_hud.get_pips()[2].get_global_rect()), "without a notch the pips sit inside the viewport")


func case_levels_bind_hud() -> void:
	for level_name: String in LEVELS:
		root.get_node("CheckpointService").clear()
		change_scene_to_file(LEVELS[level_name])
		await _frames(10)
		var hud := current_scene.get_node_or_null("HealthHud") as HealthHud
		check(hud != null and hud.is_bound(), "%s has a bound HUD" % level_name)
		check(hud != null and hud.get_pips().size() == 3, "%s shows three pips" % level_name)


## The desk freezes the world with pause_world, but heals at the celebration
## peak: the pips must be visibly full while still resting, before Luz stands.
func case_refill_shows_while_resting() -> void:
	var checkpoints := root.get_node("CheckpointService")
	checkpoints.clear()
	change_scene_to_file(DESK_LEVEL)
	await _frames(10)
	var level := current_scene
	var desk := level.get_node("StillnessDesk")
	var player := level.get_node("Player") as Player
	var hud := level.get_node("HealthHud") as HealthHud
	checkpoints.activate(DESK_ID, DESK_LEVEL, desk.get_spawn_position())
	for i: int in 2:
		player._invuln_left = 0.0
		player.take_damage(1, Vector2(-100.0, 0.0))
	await _secs(LOSS_DONE)
	player.global_position = desk.get_spawn_position()
	await _frames(30)
	var full_before := 0
	for pip: HealthPip in hud.get_pips():
		full_before += 1 if pip.is_full() else 0
	check(full_before == 1, "setup: one of three pips is full (%d)" % full_before)
	check(desk.request_rest(), "the rest is accepted")
	await _secs(2.5)
	check(paused and desk.get_phase() == DESK_PHASE_RESTING, "she is still sitting with the world paused")
	var shown := 0
	for pip: HealthPip in hud.get_pips():
		shown += 1 if pip.is_full() and pip.fill == 1.0 and pip.scale == Vector2.ONE else 0
	check(player.get_health() == 3, "the desk healed her at the peak")
	check(shown == 3, "every pip shows its final full look before she stands (%d)" % shown)
	check(hud.process_mode == Node.PROCESS_MODE_ALWAYS, "the HUD keeps processing through the pause")
	paused = false
	checkpoints.clear()

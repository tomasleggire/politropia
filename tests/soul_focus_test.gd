extends SceneTree
## Regression test for the soul meter and the focus heal: soul from enemy hits
## only, the focus channel (cost, duration, chaining, every cancel rule and
## refusal), the reset on death, the HUD soul vessel and the touch Focus button.
## Run: godot --headless --path . --script res://tests/soul_focus_test.gd
## Exits 0 when every check passes, 1 otherwise.
##
## Each case lists its check count in CHECKS; the runner compares it with the
## checks the case actually ran, so a case aborted by a script error is named.
## Waits run on the game clock (accumulated process deltas).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WALKER_SCENE := "res://scenes/enemies/walker.tscn"
const CONTACT_SCENE := "res://scenes/world/contact_damage.tscn"
const PROJECTILE_SCENE := "res://scenes/enemies/enemy_projectile.tscn"
const HUD_SCENE := "res://scenes/ui/health_hud.tscn"
const TOUCH_SCENE := "res://scenes/ui/touch_controls.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const HAZARD_RECT := Rect2(-48.0, -16.0, 96.0, 16.0)
const START_X := -300.0
const ABOVE_WALKER := Vector2(0.0, -75.0)
const ABOVE_HAZARD := Vector2(0.0, -50.0)
const BOUNCE_SPEED := -300.0
const BOUNCE_STEPS := 32
const FOCUS_SECONDS := 0.9
const LAYOUT_FRAMES := 3

const CHECKS := {
	"case_enemy_hit_adds_soul": 4,
	"case_other_hits_add_nothing": 4,
	"case_enemy_pogo_adds_soul": 3,
	"case_focus_heals_one": 6,
	"case_release_cancels": 3,
	"case_damage_cancels": 4,
	"case_leaving_the_floor_cancels": 3,
	"case_acting_cancels": 4,
	"case_focus_is_refused": 4,
	"case_focus_chains": 4,
	"case_death_resets_soul": 2,
	"case_hud_meter": 6,
	"case_touch_button": 5,
}

var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _clock := 0.0
var _rig: Node2D
var _player: Player
var _walker: Walker
var _soul_events: Array[Vector2i] = []


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
	_release_all()
	_free_rig()
	root.get_node("EnemyRegistry").clear()
	root.get_node("CheckpointService").clear()
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

## A flat floor (top at y=0) with Luz standing on it, settled.
func _build_rig() -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	LevelGeometry.add_solid(_rig, FLOOR_RECT, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(START_X, 0.0)
	_rig.add_child(_player)
	_soul_events.clear()
	_player.soul_changed.connect(func(current: int, maximum: int) -> void: _soul_events.append(Vector2i(current, maximum)))
	await _frames(SETTLE_FRAMES)


## Starts with a sturdy, motionless walker at the origin.
func _add_walker(health: int) -> void:
	_walker = (load(WALKER_SCENE) as PackedScene).instantiate() as Walker
	_walker.enemy_id = &"w1"
	_walker.walk_speed = 0.0
	_walker.max_health = health
	_rig.add_child(_walker)


func _add_hazard() -> void:
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	hazard.kind = ContactDamage.Kind.HAZARD
	_rig.add_child(hazard)
	hazard.set_area_size(HAZARD_RECT.size)
	hazard.position = HAZARD_RECT.get_center()


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_player = null
	_walker = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _secs(t: float) -> void:
	var end := _clock + t
	while _clock < end:
		await process_frame


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_down", &"jump", &"dash", &"focus"]:
		Input.action_release(action)


## Puts her at `health` pips with `soul`, on the floor and ready to focus.
func _prepare(health: int, soul: int) -> void:
	_player._health = health
	_player.add_soul(soul)


func _drop_player_at(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	for i: int in 3:
		await physics_frame


## Slashes down onto whatever is below and waits out the bounce.
func _pogo_down() -> bool:
	Input.action_press(&"move_down")
	_player.request_attack(1)
	var bounced := false
	for i: int in BOUNCE_STEPS:
		await physics_frame
		bounced = bounced or _player.velocity.y < BOUNCE_SPEED
	return bounced


func _hit_player() -> void:
	_player._invuln_left = 0.0
	_player.take_damage(1, Vector2(-100.0, 0.0))


# -- Cases -----------------------------------------------------------------------

func case_enemy_hit_adds_soul() -> void:
	await _build_rig()
	_add_walker(50)
	_player._resolve_attack_hit(_walker, &"attack_1")
	check(_player.get_soul() == 11, "a hit on an enemy gives 11 soul (%d)" % _player.get_soul())
	check(_soul_events.back() == Vector2i(11, 99), "and announces it with the maximum (%s)" % [_soul_events])
	for i: int in 12:
		_player._resolve_attack_hit(_walker, &"attack_1")
	check(_player.get_soul() == 99, "soul is capped at 99 (%d)" % _player.get_soul())
	var announced := _soul_events.size()
	_player._resolve_attack_hit(_walker, &"attack_1")
	check(_soul_events.size() == announced, "a capped hit announces nothing")


func case_other_hits_add_nothing() -> void:
	await _build_rig()
	var shot := (load(PROJECTILE_SCENE) as PackedScene).instantiate() as EnemyProjectile
	_rig.add_child(shot)
	shot.launch(Vector2(60.0, -40.0), Vector2.RIGHT, 0.0)
	_player._resolve_attack_hit(shot, &"attack_1")
	check(not shot.is_active() and _player.get_soul() == 0, "cutting a projectile gives no soul (%d)" % _player.get_soul())
	_add_hazard()
	await _drop_player_at(Vector2(0.0, ABOVE_HAZARD.y))
	var bounced := await _pogo_down()
	check(bounced, "the down slash bounces off the spike")
	check(_player.get_soul() == 0, "a spike pogo gives no soul (%d)" % _player.get_soul())
	check(_player.get_health() == 3, "and she took no damage")


func case_enemy_pogo_adds_soul() -> void:
	await _build_rig()
	_add_walker(5)
	await _frames(SETTLE_FRAMES)
	await _drop_player_at(Vector2(0.0, ABOVE_WALKER.y))
	var bounced := await _pogo_down()
	check(bounced, "the down slash bounces off the walker")
	check(_walker.get_health() == 4, "and damages it (%d)" % _walker.get_health())
	check(_player.get_soul() == 11, "an enemy pogo gives soul (%d)" % _player.get_soul())


func case_focus_heals_one() -> void:
	await _build_rig()
	_prepare(1, 33)
	_player.request_focus(true)
	await _secs(0.2)
	check(_player.is_focusing(), "holding focus starts the channel")
	check(_player.velocity == Vector2.ZERO, "she stands still")
	await _secs(FOCUS_SECONDS - 0.5)
	check(_player.get_health() == 1 and _player.get_soul() == 33, "nothing is spent before the channel ends")
	await _secs(0.6)
	check(_player.get_health() == 2, "one pip is healed (%d)" % _player.get_health())
	check(_player.get_soul() == 0, "and 33 soul spent (%d)" % _player.get_soul())
	check(not _player.is_focusing(), "with no soul left the channel ends")


func case_release_cancels() -> void:
	await _build_rig()
	_prepare(1, 33)
	_player.request_focus(true)
	await _secs(0.4)
	_player.request_focus(false)
	await _secs(0.8)
	check(not _player.is_focusing(), "releasing ends the channel")
	check(_player.get_health() == 1, "with no heal")
	check(_player.get_soul() == 33, "and no soul spent")


func case_damage_cancels() -> void:
	await _build_rig()
	_prepare(2, 33)
	_player.request_focus(true)
	await _secs(0.4)
	_hit_player()
	await _frames(2)
	check(_player._state == Player.State.HURT, "a hit follows the normal hurt flow")
	_player.request_focus(false)
	await _secs(1.5)
	check(_player.get_health() == 1, "she lost the pip and gained none (%d)" % _player.get_health())
	check(_player.get_soul() == 33, "no soul was spent")
	check(not _player.is_focusing(), "and the channel is over")


func case_leaving_the_floor_cancels() -> void:
	await _build_rig()
	_prepare(1, 33)
	_player.request_focus(true)
	await _secs(0.3)
	await _drop_player_at(Vector2(START_X, -200.0))
	check(_player._state == Player.State.FALL, "leaving the floor ends the channel (%s)" % Player.State.keys()[_player._state])
	check(_player.get_soul() == 33, "no soul was spent")
	check(_player.get_health() == 1, "and nothing healed")


func case_acting_cancels() -> void:
	await _build_rig()
	_prepare(1, 33)
	_player.request_focus(true)
	await _secs(0.3)
	_player.request_jump()
	await _frames(3)
	check(not _player.is_focusing(), "jumping cancels the channel")
	await _secs(1.0)
	_player.request_focus(true)
	await _secs(0.3)
	check(_player.is_focusing(), "holding focus on the ground starts it again")
	Input.action_press(&"move_right")
	await _frames(3)
	check(not _player.is_focusing(), "moving cancels the channel")
	Input.action_release(&"move_right")
	check(_player.get_soul() == 33 and _player.get_health() == 1, "and neither cost anything")


func case_focus_is_refused() -> void:
	await _build_rig()
	_prepare(3, 99)
	_player.request_focus(true)
	await _secs(0.3)
	check(not _player.is_focusing() and not _player.is_focus_available(), "focus is refused at full health")
	_player.request_focus(false)
	_free_rig()
	await _build_rig()
	_prepare(1, 22)
	_player.request_focus(true)
	await _secs(0.3)
	check(not _player.is_focusing() and not _player.is_focus_available(), "focus is refused with less than 33 soul")
	_player.add_soul(11)
	await _secs(0.3)
	check(_player.is_focusing(), "at exactly 33 soul it starts")
	_player.request_focus(false)
	await _secs(0.2)
	check(_player.get_soul() == 33, "and releasing early still costs nothing")


func case_focus_chains() -> void:
	await _build_rig()
	_prepare(1, 66)
	_player.request_focus(true)
	await _secs(FOCUS_SECONDS + 0.4)
	check(_player.get_health() == 2 and _player.get_soul() == 33, "the first heal lands (%d, %d)" % [_player.get_health(), _player.get_soul()])
	check(_player.is_focusing(), "and the next channel chains while held")
	await _secs(FOCUS_SECONDS)
	check(_player.get_health() == 3, "the second heal lands (%d)" % _player.get_health())
	check(_player.get_soul() == 0 and not _player.is_focusing(), "66 soul paid for both and she stops")


func case_death_resets_soul() -> void:
	await _build_rig()
	_prepare(1, 44)
	check(_player.get_soul() == 44, "she holds 44 soul")
	_hit_player()
	check(_player.get_soul() == 0, "dying resets soul to 0 (%d)" % _player.get_soul())


func case_hud_meter() -> void:
	await _build_rig()
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as HealthHud
	var art := PlaceholderTexture2D.new()
	hud.meter_full_texture = art
	_rig.add_child(hud)
	hud.bind_player(_player)
	await _frames(LAYOUT_FRAMES)
	var meter := hud.get_meter()
	check(meter.fill == 0.0 and not meter.is_cue_visible(), "the meter starts empty with no cue")
	_player.add_soul(22)
	check(is_equal_approx(meter.fill, 22.0 / 99.0) and not meter.is_cue_visible(), "22 soul fills a fifth and shows no cue (%.2f)" % meter.fill)
	_player.add_soul(11)
	check(meter.is_cue_visible(), "33 soul shows the can-heal cue")
	_player.add_soul(66)
	check(meter.fill == 1.0, "99 soul fills the vessel")
	check(meter.full_texture == art and hud.process_mode == Node.PROCESS_MODE_ALWAYS, "the art is swappable and the HUD runs while paused")
	_player.take_damage(5, Vector2(-100.0, 0.0))
	check(meter.fill == 0.0 and not meter.is_cue_visible(), "dying empties the meter")


func case_touch_button() -> void:
	await _build_rig()
	var touch := (load(TOUCH_SCENE) as PackedScene).instantiate()
	touch.force_visible = true
	_rig.add_child(touch)
	touch.bind_player(_player)
	await _frames(LAYOUT_FRAMES)
	var button: Control = touch.get_node("Root/FocusButton")
	check(not button.visible, "the Focus button is hidden at full health and no soul")
	_prepare(1, 33)
	check(button.visible, "it shows once focus is possible")
	_press_button(button, true)
	await _secs(0.3)
	check(_player.is_focusing(), "holding the button focuses")
	_press_button(button, false)
	await _secs(0.3)
	check(not _player.is_focusing() and not Input.is_action_pressed(&"focus"), "releasing it stops, and the action is not stuck")
	_player.restore_full_health()
	check(not button.visible, "it hides again at full health")


## Touch events arrive in window pixels, so the canvas position is mapped through
## the stretch transform.
func _press_button(button: Control, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = pressed
	touch.position = root.get_final_transform() * button.get_global_rect().get_center()
	Input.parse_input_event(touch)

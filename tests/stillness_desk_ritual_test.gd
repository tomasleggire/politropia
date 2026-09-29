extends SceneTree
## Regression test for the Stillness Desk rest ritual (flow, fallbacks, FX).
## Run: godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
## Exits 0 when every check passes, 1 otherwise.

const LEVEL := "res://scenes/levels/level_01.tscn"
const DESK_ID := &"level_01_desk_a"
## Total checks a complete run performs; a smaller count means the run aborted.
const EXPECTED_CHECKS := 150
const EXPECTED_CASES := 4

class Dummy extends Node:
	var n := 0

	func reset_to_checkpoint_state() -> void:
		n += 1

var checks := 0
var cases_done := 0
var failed: Array[String] = []
# StillnessDesk, Player, StillnessDeskFx and the autoloads reference autoload
# singletons, which are not resolvable in a --script run, so they are typed by
# their native base class.
var lvl: Node
var desk: Node2D
var player: CharacterBody2D
var fx: Node2D
var dummy: Dummy
var tc: Node
var cps: Node
var phases: Array[int] = []
var acts := 0
var trace: Array[Array] = []   # [anim, frame, backpack visible]
var ev: Array[Array] = []
var paper_z: Array[int] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func frames(n: int) -> void:
	for i: int in n:
		await process_frame


func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func wait_phase(ph: int, timeout: float = 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while desk.get_phase() != ph and Time.get_ticks_msec() < end:
		await process_frame
	return desk.get_phase() == ph


func place() -> void:
	player.global_position = desk.get_spawn_position()
	player.velocity = Vector2.ZERO
	await frames(30)


func sample() -> void:
	if not is_instance_valid(desk) or not is_instance_valid(player):
		return
	if desk.get_phase() in [2, 3, 4, 5]:
		trace.append([player._sprite.animation, player._sprite.frame, desk._backpack.visible])


func _initialize() -> void:
	run.call_deferred()


func setup_level() -> void:
	change_scene_to_file(LEVEL)
	await frames(10)
	lvl = current_scene
	desk = lvl.get_node("StillnessDesk")
	player = lvl.get_node("Player")
	fx = desk.get_node("Fx")
	dummy = Dummy.new()
	dummy.add_to_group("checkpoint_resettable")
	lvl.add_child(dummy)
	phases.clear()
	ev.clear()
	acts = 0
	paper_z.clear()
	for sheet: Node2D in desk.get_node("Visuals/Papers").get_children():
		paper_z.append(sheet.z_index)
	desk.phase_changed.connect(func(p: int) -> void: phases.append(p))
	desk.celebration_started.connect(func(f: bool) -> void: ev.append(["start", f, Time.get_ticks_msec(), dummy.n, acts]))
	desk.celebration_peak.connect(func() -> void: ev.append(["peak", Time.get_ticks_msec(), dummy.n, acts, player._health]))
	desk.celebration_finished.connect(func() -> void: ev.append(["finish", Time.get_ticks_msec()]))
	desk.dismount_started.connect(func() -> void: ev.append(["dismount", Time.get_ticks_msec()]))
	desk.rest_completed.connect(func(_id: StringName) -> void: ev.append(["completed", Time.get_ticks_msec()]))
	if not cps.checkpoint_activated.is_connected(count_activation):
		cps.checkpoint_activated.connect(count_activation)
	if not process_frame.is_connected(sample):
		process_frame.connect(sample)


func swing_range(t: float) -> float:
	var mx := 0.0
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		mx = maxf(mx, absf(fx.get_swing_angle()))
	return mx


func papers_home() -> bool:
	var orbit := fx.get_node("PaperOrbit")
	var sheets := desk.get_node("Visuals/Papers").get_children()
	for i: int in sheets.size():
		if sheets[i].position.distance_to(orbit.get_rest_position(i)) > 1.0:
			return false
	return true


func papers_z_home() -> bool:
	var sheets := desk.get_node("Visuals/Papers").get_children()
	for i: int in sheets.size():
		if sheets[i].z_index != paper_z[i]:
			return false
	return true


func papers_lifted() -> float:
	var orbit := fx.get_node("PaperOrbit")
	var sheets := desk.get_node("Visuals/Papers").get_children()
	var m := 0.0
	for i: int in sheets.size():
		m = maxf(m, sheets[i].position.distance_to(orbit.get_rest_position(i)))
	return m


func count_activation(_id: StringName, _path: String, _position: Vector2) -> void:
	acts += 1


func count_events(kind: String) -> int:
	return ev.filter(func(e: Array) -> bool: return e[0] == kind).size()


func run() -> void:
	await process_frame
	cps = get_root().get_node("CheckpointService")
	tc = get_root().get_node("TouchControls")
	await run_flow_cases()
	await run_fallback_cases()
	await run_fx_cases()
	cps.clear()
	finish()


func finish() -> void:
	# A script error inside a case aborts that coroutine silently, so a clean
	# `failed` list alone proves nothing: require every case to have completed.
	if cases_done != EXPECTED_CASES or checks != EXPECTED_CHECKS:
		print("FAIL incomplete run (%d checks ran)" % checks)
		for message: String in failed:
			print("  - " + message)
		quit(1)
		return
	if failed.is_empty():
		print("PASS %d/%d" % [checks, EXPECTED_CHECKS])
		quit(0)
		return
	print("FAIL %d/%d" % [failed.size(), checks])
	for message: String in failed:
		print("  - " + message)
	quit(1)


# -- Ritual flow: input, clips, effects, aborts ---------------------------------

func run_flow_cases() -> void:
	cps.clear()
	check(not cps.was_ever_activated(DESK_ID), "service: not activated initially")
	await setup_level()
	await place()
	check(desk.can_rest(), "can_rest at desk")
	check(desk.get_phase() == 0, "starts DORMANT")
	check(desk.get_spawn_position().is_equal_approx(desk.global_position), "anchor at desk centre")
	# ---- rest 1: held key from approach, first celebration, touch jump exit
	player._health = 1
	player._facing = -1
	Input.action_press("move_right")
	trace.clear(); ev.clear(); phases.clear(); dummy.n = 0; acts = 0
	check(desk.request_rest(), "rest1 accepted")
	await frames(3)
	check(paused and player.is_meditating(), "rest1 paused+meditating")
	check(not player._sprite.flip_h, "rest1 faces right")
	check(not tc._interact_button.visible, "rest1 touch button hidden")
	check(absf(player.global_position.x - desk.global_position.x) < 1.0, "rest1 snapped to desk centre")
	check(await wait_phase(4), "rest1 reaches RESTING")
	check(paused, "rest1 still paused in RESTING")
	await secs(1.0)
	check(desk.get_phase() == 4, "rest1 held key does NOT dismount")
	Input.action_release("move_right")
	await secs(4.5)
	check(desk.get_phase() == 4 and paused and player.is_meditating(), "rest1 seated >=5s with no input")
	check(player._sprite.animation == &"rest_sit" and player._sprite.is_playing(), "rest1 rest_sit looping")
	check(absf(desk.breath_period - 2.0) < 0.01, "breath_period 2.0 (%f)" % desk.breath_period)
	# The real touch path runs through the TouchControls autoload, which must
	# keep receiving input while the tree is paused for the rest.
	check(root.get_node("TouchControls").can_process(), "rest1 touch controls process while paused")
	player.request_jump()
	await frames(2)
	check(desk.get_phase() == 5, "rest1 touch request_jump dismounts")
	check(await wait_phase(1, 4.0), "rest1 back to AWAKENED")
	await frames(3)
	check(not paused and not player.is_meditating(), "rest1 unpaused, control returned")
	check(phases == [2, 3, 4, 5, 1], "rest1 phase order %s" % [phases])
	var seq: Array[StringName] = []
	for t: Array in trace:
		if seq.is_empty() or seq[-1] != t[0]: seq.append(t[0])
	check(seq == [&"rest_mount", &"rest_sit", &"rest_dismount"], "rest1 clips order %s" % [seq])
	var bad := 0
	for t: Array in trace:
		var want: bool = (t[0] == &"rest_mount" and t[1] >= 3) or t[0] == &"rest_sit" or (t[0] == &"rest_dismount" and t[1] < 4)
		if want != t[2]: bad += 1
	check(bad == 0, "rest1 backpack visible exactly mount f3..dismount f4 (bad=%d of %d)" % [bad, trace.size()])
	var st: Array[Array] = ev.filter(func(e: Array) -> bool: return e[0] == "start")
	var pk: Array[Array] = ev.filter(func(e: Array) -> bool: return e[0] == "peak")
	var fin: Array[Array] = ev.filter(func(e: Array) -> bool: return e[0] == "finish")
	check(st.size() == 1 and st[0][1] == true, "rest1 celebration first=true")
	check(pk.size() == 1 and fin.size() == 1, "rest1 one peak, one finish")
	check(st[0][3] == 0 and st[0][4] == 0, "rest1 nothing applied at start")
	check(pk[0][2] == 1 and pk[0][3] == 1 and pk[0][4] == player.max_health, "rest1 heal/reset/activate at peak once")
	var dur: float = (fin[0][1] - st[0][2]) / 1000.0
	check(absf(dur - 2.4) < 0.25, "rest1 long celebration %.2fs" % dur)
	check(dummy.n == 1 and acts == 1, "rest1 reset/activate exactly once total")
	check(cps.was_ever_activated(DESK_ID), "service records activation")
	# ---- rest 2: repeat, keyboard-style parse, grace ignore
	await place()
	player._health = 1
	trace.clear(); ev.clear(); phases.clear(); dummy.n = 0; acts = 0
	check(desk.request_rest(), "rest2 accepted")
	check(await wait_phase(4), "rest2 RESTING")
	await secs(0.1)
	Input.action_press("move_left"); await frames(2); Input.action_release("move_left")
	await frames(2)
	check(desk.get_phase() == 4, "rest2 input inside grace ignored")
	await secs(0.6)
	var kev := InputEventAction.new()
	kev.action = "attack"; kev.pressed = true
	Input.parse_input_event(kev)
	await frames(3)
	check(desk.get_phase() == 5, "rest2 fresh attack press dismounts")
	Input.action_release("attack")
	check(await wait_phase(1, 4.0), "rest2 AWAKENED")
	await frames(3)
	check(not paused and not player.is_meditating(), "rest2 released")
	st = ev.filter(func(e: Array) -> bool: return e[0] == "start")
	pk = ev.filter(func(e: Array) -> bool: return e[0] == "peak")
	fin = ev.filter(func(e: Array) -> bool: return e[0] == "finish")
	dur = (fin[0][1] - st[0][2]) / 1000.0
	check(st[0][1] == false and absf(dur - 0.8) < 0.25, "rest2 short celebration first=false %.2fs" % dur)
	check(dummy.n == 1 and acts == 1 and pk.size() == 1, "rest2 reset/activate once")
	bad = 0
	for t: Array in trace:
		var want2: bool = (t[0] == &"rest_mount" and t[1] >= 3) or t[0] == &"rest_sit" or (t[0] == &"rest_dismount" and t[1] < 4)
		if want2 != t[2]: bad += 1
	check(bad == 0, "rest2 backpack timing (bad=%d)" % bad)
	# ---- rest 3: real keyboard event exit
	await place()
	check(desk.request_interact(), "rest3 accepted via request_interact")
	check(await wait_phase(4), "rest3 RESTING")
	await secs(0.5)
	var ke := InputEventKey.new()
	ke.physical_keycode = KEY_D; ke.pressed = true
	Input.parse_input_event(ke)
	await frames(3)
	check(desk.get_phase() == 5, "rest3 keyboard D press dismounts (phase %d)" % desk.get_phase())
	ke = InputEventKey.new(); ke.physical_keycode = KEY_D; ke.pressed = false
	Input.parse_input_event(ke)
	check(await wait_phase(1, 4.0), "rest3 AWAKENED")
	# ---- movement regression outside rest
	await frames(20)
	var x0: float = player.global_position.x
	Input.action_press("move_right")
	await secs(0.5)
	Input.action_release("move_right")
	check(player.global_position.x > x0 + 5.0, "movement works (dx=%f)" % (player.global_position.x - x0))
	check(player._sprite.animation != &"rest_dismount" and player._sprite.animation != &"rest_sit", "sprite left rest clips (%s)" % player._sprite.animation)
	# ---- respawn mid-rest at each phase
	for target: int in [2, 3, 4, 5]:
		await place()
		check(desk.request_rest(), "respawn test phase %d: rest accepted" % target)
		if target == 5:
			check(await wait_phase(4), "reach RESTING for dismount case")
			await secs(0.5)
			player.request_dash()
		check(await wait_phase(target), "reached phase %d" % target)
		await frames(3)
		var n_before: int = dummy.n
		var a_before: int = acts
		player.respawn()
		await frames(3)
		check(not paused, "respawn@%d unpaused" % target)
		check(not player.is_meditating(), "respawn@%d not meditating" % target)
		check(not desk._backpack.visible, "respawn@%d backpack hidden" % target)
		check(desk.is_processing(), "respawn@%d desk alive" % target)
		var ph: int = desk.get_phase()
		check(ph == 0 or ph == 1, "respawn@%d idle phase %d" % [target, ph])
		await secs(3.2)
		check(dummy.n == n_before and acts == a_before, "respawn@%d no stale effects" % target)
		check(not paused and desk.get_phase() == ph, "respawn@%d stable" % target)
	# ---- player freed mid-rest
	await place()
	check(desk.request_rest(), "free test: rest accepted")
	await secs(1.3)
	player.queue_free()
	await frames(4)
	check(not paused, "player freed: unpaused")
	check(desk.get_phase() in [0, 1], "player freed: idle phase")
	check(not desk._backpack.visible, "player freed: backpack hidden")
	# ---- desk freed mid-rest (fresh level)
	await setup_level()
	await place()
	check(desk.request_rest(), "desk free test: rest accepted")
	await secs(1.3)
	desk.queue_free()
	await frames(4)
	check(not paused, "desk freed: unpaused")
	check(not player.is_meditating(), "desk freed: player released")
	# ---- scene reload returns to desk
	change_scene_to_file(LEVEL)
	await frames(10)
	var p2: CharacterBody2D = current_scene.get_node("Player")
	var d2: Node2D = current_scene.get_node("StillnessDesk")
	check(p2.global_position.distance_to(d2.get_spawn_position()) < 2.0, "reload spawns at desk")
	check(d2.get_phase() == 1, "reloaded desk awakened")
	cps.clear()
	check(not cps.was_ever_activated(DESK_ID), "clear() resets activation record")
	cases_done += 1


# -- Clip fallback must not double-advance ---------------------------------------

func run_fallback_cases() -> void:
	cps.clear()
	await setup_level()
	await place()
	# Real finished signal and fallback both fire: mount must advance once.
	check(desk.request_rest(), "fallback: rest accepted")
	await frames(2)
	desk._on_rest_animation_finished(&"rest_mount")
	check(await wait_phase(4, 6.0), "fallback: reaches RESTING")
	await secs(1.0)
	check(count_events("start") == 1, "fallback: one celebration despite duplicate mount finish (%d)" % count_events("start"))
	check(count_events("peak") == 1 and dummy.n == 1 and acts == 1, "fallback: effects applied once")
	# Dismount: real signal plus the late fallback must complete once.
	await secs(0.6)
	player.request_jump()
	check(await wait_phase(1, 4.0), "fallback: dismount completes")
	await secs(1.5)
	check(count_events("completed") == 1, "fallback: rest_completed once (%d)" % count_events("completed"))
	check(phases == [2, 3, 4, 5, 1], "fallback: phases not repeated %s" % [phases])
	check(not paused and not player.is_meditating(), "fallback: control returned")
	cases_done += 1


# -- FX layer -------------------------------------------------------------------

func run_fx_cases() -> void:
	cps.clear()
	await setup_level()
	await place()
	var sw: FireflySwarm = fx.get_node("Fireflies")
	var halo: HaloSigil = fx.get_halo()
	var shaft: AltarLightShaft = fx.get_shaft()
	var candelabras: Array[GothicCandle] = [desk.get_node("Visuals/CandelabraLeft"), desk.get_node("Visuals/CandelabraRight")]
	# dormant
	check(halo.fill == 0.0 and halo.flare == 0.0, "dormant halo unfilled (fill %.2f)" % halo.fill)
	check(halo.intensity > 0.2, "dormant halo faintly engraved (%.2f)" % halo.intensity)
	check(not desk.has_node("Visuals/FloorRingLit"), "floor ring nodes removed")
	check(halo.can_process() and shaft.can_process(), "halo and shaft process while paused")
	check(candelabras[0].can_process() and candelabras[1].can_process() and candelabras[0].candelabra, "candelabras exist and process while paused")
	check(halo.get_parent().z_index + halo.z_index < 0, "halo drawn behind Luz")
	check(shaft.material.shader.get_shader_uniform_list().any(func(u: Dictionary) -> bool: return u.name == "mask_strength"), "shaft head mask uniform present")
	var shaft_dormant: float = shaft.get_effective_level()
	var shaft_awakened := 0.0
	var shaft_resting := 0.0
	var mx := await swing_range(3.0)
	check(mx > 0.06 and mx <= 0.105, "dormant pendulum swings (max %.3f rad)" % mx)
	check(sw.get_visible_count() == 7, "dormant: 7 fireflies visible (%d)" % sw.get_visible_count())
	check(papers_home(), "dormant papers at rest")
	# determinism
	var a := FireflySwarm.new()
	var b := FireflySwarm.new()
	root.add_child(a); root.add_child(b)
	a.setup(12345); b.setup(12345)
	for i: int in 200:
		a.step(0.016, i * 0.016, 0.5); b.step(0.016, i * 0.016, 0.5)
	var same := true
	for i: int in 10:
		if a.get_firefly_position(i) != b.get_firefly_position(i): same = false
	check(same, "firefly swarm deterministic for equal seed")
	a.queue_free(); b.queue_free()
	# bounded wander
	var inb := true
	for i: int in 7:
		var p := sw.get_firefly_position(i)
		if p.y < -122.0 or p.y > -8.0 or absf(p.x) > 140.0: inb = false
	check(inb, "wander bounded")
	# first rest
	desk.request_rest()
	check(await wait_phase(3), "CELEBRATE reached")
	await secs(0.15)
	check(halo.fill < 0.5 and halo.intensity > 0.45, "first: halo fill in progress (%.2f)" % halo.fill)
	check(fx.can_process() and sw.can_process() and fx.get_node("PeakBloom").can_process(), "FX process while paused")
	check(halo.can_process() and shaft.can_process() and candelabras[0].can_process(), "rest: halo, shaft, candelabras process while paused")
	check(paused, "tree paused")
	await wait_phase(4)
	await secs(1.2)
	check(absf(fx.get_swing_angle()) < 0.0001, "pendulum still while RESTING (%.5f)" % fx.get_swing_angle())
	check(halo.intensity > 0.6 and halo.warmth > 0.9, "halo lit while resting (%.2f)" % halo.intensity)
	check(halo.fill >= 0.999, "halo fill completed")
	check(halo.breath_weight > 0.9, "halo ticks breathe while resting")
	check(sw.get_visible_count() == 10, "extras present after first celebration (%d)" % sw.get_visible_count())
	check(papers_lifted() > 20.0, "papers orbit while resting (%.1f)" % papers_lifted())
	var nodes: int = fx.get_fx_node_count()
	var budget: int = fx.FX_NODE_BUDGET
	check(nodes == 55, "FX-driven node count is 55 (%d)" % nodes)
	check(nodes <= budget, "FX-driven nodes %d within budget %d" % [nodes, budget])
	var tot := 0
	for n: Sprite2D in fx.find_children("*", "Sprite2D", true, false):
		if n.visible: tot += 1
	check(tot <= budget, "visible FX sprites %d <= %d" % [tot, budget])
	var shaft_lo := 99.0
	var shaft_hi := -99.0
	for i: int in 150:
		await process_frame
		shaft_lo = minf(shaft_lo, shaft.get_effective_level())
		shaft_hi = maxf(shaft_hi, shaft.get_effective_level())
	shaft_resting = shaft_hi
	check(shaft_hi - shaft_lo > 0.15, "shaft breathes while resting (%.2f)" % (shaft_hi - shaft_lo))
	var m2 := 0.0
	for i: int in 120:
		await process_frame
		m2 = maxf(m2, absf(fx.get_swing_angle()))
	check(m2 < 0.0001, "pendulum held still")
	# fallback for dismount: drop finished signal
	player.rest_animation_finished.disconnect(desk._on_rest_animation_finished)
	player.request_jump()
	await frames(2)
	check(desk.get_phase() == 5, "DISMOUNT")
	check(await wait_phase(1, 3.0), "dismount fallback advances without finished signal")
	await frames(3)
	check(not paused and not player.is_meditating(), "unpaused after fallback dismount")
	await secs(1.6)
	check(papers_home(), "papers home ±1px after dismount")
	check(papers_z_home(), "paper z_index restored after dismount")
	check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "halo back to awakened idle (%.2f)" % halo.intensity)
	check(sw.get_visible_count() == 7, "extras gone (%d)" % sw.get_visible_count())
	for i: int in 30:
		await process_frame
		shaft_awakened = maxf(shaft_awakened, shaft.get_effective_level())
	check(shaft_dormant < shaft_awakened and shaft_awakened < shaft_resting, "shaft levels dormant %.2f < awakened %.2f < resting peak %.2f" % [shaft_dormant, shaft_awakened, shaft_resting])
	var m3 := await swing_range(3.0)
	check(m3 > 0.05, "pendulum swinging after dismount (%.3f)" % m3)
	# repeat rest + mount fallback
	await secs(0.5)
	desk.request_rest()
	await frames(2)
	player.rest_animation_finished.disconnect(desk._on_rest_animation_finished)
	check(await wait_phase(3, 3.0), "mount fallback advances without finished signal")
	await frames(3)
	check(halo.fill == 1.0, "repeat: no fill sweep")
	await wait_phase(4)
	await secs(0.5)
	check(sw.get_visible_count() == 7, "repeat: no extras (%d)" % sw.get_visible_count())
	check(absf(fx.get_swing_angle()) < 0.0001, "repeat: pendulum still")
	# breathing: glow alpha varies with period
	var g: Node2D = desk.get_node("Visuals/Glow")
	var lo := 9.0; var hi := -9.0
	var end := Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < end:
		await process_frame
		lo = minf(lo, g.modulate.a); hi = maxf(hi, g.modulate.a)
	check(hi - lo > 0.2, "glow breathes while resting (%.2f)" % (hi - lo))
	# abort mid-rest via respawn-like meditation end
	player.exit_meditation()
	await frames(3)
	check(not paused, "abort unpauses")
	await secs(1.6)
	check(papers_home(), "papers home after abort")
	check(papers_z_home(), "paper z_index restored after abort")
	await run_mount_abort_case()
	cases_done += 1


func run_mount_abort_case() -> void:
	# Abort during MOUNT (before any celebration) must still reset the FX.
	await secs(0.5)
	desk.request_rest()
	await frames(3)
	check(desk.get_phase() == 2, "mount abort: in MOUNT")
	player.exit_meditation()
	await frames(3)
	check(not paused, "mount abort: unpaused")
	await secs(1.6)
	check(fx.intensity <= 0.45, "mount abort: intensity back to idle (%.2f)" % fx.intensity)
	check(papers_home() and papers_z_home(), "mount abort: papers at rest")
	var halo: HaloSigil = fx.get_halo()
	check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "mount abort: halo idle (%.2f)" % halo.intensity)
	var mx := await swing_range(3.0)
	check(mx > 0.05, "mount abort: pendulum swings (%.3f)" % mx)
	cases_done += 1

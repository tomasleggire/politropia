extends SceneTree
## Regression test for the Stillness Desk rest ritual (flow, fallbacks, FX).
## Run: godot --headless --path . --script res://tests/stillness_desk_ritual_test.gd
## Exits 0 when every check passes, 1 otherwise.

const LEVEL := "res://scenes/levels/level_01.tscn"
const DESK_ID := &"level_01_desk_a"
## Total checks a complete run performs; a smaller count means the run aborted.
const EXPECTED_CHECKS := 225
const EXPECTED_CASES := 5

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
var cam: RoomCamera
var shaft_awakened_ref := 0.0
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
	cam = lvl.get_node("RoomCamera")
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


## Samples every frame from the celebration's start until 0.6s into RESTING and
## reports when each beat first showed, so their order can be asserted.
func record_celebration() -> Dictionary:
	var halo: HaloSigil = fx.get_halo()
	var shaft: AltarLightShaft = fx.get_shaft()
	var vig: AltarVignette = fx.get_vignette()
	var wave: AltarShockwave = fx.get_shockwave()
	var sparks: AltarSparks = fx.get_sparks()
	var peaks_before := count_events("peak")
	var starts: Array[Array] = ev.filter(func(e: Array) -> bool: return e[0] == "start")
	var base_ms: int = starts[-1][2]
	var r := {
		"vig_t": -1.0, "fill_t": -1.0, "wave_t": -1.0, "spark_t": -1.0, "peak_t": -1.0,
		"monotonic": true, "max_fill_pre": 0.0, "flare_pre": 0.0, "flare_post": 0.0,
		"wave_pre": false, "sparks_pre": 0, "max_sparks": 0, "max_swell": 0.0, "max_zoom": 1.0,
	}
	var last_fill := 0.0
	var rest_ms := -1
	while true:
		await process_frame
		var t := (Time.get_ticks_msec() - base_ms) / 1000.0
		var peaked := count_events("peak") > peaks_before
		if peaked and r["peak_t"] < 0.0:
			var peaks: Array[Array] = ev.filter(func(e: Array) -> bool: return e[0] == "peak")
			r["peak_t"] = (peaks[-1][1] - base_ms) / 1000.0
		if vig.level > 0.05 and r["vig_t"] < 0.0: r["vig_t"] = t
		if halo.fill > 0.02 and r["fill_t"] < 0.0: r["fill_t"] = t
		if wave.is_active() and r["wave_t"] < 0.0: r["wave_t"] = t
		if sparks.get_live_count() > 0 and r["spark_t"] < 0.0: r["spark_t"] = t
		if not peaked:
			if halo.fill < last_fill - 0.0001: r["monotonic"] = false
			last_fill = halo.fill
			r["max_fill_pre"] = maxf(r["max_fill_pre"], halo.fill)
			r["flare_pre"] = maxf(r["flare_pre"], halo.flare)
			if wave.is_active(): r["wave_pre"] = true
			r["sparks_pre"] = maxi(r["sparks_pre"], sparks.get_live_count())
		else:
			r["flare_post"] = maxf(r["flare_post"], halo.flare)
		r["max_sparks"] = maxi(r["max_sparks"], sparks.get_live_count())
		r["max_swell"] = maxf(r["max_swell"], shaft.swell)
		r["max_zoom"] = maxf(r["max_zoom"], cam.get_zoom_ratio())
		if desk.get_phase() == 4 and rest_ms < 0:
			rest_ms = Time.get_ticks_msec()
		if rest_ms > 0 and Time.get_ticks_msec() - rest_ms > 600:
			break
		if t > 8.0:
			break
	return r


func cam_home() -> bool:
	return absf(cam.get_zoom_ratio() - 1.0) < 0.02 and cam.get_focus_weight() < 0.01


func run() -> void:
	await process_frame
	cps = get_root().get_node("CheckpointService")
	tc = get_root().get_node("TouchControls")
	await run_flow_cases()
	await run_fallback_cases()
	await run_fx_cases()
	await run_trail_cases()
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
	check(absf(dur - 3.0) < 0.25, "rest1 long celebration %.2fs" % dur)
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
	check(st[0][1] == false and absf(dur - 1.0) < 0.25, "rest2 short celebration first=false %.2fs" % dur)
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
	# ---- rest 4: end-to-end touch exit. A real InputEventScreenTouch pressed on
	# the jump button while the tree is paused, through the TouchControls autoload.
	await place()
	var was_visible: bool = tc.visible
	tc.visible = true
	await frames(3)
	check(desk.request_rest(), "rest4 accepted")
	check(await wait_phase(4), "rest4 RESTING")
	await secs(0.6)
	var jump_rect: Rect2 = tc._jump_button.get_global_rect()
	check(paused and jump_rect.size.x > 0.0, "rest4 paused with a laid-out jump button (%s)" % [jump_rect])
	# Input events arrive in window pixels; the stretch transform maps the
	# button's canvas position there (the headless window is only 64x64).
	var window_point: Vector2 = root.get_final_transform() * jump_rect.get_center()
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.position = window_point
	touch_down.pressed = true
	Input.parse_input_event(touch_down)
	await frames(3)
	check(desk.get_phase() == 5, "rest4 real touch on the jump button dismounts (phase %d)" % desk.get_phase())
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.position = window_point
	touch_up.pressed = false
	Input.parse_input_event(touch_up)
	check(await wait_phase(1, 4.0), "rest4 AWAKENED after touch dismount")
	await frames(3)
	check(not paused and not player.is_meditating(), "rest4 control returned")
	tc.visible = was_visible
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
		check(cam_home() and fx.get_vignette().level < 0.01, "respawn@%d camera and vignette reset (zoom %.3f, vig %.2f)" % [target, cam.get_zoom_ratio(), fx.get_vignette().level])
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
	check(fx.can_process() and sw.can_process() and fx.get_node("PeakBloom").can_process(), "FX process while paused")
	check(halo.can_process() and shaft.can_process() and candelabras[0].can_process(), "rest: halo, shaft, candelabras process while paused")
	check(fx.get_vignette().can_process() and fx.get_shockwave().can_process() and fx.get_sparks().can_process(), "vignette, shockwave, sparks process while paused")
	check(paused, "tree paused")
	var beats: Dictionary = await record_celebration()
	check(beats["vig_t"] >= 0.0 and beats["fill_t"] >= 0.0 and beats["vig_t"] < beats["fill_t"], "first: vignette (%.2fs) before halo fill (%.2fs)" % [beats["vig_t"], beats["fill_t"]])
	check(beats["fill_t"] > 0.45, "first: ignition waits for the stillness beat (%.2fs)" % beats["fill_t"])
	check(beats["monotonic"] and beats["max_fill_pre"] > 0.9, "first: halo fill monotonic to ~1 before the peak (max %.2f)" % beats["max_fill_pre"])
	check(beats["peak_t"] > 1.6 and beats["peak_t"] < 2.0, "first: peak at ~1.8s (%.2fs)" % beats["peak_t"])
	check(beats["flare_pre"] < 0.05 and beats["flare_post"] > 0.9, "first: flare only at the peak (pre %.2f post %.2f)" % [beats["flare_pre"], beats["flare_post"]])
	check(not beats["wave_pre"] and beats["wave_t"] >= beats["peak_t"] - 0.05 and beats["wave_t"] < beats["peak_t"] + 0.15, "first: shockwave at the peak (%.2fs vs %.2fs)" % [beats["wave_t"], beats["peak_t"]])
	check(beats["sparks_pre"] == 0 and beats["spark_t"] >= beats["peak_t"] - 0.05 and beats["max_sparks"] >= 12, "first: sparks after the peak (t %.2fs, max %d)" % [beats["spark_t"], beats["max_sparks"]])
	check(beats["max_swell"] > 0.9, "first: shaft swells into a pillar (%.2f)" % beats["max_swell"])
	check(beats["max_zoom"] > 1.2, "first: camera closes in (x%.2f)" % beats["max_zoom"])
	check(cam.get_zoom_ratio() > 1.1 and fx.get_vignette().level > 0.9, "first: camera focused and vignette held while resting (x%.2f, %.2f)" % [cam.get_zoom_ratio(), fx.get_vignette().level])
	check(shaft.swell < 0.05, "first: shaft settled after the release (%.2f)" % shaft.swell)
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
	check(nodes == 80, "FX-driven node count is 80 (%d)" % nodes)
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
	check(cam_home(), "dismount: camera back to the room framing (x%.3f)" % cam.get_zoom_ratio())
	check(fx.get_vignette().level < 0.01 and shaft.swell < 0.01, "dismount: vignette off, shaft swell released")
	check(fx.get_sparks().get_live_count() == 0 and not fx.get_shockwave().is_active(), "dismount: no sparks or shockwave left")
	check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "halo back to awakened idle (%.2f)" % halo.intensity)
	check(sw.get_visible_count() == 7, "extras gone (%d)" % sw.get_visible_count())
	for i: int in 30:
		await process_frame
		shaft_awakened = maxf(shaft_awakened, shaft.get_effective_level())
	shaft_awakened_ref = shaft_awakened
	check(shaft_dormant < shaft_awakened and shaft_awakened < shaft_resting, "shaft levels dormant %.2f < awakened %.2f < resting peak %.2f" % [shaft_dormant, shaft_awakened, shaft_resting])
	var m3 := await swing_range(3.0)
	check(m3 > 0.05, "pendulum swinging after dismount (%.3f)" % m3)
	# repeat rest + mount fallback
	await secs(0.5)
	desk.request_rest()
	await frames(2)
	player.rest_animation_finished.disconnect(desk._on_rest_animation_finished)
	check(await wait_phase(3, 3.0), "mount fallback advances without finished signal")
	var rep: Dictionary = await record_celebration()
	check(rep["vig_t"] >= 0.0 and rep["fill_t"] >= 0.0 and rep["monotonic"] and rep["max_fill_pre"] > 0.9, "repeat: quick monotonic halo fill (max %.2f)" % rep["max_fill_pre"])
	check(rep["wave_t"] < 0.0, "repeat: no shockwave")
	check(rep["max_sparks"] > 0 and rep["max_sparks"] <= 8, "repeat: a few sparks (%d)" % rep["max_sparks"])
	check(rep["peak_t"] > 0.35 and rep["peak_t"] < 0.6, "repeat: peak at ~0.45s (%.2fs)" % rep["peak_t"])
	check(rep["max_zoom"] > 1.1 and rep["max_swell"] < 0.05, "repeat: camera eases in, no pillar (x%.2f, swell %.2f)" % [rep["max_zoom"], rep["max_swell"]])
	check(rep["flare_post"] > 0.3 and rep["flare_post"] < 0.7, "repeat: small flare (%.2f)" % rep["flare_post"])
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
	check(cam_home() and fx.get_vignette().level < 0.01, "abort mid-rest: camera focus popped, vignette off (x%.3f)" % cam.get_zoom_ratio())
	check(fx.get_sparks().get_live_count() == 0 and not fx.get_shockwave().is_active(), "abort mid-rest: no sparks or shockwave")
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
	var shaft: AltarLightShaft = fx.get_shaft()
	check(absf(shaft.level - fx.SHAFT_AWAKENED) < 0.02 and shaft.swell < 0.01, "mount abort: shaft back at the awakened level (%.2f, swell %.2f)" % [shaft.level, shaft.swell])
	check(shaft_awakened_ref > 0.0 and absf(shaft.get_effective_level() - shaft_awakened_ref) < 0.25, "mount abort: shaft effective %.2f near awakened %.2f" % [shaft.get_effective_level(), shaft_awakened_ref])
	var halo: HaloSigil = fx.get_halo()
	check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "mount abort: halo idle (%.2f)" % halo.intensity)
	var mx := await swing_range(3.0)
	check(mx > 0.05, "mount abort: pendulum swings (%.3f)" % mx)
	cases_done += 1


# -- Wayfinding trails -----------------------------------------------------------

func make_trail(scene: PackedScene, seed_value: int, dens: float, branches: int) -> Node2D:
	var t: Node2D = scene.instantiate()
	t.snap_to_ground = false
	t.trail_seed = seed_value
	t.length = 500.0
	t.density = dens
	t.branch_count = branches
	t.position = Vector2(2000.0, 200.0)
	lvl.add_child(t)
	return t


func trail_nodes() -> Array[Node2D]:
	var found: Array[Node2D] = []
	for n: Node in lvl.get_children():
		if n.has_method("fire_outward_pulse") and not n.is_queued_for_deletion():
			found.append(n as Node2D)
	return found


func run_trail_cases() -> void:
	cps.clear()
	await setup_level()
	await place()
	var scene := load("res://scenes/world/altar_trail.tscn") as PackedScene
	var a := make_trail(scene, 5, 1.0, 6)
	var b := make_trail(scene, 5, 1.0, 6)
	var c := make_trail(scene, 6, 1.0, 6)
	var d := make_trail(scene, 9, 2.0, 16)
	await frames(3)
	# determinism and density
	check(a.get_point_count() > 40 and a.get_point_count() == b.get_point_count(), "trail: same seed, same point count (%d, %d)" % [a.get_point_count(), b.get_point_count()])
	check(a.get_first_points(8) == b.get_first_points(8) and a.get_first_points(8).size() == 8, "trail: same seed, same first points")
	check(a.get_point_count() != c.get_point_count() or a.get_first_points(8) != c.get_first_points(8), "trail: another seed builds another trail")
	var points_before: PackedVector2Array = a.get_first_points(10000)
	a.rebuild()
	check(a.get_first_points(10000) == points_before, "trail: rebuild is idempotent")
	var near: float = a.get_coverage_weight(0.92)
	var far: float = a.get_coverage_weight(0.08)
	check(near > far * 2.0 and far > 0.0, "trail: density grows toward the altar (far %.1f, near %.1f)" % [far, near])
	check(a.get_strand_count_at(0.92) > a.get_strand_count_at(0.08), "trail: more strands near the altar (%d vs %d)" % [a.get_strand_count_at(0.92), a.get_strand_count_at(0.08)])
	check(a.get_strand_count() <= 24 and d.get_strand_count() <= 24 and d.get_strand_count() > a.get_strand_count() and a.get_render_node_count() == 1, "trail: strands bounded, one canvas node (%d, max config %d)" % [a.get_strand_count(), d.get_strand_count()])
	check(not a.get_pulse_material().shader.code.is_empty() and a.get_pulse_material().get_shader_parameter(&"path_length") >= 500.0, "trail: pulse shader configured")
	# pulses advance while the tree is paused
	var clock0: float = a.get_pulse_clock()
	paused = true
	check(a.can_process() and a.get_swarm().can_process(), "trail: processes while paused")
	await frames(20)
	paused = false
	var clock1: float = a.get_pulse_clock()
	var uniform1: float = a.get_pulse_material().get_shader_parameter(&"pulse_clock")
	check(clock1 - clock0 > 0.1 and absf(uniform1 - clock1) < 0.1, "trail: pulse clock advances while paused (%.2f -> %.2f, uniform %.2f)" % [clock0, clock1, uniform1])
	for t: Node2D in [a, b, c, d]:
		t.queue_free()
	# level placement
	var trails := trail_nodes()
	check(trails.size() >= 2, "level_01 has %d trails" % trails.size())
	var linked := 0
	for t: Node2D in trails:
		if not t.desk_path.is_empty() and t.get_node(t.desk_path) == desk:
			linked += 1
	check(linked >= 2, "level_01: %d trails linked to the desk" % linked)
	var right: Node2D = lvl.get_node("TrailFromRight")
	var left: Node2D = lvl.get_node("TrailFromLeft")
	check(right.direction == -1 and right.global_position.x > desk.global_position.x, "right trail leads left to the desk")
	check(left.direction == 1 and left.global_position.x < desk.global_position.x, "left trail leads right to the desk")
	check(not right.show_roots and not left.show_roots and right.get_canvas_sprite() == null and left.get_canvas_sprite() == null, "level trails hide their roots: no canvas built")
	# roots geometry, checked on a visible trail placed like the right one
	var probe := make_trail(scene, 7, 1.0, 14)
	probe.snap_to_ground = true
	probe.set_physics_process(true)
	probe.position = right.position
	probe.direction = -1
	probe.length = 586.0
	await frames(8)
	var roots_l: Node2D = desk.get_node("Visuals/Roots/RootsLeft")
	var roots_r: Node2D = desk.get_node("Visuals/Roots/RootsRight")
	var on_floor := true
	var y_lo := 9999.0
	var y_hi := -9999.0
	var worst_gap := 0.0
	for t: Node2D in [probe, roots_l, roots_r]:
		var pts: PackedVector2Array = t.get_all_points()
		for i: int in range(0, pts.size(), 7):
			var y: float = t.to_global(pts[i]).y
			y_lo = minf(y_lo, y)
			y_hi = maxf(y_hi, y)
			if y < 470.0 or y > 640.0:
				on_floor = false
			worst_gap = maxf(worst_gap, t.distance_to_surface_texels(pts[i]))
	check(on_floor, "trail strands stay within the floor band (y %.0f..%.0f)" % [y_lo, y_hi])
	check(worst_gap <= 14.0 and probe.get_max_offset_texels() <= 12, "strands creep on the surface: worst gap %.1f texels, max offset %d" % [worst_gap, probe.get_max_offset_texels()])
	check(probe.get_ground_offset(-250.0) < -40.0 and roots_l.get_max_offset_texels() <= 12, "probed trail climbs the step; desk roots stay flat")
	probe.queue_free()
	var space: PhysicsDirectSpaceState2D = lvl.get_world_2d().direct_space_state
	var surface_err := 0.0
	for lx: float in [-450.0, -300.0, -100.0]:
		var query := PhysicsRayQueryParameters2D.create(Vector2(right.global_position.x + lx, right.global_position.y - 160.0), Vector2(right.global_position.x + lx, right.global_position.y + 200.0), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			surface_err = 99.0
		else:
			var hy: float = hit["position"].y - right.global_position.y
			surface_err = maxf(surface_err, absf(hy - right.get_surface_offset(lx)))
	check(surface_err <= 1.5, "surface profile matches the physics floor and steps (err %.2f)" % surface_err)
	check(right.get_ground_offset(-250.0) < -40.0, "right trail climbs the step it crosses (%.1f)" % right.get_ground_offset(-250.0))
	var swarm: FireflySwarm = right.get_swarm()
	check(swarm.base_active == right.firefly_count and right.firefly_count >= 10 and swarm.field_span == right.length and swarm.flow_span == 0.0, "trail fireflies are a hint field, not a flow (%d)" % right.firefly_count)
	await frames(20)
	check(swarm.get_visible_count() >= 6, "trail fireflies visible (%d)" % swarm.get_visible_count())
	var near_count := 0
	var far_count := 0
	var in_band := true
	for i: int in swarm.base_active:
		var home: Vector2 = swarm.get_home_position(i)
		var along: float = absf(home.x) / float(right.length)
		if along > 2.0 / 3.0:
			near_count += 1
		elif along < 1.0 / 3.0:
			far_count += 1
		if home.y < -80.5 or home.y > -9.5:
			in_band = false
	check(near_count > far_count and far_count >= 1, "fireflies thicken toward the altar (far third %d, near third %d)" % [far_count, near_count])
	check(in_band, "fireflies live in the air band 10 to 80 units up")
	var start_x := PackedFloat32Array()
	for i: int in swarm.base_active:
		start_x.append(swarm.get_firefly_position(i).x)
	await secs(3.0)
	var toward := 0
	var away := 0
	for i: int in swarm.base_active:
		var moved := (swarm.get_firefly_position(i).x - start_x[i]) * float(right.direction)
		if moved > 0.5:
			toward += 1
		elif moved < -0.5:
			away += 1
	check(toward >= 1 and away >= 1, "firefly drift is mixed, not a flow to the altar (toward %d, away %d)" % [toward, away])
	# roots off: nothing built, pulses still tick
	var hidden := make_trail(scene, 3, 1.0, 6)
	hidden.show_roots = false
	await frames(3)
	check(hidden.get_canvas_sprite() == null and hidden.get_strand_count() == 0 and hidden.get_render_node_count() == 0, "show_roots off: no canvas, no strands")
	var hidden_clock: float = hidden.get_pulse_clock()
	hidden.fire_outward_pulse()
	await frames(10)
	check(hidden.get_pulse_clock() > hidden_clock and hidden.get_outward_count() == 1, "show_roots off: pulse logic keeps running")
	hidden.queue_free()
	check(roots_l.show_roots and roots_l.get_canvas_sprite() != null and roots_l.get_canvas_sprite().visible and roots_l.root_alpha < 0.8 and not roots_l.snap_to_ground, "desk roots stay visible, subtler and grounded under the desk")
	# the altar's roots are the same procedural system
	var roots_left: Node2D = desk.get_node("Visuals/Roots/RootsLeft")
	var roots_right: Node2D = desk.get_node("Visuals/Roots/RootsRight")
	check(roots_left.has_method("get_coverage_weight") and roots_right.has_method("get_coverage_weight"), "desk roots are AltarTrail")
	check(not desk.has_node("Visuals/Roots/RootLeft") and not desk.has_node("Visuals/Roots/RootRight"), "interim root sprites removed")
	var uses_png := false
	for sprite: Sprite2D in desk.find_children("*", "Sprite2D", true, false):
		if sprite.texture != null and sprite.texture.resource_path.contains("roots_"):
			uses_png = true
	check(not uses_png, "no desk sprite uses the interim roots PNGs")
	check(roots_left.get_strand_count() > 3 and roots_left.get_strand_count() <= 24 and roots_right.get_strand_count() <= 24 and roots_left.get_render_node_count() == 1, "desk roots: %d strands, bounded" % roots_left.get_strand_count())
	var plug_left: float = roots_left.to_global(roots_left.get_first_points(10000)[-1]).x
	var plug_right: float = roots_right.to_global(roots_right.get_first_points(10000)[-1]).x
	check(absf(plug_left - desk.global_position.x) < 30.0 and absf(plug_right - desk.global_position.x) < 30.0, "desk roots plug into the desk legs (%.1f, %.1f)" % [plug_left - desk.global_position.x, plug_right - desk.global_position.x])
	check(roots_left.desk_path == NodePath("../../..") and roots_left.get_node(roots_left.desk_path) == desk, "desk roots linked to their desk")
	# celebration peak sends the outward pulse along every linked strand
	var rate_idle: float = right.get_pulse_rate()
	check(rate_idle < 1.05 and not right.is_outward_active(), "dormant trail: base rate (%.2f), no outward pulse" % rate_idle)
	var linked_trails: Array[Node2D] = [right, left, roots_left, roots_right]
	var counts: Array[int] = []
	for t: Node2D in linked_trails:
		counts.append(t.get_outward_count())
	desk.request_rest()
	check(await wait_phase(3), "trail case: CELEBRATE reached")
	var peaks_before := count_events("peak")
	var waited := 0
	while count_events("peak") == peaks_before and waited < 600:
		await process_frame
		waited += 1
	await frames(3)
	var all_fired := true
	for i: int in linked_trails.size():
		if linked_trails[i].get_outward_count() != counts[i] + 1:
			all_fired = false
	check(all_fired, "celebration_peak fires one outward pulse on every linked trail")
	var material: ShaderMaterial = right.get_pulse_material()
	check(right.is_outward_active() and float(material.get_shader_parameter(&"burst_strength")) > 0.3, "outward pulse visible at the peak (strength %.2f)" % float(material.get_shader_parameter(&"burst_strength")))
	check(paused and right.can_process(), "outward pulse runs while paused")
	await secs(3.2)
	check(not right.is_outward_active() and float(material.get_shader_parameter(&"burst_strength")) == 0.0, "outward pulse finishes on its own")
	check(right.get_pulse_rate() > 1.3 and float(material.get_shader_parameter(&"warmth")) > 0.6, "awakened desk: trail pulses faster and warmer (%.2f)" % right.get_pulse_rate())
	player.exit_meditation()
	await frames(3)
	check(not paused, "trail case: abort unpauses")
	cases_done += 1

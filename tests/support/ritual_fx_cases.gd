extends "res://tests/support/ritual_suite.gd"
## FX layer: idle look, staged celebration, resting look, dismount and aborts.

const Recorder := preload("res://tests/support/ritual_celebration_recorder.gd")

const CHECKS := {
	"case_fx_dormant_baseline": 11,
	"case_firefly_determinism": 1,
	"case_first_ritual": 39,
	"case_dismount_without_finished_signal": 12,
	"case_repeat_celebration_beats": 10,
	"case_abort_mid_rest": 8,
	"case_mount_abort": 8,
}

var _shaft_dormant := 0.0
var _shaft_resting := 0.0


func expected_checks() -> Dictionary:
	return CHECKS


# -- Dormant altar ---------------------------------------------------------------

func case_fx_dormant_baseline() -> void:
	await h.fresh_level()
	_check_dormant_look()
	_check_paused_processing()
	await _check_dormant_motion()


func _check_dormant_look() -> void:
	var halo: HaloSigil = h.fx.get_halo()
	h.check(halo.fill == 0.0 and halo.flare == 0.0, "dormant halo unfilled (fill %.2f)" % halo.fill)
	h.check(halo.intensity > 0.2, "dormant halo faintly engraved (%.2f)" % halo.intensity)
	h.check(not h.desk.has_node("Visuals/FloorRingLit"), "floor ring nodes removed")
	h.check(halo.get_parent().z_index + halo.z_index < 0, "halo drawn behind Luz")


func _check_paused_processing() -> void:
	var halo: HaloSigil = h.fx.get_halo()
	var shaft: AltarLightShaft = h.fx.get_shaft()
	var left: GothicCandle = h.desk.get_node("Visuals/CandelabraLeft")
	var right: GothicCandle = h.desk.get_node("Visuals/CandelabraRight")
	h.check(halo.can_process() and shaft.can_process(), "halo and shaft process while paused")
	h.check(left.can_process() and right.can_process() and left.candelabra, "candelabras exist and process while paused")
	var uniforms: Array = shaft.material.shader.get_shader_uniform_list()
	h.check(uniforms.any(func(u: Dictionary) -> bool: return u.name == "mask_strength"), "shaft head mask uniform present")


func _check_dormant_motion() -> void:
	var swarm: FireflySwarm = h.fx.get_node("Fireflies")
	var mx: float = await h.swing_range(3.0)
	h.check(mx > 0.06 and mx <= 0.105, "dormant pendulum swings (max %.3f rad)" % mx)
	h.check(swarm.get_visible_count() == 7, "dormant: 7 fireflies visible (%d)" % swarm.get_visible_count())
	h.check(h.papers_home(), "dormant papers at rest")
	var inb := true
	for i: int in 7:
		var p := swarm.get_firefly_position(i)
		if p.y < -122.0 or p.y > -8.0 or absf(p.x) > 140.0:
			inb = false
	h.check(inb, "wander bounded")


func case_firefly_determinism() -> void:
	var a := FireflySwarm.new()
	var b := FireflySwarm.new()
	h.tree.root.add_child(a)
	h.tree.root.add_child(b)
	a.setup(12345)
	b.setup(12345)
	for i: int in 200:
		a.step(0.016, i * 0.016, 0.5)
		b.step(0.016, i * 0.016, 0.5)
	var same := true
	for i: int in 10:
		if a.get_firefly_position(i) != b.get_firefly_position(i):
			same = false
	h.check(same, "firefly swarm deterministic for equal seed")
	a.queue_free()
	b.queue_free()


# -- First ritual: celebration, resting look, normal dismount ----------------------

func case_first_ritual() -> void:
	await h.fresh_level()
	_shaft_dormant = h.fx.get_shaft().get_effective_level()
	h.desk.request_rest()
	h.check(await h.wait_phase(h.PHASE_CELEBRATE), "CELEBRATE reached")
	_check_fx_process_while_paused()
	var beats := Recorder.new(h)
	await beats.run()
	_check_first_stillness_and_ignition(beats)
	_check_first_peak_and_release(beats)
	_check_first_camera_and_settle(beats)
	await _check_first_resting_look()
	await _check_shaft_and_pendulum_while_resting()
	await _dismount_normally()
	await _check_first_shaft_levels_and_pendulum()


func _check_fx_process_while_paused() -> void:
	var left: GothicCandle = h.desk.get_node("Visuals/CandelabraLeft")
	h.check(h.fx.can_process() and h.fx.get_node("Fireflies").can_process() and h.fx.get_node("PeakBloom").can_process(), "FX process while paused")
	h.check(h.fx.get_halo().can_process() and h.fx.get_shaft().can_process() and left.can_process(), "rest: halo, shaft, candelabras process while paused")
	h.check(h.fx.get_vignette().can_process() and h.fx.get_shockwave().can_process() and h.fx.get_sparks().can_process(), "vignette, shockwave, sparks process while paused")
	h.check(h.tree.paused, "tree paused")


func _check_first_stillness_and_ignition(b: Recorder) -> void:
	h.check(b.vig_t >= 0.0 and b.fill_t >= 0.0 and b.vig_t < b.fill_t, "first: vignette (%.2fs) before halo fill (%.2fs)" % [b.vig_t, b.fill_t])
	h.check(b.fill_t > 0.45, "first: ignition waits for the stillness beat (%.2fs)" % b.fill_t)
	h.check(b.monotonic and b.max_fill_pre > 0.9, "first: halo fill monotonic to ~1 before the peak (max %.2f)" % b.max_fill_pre)
	h.check(absf(b.peak_t - 1.8) < h.slack(0.2), "first: peak at ~1.8s (%.2fs)" % b.peak_t)
	h.check(b.flare_pre < 0.05 and b.flare_post > 0.9, "first: flare only at the peak (pre %.2f post %.2f)" % [b.flare_pre, b.flare_post])


func _check_first_peak_and_release(b: Recorder) -> void:
	var wave_ok: bool = not b.wave_pre and b.wave_t >= b.peak_t - 0.05 and b.wave_t < b.peak_t + h.slack(0.15)
	h.check(wave_ok, "first: shockwave at the peak (%.2fs vs %.2fs)" % [b.wave_t, b.peak_t])
	var sparks_ok: bool = b.sparks_pre == 0 and b.spark_t >= b.peak_t - 0.05 and b.max_sparks >= 12
	h.check(sparks_ok, "first: sparks after the peak (t %.2fs, max %d)" % [b.spark_t, b.max_sparks])
	h.check(b.max_swell > 0.9, "first: shaft swells into a pillar (%.2f)" % b.max_swell)


func _check_first_camera_and_settle(b: Recorder) -> void:
	var vig: AltarVignette = h.fx.get_vignette()
	h.check(b.max_zoom > 1.2, "first: camera closes in (x%.2f)" % b.max_zoom)
	h.check(h.cam.get_zoom_ratio() > 1.1 and vig.level > 0.9, "first: camera focused and vignette held while resting (x%.2f, %.2f)" % [h.cam.get_zoom_ratio(), vig.level])
	h.check(h.fx.get_shaft().swell < 0.05, "first: shaft settled after the release (%.2f)" % h.fx.get_shaft().swell)


func _check_first_resting_look() -> void:
	var halo: HaloSigil = h.fx.get_halo()
	var swarm: FireflySwarm = h.fx.get_node("Fireflies")
	await h.wait_phase(h.PHASE_RESTING)
	await h.secs(1.2)
	h.check(absf(h.fx.get_swing_angle()) < 0.0001, "pendulum still while RESTING (%.5f)" % h.fx.get_swing_angle())
	h.check(halo.intensity > 0.6 and halo.warmth > 0.9, "halo lit while resting (%.2f)" % halo.intensity)
	h.check(halo.fill >= 0.999, "halo fill completed")
	h.check(halo.breath_weight > 0.9, "halo ticks breathe while resting")
	h.check(swarm.get_visible_count() == 10, "extras present after first celebration (%d)" % swarm.get_visible_count())
	h.check(h.papers_lifted() > 20.0, "papers orbit while resting (%.1f)" % h.papers_lifted())
	_check_node_budget()


func _check_node_budget() -> void:
	var nodes: int = h.fx.get_fx_node_count()
	var budget: int = h.fx.FX_NODE_BUDGET
	h.check(nodes == 80, "FX-driven node count is 80 (%d)" % nodes)
	h.check(nodes <= budget, "FX-driven nodes %d within budget %d" % [nodes, budget])
	var visible_sprites := 0
	for sprite: Sprite2D in h.fx.find_children("*", "Sprite2D", true, false):
		if sprite.visible:
			visible_sprites += 1
	h.check(visible_sprites <= budget, "visible FX sprites %d <= %d" % [visible_sprites, budget])


## Two full breaths of the rest loop cover the shaft's whole swing.
func _check_shaft_and_pendulum_while_resting() -> void:
	var shaft: AltarLightShaft = h.fx.get_shaft()
	var lo := 99.0
	var hi := -99.0
	var end := h.clock + 2.5
	while h.clock < end:
		await h.tree.process_frame
		lo = minf(lo, shaft.get_effective_level())
		hi = maxf(hi, shaft.get_effective_level())
	_shaft_resting = hi
	h.check(hi - lo > 0.15, "shaft breathes while resting (%.2f)" % (hi - lo))
	var held: float = await h.swing_range(1.0)
	h.check(held < 0.0001, "pendulum held still")


func _dismount_normally() -> void:
	h.player.request_jump()
	await h.frames(2)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "DISMOUNT")
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "dismount reaches AWAKENED")
	await h.frames(3)
	h.check(not h.tree.paused and not h.player.is_meditating(), "unpaused after dismount")
	await h.secs(1.6)
	_check_idle_after_dismount()


func _check_first_shaft_levels_and_pendulum() -> void:
	var shaft: AltarLightShaft = h.fx.get_shaft()
	var awakened := -99.0
	var end := h.clock + 0.5
	while h.clock < end:
		await h.tree.process_frame
		awakened = maxf(awakened, shaft.get_effective_level())
	h.check(_shaft_dormant < awakened and awakened < _shaft_resting, "shaft levels dormant %.2f < awakened %.2f < resting peak %.2f" % [_shaft_dormant, awakened, _shaft_resting])
	var resumed: float = await h.swing_range(3.0)
	h.check(resumed > 0.05, "pendulum swinging after dismount (%.3f)" % resumed)


## Shared by every dismount case: everything ritual-only is back to idle.
func _check_idle_after_dismount() -> void:
	var halo: HaloSigil = h.fx.get_halo()
	var swarm: FireflySwarm = h.fx.get_node("Fireflies")
	h.check(h.papers_home(), "papers home ±1px after dismount")
	h.check(h.papers_z_home(), "paper z_index restored after dismount")
	h.check(h.cam_home(), "dismount: camera back to the room framing (x%.3f)" % h.cam.get_zoom_ratio())
	h.check(h.fx.get_vignette().level < 0.01 and h.fx.get_shaft().swell < 0.01, "dismount: vignette off, shaft swell released")
	h.check(h.fx.get_sparks().get_live_count() == 0 and not h.fx.get_shockwave().is_active(), "dismount: no sparks or shockwave left")
	h.check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "halo back to awakened idle (%.2f)" % halo.intensity)
	h.check(swarm.get_visible_count() == 7, "extras gone (%d)" % swarm.get_visible_count())


# -- Dismount without the clip's finished signal ------------------------------------

func case_dismount_without_finished_signal() -> void:
	await h.fresh_level()
	await h.awaken()
	h.check(h.desk.request_rest(), "dismount fallback: rest accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "dismount fallback: RESTING")
	await h.secs(0.6)
	h.player.rest_animation_finished.disconnect(h.desk._on_rest_animation_finished)
	h.player.request_jump()
	await h.frames(2)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "DISMOUNT (no finished signal)")
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 3.0), "dismount fallback advances without finished signal")
	await h.frames(3)
	h.check(not h.tree.paused and not h.player.is_meditating(), "unpaused after fallback dismount")
	await h.secs(1.6)
	_check_idle_after_dismount()


# -- Repeat celebration -------------------------------------------------------------

func case_repeat_celebration_beats() -> void:
	await h.fresh_level()
	await h.awaken()
	await h.secs(0.5)
	h.desk.request_rest()
	await h.frames(2)
	h.player.rest_animation_finished.disconnect(h.desk._on_rest_animation_finished)
	h.check(await h.wait_phase(h.PHASE_CELEBRATE, 3.0), "mount fallback advances without finished signal")
	var beats := Recorder.new(h)
	await beats.run()
	_check_repeat_beats(beats)
	await h.wait_phase(h.PHASE_RESTING)
	await h.secs(0.5)
	_check_repeat_resting_look()
	await _check_glow_breathes()


func _check_repeat_beats(b: Recorder) -> void:
	h.check(b.vig_t >= 0.0 and b.fill_t >= 0.0 and b.monotonic and b.max_fill_pre > 0.9, "repeat: quick monotonic halo fill (max %.2f)" % b.max_fill_pre)
	h.check(b.wave_t < 0.0, "repeat: no shockwave")
	h.check(b.max_sparks > 0 and b.max_sparks <= 8, "repeat: a few sparks (%d)" % b.max_sparks)
	h.check(absf(b.peak_t - 0.45) < h.slack(0.1), "repeat: peak at ~0.45s (%.2fs)" % b.peak_t)
	h.check(b.max_zoom > 1.1 and b.max_swell < 0.05, "repeat: camera eases in, no pillar (x%.2f, swell %.2f)" % [b.max_zoom, b.max_swell])
	h.check(b.flare_post > 0.3 and b.flare_post < 0.7, "repeat: small flare (%.2f)" % b.flare_post)


func _check_repeat_resting_look() -> void:
	var swarm: FireflySwarm = h.fx.get_node("Fireflies")
	h.check(swarm.get_visible_count() == 7, "repeat: no extras (%d)" % swarm.get_visible_count())
	h.check(absf(h.fx.get_swing_angle()) < 0.0001, "repeat: pendulum still")


## The glow's alpha follows the breath, so one full period must show a swing.
func _check_glow_breathes() -> void:
	var glow: Node2D = h.desk.get_node("Visuals/Glow")
	var lo := 9.0
	var hi := -9.0
	var end := h.clock + 2.2
	while h.clock < end:
		await h.tree.process_frame
		lo = minf(lo, glow.modulate.a)
		hi = maxf(hi, glow.modulate.a)
	h.check(hi - lo > 0.2, "glow breathes while resting (%.2f)" % (hi - lo))


# -- Aborts ---------------------------------------------------------------------

func case_abort_mid_rest() -> void:
	await h.fresh_level()
	await h.awaken()
	h.check(h.desk.request_rest(), "abort mid-rest: rest accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "abort mid-rest: RESTING")
	await h.secs(0.5)
	h.check(h.cam.get_zoom_ratio() > 1.05, "abort mid-rest: camera was focused (x%.2f)" % h.cam.get_zoom_ratio())
	h.player.exit_meditation()
	await h.frames(3)
	_check_abort_cut()
	await h.secs(1.6)
	h.check(h.papers_home(), "papers home after abort")
	h.check(h.papers_z_home(), "paper z_index restored after abort")


func _check_abort_cut() -> void:
	h.check(not h.tree.paused, "abort unpauses")
	h.check(h.cam_home() and h.fx.get_vignette().level < 0.01, "abort mid-rest: camera focus popped, vignette off (x%.3f)" % h.cam.get_zoom_ratio())
	h.check(h.fx.get_sparks().get_live_count() == 0 and not h.fx.get_shockwave().is_active(), "abort mid-rest: no sparks or shockwave")


## Abort during MOUNT (before any celebration) must still reset the FX.
func case_mount_abort() -> void:
	await h.fresh_level()
	await h.awaken()
	await h.secs(1.6)
	var envelope := await _idle_shaft_envelope()
	h.desk.request_rest()
	await h.frames(3)
	h.check(h.desk.get_phase() == h.PHASE_MOUNT, "mount abort: in MOUNT")
	h.player.exit_meditation()
	await h.frames(3)
	h.check(not h.tree.paused, "mount abort: unpaused")
	await h.secs(1.6)
	_check_mount_abort_idle(envelope)
	var mx: float = await h.swing_range(3.0)
	h.check(mx > 0.05, "mount abort: pendulum swings (%.3f)" % mx)


## Lowest and highest effective shaft level over one full idle breath.
func _idle_shaft_envelope() -> Vector2:
	var shaft: AltarLightShaft = h.fx.get_shaft()
	var envelope := Vector2(99.0, -99.0)
	var end := h.clock + 4.2
	while h.clock < end:
		await h.tree.process_frame
		envelope.x = minf(envelope.x, shaft.get_effective_level())
		envelope.y = maxf(envelope.y, shaft.get_effective_level())
	return envelope


func _check_mount_abort_idle(envelope: Vector2) -> void:
	var shaft: AltarLightShaft = h.fx.get_shaft()
	var halo: HaloSigil = h.fx.get_halo()
	h.check(h.fx.intensity <= 0.45, "mount abort: intensity back to idle (%.2f)" % h.fx.intensity)
	h.check(h.papers_home() and h.papers_z_home(), "mount abort: papers at rest")
	h.check(absf(shaft.level - h.fx.SHAFT_AWAKENED) < 0.02 and shaft.swell < 0.01, "mount abort: shaft back at the awakened level (%.2f, swell %.2f)" % [shaft.level, shaft.swell])
	var effective := shaft.get_effective_level()
	h.check(effective > envelope.x - 0.1 and effective < envelope.y + 0.1, "mount abort: shaft effective %.2f inside the idle range %.2f..%.2f" % [effective, envelope.x, envelope.y])
	h.check(halo.flare < 0.01 and absf(halo.intensity - halo.awakened_level) < 0.05, "mount abort: halo idle (%.2f)" % halo.intensity)

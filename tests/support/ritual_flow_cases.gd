extends "res://tests/support/ritual_suite.gd"
## Ritual flow: input, clip order, effect timing, fallbacks and aborts.

const CHECKS := {
	"case_first_rest": 29,
	"case_repeat_rest": 9,
	"case_keyboard_exit": 4,
	"case_touch_exit_end_to_end": 6,
	"case_movement_after_rest": 5,
	"case_respawn_at_mount": 10,
	"case_respawn_at_celebrate": 10,
	"case_respawn_at_resting": 10,
	"case_respawn_at_dismount": 11,
	"case_player_freed_mid_rest": 4,
	"case_desk_freed_mid_celebration": 7,
	"case_desk_freed_mid_rest": 7,
	"case_early_awakened_keeps_eases": 5,
	"case_scene_reload_returns_to_desk": 3,
	"case_clip_fallback_no_double_advance": 8,
}


func expected_checks() -> Dictionary:
	return CHECKS


# -- First rest: held key, first celebration, touch jump exit ---------------------

func case_first_rest() -> void:
	h.cps.clear()
	h.check(not h.cps.was_ever_activated(h.DESK_ID), "service: not activated initially")
	await h.fresh_level()
	_check_initial_state()
	await _start_first_rest_with_held_key()
	await _sit_without_input()
	await _dismount_by_touch_jump()
	_check_first_rest_flow()
	_check_first_rest_events()


func _check_initial_state() -> void:
	h.check(h.desk.can_rest(), "can_rest at desk")
	h.check(h.desk.get_phase() == h.PHASE_DORMANT, "starts DORMANT")
	h.check(h.desk.get_spawn_position().is_equal_approx(h.desk.global_position), "anchor at desk centre")


func _start_first_rest_with_held_key() -> void:
	h.player._health = 1
	h.player._facing = -1
	Input.action_press("move_right")
	h.clear_records()
	h.check(h.desk.request_rest(), "rest1 accepted")
	await h.frames(3)
	h.check(h.tree.paused and h.player.is_meditating(), "rest1 paused+meditating")
	h.check(not h.player._sprite.flip_h, "rest1 faces right")
	h.check(not h.tc._interact_button.visible, "rest1 touch button hidden")
	h.check(absf(h.player.global_position.x - h.desk.global_position.x) < 1.0, "rest1 snapped to desk centre")
	h.check(await h.wait_phase(h.PHASE_RESTING), "rest1 reaches RESTING")
	h.check(h.tree.paused, "rest1 still paused in RESTING")
	await h.secs(1.0)
	h.check(h.desk.get_phase() == h.PHASE_RESTING, "rest1 held key does NOT dismount")
	Input.action_release("move_right")


func _sit_without_input() -> void:
	await h.secs(4.5)
	h.check(h.desk.get_phase() == h.PHASE_RESTING and h.tree.paused and h.player.is_meditating(), "rest1 seated >=5s with no input")
	h.check(h.player._sprite.animation == &"rest_sit" and h.player._sprite.is_playing(), "rest1 rest_sit looping")
	h.check(absf(h.desk.breath_period - 2.0) < 0.01, "breath_period 2.0 (%f)" % h.desk.breath_period)
	# The real touch path runs through the TouchControls autoload, which must
	# keep receiving input while the tree is paused for the rest.
	h.check(h.tc.can_process(), "rest1 touch controls process while paused")


func _dismount_by_touch_jump() -> void:
	h.player.request_jump()
	await h.frames(2)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "rest1 touch request_jump dismounts")
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "rest1 back to AWAKENED")
	await h.frames(3)
	h.check(not h.tree.paused and not h.player.is_meditating(), "rest1 unpaused, control returned")


func _check_first_rest_flow() -> void:
	h.check(h.phases == [2, 3, 4, 5, 1], "rest1 phase order %s" % [h.phases])
	var seq := _clip_sequence()
	h.check(seq == [&"rest_mount", &"rest_sit", &"rest_dismount"], "rest1 clips order %s" % [seq])
	var bad := _backpack_mismatches()
	h.check(bad == 0, "rest1 backpack visible exactly mount f3..dismount f4 (bad=%d of %d)" % [bad, h.trace.size()])


func _check_first_rest_events() -> void:
	var st := h.events_of("start")
	var pk := h.events_of("peak")
	var fin := h.events_of("finish")
	h.check(st.size() == 1 and st[0]["first"] == true, "rest1 celebration first=true")
	h.check(pk.size() == 1 and fin.size() == 1, "rest1 one peak, one finish")
	h.check(st[0]["n"] == 0 and st[0]["acts"] == 0, "rest1 nothing applied at start")
	h.check(pk[0]["n"] == 1 and pk[0]["acts"] == 1 and pk[0]["health"] == h.player.max_health, "rest1 heal/reset/activate at peak once")
	var dur: float = fin[0]["t"] - st[0]["t"]
	h.check(absf(dur - 3.0) < h.slack(0.25), "rest1 long celebration %.2fs" % dur)
	h.check(h.dummy.n == 1 and h.acts == 1, "rest1 reset/activate exactly once total")
	h.check(h.cps.was_ever_activated(h.DESK_ID), "service records activation")


func _clip_sequence() -> Array[StringName]:
	var seq: Array[StringName] = []
	for sample: Array in h.trace:
		if seq.is_empty() or seq[-1] != sample[0]:
			seq.append(sample[0])
	return seq


func _backpack_mismatches() -> int:
	var bad := 0
	for sample: Array in h.trace:
		var want: bool = (sample[0] == &"rest_mount" and sample[1] >= 3) or sample[0] == &"rest_sit" or (sample[0] == &"rest_dismount" and sample[1] < 4)
		if want != sample[2]:
			bad += 1
	return bad


# -- Repeat rest: grace window, fresh action press --------------------------------

func case_repeat_rest() -> void:
	await h.fresh_level()
	await h.awaken()
	h.player._health = 1
	h.check(h.desk.request_rest(), "rest2 accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "rest2 RESTING")
	await _probe_grace_then_attack_exit()
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "rest2 AWAKENED")
	await h.frames(3)
	h.check(not h.tree.paused and not h.player.is_meditating(), "rest2 released")
	_check_repeat_events()


func _probe_grace_then_attack_exit() -> void:
	await h.secs(0.1)
	Input.action_press("move_left")
	await h.frames(2)
	Input.action_release("move_left")
	await h.frames(2)
	h.check(h.desk.get_phase() == h.PHASE_RESTING, "rest2 input inside grace ignored")
	await h.secs(0.6)
	h.press_action("attack")
	await h.frames(3)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "rest2 fresh attack press dismounts")
	Input.action_release("attack")


func _check_repeat_events() -> void:
	var st := h.events_of("start")
	var fin := h.events_of("finish")
	var dur: float = fin[0]["t"] - st[0]["t"]
	h.check(st[0]["first"] == false and absf(dur - 1.0) < h.slack(0.25), "rest2 short celebration first=false %.2fs" % dur)
	h.check(h.dummy.n == 1 and h.acts == 1 and h.count_events("peak") == 1, "rest2 reset/activate once")
	var bad := _backpack_mismatches()
	h.check(bad == 0, "rest2 backpack timing (bad=%d)" % bad)


# -- Exit inputs ------------------------------------------------------------------

func case_keyboard_exit() -> void:
	await h.fresh_level()
	await h.awaken()
	h.check(h.desk.request_interact(), "rest3 accepted via request_interact")
	h.check(await h.wait_phase(h.PHASE_RESTING), "rest3 RESTING")
	await h.secs(0.5)
	h.key_event(KEY_D, true)
	await h.frames(3)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "rest3 keyboard D press dismounts (phase %d)" % h.desk.get_phase())
	h.key_event(KEY_D, false)
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "rest3 AWAKENED")


## A real InputEventScreenTouch on the jump button while the tree is paused,
## through the TouchControls autoload.
func case_touch_exit_end_to_end() -> void:
	await h.fresh_level()
	await h.awaken()
	var was_visible: bool = h.tc.visible
	h.tc.visible = true
	await h.frames(3)
	h.check(h.desk.request_rest(), "rest4 accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "rest4 RESTING")
	await h.secs(0.6)
	var point := _jump_button_window_point()
	h.touch_event(point, true)
	await h.frames(3)
	h.check(h.desk.get_phase() == h.PHASE_DISMOUNT, "rest4 real touch on the jump button dismounts (phase %d)" % h.desk.get_phase())
	h.touch_event(point, false)
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "rest4 AWAKENED after touch dismount")
	await h.frames(3)
	h.check(not h.tree.paused and not h.player.is_meditating(), "rest4 control returned")
	h.tc.visible = was_visible


## Input events arrive in window pixels; the stretch transform maps the
## button's canvas position there (the headless window is only 64x64).
func _jump_button_window_point() -> Vector2:
	var jump_rect: Rect2 = h.tc._jump_button.get_global_rect()
	h.check(h.tree.paused and jump_rect.size.x > 0.0, "rest4 paused with a laid-out jump button (%s)" % [jump_rect])
	return h.tree.root.get_final_transform() * jump_rect.get_center()


func case_movement_after_rest() -> void:
	await h.fresh_level()
	await h.awaken()
	h.check(h.desk.request_rest(), "movement: rest accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "movement: RESTING")
	await h.secs(0.5)
	h.player.request_jump()
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "movement: AWAKENED")
	await h.frames(20)
	var x0: float = h.player.global_position.x
	Input.action_press("move_right")
	await h.secs(0.5)
	Input.action_release("move_right")
	h.check(h.player.global_position.x > x0 + 5.0, "movement works (dx=%f)" % (h.player.global_position.x - x0))
	h.check(h.player._sprite.animation != &"rest_dismount" and h.player._sprite.animation != &"rest_sit", "sprite left rest clips (%s)" % h.player._sprite.animation)


# -- Respawn mid-rest at each phase -----------------------------------------------

func case_respawn_at_mount() -> void:
	await _respawn_at(h.PHASE_MOUNT)


func case_respawn_at_celebrate() -> void:
	await _respawn_at(h.PHASE_CELEBRATE)


func case_respawn_at_resting() -> void:
	await _respawn_at(h.PHASE_RESTING)


func case_respawn_at_dismount() -> void:
	await _respawn_at(h.PHASE_DISMOUNT)


func _respawn_at(target: int) -> void:
	await h.fresh_level()
	await _reach_phase(target)
	await h.frames(3)
	var n_before: int = h.dummy.n
	var a_before: int = h.acts
	h.player.respawn()
	await h.frames(3)
	_check_released_after_respawn(target)
	var ph: int = h.desk.get_phase()
	await h.secs(3.2)
	h.check(h.dummy.n == n_before and h.acts == a_before, "respawn@%d no stale effects" % target)
	h.check(not h.tree.paused and h.desk.get_phase() == ph, "respawn@%d stable" % target)


func _reach_phase(target: int) -> void:
	h.check(h.desk.request_rest(), "respawn test phase %d: rest accepted" % target)
	if target == h.PHASE_DISMOUNT:
		h.check(await h.wait_phase(h.PHASE_RESTING), "reach RESTING for dismount case")
		await h.secs(0.5)
		h.player.request_dash()
	h.check(await h.wait_phase(target), "reached phase %d" % target)


func _check_released_after_respawn(target: int) -> void:
	var vig: AltarVignette = h.fx.get_vignette()
	h.check(not h.tree.paused, "respawn@%d unpaused" % target)
	h.check(not h.player.is_meditating(), "respawn@%d not meditating" % target)
	h.check(not h.desk._backpack.visible, "respawn@%d backpack hidden" % target)
	h.check(h.cam_home() and vig.level < 0.01, "respawn@%d camera and vignette reset (zoom %.3f, vig %.2f)" % [target, h.cam.get_zoom_ratio(), vig.level])
	h.check(h.desk.is_processing(), "respawn@%d desk alive" % target)
	var ph: int = h.desk.get_phase()
	h.check(ph == h.PHASE_DORMANT or ph == h.PHASE_AWAKENED, "respawn@%d idle phase %d" % [target, ph])


# -- Player or desk freed mid-ritual ---------------------------------------------

func case_player_freed_mid_rest() -> void:
	await h.fresh_level()
	h.check(h.desk.request_rest(), "free test: rest accepted")
	await h.secs(1.3)
	h.player.queue_free()
	await h.frames(4)
	h.check(not h.tree.paused, "player freed: unpaused")
	h.check(h.desk.get_phase() in [h.PHASE_DORMANT, h.PHASE_AWAKENED], "player freed: idle phase")
	h.check(not h.desk._backpack.visible, "player freed: backpack hidden")


func case_desk_freed_mid_celebration() -> void:
	await h.fresh_level()
	h.check(h.desk.request_rest(), "desk freed@celebration: rest accepted")
	h.check(await h.wait_phase(h.PHASE_CELEBRATE), "desk freed@celebration: CELEBRATE")
	await h.secs(0.9)
	await _free_desk_and_check("celebration")


func case_desk_freed_mid_rest() -> void:
	await h.fresh_level()
	h.check(h.desk.request_rest(), "desk freed@rest: rest accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "desk freed@rest: RESTING")
	await h.secs(0.4)
	await _free_desk_and_check("rest")


func _free_desk_and_check(label: String) -> void:
	var vig: AltarVignette = h.fx.get_vignette()
	h.check(h.cam.get_zoom_ratio() > 1.05 and vig.level > 0.3, "desk freed@%s: focus was on (x%.2f, vig %.2f)" % [label, h.cam.get_zoom_ratio(), vig.level])
	h.desk.queue_free()
	await h.frames(4)
	h.check(not h.tree.paused, "desk freed@%s: unpaused" % label)
	h.check(not h.player.is_meditating(), "desk freed@%s: player released" % label)
	h.check(h.cam_home(), "desk freed@%s: camera focus popped (x%.3f)" % [label, h.cam.get_zoom_ratio()])
	h.check(not is_instance_valid(vig) or vig.level < 0.01, "desk freed@%s: vignette off" % label)


# -- Dismount eases finish even when the phase settles early -----------------------

func case_early_awakened_keeps_eases() -> void:
	await h.fresh_level()
	await h.awaken()
	h.check(h.desk.request_rest(), "early awakened: rest accepted")
	h.check(await h.wait_phase(h.PHASE_RESTING), "early awakened: RESTING")
	await h.secs(0.5)
	h.player.request_jump()
	await h.frames(1)
	h.desk._on_rest_animation_finished(&"rest_dismount")
	await h.frames(2)
	var vig: AltarVignette = h.fx.get_vignette()
	h.check(h.desk.get_phase() == h.PHASE_AWAKENED, "early awakened: phase settled at once")
	h.check(h.cam.get_zoom_ratio() > 1.03 and vig.level > 0.3, "early awakened: eases not cut (x%.2f, vig %.2f)" % [h.cam.get_zoom_ratio(), vig.level])
	await h.secs(0.8)
	h.check(h.cam_home() and vig.level < 0.01, "early awakened: eases completed (x%.3f, vig %.2f)" % [h.cam.get_zoom_ratio(), vig.level])


# -- Reload ----------------------------------------------------------------------

func case_scene_reload_returns_to_desk() -> void:
	await h.fresh_level()
	h.cps.activate(h.DESK_ID, h.LEVEL, h.desk.get_spawn_position())
	h.tree.change_scene_to_file(h.LEVEL)
	await h.frames(10)
	var p2: CharacterBody2D = h.tree.current_scene.get_node("Player")
	var d2: Node2D = h.tree.current_scene.get_node("StillnessDesk")
	h.check(p2.global_position.distance_to(d2.get_spawn_position()) < 2.0, "reload spawns at desk")
	h.check(d2.get_phase() == h.PHASE_AWAKENED, "reloaded desk awakened")
	h.cps.clear()
	h.check(not h.cps.was_ever_activated(h.DESK_ID), "clear() resets activation record")


# -- Clip fallback must not double-advance ---------------------------------------

func case_clip_fallback_no_double_advance() -> void:
	await h.fresh_level()
	# Real finished signal and fallback both fire: mount must advance once.
	h.check(h.desk.request_rest(), "fallback: rest accepted")
	await h.frames(2)
	h.desk._on_rest_animation_finished(&"rest_mount")
	h.check(await h.wait_phase(h.PHASE_RESTING, 6.0), "fallback: reaches RESTING")
	await h.secs(1.0)
	h.check(h.count_events("start") == 1, "fallback: one celebration despite duplicate mount finish (%d)" % h.count_events("start"))
	h.check(h.count_events("peak") == 1 and h.dummy.n == 1 and h.acts == 1, "fallback: effects applied once")
	await _dismount_with_late_fallback()


## Dismount: real signal plus the late fallback must complete once.
func _dismount_with_late_fallback() -> void:
	await h.secs(0.6)
	h.player.request_jump()
	h.check(await h.wait_phase(h.PHASE_AWAKENED, 4.0), "fallback: dismount completes")
	await h.secs(1.5)
	h.check(h.count_events("completed") == 1, "fallback: rest_completed once (%d)" % h.count_events("completed"))
	h.check(h.phases == [2, 3, 4, 5, 1], "fallback: phases not repeated %s" % [h.phases])
	h.check(not h.tree.paused and not h.player.is_meditating(), "fallback: control returned")

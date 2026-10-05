extends "res://tests/support/ritual_suite.gd"
## Wayfinding trails: procedural roots, level placement, hint fireflies and the
## outward pulse the celebration peak sends along every linked strand.

const TRAIL_SCENE := "res://scenes/world/altar_trail.tscn"

const CHECKS := {
	"case_trail_determinism": 4,
	"case_trail_density": 4,
	"case_trail_pulse_while_paused": 2,
	"case_level_trail_placement": 5,
	"case_trail_roots_geometry": 3,
	"case_trail_surface_profile": 2,
	"case_trail_fireflies": 5,
	"case_trail_roots_off": 3,
	"case_desk_roots_are_trails": 6,
	"case_peak_outward_pulse": 8,
}


func expected_checks() -> Dictionary:
	return CHECKS


func make_trail(seed_value: int, dens: float, branches: int) -> Node2D:
	var scene := load(TRAIL_SCENE) as PackedScene
	var t: Node2D = scene.instantiate()
	t.snap_to_ground = false
	t.trail_seed = seed_value
	t.length = 500.0
	t.density = dens
	t.branch_count = branches
	t.position = Vector2(2000.0, 200.0)
	h.lvl.add_child(t)
	return t


func _trail_nodes() -> Array[Node2D]:
	var found: Array[Node2D] = []
	for n: Node in h.lvl.get_children():
		if n.has_method("fire_outward_pulse") and not n.is_queued_for_deletion():
			found.append(n as Node2D)
	return found


func _desk_roots() -> Array[Node2D]:
	var roots: Array[Node2D] = [h.desk.get_node("Visuals/Roots/RootsLeft"), h.desk.get_node("Visuals/Roots/RootsRight")]
	return roots


# -- Generation ------------------------------------------------------------------

func case_trail_determinism() -> void:
	await h.fresh_level()
	var a := make_trail(5, 1.0, 6)
	var b := make_trail(5, 1.0, 6)
	var c := make_trail(6, 1.0, 6)
	await h.frames(3)
	h.check(a.get_point_count() > 40 and a.get_point_count() == b.get_point_count(), "trail: same seed, same point count (%d, %d)" % [a.get_point_count(), b.get_point_count()])
	h.check(a.get_first_points(8) == b.get_first_points(8) and a.get_first_points(8).size() == 8, "trail: same seed, same first points")
	h.check(a.get_point_count() != c.get_point_count() or a.get_first_points(8) != c.get_first_points(8), "trail: another seed builds another trail")
	var points_before: PackedVector2Array = a.get_first_points(10000)
	a.rebuild()
	h.check(a.get_first_points(10000) == points_before, "trail: rebuild is idempotent")


func case_trail_density() -> void:
	await h.fresh_level()
	var a := make_trail(5, 1.0, 6)
	var d := make_trail(9, 2.0, 16)
	await h.frames(3)
	var near: float = a.get_coverage_weight(0.92)
	var far: float = a.get_coverage_weight(0.08)
	h.check(near > far * 2.0 and far > 0.0, "trail: density grows toward the altar (far %.1f, near %.1f)" % [far, near])
	h.check(a.get_strand_count_at(0.92) > a.get_strand_count_at(0.08), "trail: more strands near the altar (%d vs %d)" % [a.get_strand_count_at(0.92), a.get_strand_count_at(0.08)])
	h.check(a.get_strand_count() <= 24 and d.get_strand_count() <= 24 and d.get_strand_count() > a.get_strand_count() and a.get_render_node_count() == 1, "trail: strands bounded, one canvas node (%d, max config %d)" % [a.get_strand_count(), d.get_strand_count()])
	h.check(not a.get_pulse_material().shader.code.is_empty() and a.get_pulse_material().get_shader_parameter(&"path_length") >= 500.0, "trail: pulse shader configured")


func case_trail_pulse_while_paused() -> void:
	await h.fresh_level()
	var a := make_trail(5, 1.0, 6)
	await h.frames(3)
	var clock0: float = a.get_pulse_clock()
	h.tree.paused = true
	h.check(a.can_process() and a.get_swarm().can_process(), "trail: processes while paused")
	await h.frames(20)
	h.tree.paused = false
	var clock1: float = a.get_pulse_clock()
	var uniform1: float = a.get_pulse_material().get_shader_parameter(&"pulse_clock")
	h.check(clock1 - clock0 > 0.1 and absf(uniform1 - clock1) < 0.1, "trail: pulse clock advances while paused (%.2f -> %.2f, uniform %.2f)" % [clock0, clock1, uniform1])


# -- Level placement ---------------------------------------------------------------

func case_level_trail_placement() -> void:
	await h.fresh_level()
	var trails := _trail_nodes()
	h.check(trails.size() >= 2, "level_01 has %d trails" % trails.size())
	var linked := 0
	for t: Node2D in trails:
		if not t.desk_path.is_empty() and t.get_node(t.desk_path) == h.desk:
			linked += 1
	h.check(linked >= 2, "level_01: %d trails linked to the desk" % linked)
	var right: Node2D = h.lvl.get_node("TrailFromRight")
	var left: Node2D = h.lvl.get_node("TrailFromLeft")
	h.check(right.direction == -1 and right.global_position.x > h.desk.global_position.x, "right trail leads left to the desk")
	h.check(left.direction == 1 and left.global_position.x < h.desk.global_position.x, "left trail leads right to the desk")
	h.check(not right.show_roots and not left.show_roots and right.get_canvas_sprite() == null and left.get_canvas_sprite() == null, "level trails hide their roots: no canvas built")


## A visible probe placed like the right trail, plus the desk's roots.
func case_trail_roots_geometry() -> void:
	await h.fresh_level()
	var probe := await _make_probe()
	var band := _floor_band_stats(probe)
	h.check(band["on_floor"], "trail strands stay within the floor band (y %.0f..%.0f)" % [band["y_lo"], band["y_hi"]])
	var roots := _desk_roots()
	h.check(band["worst_gap"] <= 14.0 and probe.get_max_offset_texels() <= 12, "strands creep on the surface: worst gap %.1f texels, max offset %d" % [band["worst_gap"], probe.get_max_offset_texels()])
	h.check(probe.get_ground_offset(-250.0) < -40.0 and roots[0].get_max_offset_texels() <= 12, "probed trail climbs the step; desk roots stay flat")


func _make_probe() -> Node2D:
	var right: Node2D = h.lvl.get_node("TrailFromRight")
	var probe := make_trail(7, 1.0, 14)
	probe.snap_to_ground = true
	probe.set_physics_process(true)
	probe.position = right.position
	probe.direction = -1
	probe.length = 586.0
	await h.frames(8)
	return probe


func _floor_band_stats(probe: Node2D) -> Dictionary:
	var roots := _desk_roots()
	var stats := {"on_floor": true, "y_lo": 9999.0, "y_hi": -9999.0, "worst_gap": 0.0}
	for t: Node2D in [probe, roots[0], roots[1]]:
		var pts: PackedVector2Array = t.get_all_points()
		for i: int in range(0, pts.size(), 7):
			var y: float = t.to_global(pts[i]).y
			stats["y_lo"] = minf(stats["y_lo"], y)
			stats["y_hi"] = maxf(stats["y_hi"], y)
			if y < 470.0 or y > 640.0:
				stats["on_floor"] = false
			stats["worst_gap"] = maxf(stats["worst_gap"], t.distance_to_surface_texels(pts[i]))
	return stats


func case_trail_surface_profile() -> void:
	await h.fresh_level()
	var right: Node2D = h.lvl.get_node("TrailFromRight")
	var space: PhysicsDirectSpaceState2D = h.lvl.get_world_2d().direct_space_state
	var surface_err := 0.0
	for lx: float in [-450.0, -300.0, -100.0]:
		surface_err = maxf(surface_err, _surface_error_at(space, right, lx))
	h.check(surface_err <= 1.5, "surface profile matches the physics floor and steps (err %.2f)" % surface_err)
	h.check(right.get_ground_offset(-250.0) < -40.0, "right trail climbs the step it crosses (%.1f)" % right.get_ground_offset(-250.0))


func _surface_error_at(space: PhysicsDirectSpaceState2D, right: Node2D, lx: float) -> float:
	var from := Vector2(right.global_position.x + lx, right.global_position.y - 160.0)
	var to := Vector2(from.x, right.global_position.y + 200.0)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))
	if hit.is_empty():
		return 99.0
	var hy: float = hit["position"].y - right.global_position.y
	return absf(hy - right.get_surface_offset(lx))


# -- Hint fireflies ----------------------------------------------------------------

func case_trail_fireflies() -> void:
	await h.fresh_level()
	var right: Node2D = h.lvl.get_node("TrailFromRight")
	var swarm: FireflySwarm = right.get_swarm()
	h.check(swarm.base_active == right.firefly_count and right.firefly_count >= 10 and swarm.field_span == right.length and swarm.flow_span == 0.0, "trail fireflies are a hint field, not a flow (%d)" % right.firefly_count)
	await h.frames(20)
	h.check(swarm.get_visible_count() >= 6, "trail fireflies visible (%d)" % swarm.get_visible_count())
	_check_firefly_layout(right, swarm)
	await _check_firefly_drift_is_mixed(right, swarm)


func _check_firefly_layout(right: Node2D, swarm: FireflySwarm) -> void:
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
	h.check(near_count > far_count and far_count >= 1, "fireflies thicken toward the altar (far third %d, near third %d)" % [far_count, near_count])
	h.check(in_band, "fireflies live in the air band 10 to 80 units up")


func _check_firefly_drift_is_mixed(right: Node2D, swarm: FireflySwarm) -> void:
	var start_x := PackedFloat32Array()
	for i: int in swarm.base_active:
		start_x.append(swarm.get_firefly_position(i).x)
	await h.secs(3.0)
	var toward := 0
	var away := 0
	for i: int in swarm.base_active:
		var moved := (swarm.get_firefly_position(i).x - start_x[i]) * float(right.direction)
		if moved > 0.5:
			toward += 1
		elif moved < -0.5:
			away += 1
	h.check(toward >= 1 and away >= 1, "firefly drift is mixed, not a flow to the altar (toward %d, away %d)" % [toward, away])


# -- Desk roots ------------------------------------------------------------------

func case_trail_roots_off() -> void:
	await h.fresh_level()
	var scene_trail := make_trail(3, 1.0, 6)
	scene_trail.show_roots = false
	await h.frames(3)
	h.check(scene_trail.get_canvas_sprite() == null and scene_trail.get_strand_count() == 0 and scene_trail.get_render_node_count() == 0, "show_roots off: no canvas, no strands")
	var clock_before: float = scene_trail.get_pulse_clock()
	scene_trail.fire_outward_pulse()
	await h.frames(10)
	h.check(scene_trail.get_pulse_clock() > clock_before and scene_trail.get_outward_count() == 1, "show_roots off: pulse logic keeps running")
	var roots_l := _desk_roots()[0]
	h.check(roots_l.show_roots and roots_l.get_canvas_sprite() != null and roots_l.get_canvas_sprite().visible and roots_l.root_alpha < 0.8 and not roots_l.snap_to_ground, "desk roots stay visible, subtler and grounded under the desk")


func case_desk_roots_are_trails() -> void:
	await h.fresh_level()
	var roots := _desk_roots()
	h.check(roots[0].has_method("get_coverage_weight") and roots[1].has_method("get_coverage_weight"), "desk roots are AltarTrail")
	h.check(not h.desk.has_node("Visuals/Roots/RootLeft") and not h.desk.has_node("Visuals/Roots/RootRight"), "interim root sprites removed")
	var uses_png := false
	for sprite: Sprite2D in h.desk.find_children("*", "Sprite2D", true, false):
		if sprite.texture != null and sprite.texture.resource_path.contains("roots_"):
			uses_png = true
	h.check(not uses_png, "no desk sprite uses the interim roots PNGs")
	h.check(roots[0].get_strand_count() > 3 and roots[0].get_strand_count() <= 24 and roots[1].get_strand_count() <= 24 and roots[0].get_render_node_count() == 1, "desk roots: %d strands, bounded" % roots[0].get_strand_count())
	_check_roots_plug_into_desk(roots)


func _check_roots_plug_into_desk(roots: Array[Node2D]) -> void:
	var plug_left: float = roots[0].to_global(roots[0].get_first_points(10000)[-1]).x
	var plug_right: float = roots[1].to_global(roots[1].get_first_points(10000)[-1]).x
	var dx_left: float = plug_left - h.desk.global_position.x
	var dx_right: float = plug_right - h.desk.global_position.x
	h.check(absf(dx_left) < 30.0 and absf(dx_right) < 30.0, "desk roots plug into the desk legs (%.1f, %.1f)" % [dx_left, dx_right])
	h.check(roots[0].desk_path == NodePath("../../..") and roots[0].get_node(roots[0].desk_path) == h.desk, "desk roots linked to their desk")


# -- Outward pulse -----------------------------------------------------------------

## The celebration peak sends the outward pulse along every linked strand.
func case_peak_outward_pulse() -> void:
	await h.fresh_level()
	var right: Node2D = h.lvl.get_node("TrailFromRight")
	var linked: Array[Node2D] = [right, h.lvl.get_node("TrailFromLeft"), _desk_roots()[0], _desk_roots()[1]]
	var rate_idle: float = right.get_pulse_rate()
	h.check(rate_idle < 1.05 and not right.is_outward_active(), "dormant trail: base rate (%.2f), no outward pulse" % rate_idle)
	var counts := _outward_counts(linked)
	h.desk.request_rest()
	h.check(await h.wait_phase(h.PHASE_CELEBRATE), "trail case: CELEBRATE reached")
	await _wait_for_peak()
	await h.frames(3)
	h.check(_all_fired_once(linked, counts), "celebration_peak fires one outward pulse on every linked trail")
	await _check_outward_pulse_lifecycle(right)
	h.player.exit_meditation()
	await h.frames(3)
	h.check(not h.tree.paused, "trail case: abort unpauses")


func _outward_counts(trails: Array[Node2D]) -> Array[int]:
	var counts: Array[int] = []
	for t: Node2D in trails:
		counts.append(t.get_outward_count())
	return counts


func _all_fired_once(trails: Array[Node2D], before: Array[int]) -> bool:
	for i: int in trails.size():
		if trails[i].get_outward_count() != before[i] + 1:
			return false
	return true


func _wait_for_peak() -> void:
	var peaks_before := h.count_events("peak")
	var deadline := h.clock + 10.0
	while h.count_events("peak") == peaks_before and h.clock < deadline:
		await h.tree.process_frame


func _check_outward_pulse_lifecycle(right: Node2D) -> void:
	var material: ShaderMaterial = right.get_pulse_material()
	var strength := float(material.get_shader_parameter(&"burst_strength"))
	h.check(right.is_outward_active() and strength > 0.3, "outward pulse visible at the peak (strength %.2f)" % strength)
	h.check(h.tree.paused and right.can_process(), "outward pulse runs while paused")
	await h.secs(3.2)
	h.check(not right.is_outward_active() and float(material.get_shader_parameter(&"burst_strength")) == 0.0, "outward pulse finishes on its own")
	h.check(right.get_pulse_rate() > 1.3 and float(material.get_shader_parameter(&"warmth")) > 0.6, "awakened desk: trail pulses faster and warmer (%.2f)" % right.get_pulse_rate())

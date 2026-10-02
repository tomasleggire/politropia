@tool
class_name AltarTrail
extends Node2D

## Wayfinding roots that lead to a rest altar: thin, irregular white paper
## strands creep along the floor, climb flush up the faces of steps and run
## along their tops, thickening and multiplying toward the altar. Amber
## packets travel along them toward it and a few fireflies drift the same way.
## The node's origin is the FAR end of the trail; the altar is `length` units
## away in `direction`.
##
## The strands are rasterised once into a small image (one texel per art
## pixel, `texel_size` world units) shown with nearest filtering, so every edge
## is stair-stepped. Linked to a StillnessDesk (`desk_path`) the trail warms up
## while the checkpoint is active and, at the celebration peak, sends one
## bright packet back out along every strand. Generation is deterministic for
## a given `trail_seed`; only the surface profile depends on the level.

const SHADER := preload("res://shaders/altar_trail.gdshader")
const PROBE_TICKS := 2
const PROBE_DEPTH := 200.0
## Ground heights are blurred for the fireflies only, so they glide over step
## corners instead of jumping up the face.
const FIREFLY_SMOOTH_RADIUS := 10
const FIREFLY_SMOOTH_PASSES := 2
const MAX_TRUNKS := 4
const MAX_BRANCHES := 16
const MAX_SCRAPS := 6
const TRUNK_STARTS: Array[float] = [0.0, 0.12, 0.3, 0.5]
const KIND_PAPER := 1
const KIND_INK := 2
const KIND_SCRAP := 3
const MARGIN_TOP := 24
const MARGIN_SIDE := 24
const MARGIN_BOTTOM := 4
const MAX_OFFSET := 12
const BURST_SPEED := 520.0
const BURST_MARGIN := 1.3
const EASE_RATE := 2.5
## A strand point farther than this from the surface would read as floating.
const MAX_SURFACE_GAP_TEXELS := 14.0

@export_group("Shape")
@export_range(40.0, 1600.0, 1.0, "suffix:px") var length := 400.0:
	set(value):
		length = value
		_request_rebuild()
## Which way the altar is from the trail's far end.
@export_enum("Left:-1", "Right:1") var direction := 1:
	set(value):
		direction = value
		_request_rebuild()
@export var trail_seed := 1:
	set(value):
		trail_seed = value
		_request_rebuild()
## World units per art pixel of the trail.
@export_range(0.25, 2.0, 0.05) var texel_size := 1.0:
	set(value):
		texel_size = value
		_request_rebuild()

@export_group("Roots")
## Draw the paper roots. When off no root canvas is built and the pulses are
## simply not visible (their timing keeps running at no visible cost).
@export var show_roots := true:
	set(value):
		show_roots = value
		_request_rebuild()
@export_range(0.05, 1.0, 0.05) var root_alpha := 1.0:
	set(value):
		root_alpha = value
		_request_rebuild()
## Thickest paper strand, in texels.
@export_range(1, 4) var max_thickness := 4:
	set(value):
		max_thickness = value
		_request_rebuild()

@export_group("Density")
## More and thicker strands near the altar; the far end stays sparse.
@export_range(0.25, 2.0, 0.05) var density := 1.0:
	set(value):
		density = value
		_request_rebuild()
@export_range(0, 16) var branch_count := 6:
	set(value):
		branch_count = value
		_request_rebuild()

@export_group("Fireflies")
## Fireflies scattered over the trail as a hint zone: sparse far away, denser
## toward the altar, wandering freely (no flow toward it).
@export_range(0, 14) var firefly_count := 10

@export_group("Link")
@export var desk_path: NodePath

@export_group("Ground")
## Follow the floor and step faces (probed once, shortly after the level is built).
@export var snap_to_ground := true
@export_flags_2d_physics var ground_mask := 1
@export_range(20.0, 400.0, 1.0) var probe_height := 160.0

@export_group("Look")
@export var paper_color := Color("efe6d2"):
	set(value):
		paper_color = value
		_request_rebuild()
@export var ink_color := Color("3a3446"):
	set(value):
		ink_color = value
		_request_rebuild()
@export var pulse_color := Color(1.0, 0.72, 0.28):
	set(value):
		pulse_color = value
		_request_rebuild()
@export_range(0.0, 1.0, 0.01) var glow_strength := 0.26:
	set(value):
		glow_strength = value
		_request_rebuild()

@export_group("Pulses")
## World units per second a packet travels toward the altar.
@export_range(40.0, 600.0, 1.0) var pulse_speed := 150.0:
	set(value):
		pulse_speed = value
		_request_rebuild()
@export_range(0.0, 10.0, 0.1) var pulse_gap := 1.4:
	set(value):
		pulse_gap = value
		_request_rebuild()
## Packet head-to-tail length in world units.
@export_range(2.0, 60.0, 1.0) var pulse_length := 16.0:
	set(value):
		pulse_length = value
		_request_rebuild()
## Pulse clock speed once the linked desk is the active checkpoint.
@export_range(1.0, 3.0, 0.05) var awakened_rate := 1.6

var _rng := RandomNumberGenerator.new()
var _strands: Array[PackedVector2Array] = []
var _built: Array[Strand] = []
var _widths := PackedFloat32Array()
var _u_min := PackedFloat32Array()
var _u_max := PackedFloat32Array()
var _rows := PackedInt32Array()
var _ground_smooth := PackedFloat32Array()
var _path_col := PackedInt32Array()
var _path_row := PackedInt32Array()
var _path_nx := PackedInt32Array()
var _path_ny := PackedInt32Array()
var _image: Image
var _origin_col := 0
var _origin_row := 0
var _sprite: Sprite2D
var _material: ShaderMaterial
var _swarm: FireflySwarm
var _desk: StillnessDesk
var _rebuild_pending := false
var _probe_ticks := 0
var _time := 0.0
var _clock := 0.0
var _rate := 1.0
var _warmth := 0.0
var _burst_time := -1.0
var _burst_count := 0
var _max_offset := 0


## One traced strand: per point a distance above the surface path (`offset`)
## and a paper thickness, following the path from path index `start`.
class Strand extends RefCounted:
	var id := 0
	var start := 0
	var offset := PackedInt32Array()
	var thickness := PackedInt32Array()
	var dash := PackedByteArray()

	func size() -> int:
		return offset.size()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rebuild()
	if Engine.is_editor_hint():
		return
	_link_desk()
	set_physics_process(snap_to_ground)


func _exit_tree() -> void:
	if _desk != null and is_instance_valid(_desk) and _desk.celebration_peak.is_connected(fire_outward_pulse):
		_desk.celebration_peak.disconnect(fire_outward_pulse)
	_desk = null


func _physics_process(_delta: float) -> void:
	# Solids are built by the level after this node is ready, so wait a tick.
	_probe_ticks += 1
	if _probe_ticks < PROBE_TICKS:
		return
	set_physics_process(false)
	_probe_ground()


func _process(delta: float) -> void:
	_time += delta
	_follow_desk(delta)
	_clock += delta * _rate
	_advance_burst(delta)
	_push_uniforms()
	if _swarm != null:
		_swarm.brightness = lerpf(0.7, 1.0, _warmth)
		_swarm.glow_color = Color(1.0, lerpf(0.78, 0.62, _warmth), lerpf(0.42, 0.24, _warmth), 0.6)
		_swarm.step(delta, _time, 0.5)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Editor-only guide: a dashed line and arrowhead toward the altar.
	var altar := Vector2(float(direction) * length, 0.0)
	var guide := Color(1.0, 0.8, 0.4, 0.55)
	draw_dashed_line(Vector2.ZERO, altar, guide, 1.0, 8.0)
	var back := Vector2(-float(direction) * 10.0, 0.0)
	draw_colored_polygon(PackedVector2Array([altar, altar + back + Vector2(0.0, -5.0), altar + back + Vector2(0.0, 5.0)]), guide)


# -- Public API -----------------------------------------------------------------

func rebuild() -> void:
	_rebuild()


## One bright packet from the altar back out along every strand.
func fire_outward_pulse() -> void:
	_burst_time = 0.0
	_burst_count += 1


func is_outward_active() -> bool:
	return _burst_time >= 0.0


func get_outward_count() -> int:
	return _burst_count


func get_pulse_clock() -> float:
	return _clock


## Pulse clock speed factor (1 dormant, `awakened_rate` once the desk is active).
func get_pulse_rate() -> float:
	return _rate


func get_pulse_material() -> ShaderMaterial:
	return _material


func get_canvas_sprite() -> Sprite2D:
	return _sprite


func get_strand_count() -> int:
	return _strands.size()


## Number of Line2D or Sprite2D nodes the trail draws with (always one canvas).
func get_render_node_count() -> int:
	return 1 if _sprite != null and _sprite.visible else 0


func get_point_count() -> int:
	var count := 0
	for points: PackedVector2Array in _strands:
		count += points.size()
	return count


func get_first_points(count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if _strands.is_empty():
		return result
	for i in mini(count, _strands[0].size()):
		result.append(_strands[0][i])
	return result


func get_all_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for points: PackedVector2Array in _strands:
		result.append_array(points)
	return result


func get_swarm() -> FireflySwarm:
	return _swarm


## Longest strand offset from the surface, in texels.
func get_max_offset_texels() -> int:
	return _max_offset


## Summed strand thickness covering `u` (0 at the far end, 1 at the altar): a
## direct measure of how dense the trail is there.
func get_coverage_weight(u: float) -> float:
	var total := 0.0
	for i in _strands.size():
		if _u_min[i] <= u and u <= _u_max[i]:
			total += _widths[i]
	return total


func get_strand_count_at(u: float) -> int:
	var count := 0
	for i in _strands.size():
		if _u_min[i] <= u and u <= _u_max[i]:
			count += 1
	return count


## Exact surface height relative to this node at local `x`, in world units.
func get_surface_offset(x: float) -> float:
	if _rows.is_empty():
		return 0.0
	var k := clampi(int(floorf(x * float(direction) / texel_size)), 0, _rows.size() - 1)
	return float(_rows[k]) * texel_size


## Smoothed ground height for gliding things (fireflies), in world units.
func get_ground_offset(x: float) -> float:
	if _ground_smooth.is_empty():
		return 0.0
	var f := clampf(x * float(direction) / texel_size, 0.0, float(_ground_smooth.size() - 1))
	var i := int(f)
	var j := mini(i + 1, _ground_smooth.size() - 1)
	return lerpf(_ground_smooth[i], _ground_smooth[j], f - float(i)) * texel_size


## Distance in texels from a local point to the nearest point of the surface
## path the strands follow.
func distance_to_surface_texels(local_point: Vector2) -> float:
	var best := INF
	var col := local_point.x / texel_size - 0.5
	var row := local_point.y / texel_size - 0.5
	for i in _path_col.size():
		var dx := float(_path_col[i]) - col
		var dy := float(_path_row[i]) - row
		best = minf(best, dx * dx + dy * dy)
	return sqrt(best)


func get_path_size() -> int:
	return _path_col.size()


# -- Ground and desk link ---------------------------------------------------------

func _probe_ground() -> void:
	var space := get_world_2d().direct_space_state
	var count := _column_count()
	_rows.resize(count)
	var origin := global_position
	var excluded := _moving_bodies()
	for k in count:
		var x := origin.x + (float(k * direction) + 0.5) * texel_size
		var query := PhysicsRayQueryParameters2D.create(
			Vector2(x, origin.y - probe_height), Vector2(x, origin.y + PROBE_DEPTH), ground_mask
		)
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		var hit_position: Vector2 = hit.get("position", Vector2(x, origin.y))
		_rows[k] = roundi((hit_position.y - origin.y) / texel_size)
	_rebuild()


## The player shares the solids' physics layer; it must never read as floor.
func _moving_bodies() -> Array[RID]:
	var result: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var body := node as CollisionObject2D
		if body != null:
			result.append(body.get_rid())
	return result


func _link_desk() -> void:
	if desk_path.is_empty():
		return
	_desk = get_node_or_null(desk_path) as StillnessDesk
	if _desk != null:
		_desk.celebration_peak.connect(fire_outward_pulse)


func _follow_desk(delta: float) -> void:
	var awakened := _desk != null and is_instance_valid(_desk) and _desk.get_phase() != StillnessDesk.Phase.DORMANT
	var k := 1.0 - exp(-EASE_RATE * delta)
	_rate = lerpf(_rate, awakened_rate if awakened else 1.0, k)
	_warmth = lerpf(_warmth, 1.0 if awakened else 0.0, k)


func _advance_burst(delta: float) -> void:
	if _burst_time < 0.0:
		return
	_burst_time += delta
	if _burst_time >= _burst_duration():
		_burst_time = -1.0


func _path_length_units() -> float:
	return maxf(float(_path_col.size()) * texel_size, length)


func _burst_duration() -> float:
	return _path_length_units() * BURST_MARGIN / BURST_SPEED + 0.25


func _push_uniforms() -> void:
	_material.set_shader_parameter(&"pulse_clock", _clock)
	_material.set_shader_parameter(&"warmth", _warmth)
	if _burst_time < 0.0:
		_material.set_shader_parameter(&"burst_pos", -2.0)
		_material.set_shader_parameter(&"burst_strength", 0.0)
		return
	var fade := 1.0 - smoothstep(0.6, 1.0, _burst_time / _burst_duration())
	_material.set_shader_parameter(&"burst_pos", 1.15 - _burst_time * BURST_SPEED / _path_length_units())
	_material.set_shader_parameter(&"burst_strength", fade)


# -- Generation -------------------------------------------------------------------

func _request_rebuild() -> void:
	if not is_node_ready() or _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	_rng.seed = trail_seed
	_prepare_ground()
	if show_roots:
		_build_path()
		_build_strands()
		_rasterise()
		_build_world_points()
	else:
		_clear_roots()
	_configure_sprite()
	_configure_material()
	_configure_swarm()
	queue_redraw()


func _column_count() -> int:
	return int(ceil(length / texel_size)) + 1


func _row_at(k: int) -> int:
	return _rows[k] if k < _rows.size() else 0


func _prepare_ground() -> void:
	var count := _column_count()
	if _rows.size() != count:
		_rows.resize(count)
		_rows.fill(0)
	_smooth_for_fireflies()


func _clear_roots() -> void:
	_path_col.clear()
	_path_row.clear()
	_path_nx.clear()
	_path_ny.clear()
	_built.clear()
	_strands.clear()
	_widths.clear()
	_u_min.clear()
	_u_max.clear()
	_max_offset = 0
	_image = null


func _add_path(col: int, row: int, nx: int, ny: int) -> void:
	_path_col.append(col)
	_path_row.append(row)
	_path_nx.append(nx)
	_path_ny.append(ny)


## The surface the strands creep on, one texel per step from the far end: it
## hugs the floor top and, where the height jumps, runs up (or down) the
## air-side column flush against the face, turning the corner tightly.
func _build_path() -> void:
	_path_col.clear()
	_path_row.clear()
	_path_nx.clear()
	_path_ny.clear()
	var count := _column_count()
	var previous := _row_at(0)
	_add_path(0, previous - 1, 0, -1)
	for k in range(1, count):
		var row := _row_at(k)
		var col := k * direction
		if row < previous - 1:
			for r in range(previous - 2, row - 2, -1):
				_add_path((k - 1) * direction, r, -direction, 0)
		elif row > previous + 1:
			for r in range(previous - 1, row - 1):
				_add_path(col, r, direction, 0)
		_add_path(col, row - 1, 0, -1)
		previous = row


func _smooth_for_fireflies() -> void:
	_ground_smooth.resize(_rows.size())
	for k in _rows.size():
		_ground_smooth[k] = float(_rows[k])
	for _pass in FIREFLY_SMOOTH_PASSES:
		var source := _ground_smooth.duplicate()
		var last := source.size() - 1
		for k in source.size():
			var lo := maxi(k - FIREFLY_SMOOTH_RADIUS, 0)
			var hi := mini(k + FIREFLY_SMOOTH_RADIUS, last)
			var total := 0.0
			for j in range(lo, hi + 1):
				total += source[j]
			_ground_smooth[k] = total / float(hi - lo + 1)


func _trunk_count() -> int:
	return clampi(roundi(1.0 + density * 1.6), 2, MAX_TRUNKS)


func _new_strand(start: int, size: int) -> Strand:
	var strand := Strand.new()
	strand.id = _built.size()
	strand.start = start
	strand.offset.resize(size)
	strand.thickness.resize(size)
	strand.dash.resize(size)
	return strand


## Random walk of offsets above the surface: mostly still, sometimes a texel
## up or down, never above `cap` at that point.
func _walk_offsets(strand: Strand, first: int, cap_far: int, cap_near: int, path_last: int) -> void:
	var value := first
	for i in strand.size():
		var u := float(strand.start + i) / float(path_last)
		var cap := roundi(lerpf(float(cap_far), float(cap_near), pow(u, 1.5)))
		if _rng.randf() < 0.12:
			value += 1 if _rng.randf() < 0.5 else -1
		value = clampi(value, 0, maxi(cap, 0))
		strand.offset[i] = value


func _trunk_thickness(strand: Strand, index: int, path_last: int) -> void:
	var gain := 1.4 + density * 1.0
	for i in strand.size():
		var u := float(strand.start + i) / float(path_last)
		var w := (2 if index < 2 else 1) + int(u * gain * (1.0 - 0.18 * float(index)))
		strand.thickness[i] = clampi(w, 1, max_thickness)


## Handwriting-like dashes down the middle of a wide ribbon.
func _lay_dashes(strand: Strand) -> void:
	var i := 0
	while i < strand.size():
		i += _rng.randi_range(4, 9)
		var run := _rng.randi_range(2, 4)
		for j in run:
			if i + j < strand.size() and strand.thickness[i + j] >= 3:
				strand.dash[i + j] = 1
		i += run


func _build_trunk(index: int, path_last: int) -> void:
	var s0 := 0
	if index > 0:
		s0 = clampi(int((TRUNK_STARTS[index] + _rng.randf_range(-0.04, 0.04)) * float(path_last)), 0, path_last - 8)
	var strand := _new_strand(s0, path_last - s0 + 1)
	var dense := 4 + int(density * 3.0)
	_walk_offsets(strand, index * 2, 2 + index, dense + index * 2, path_last)
	_trunk_thickness(strand, index, path_last)
	_lay_dashes(strand)
	_hook_tip(strand)
	_built.append(strand)


## A tiny 1 to 2 texel upturn at the far tip instead of a spiral.
func _hook_tip(strand: Strand) -> void:
	strand.thickness[0] = 1
	if strand.size() > 3:
		strand.thickness[1] = 1
		strand.offset[0] = mini(strand.offset[1] + 2, MAX_OFFSET)
		strand.offset[1] = mini(strand.offset[2] + 1, MAX_OFFSET)


## A thin fork that leaves a trunk and runs away from the altar, lifting off
## the surface a few texels as it goes.
func _build_branch(path_last: int) -> void:
	var trunk := _built[_rng.randi_range(0, _trunk_count() - 1)]
	var s_junction := int(lerpf(0.15, 0.98, pow(_rng.randf(), 0.55)) * float(path_last))
	s_junction = maxi(s_junction, trunk.start + 6)
	var reach := mini(maxi(_rng.randi_range(14, 52) + int(density * 8.0), 8), s_junction)
	var strand := _new_strand(s_junction - reach, reach + 1)
	var base := trunk.offset[s_junction - trunk.start]
	var grow := _rng.randi_range(2, 5)
	for i in strand.size():
		var away := 1.0 - float(i) / float(reach)
		var wobble := 0
		if _rng.randf() < 0.18:
			wobble = 1 if _rng.randf() < 0.5 else -1
		strand.offset[i] = clampi(base + int(away * float(grow)) + wobble, 0, MAX_OFFSET)
		strand.thickness[i] = 1
	_hook_tip(strand)
	_built.append(strand)


func _build_strands() -> void:
	_built.clear()
	_max_offset = 0
	var path_last := _path_col.size() - 1
	for index in _trunk_count():
		_build_trunk(index, path_last)
	for i in mini(branch_count, MAX_BRANCHES):
		_build_branch(path_last)


## Position of point `i` of a strand at extra offset `extra` above the path,
## in image-independent texel coordinates.
func _cell(strand: Strand, i: int, extra: int) -> Vector2i:
	var s := strand.start + i
	var d := strand.offset[i] + extra
	return Vector2i(_path_col[s] + _path_nx[s] * d, _path_row[s] + _path_ny[s] * d)


func _rasterise() -> void:
	_setup_image()
	# Thin forks first, trunks over them, so bundles keep visible ink lines.
	for i in range(_built.size() - 1, -1, -1):
		_paint_strand(_built[i])
	_paint_scraps()


func _setup_image() -> void:
	var min_col := 0
	var max_col := 0
	var min_row := 1 << 30
	var max_row := -(1 << 30)
	for i in _path_col.size():
		min_col = mini(min_col, _path_col[i])
		max_col = maxi(max_col, _path_col[i])
		min_row = mini(min_row, _path_row[i])
		max_row = maxi(max_row, _path_row[i])
	_origin_col = min_col - MARGIN_SIDE
	_origin_row = min_row - MARGIN_TOP
	var width := max_col - min_col + 1 + MARGIN_SIDE * 2
	var height := max_row - min_row + 1 + MARGIN_TOP + MARGIN_BOTTOM
	_image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)


func _put(cell: Vector2i, kind: int, id: int, s: int) -> void:
	var x := cell.x - _origin_col
	var y := cell.y - _origin_row
	if x < 0 or y < 0 or x >= _image.get_width() or y >= _image.get_height():
		return
	var along := int(float(s) / float(maxi(_path_col.size() - 1, 1)) * 65535.0)
	_image.set_pixel(x, y, Color8(kind * 64 + id, along >> 8, along & 255, 255))


## Paper thickness extent at point `i`, widened to the previous point's offset
## so texel steps between offsets stay connected.
func _extent(strand: Strand, i: int) -> Vector2i:
	var lo := strand.offset[i]
	var hi := lo
	if i > 0:
		lo = mini(lo, strand.offset[i - 1])
		hi = maxi(hi, strand.offset[i - 1])
	return Vector2i(lo, hi + strand.thickness[i] - 1)


func _paint_strand(strand: Strand) -> void:
	for i in strand.size():
		var extent := _extent(strand, i)
		_max_offset = maxi(_max_offset, extent.y)
		for t in range(extent.x - 1, extent.y + 2):
			var cell := _cell(strand, i, t - strand.offset[i])
			_put(cell, KIND_INK, strand.id, strand.start + i)
			_put(cell + Vector2i(1, 0), KIND_INK, strand.id, strand.start + i)
			_put(cell - Vector2i(1, 0), KIND_INK, strand.id, strand.start + i)
	for i in strand.size():
		var extent := _extent(strand, i)
		for t in range(extent.x, extent.y + 1):
			var kind := KIND_PAPER
			if strand.dash[i] == 1 and t == (extent.x + extent.y) >> 1:
				kind = KIND_INK
			_put(_cell(strand, i, t - strand.offset[i]), kind, strand.id, strand.start + i)


## A few tiny paper scraps with ink lines, standing on the main strands.
func _paint_scraps() -> void:
	var count := mini(MAX_SCRAPS, 2 + int(length / 160.0))
	for n in count:
		var strand := _built[_rng.randi_range(0, _trunk_count() - 1)]
		var i := clampi(int(_rng.randf_range(0.3, 0.95) * float(strand.size())), 0, strand.size() - 1)
		var s := strand.start + i
		if _path_ny[s] != -1:
			continue
		var base := _cell(strand, i, strand.thickness[i] + 1)
		_paint_scrap(base, s)


func _paint_scrap(base: Vector2i, s: int) -> void:
	var height := 4
	for y in range(-height - 1, 1):
		for x in range(-2, 3):
			_put(base + Vector2i(x, y), KIND_INK, 0, s)
	for y in range(-height, 0):
		for x in range(-1, 2):
			_put(base + Vector2i(x, y), KIND_SCRAP, 0, s)
	_put(base + Vector2i(-1, -height + 1), KIND_INK, 0, s)
	_put(base + Vector2i(0, -height + 1), KIND_INK, 0, s)
	_put(base + Vector2i(-1, -height + 3), KIND_INK, 0, s)


func _build_world_points() -> void:
	_strands.clear()
	_widths.clear()
	_u_min.clear()
	_u_max.clear()
	var last := float(maxi(_path_col.size() - 1, 1))
	for strand in _built:
		var points := PackedVector2Array()
		var total := 0
		for i in strand.size():
			var cell := _cell(strand, i, 0)
			points.append((Vector2(cell) + Vector2(0.5, 0.5)) * texel_size)
			total += strand.thickness[i]
		_strands.append(points)
		_widths.append(float(total) / float(strand.size()))
		_u_min.append(float(strand.start) / last)
		_u_max.append(float(strand.start + strand.size() - 1) / last)


func _configure_sprite() -> void:
	if _image == null:
		if _sprite != null:
			_sprite.queue_free()
			_sprite = null
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Canvas"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.material = _material
		add_child(_sprite)
	_sprite.texture = ImageTexture.create_from_image(_image)
	_sprite.scale = Vector2.ONE * texel_size
	_sprite.position = Vector2(_origin_col, _origin_row) * texel_size


func _configure_material() -> void:
	var path_units := _path_length_units()
	var travel := path_units * BURST_MARGIN / pulse_speed
	_material.set_shader_parameter(&"paper_color", paper_color)
	_material.set_shader_parameter(&"ink_color", ink_color)
	_material.set_shader_parameter(&"pulse_color", pulse_color)
	_material.set_shader_parameter(&"glow_strength", glow_strength)
	_material.set_shader_parameter(&"root_opacity", root_alpha)
	_material.set_shader_parameter(&"trail_length", length)
	_material.set_shader_parameter(&"path_length", path_units)
	_material.set_shader_parameter(&"pulse_travel", travel)
	_material.set_shader_parameter(&"pulse_cycle", travel + pulse_gap)
	_material.set_shader_parameter(&"pulse_length", pulse_length)
	_push_uniforms()


func _configure_swarm() -> void:
	if Engine.is_editor_hint():
		return
	if firefly_count <= 0:
		if _swarm != null:
			_swarm.queue_free()
			_swarm = null
		return
	if _swarm == null:
		_swarm = FireflySwarm.new()
		_swarm.name = "TrailFireflies"
		_swarm.base_count = firefly_count
		add_child(_swarm)
		_swarm.ground_profile = get_ground_offset
	_swarm.base_active = mini(firefly_count, _swarm.base_count)
	_swarm.field_span = length
	_swarm.field_direction = direction
	_swarm.wander_speed = 0.3
	_swarm.beacon_reach = 0.0
	_swarm.glow_scale = 0.3
	_swarm.setup(trail_seed)

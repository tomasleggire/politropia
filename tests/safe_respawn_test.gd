extends SceneTree
## Regression test for the safe-ground memory used by spikes, pits and respawns.
## Real library/Greece floors are TileMapLayer nodes, so the remembered spot must
## work with them (not only with synthetic StaticBody2D floors), stay away from
## ledges and hazards, follow a moving platform, and reset Luz cleanly.
## Run: godot --headless --path . --script res://tests/safe_respawn_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CONTACT_SCENE := "res://scenes/world/contact_damage.tscn"
const WATCHDOG_SECONDS := 120.0
const SETTLE_FRAMES := 30
const TILE := 16
const FLOOR_RECT := Rect2(-3000.0, 0.0, 6000.0, 200.0)
const PLAYER_BODY := Vector2(29.0, 46.0)

const CHECKS := {
	"case_tilemap_floor_records_safe_ground": 4,
	"case_tilemap_spike_returns_to_safe_ground": 5,
	"case_fall_returns_to_tilemap_safe_ground": 3,
	"case_safe_ground_follows_moving_platform": 2,
	"case_respawn_clears_state_and_grants_iframes": 6,
}


var checks := 0
var failed: Array[String] = []
var _expected_total := 0
var _problems: Array[String] = []
var _rig: Node2D
var _player: Player


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	for case_name: String in CHECKS:
		_expected_total += CHECKS[case_name]
		await _run_case(case_name, CHECKS[case_name])
	finish()


func _run_case(case_name: String, wanted: int) -> void:
	var before := checks
	var failed_before := failed.size()
	await call(case_name)
	var ran := checks - before
	print("case %s: %d checks, %d failed" % [case_name, ran, failed.size() - failed_before])
	if ran != wanted:
		_problems.append("%s ran %d checks, expected %d" % [case_name, ran, wanted])
	_free_rig()
	await process_frame


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


# -- Rig -------------------------------------------------------------------------

## Flat synthetic floor made of one TileMapLayer, exactly like the real zones.
func _build_tile_floor(cells: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)

	var source := TileSetAtlasSource.new()
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(TILE, TILE)
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, 0)

	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	var data := source.get_tile_data(Vector2i.ZERO, 0)
	data.set_collision_polygons_count(0, 1)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, TILE * 0.5),
		Vector2(-TILE * 0.5, TILE * 0.5),
	]))

	layer.tile_set = tile_set
	_rig.add_child(layer)
	for i: int in cells:
		layer.set_cell(Vector2i(i, 0), 0, Vector2i.ZERO)
	return layer


func _build_rig(start_x: float = 0.0) -> void:
	_rig = Node2D.new()
	root.add_child(_rig)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, 0.0)
	_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)


## Rig whose only floor is a TileMapLayer, built before Luz so she settles on it.
func _build_tile_rig(start_x: float, cells: int) -> TileMapLayer:
	_rig = Node2D.new()
	root.add_child(_rig)
	var layer := _build_tile_floor(cells)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, 0.0)
	_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)
	return layer


## Rig over a single solid body, returned so a case can move it.
func _build_solid_rig(start_x: float, floor_rect: Rect2) -> StaticBody2D:
	_rig = Node2D.new()
	root.add_child(_rig)
	var body := LevelGeometry.add_solid(_rig, floor_rect, Color.DIM_GRAY)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.position = Vector2(start_x, floor_rect.position.y)
	_rig.add_child(_player)
	await _frames(SETTLE_FRAMES)
	return body


func _free_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = null
	_player = null


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _add_hazard(rect: Rect2) -> ContactDamage:
	var hazard := (load(CONTACT_SCENE) as PackedScene).instantiate() as ContactDamage
	hazard.kind = ContactDamage.Kind.HAZARD
	_rig.add_child(hazard)
	hazard.set_area_size(rect.size)
	hazard.position = rect.get_center()
	return hazard


func _overlaps_hazard(hazard: ContactDamage) -> bool:
	var body := Rect2(_player.global_position - Vector2(PLAYER_BODY.x * 0.5, PLAYER_BODY.y), PLAYER_BODY)
	return hazard.get_world_rect().intersects(body)


func _wait_until(condition: Callable, limit_frames: int = 240) -> bool:
	for i: int in limit_frames:
		if condition.call():
			return true
		await process_frame
	return condition.call()


# -- Cases -----------------------------------------------------------------------

func case_tilemap_floor_records_safe_ground() -> void:
	await _build_tile_rig(100.0, 12)  # 12 tiles: floor spans x 0..192, top at y 0
	check(_player.is_on_floor(), "Luz stands on the TileMapLayer floor")
	_player.global_position.x = 160.0
	await _frames(20)
	check(_player._has_safe_ground, "the tilemap floor is remembered as safe ground")
	check(absf(_player.get_last_safe_ground().x - 160.0) < 2.0, "the safe spot follows her along the tilemap (x %.1f)" % _player.get_last_safe_ground().x)
	_player.global_position.x = 170.0
	await _frames(20)
	check(absf(_player.get_last_safe_ground().x - 160.0) < 2.0, "a spot next to the tile edge is not remembered (x %.1f)" % _player.get_last_safe_ground().x)


func case_tilemap_spike_returns_to_safe_ground() -> void:
	await _build_tile_rig(60.0, 24)  # floor spans x 0..384
	var hazard := _add_hazard(Rect2(250.0, -16.0, 96.0, 16.0))
	var health_before := _player.get_health()
	Input.action_press(&"move_right")
	var hit := await _wait_until(func() -> bool: return _player.get_health() < health_before, 300)
	Input.action_release(&"move_right")
	check(hit, "walking into the spikes hurts once")
	var safe := _player.get_last_safe_ground()
	await _wait_until(func() -> bool: return not _player.is_returning_to_safe_ground() and not _player.is_input_locked(), 180)
	check(_player.get_health() == health_before - 1, "the spikes cost exactly one pip (%d)" % _player.get_health())
	check(_player.global_position.distance_to(safe) < 3.0, "she returns to the remembered tilemap spot (%s vs %s)" % [_player.global_position, safe])
	check(safe.x < hazard.get_world_rect().position.x - _player.safe_ground_margin, "the tilemap spot is clear of the spikes (x %.0f)" % safe.x)
	check(not _overlaps_hazard(hazard), "she is not left inside the spikes")


func case_fall_returns_to_tilemap_safe_ground() -> void:
	await _build_tile_rig(0.0, 12)
	_player.global_position.x = 150.0
	await _frames(20)
	var safe := _player.get_last_safe_ground()
	_player.global_position.y = 1200.0
	await _frames(2)
	check(_player.fall_out_of_bounds(), "the out-of-bounds fall is accepted")
	await _wait_until(func() -> bool: return not _player.is_returning_to_safe_ground() and not _player.is_input_locked(), 180)
	check(_player.global_position.distance_to(safe) < 3.0, "the fall returns her to the tilemap spot (%s vs %s)" % [_player.global_position, safe])
	check(_player.global_position.distance_to(Vector2(0.0, 0.0)) > 100.0, "the fall does not use the scene start")


func case_safe_ground_follows_moving_platform() -> void:
	var platform := await _build_solid_rig(40.0, Rect2(-200.0, 0.0, 400.0, 40.0))
	await _frames(5)
	var before := _player.get_last_safe_ground()
	# Ride the platform: body and rider move together, as a moving platform does.
	platform.global_position.x += 120.0
	_player.global_position.x += 120.0
	await _frames(5)
	var after := _player.get_last_safe_ground()
	check(absf(after.x - (before.x + 120.0)) < 2.0, "the remembered spot moves with its platform (%.0f -> %.0f)" % [before.x, after.x])
	# Jumping off must leave the spot on the platform, not at its old world position.
	_player.global_position.y = -120.0
	await _frames(5)
	var jumped := _player.get_last_safe_ground()
	check(absf(jumped.x - after.x) < 2.0 and _player._safe_ground_anchor == platform, "the spot stays anchored to the platform after leaving it (x %.0f)" % jumped.x)


func case_respawn_clears_state_and_grants_iframes() -> void:
	await _build_rig(100.0)
	_player.set_checkpoint(Vector2(40.0, 0.0))
	_player.global_position = Vector2(300.0, 0.0)
	_player.velocity = Vector2(220.0, -300.0)
	_player._enter_state(Player.State.DASH)
	_player._air_jumps_left = 0
	_player._respawn_after_death()
	check(_player.global_position.distance_to(Vector2(40.0, 0.0)) < 2.0, "respawn moves her to the checkpoint")
	check(_player.velocity == Vector2.ZERO, "respawn cancels the old velocity")
	check(_player._state == Player.State.IDLE, "respawn returns her to idle")
	check(_player.get_health() == _player.max_health, "respawn restores full health")
	check(_player._invuln_left > 0.0, "respawn grants the post-death i-frames")
	check(not _player.take_hazard_damage(1, Vector2(0.0, 0.0)), "an immediate hazard hit is refused during those i-frames")

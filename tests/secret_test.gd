extends SceneTree
## Regression test for secret rooms: BreakableWall (hits, crumble, memory across
## reloads, no soul from hits, real attack hitbox), SoulCache (reward once, toast
## text), SecretChamber (cover hides the room until the wall breaks) and the
## New Game reset. The two real placements (library zone_5, Greece zone_3) are
## loaded as the player would meet them.
## Run: godot --headless --path . --script res://tests/secret_test.gd
## Exits 0 when every check passes, 1 otherwise.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WALL_SCENE := preload("res://scenes/world/breakable_wall.tscn")
const CACHE_SCENE := preload("res://scenes/world/soul_cache.tscn")
const ZONES := {
	"res://scenes/levels/library/zone_5.tscn": [&"library_zone_5_wall", &"library_zone_5_cache"],
	"res://scenes/levels/greece/zone_3.tscn": [&"greece_zone_3_wall", &"greece_zone_3_cache"],
}
const PLATFORMS := "TilemapLayers/Ground/Platforms"
const WATCHDOG_SECONDS := 120.0

var checks := 0
var failed: Array[String] = []
var _rig: Node2D
var _player: Player


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS)
	watchdog.timeout.connect(func() -> void:
		print("FAIL: watchdog")
		quit(1))
	await _run()
	var verdict := "PASS %d/%d" % [checks, checks] if failed.is_empty() else "FAIL %d/%d: %s" % [failed.size(), checks, ", ".join(failed)]
	print(verdict)
	quit(0 if failed.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed.append(label)


func _run() -> void:
	var progress := root.get_node("SecretProgress")
	progress.clear()
	await _case_wall_hits_and_crumble()
	await _case_wall_gives_no_soul()
	await _case_real_attack_breaks_wall()
	await _case_cache_gives_reward_once()
	for zone_path: String in ZONES:
		await _case_zone_placement(zone_path, ZONES[zone_path][0], ZONES[zone_path][1])
	_case_progress_memory_and_reset()
	progress.clear()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _build_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	_rig = Node2D.new()
	root.add_child(_rig)
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1200.0, 100.0)
	shape.shape = rect
	body.position = Vector2(0.0, 50.0)
	body.add_child(shape)
	_rig.add_child(body)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(-200.0, 0.0)
	_rig.add_child(_player)
	await _frames(20)


func _make_wall(id: StringName, hits: int) -> BreakableWall:
	var wall := WALL_SCENE.instantiate() as BreakableWall
	wall.wall_id = id
	wall.hits_required = hits
	wall.hit_cooldown = 0.0
	wall.position = Vector2(40.0, -48.0)
	_rig.add_child(wall)
	return wall


func _case_wall_hits_and_crumble() -> void:
	await _build_rig()
	var progress := root.get_node("SecretProgress")
	var wall := _make_wall(&"t_wall", 3)
	await _frames(2)
	check(wall.collision_layer & 1 == 1 and (wall.get_node("Hurtbox") as Area2D).collision_layer & 8 == 8, "wall is solid and its hurtbox is on the enemies layer")
	check(wall.receive_hit(1, Vector2.ZERO, &"attack_1"), "a hit counts")
	check(wall.receive_hit(1, Vector2.ZERO, &"attack_1") and wall.get_hits() == 2, "second hit counts")
	check(not wall.is_broken() and not progress.is_wall_broken(&"t_wall"), "N-1 hits leave it standing and unrecorded")
	var cooled := _make_wall(&"t_cool", 3)
	cooled.hit_cooldown = 0.5
	cooled.receive_hit(1, Vector2.ZERO)
	check(not cooled.receive_hit(1, Vector2.ZERO) and cooled.get_hits() == 1, "the cooldown ignores a repeat inside one swing")
	var crumbled := [false]
	wall.broken.connect(func(_id: StringName) -> void: crumbled[0] = true)
	wall.receive_hit(1, Vector2.ZERO, &"attack_1")
	check(wall.is_broken() and crumbled[0] and progress.is_wall_broken(&"t_wall"), "the last hit breaks it and records it")
	check(not wall.receive_hit(1, Vector2.ZERO), "a broken wall takes no more hits")
	await _wait(0.5)
	check(not is_instance_valid(wall), "the broken wall frees itself")
	var again := _make_wall(&"t_wall", 3)
	await _frames(2)
	check(not is_instance_valid(again) or again.is_queued_for_deletion(), "a wall already broken in this run does not come back")


func _case_wall_gives_no_soul() -> void:
	await _build_rig()
	var wall := _make_wall(&"t_nosoul", 2)
	await _frames(2)
	_player._resolve_attack_hit(wall, &"attack_1")
	_player._resolve_attack_hit(wall, &"attack_1")
	check(wall.is_broken(), "Luz's attack seam breaks the wall")
	check(_player.get_soul() == 0, "hitting a wall grants no soul")


func _case_real_attack_breaks_wall() -> void:
	await _build_rig()
	var wall := _make_wall(&"t_real", 20)
	wall.position = Vector2(30.0, -48.0)
	_player.position = Vector2(0.0, 0.0)
	await _frames(10)
	_player.request_attack(0)
	await _wait(0.7)
	check(wall.get_hits() >= 1, "Luz's real attack hitbox lands on the wall (%d hits)" % wall.get_hits())
	check(_player.get_soul() == 0, "and still gives no soul")


func _case_cache_gives_reward_once() -> void:
	await _build_rig()
	var progress := root.get_node("SecretProgress")
	var cache := CACHE_SCENE.instantiate() as SoulCache
	cache.reward_id = &"t_cache"
	cache.position = Vector2(100.0, 0.0)
	_rig.add_child(cache)
	await _frames(2)
	var opened := [0]
	cache.opened.connect(func(_id: StringName) -> void: opened[0] += 1)
	check(_player.get_soul() == 0, "soul starts empty")
	_player.global_position = cache.global_position + Vector2(0.0, -4.0)
	await _frames(6)
	check(_player.get_soul() == _player.get_max_soul(), "touching the cache fills the soul")
	check(opened[0] == 1 and progress.is_reward_claimed(&"t_cache") and cache.is_claimed(), "it opens once and is recorded")
	_player._set_soul(0)
	_player.global_position = cache.global_position + Vector2(200.0, -4.0)
	await _frames(4)
	_player.global_position = cache.global_position + Vector2(0.0, -4.0)
	await _frames(6)
	check(_player.get_soul() == 0 and opened[0] == 1, "touching it again gives nothing")
	var reloaded := CACHE_SCENE.instantiate() as SoulCache
	reloaded.reward_id = &"t_cache"
	reloaded.position = Vector2(300.0, 0.0)
	_rig.add_child(reloaded)
	await _frames(2)
	check(reloaded.is_claimed(), "a cache opened earlier in the run comes back empty")


## Loads a real zone, hits its secret wall open, reloads it and checks memory.
func _case_zone_placement(zone_path: String, wall_id: StringName, reward_id: StringName) -> void:
	var progress := root.get_node("SecretProgress")
	progress.clear()
	var zone := (load(zone_path) as PackedScene).instantiate()
	root.add_child(zone)
	await _frames(4)
	var label := zone_path.get_file()
	var wall := zone.find_child("SecretWall", true, false) as BreakableWall
	var chamber := zone.find_child("SecretChamber", true, false) as SecretChamber
	var cache := zone.find_child("SecretCache", true, false) as SoulCache
	var platforms := zone.get_node(PLATFORMS) as TileMapLayer
	check(wall != null and chamber != null and cache != null, "%s has a wall, a chamber and a cache" % label)
	if wall == null or chamber == null or cache == null:
		zone.free()
		return
	check(wall.wall_id == wall_id and chamber.reveal_wall_id == wall_id and cache.reward_id == reward_id, "%s ids line up" % label)
	var wall_cell := platforms.local_to_map(platforms.to_local(wall.global_position + Vector2.ONE * 0.5))
	check(platforms.get_cell_source_id(wall_cell) == -1, "%s the wall's tiles moved into its own look layer" % label)
	check(wall.get_node(wall.source_layer).get_child_count() > 0 and chamber.is_covered(), "%s the wall is drawn from tiles and the room is covered" % label)
	var room_cell := platforms.local_to_map(platforms.to_local(chamber.global_position + Vector2(20.0, 20.0)))
	check(platforms.get_cell_source_id(room_cell) == -1, "%s the room's cells are carved out of the solid layer" % label)
	wall.hit_cooldown = 0.0
	for i in wall.hits_required:
		wall.receive_hit(1, wall.global_position + Vector2(-30.0, 20.0), &"attack_1")
	check(wall.is_broken() and progress.is_wall_broken(wall_id), "%s breaks after hits_required hits" % label)
	await _wait(chamber.reveal_time + 0.5)
	check(not chamber.is_covered(), "%s the room is revealed once the wall breaks" % label)
	zone.free()
	var second := (load(zone_path) as PackedScene).instantiate()
	root.add_child(second)
	await _frames(4)
	var wall_again := second.find_child("SecretWall", true, false)
	var chamber_again := second.find_child("SecretChamber", true, false) as SecretChamber
	check(wall_again == null or wall_again.is_queued_for_deletion(), "%s stays broken after the zone reloads" % label)
	check(not chamber_again.is_covered(), "%s stays revealed after the zone reloads" % label)
	var reloaded_platforms := second.get_node(PLATFORMS) as TileMapLayer
	check(reloaded_platforms.get_cell_source_id(wall_cell) == -1, "%s the opening is clear after reload" % label)
	second.free()
	progress.clear()
	var fresh := (load(zone_path) as PackedScene).instantiate()
	root.add_child(fresh)
	await _frames(4)
	var fresh_wall := fresh.find_child("SecretWall", true, false) as BreakableWall
	check(fresh_wall != null and not fresh_wall.is_queued_for_deletion(), "%s the wall is back after a reset (New Game)" % label)
	fresh.free()


func _case_progress_memory_and_reset() -> void:
	var progress := root.get_node("SecretProgress")
	progress.clear()
	check(progress.break_wall(&"a") and not progress.break_wall(&"a"), "a wall is recorded once")
	check(progress.claim_reward(&"r") and not progress.claim_reward(&"r"), "a reward is recorded once")
	check(progress.count() == 2, "count adds walls and rewards")
	var copy: Dictionary = progress.to_dict()
	progress.clear()
	check(progress.count() == 0 and not progress.is_wall_broken(&"a"), "clear forgets everything")
	progress.from_dict(copy)
	check(progress.is_wall_broken(&"a") and progress.is_reward_claimed(&"r"), "to_dict and from_dict round-trip")
	progress.from_dict({"walls": 5})
	check(progress.count() == 0, "invalid data leaves a clean slate")
	var menu_source := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	check(menu_source.contains("/root/SecretProgress"), "New Game resets the secret progress")
	progress.clear()

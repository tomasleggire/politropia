extends SceneTree
## Ambience of the library and Greece zones: each playable zone has exactly one
## ZoneAmbience and one ParallaxBackdrop, the tint never reaches the HUD layers,
## the number of lights stays under the mobile budget, the biome styles load and
## the far parallax layer covers the whole view at the corners of the camera area.
## Run: godot --headless --path . --script res://tests/ambience_test.gd
## Exits 0 when every check passes, 1 otherwise.

const LEVELS: Array[String] = ["library", "greece"]
const ZONES: Array[String] = [
	"zone_1", "zone_2", "zone_3", "zone_4", "zone_5", "zone_6", "zone_healing", "zone_lectern",
	"zone_artemis",
]
const WATCHDOG_SECONDS := 180.0
## Most PointLight2D a zone may hold, Luz's own light included.
const MAX_LIGHTS := 8
## Window sizes the parallax must cover: the 640x360 base view and the largest
## view (wide phones and tablets) the backdrop is designed for.
const VIEW_SIZES: Array[Vector2i] = [Vector2i(640, 360), Vector2i(800, 500)]
## First CanvasLayer index of the HUD; the ambience layers must sit below it.
const HUD_LAYER := 40

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_check_styles()
	_check_light_prefab()
	for view_size: Vector2i in VIEW_SIZES:
		root.size = view_size
		for level: String in LEVELS:
			for zone: String in ZONES:
				await _check_zone("res://scenes/levels/%s/%s.tscn" % [level, zone], view_size == VIEW_SIZES[0])
	finish()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func finish() -> void:
	if failed.is_empty():
		print("PASS %d/%d" % [checks, checks])
		quit(0)
		return
	print("FAIL %d/%d" % [failed.size(), checks])
	for line: String in failed:
		print("  - " + line)
	quit(1)


func _on_watchdog() -> void:
	print("FAIL watchdog: the run did not finish in %.0fs" % WATCHDOG_SECONDS)
	quit(1)


func _check_styles() -> void:
	for biome: String in LEVELS:
		var style := load("res://data/ambience/%s.tres" % biome) as AmbienceStyle
		check(style != null, "%s ambience style loads" % biome)
		if style != null:
			check(style.tint_color != Color.WHITE, "%s style tints the world" % biome)


func _check_light_prefab() -> void:
	var light := (load("res://scenes/world/ambient_light.tscn") as PackedScene).instantiate() as AmbientLight
	root.add_child(light)
	light.base_energy = 1.0
	light.flicker_amount = 0.0
	check(not light.shadow_enabled, "ambient light casts no shadows (mobile budget)")
	check(is_equal_approx(light.energy, 1.0), "a steady light keeps its base energy")
	check(not light.is_processing(), "a steady light does not run every frame")
	light.flicker_amount = 0.3
	check(light.is_processing(), "a flickering light runs every frame")
	light.radius = 128.0
	check(is_equal_approx(light.texture_scale, 2.0), "radius maps to the texture scale")
	light.free()


## `full` also runs the ambience checks, which do not depend on the view size.
func _check_zone(path: String, full: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var zone := (load(path) as PackedScene).instantiate()
	root.add_child(zone)
	for i in 4:
		await physics_frame
	var label := path.get_base_dir().get_file() + "/" + path.get_file().get_basename()
	if full:
		var ambiences: Array[Node] = zone.find_children("*", "Node2D", false, false).filter(func(n: Node) -> bool: return n is ZoneAmbience)
		check(ambiences.size() == 1, "%s has exactly one ZoneAmbience (%d)" % [label, ambiences.size()])
		if ambiences.size() == 1:
			_check_tint(ambiences[0] as ZoneAmbience, label)
	var backdrops: Array[Node] = zone.find_children("*", "Node2D", false, false).filter(func(n: Node) -> bool: return n is ParallaxBackdrop)
	check(backdrops.size() == 1, "%s has exactly one ParallaxBackdrop (%d)" % [label, backdrops.size()])
	if backdrops.size() == 1:
		await _check_backdrop(zone, backdrops[0] as ParallaxBackdrop, label)
	if full:
		var lights := zone.find_children("*", "PointLight2D", true, false)
		check(lights.size() <= MAX_LIGHTS, "%s stays under %d lights (%d)" % [label, MAX_LIGHTS, lights.size()])
		check(zone.find_children("*", "CanvasModulate", true, false).size() == 1, "%s has a single CanvasModulate" % label)
	root.remove_child(zone)
	zone.free()
	await process_frame


func _check_backdrop(zone: Node, backdrop: ParallaxBackdrop, label: String) -> void:
	check(backdrop.style != null, "%s backdrop has a style" % label)
	check(backdrop.get_node("Haze").z_index > 1, "%s haze draws over the world" % label)
	var original := zone.get_node_or_null("TilemapLayers/Background")
	if original != null:
		for child in original.get_children():
			if child is Sprite2D:
				check(not (child as Sprite2D).visible, "%s original background is hidden" % label)
	var far := backdrop.get_node("Far") as Parallax2D
	var image := backdrop.get_node("Far/Image") as Sprite2D
	check(image.texture != null, "%s far layer has a picture" % label)
	if image.texture == null:
		return
	# Parking Luz at the corners must not trigger a door and unload the zone.
	for door in zone.find_children("*", "Area2D", true, false):
		if door is SceneTransitionArea:
			(door as SceneTransitionArea).set_deferred("monitoring", false)
	var player := get_first_node_in_group(&"player") as CharacterBody2D
	player.set_physics_process(false)
	var area := backdrop.get_area_rect()
	# Luz's camera centre roams the area minus half a view (the camera clamps
	# there in zones with limits; in the others Luz cannot go farther anyway).
	var reach := area.grow_individual(-root.size.x * 0.5, -root.size.y * 0.5, -root.size.x * 0.5, -root.size.y * 0.5)
	var corners: Array[Vector2] = [
		reach.position, Vector2(reach.end.x, reach.position.y),
		Vector2(reach.position.x, reach.end.y), reach.end,
	]
	for corner: Vector2 in corners:
		player.global_position = corner
		for i in 40:
			await physics_frame
		var camera := get_first_node_in_group(&"player_camera") as Camera2D
		var view_size := root.get_visible_rect().size
		var view := Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size)
		var shown := Rect2(image.global_position - image.texture.get_size() * image.global_scale * 0.5, image.texture.get_size() * image.global_scale)
		check(shown.encloses(view), "%s far layer covers a %s view at %s" % [label, root.size, corner])
	player.global_position = area.get_center()
	check(far.scroll_scale.x <= 1.0 and far.scroll_scale.y <= 1.0, "%s far layer scrolls slower than the world" % label)


func _check_tint(ambience: ZoneAmbience, label: String) -> void:
	var tint := ambience.get_node("Tint") as CanvasModulate
	check(tint.get_canvas_layer_node() == null, "%s tint sits on the world canvas, not a layer" % label)
	var layer := ambience.get_node("VignetteLayer") as CanvasLayer
	check(layer.layer < HUD_LAYER, "%s vignette sits below the HUD" % label)
	for node: Node in root.get_children():
		if node is CanvasLayer:
			check((node as CanvasLayer).get_canvas() != tint.get_canvas(), "%s: layer %s is not tinted" % [label, node.name])

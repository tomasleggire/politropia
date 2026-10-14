extends SceneTree
## Ambience of the library and Greece zones: each playable zone has exactly one
## ZoneAmbience, the tint never reaches the HUD layers, the number of lights
## stays under the mobile budget and the biome styles load.
## Run: godot --headless --path . --script res://tests/ambience_test.gd
## Exits 0 when every check passes, 1 otherwise.

const LEVELS: Array[String] = ["library", "greece"]
const ZONES: Array[String] = [
	"zone_1", "zone_2", "zone_3", "zone_4", "zone_5", "zone_6", "zone_healing", "zone_lectern",
]
const WATCHDOG_SECONDS := 180.0
## Most PointLight2D a zone may hold, Luz's own light included.
const MAX_LIGHTS := 8
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
	for level: String in LEVELS:
		for zone: String in ZONES:
			await _check_zone("res://scenes/levels/%s/%s.tscn" % [level, zone])
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


func _check_zone(path: String) -> void:
	var zone := (load(path) as PackedScene).instantiate()
	root.add_child(zone)
	for i in 4:
		await physics_frame
	var label := path.get_base_dir().get_file() + "/" + path.get_file().get_basename()
	var ambiences: Array[Node] = zone.find_children("*", "Node2D", false, false).filter(func(n: Node) -> bool: return n is ZoneAmbience)
	check(ambiences.size() == 1, "%s has exactly one ZoneAmbience (%d)" % [label, ambiences.size()])
	if ambiences.size() == 1:
		_check_tint(ambiences[0] as ZoneAmbience, label)
	var lights := zone.find_children("*", "PointLight2D", true, false)
	check(lights.size() <= MAX_LIGHTS, "%s stays under %d lights (%d)" % [label, MAX_LIGHTS, lights.size()])
	check(zone.find_children("*", "CanvasModulate", true, false).size() == 1, "%s has a single CanvasModulate" % label)
	root.remove_child(zone)
	zone.free()
	await process_frame


func _check_tint(ambience: ZoneAmbience, label: String) -> void:
	var tint := ambience.get_node("Tint") as CanvasModulate
	check(tint.get_canvas_layer_node() == null, "%s tint sits on the world canvas, not a layer" % label)
	var layer := ambience.get_node("VignetteLayer") as CanvasLayer
	check(layer.layer < HUD_LAYER, "%s vignette sits below the HUD" % label)
	for node: Node in root.get_children():
		if node is CanvasLayer:
			check((node as CanvasLayer).get_canvas() != tint.get_canvas(), "%s: layer %s is not tinted" % [label, node.name])

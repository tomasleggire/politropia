extends Node

const DEMO_SCENES: Array[String] = [
	"res://scenes/levels/zone_healing.tscn",
    "res://scenes/levels/zone_artemis.tscn"
]


func preload_demo_scenes() -> void:
	for path in DEMO_SCENES:
		if ResourceLoader.has_cached(path):
			continue

		var error := ResourceLoader.load_threaded_request(path)

		if error != OK and error != ERR_ALREADY_IN_USE:
			push_warning("Could not preload scene: " + path)

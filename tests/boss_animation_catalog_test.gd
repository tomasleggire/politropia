extends SceneTree
## BossAnimationCatalog: SpriteFrames built from a manifest (clips, frame counts, speeds,
## looping, grid regions), clip resolution through fallbacks and the default clip, the
## event frame, the sprite scale and offset, the props sheet, and the silence of a missing
## manifest, a missing texture, a malformed manifest and a missing sheet entry.
## The fixture (a manifest and a tiny sheet PNG) is written to user:// at test time.
## Run: godot --headless --path . --script res://tests/boss_animation_catalog_test.gd
## Exits 0 when every check passes, 1 otherwise.

const FIXTURE_DIR := "user://boss_animation_catalog_test"
const MANIFEST := FIXTURE_DIR + "/animation_manifest.json"
const CELL := 4
const COLUMNS := 4
const ROWS := 2
const SPEEDS := {"idle": 8.0, "run": 12.0}
const LOOPING := ["idle"]
const FALLBACKS := {"jump": ["run", "idle"], "glide": ["nothing"]}

var checks := 0
var failed: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	_write_fixture()
	case_builds_clips()
	case_speed_and_looping()
	case_grid_regions()
	case_resolves_fallbacks()
	case_events_scale_and_offset()
	case_props()
	case_missing_manifest()
	case_missing_texture()
	case_malformed_manifest()
	case_missing_default_clip()
	_remove_fixture()
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


# -- Fixture --------------------------------------------------------------------------

func _catalog(path := MANIFEST) -> BossAnimationCatalog:
	return BossAnimationCatalog.new(path, FALLBACKS, SPEEDS, LOOPING)


func _write_sheet(file_name: String, columns: int, rows: int) -> void:
	var image := Image.create_empty(columns * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png(FIXTURE_DIR.path_join(file_name))


func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data) if not data is String else data)


func _grid(columns: int, rows: int) -> Dictionary:
	return {"columns": columns, "rows": rows, "cell_width": CELL, "cell_height": CELL}


func _write_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	_write_sheet("main_sheet.png", COLUMNS, ROWS)
	_write_sheet("props_sheet.png", COLUMNS, 1)
	_write_json(MANIFEST, {
		"cell": 448, "feet_row": 416, "sprite_scale": 0.25,
		"sheets": {
			"main_sheet.png": {
				"grid": _grid(COLUMNS, ROWS),
				"clips": {"idle": [0, 1, 2], "run": [3, 4, 5, 6], "strike": [7]},
				"events": {"strike": 0, "run": 2},
			},
			"ghost_sheet.png": {"grid": _grid(COLUMNS, ROWS), "clips": {"ghost": [0, 1]}, "events": {}},
		},
		"props": {"sheet": "props_sheet.png", "sprite_scale": 0.25, "grid": _grid(COLUMNS, 1), "clips": {"spark": [0], "steam": [1, 2]}},
	})


func _remove_fixture() -> void:
	for file_name: String in DirAccess.get_files_at(FIXTURE_DIR):
		DirAccess.remove_absolute(FIXTURE_DIR.path_join(file_name))
	DirAccess.remove_absolute(FIXTURE_DIR)


# -- Cases ----------------------------------------------------------------------------

func case_builds_clips() -> void:
	var catalog := _catalog()
	var frames := catalog.build_sprite_frames()
	check(catalog.has_art(), "a manifest with the default clip has art")
	check(frames.has_animation(&"idle") and frames.has_animation(&"run") and frames.has_animation(&"strike"), "every clip of a loaded sheet is built")
	check(frames.get_frame_count(&"idle") == 3 and frames.get_frame_count(&"run") == 4 and frames.get_frame_count(&"strike") == 1, "each clip has the frames the manifest lists")
	check(not frames.has_animation(&"default"), "the engine's default animation is removed")
	check(not frames.has_animation(&"ghost"), "a sheet whose texture is missing adds no clips")
	check(catalog.build_sprite_frames() == frames, "the frames are built once")


func case_speed_and_looping() -> void:
	var frames := _catalog().build_sprite_frames()
	check(is_equal_approx(frames.get_animation_speed(&"idle"), 8.0) and is_equal_approx(frames.get_animation_speed(&"run"), 12.0), "speeds come from the table")
	check(is_equal_approx(frames.get_animation_speed(&"strike"), BossAnimationCatalog.DEFAULT_FPS), "a clip with no speed uses the default fps")
	check(frames.get_animation_loop(&"idle") and not frames.get_animation_loop(&"run"), "only the listed clips loop")


func case_grid_regions() -> void:
	var frames := _catalog().build_sprite_frames()
	var first := frames.get_frame_texture(&"run", 0) as AtlasTexture
	var wrapped := frames.get_frame_texture(&"strike", 0) as AtlasTexture
	check(first != null and first.region == Rect2(3 * CELL, 0, CELL, CELL), "frame 3 is the last cell of the first row")
	check(wrapped != null and wrapped.region == Rect2(3 * CELL, CELL, CELL, CELL), "frame 7 is the last cell of the second row")


func case_resolves_fallbacks() -> void:
	var catalog := _catalog()
	check(catalog.resolve_clip(&"run") == &"run", "a drawn clip resolves to itself")
	check(catalog.resolve_clip(&"jump") == &"run", "a missing clip resolves to its first fallback that exists")
	check(catalog.resolve_clip(&"glide") == &"idle", "a clip whose fallbacks are missing resolves to the default clip")
	check(catalog.resolve_clip(&"never_heard_of") == &"idle", "an unknown clip resolves to the default clip")


func case_events_scale_and_offset() -> void:
	var catalog := _catalog()
	check(catalog.event_frame(&"run") == 2 and catalog.event_frame(&"strike") == 0, "the event frame comes from the manifest")
	check(catalog.event_frame(&"idle") == 0, "a clip with no event reports frame 0")
	check(is_equal_approx(catalog.sprite_scale(), 0.25), "the sprite scale comes from the manifest")
	check(catalog.sprite_offset() == Vector2(0.0, -192.0), "the offset puts the feet row (416) on the origin of a 448 cell")


func case_props() -> void:
	var props := _catalog().build_props_frames()
	check(props.has_animation(&"spark") and props.get_frame_count(&"steam") == 2, "the props sheet builds its own clips")
	check(not props.has_animation(&"idle"), "the props frames do not mix with the character's")


func case_missing_manifest() -> void:
	var catalog := _catalog(FIXTURE_DIR + "/nope.json")
	var frames := catalog.build_sprite_frames()
	check(frames != null and frames.get_animation_names().is_empty(), "a missing manifest builds empty frames")
	check(not catalog.has_art(), "a missing manifest has no art")
	check(catalog.resolve_clip(&"idle") == &"", "nothing resolves without art")
	check(catalog.build_props_frames().get_animation_names().is_empty(), "a missing manifest has no props")
	check(catalog.event_frame(&"strike") == 0 and is_equal_approx(catalog.sprite_scale(), BossAnimationCatalog.DEFAULT_SPRITE_SCALE), "the accessors fall back to defaults")


func case_missing_texture() -> void:
	var path := FIXTURE_DIR + "/no_texture.json"
	_write_json(path, {"cell": 4, "feet_row": 3, "sprite_scale": 0.3, "sheets": {"absent_sheet.png": {"grid": _grid(COLUMNS, ROWS), "clips": {"idle": [0]}, "events": {}}}})
	var catalog := _catalog(path)
	check(not catalog.has_art() and catalog.build_sprite_frames().get_animation_names().is_empty(), "a manifest whose texture is missing has no art and no clips")


func case_malformed_manifest() -> void:
	var path := FIXTURE_DIR + "/broken.json"
	_write_json(path, "{ this is not json")
	check(not _catalog(path).has_art(), "a malformed manifest has no art")
	_write_json(path, [1, 2, 3])
	check(not _catalog(path).has_art(), "a manifest that is not a dictionary has no art")


func case_missing_default_clip() -> void:
	var path := FIXTURE_DIR + "/no_idle.json"
	_write_json(path, {"sheets": {"main_sheet.png": {"grid": _grid(COLUMNS, ROWS), "clips": {"run": [0, 1]}, "events": {}}}})
	var catalog := _catalog(path)
	check(not catalog.has_art(), "art without the default clip is not usable art")
	check(catalog.resolve_clip(&"jump") == &"run", "a fallback still resolves without the default clip")
	check(catalog.resolve_clip(&"glide") == &"", "no fallback and no default clip resolves to nothing")

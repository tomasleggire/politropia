extends SceneTree

# CHANGE THESE PATHS to match your project.
const MINIGAME_SCENE: PackedScene = preload("res://scenes/world/mini_game.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/world/secret_chest.tscn")

var failures := 0
var tests_run := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var test_root := Node2D.new()
	root.add_child(test_root)
	current_scene = test_root

	await _test_minigame()
	await _test_chest(test_root)

	print("\n-----------------------------")
	print("Tests run: ", tests_run)
	print("Failures: ", failures)
	print("-----------------------------")

	quit(1 if failures > 0 else 0)


func check(condition: bool, description: String) -> void:
	tests_run += 1

	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _test_minigame() -> void:
	print("\n--- MINIGAME TESTS ---")

	var game = MINIGAME_SCENE.instantiate()
	game.target_word = "BIBLIOTECA"
	game.syllables = ["BI", "BLO", "TE", "CA"]
	root.add_child(game)

	await process_frame

	# Incomplete answer should not allow submission.
	check(game.check_button.disabled, "Check disabled with empty answer")

	# Select one syllable.
	var li_index: int = game.shuffled_syllables.find("LI")
	game._on_syllable_pressed(li_index)

	check(
		game.selected_indices.count(-1) == 1,
		"Selecting a syllable fills one answer slot"
	)

	# Selecting the same syllable twice should not duplicate it.
	game._on_syllable_pressed(li_index)

	check(
		game.selected_indices.count(li_index) == 1,
		"Cannot select the same syllable twice"
	)

	# Remove the selected syllable.
	game._on_slot_pressed(0)

	check(
		game.selected_indices.count(-1) == 2,
		"Removing a syllable clears its answer slot"
	)

	game.queue_free()
	await process_frame

	# Test an incorrect answer.
	game = MINIGAME_SCENE.instantiate()
	game.target_word = "LIBRO"
	game.syllables = ["LI", "BRO"]
	root.add_child(game)

	await process_frame

	var bro_index: int = game.shuffled_syllables.find("BRO")
	li_index = game.shuffled_syllables.find("LI")

	game._on_syllable_pressed(bro_index)
	game._on_syllable_pressed(li_index)
	game._on_check_pressed()

	check(
		not game.finished,
		"Incorrect answer does not finish the minigame"
	)
	check(
		game.feedback.text == "¡Intentá de nuevo!",
		"Incorrect answer displays retry feedback"
	)

	game.queue_free()
	await process_frame

	# Test a correct answer.
	game = MINIGAME_SCENE.instantiate()
	game.target_word = "LIBRO"
	game.syllables = ["LI", "BRO"]

	var result: Array[bool] = []
	game.completed.connect(func(success: bool): result.append(success))

	root.add_child(game)
	await process_frame

	li_index = game.shuffled_syllables.find("LI")
	bro_index = game.shuffled_syllables.find("BRO")

	game._on_syllable_pressed(li_index)
	game._on_syllable_pressed(bro_index)
	game._on_check_pressed()

	await create_timer(1.0).timeout

	check(
		result.size() == 1 and result[0],
		"Correct answer emits completed(true)"
	)


func _test_chest(test_root: Node2D) -> void:
	print("\n--- CHEST TESTS ---")

	var chest = CHEST_SCENE.instantiate()
	test_root.add_child(chest)

	await process_frame

	check(not chest.visible, "Chest starts hidden")
	check(
		not chest.interaction_area.monitoring,
		"Interaction starts disabled"
	)

	# Reveal chest.
	chest.reveal()

	check(chest.visible, "Revealing chest makes it visible")
	check(
		chest.interaction_area.monitoring,
		"Revealing chest enables interaction"
	)

	# Simulate an unsuccessful minigame result.
	chest.minigame_active = true
	chest._on_minigame_completed(false)

	check(
		not chest.opened,
		"Failed minigame does not open chest"
	)
	check(
		not chest.minigame_active,
		"Failed minigame allows another attempt"
	)

	# Simulate a successful result.
	var opened_signal: Array[bool] = []
	chest.chest_opened.connect(func(): opened_signal.append(true))

	chest._on_minigame_completed(true)

	check(chest.opened, "Successful minigame opens chest")
	check(
		not chest.interaction_area.monitoring,
		"Opening chest disables interaction"
	)
	check(
		opened_signal.size() == 1,
		"Chest emits chest_opened once"
	)

	# Trying to open it again must not emit another signal.
	chest.open_chest()

	check(
		opened_signal.size() == 1,
		"Already-open chest cannot open twice"
	)

	chest.queue_free()

extends Node
## Scripted gameplay capture of Luz in the real Greece level (Movie Maker).
##
## One line (from the project root, non-headless; needs ffmpeg and a python with
## pillow + numpy):
##   PYTHON=<venv>/bin/python tools/capture/capture.sh <out_dir> ~/Desktop/Caminar.mov
## capture.sh runs this scene with Godot Movie Maker (--write-movie run.avi
## --fixed-fps 60, 1280x720 through a temporary override.cfg), then extract.py cuts
## frames, a close-up MP4 and the side-by-side against the Penitent reference.
##
## Sequence: idle 1.5 s, run right 2 s, stop (skid), idle 1 s, run left 1.5 s
## (turn from idle-run), reverse to right while running (turn), run 1 s,
## stop, idle 1 s, a standing jump and a running jump, then three reversal cases
## (release for 3 frames, release for 6 frames, plain stop), then the jump and dash
## set: standing full jump, tap jump, running jump (held), the standing landing
## recovery, a ground dash from rest, a ground dash from a run and an air dash.
## LUZ_CAPTURE_MODE=attacks records an attack sequence instead (see _attack_steps):
## whiffs, a full 3-hit combo on a dummy walker, crouch, up, a fast mash and air attacks.
## LUZ_CAPTURE_MODE=air records the vertical set (see _air_steps): standing and running
## jumps, a double jump (unlocked for the capture), landings, crouch, crouch attack and
## standing up.
## Input goes through Input.action_press/release like a player. track.csv has a
## `step` column (index into the sequence) to cut each action out.

const LEVEL_PATH := "res://scenes/levels/greece/level_greece.tscn"
const LEVEL_FALLBACK := "res://scenes/levels/greece_level.tscn"
## Start on a long flat stretch of the Greece level (x 1144-2048, floor y -414).
const START_POSITION := Vector2(1250.0, -440.0)
## [seconds, action to press (""=none), ...] built in _ready.
var _steps: Array = []
var _time := 0.0
var _index := 0
var _held: Array = []
var _player: Player
var _sprite: AnimatedSprite2D
var _log: FileAccess
var _frame := 0
var _attack_mode := false
var _air_mode := false
var _target: Node2D
var _tag := ""


func _ready() -> void:
	var path := LEVEL_PATH if ResourceLoader.exists(LEVEL_PATH) else LEVEL_FALLBACK
	add_child((load(path) as PackedScene).instantiate())
	_attack_mode = OS.get_environment("LUZ_CAPTURE_MODE") == "attacks"
	_air_mode = OS.get_environment("LUZ_CAPTURE_MODE") == "air"
	_steps = _attack_steps() if _attack_mode else (_air_steps() if _air_mode else _locomotion_steps())
	await get_tree().process_frame
	_player = _find_player(self)
	if _player == null:
		push_error("luz_capture: no Player in the level")
		get_tree().quit(1)
		return
	_sprite = _player.get_node_or_null("AnimatedSprite2D")
	if path == LEVEL_PATH:
		_player.global_position = START_POSITION
		_player.velocity = Vector2.ZERO
		_player.reset_physics_interpolation()
		var camera := get_tree().get_first_node_in_group(&"player_camera") as Camera2D
		if camera != null:
			camera.reset_smoothing()
			camera.reset_physics_interpolation()
	if _air_mode:
		_player.unlock_double_jump()
	if _attack_mode:
		_spawn_target()
	# Per-frame track (frame, screen x/y, world x/y, velocity x, animation, frame
	# index) so extract.py can follow Luz with the close-up crop.
	var out := OS.get_environment("LUZ_CAPTURE_OUT")
	if out != "":
		_log = FileAccess.open(out.path_join("track.csv"), FileAccess.WRITE)
		_log.store_line("frame,sx,sy,wx,wy,vx,anim,aframe,step,tag")


## Attack sequence: whiffs (mashed), a landed combo on the dummy (the dummy moves
## in front of her at the "target" step), crouch, up and air attacks. Entries may
## carry a tag (third item); a tag is also the callback name for "target".
func _attack_steps() -> Array:
	return [
		[1.0, &""],
		# Whiffs: hit 1 repeats.
		[0.05, &"attack", "whiff"], [0.25, &"", "whiff"], [0.05, &"attack", "whiff"], [0.25, &"", "whiff"],
		[0.05, &"attack", "whiff"], [0.25, &"", "whiff"], [0.05, &"attack", "whiff"], [0.9, &"", "whiff"],
		[0.2, &"", "target"],
		# A landed 3-hit combo: taps spaced so each press continues the chain.
		[0.05, &"attack", "combo"], [0.30, &"", "combo"], [0.05, &"attack", "combo"], [0.38, &"", "combo"],
		[0.05, &"attack", "combo"], [1.0, &"", "combo"],
		[0.6, &"", ""],
		[0.5, &"move_down", ""], [0.05, [&"move_down", &"attack"], "crouch"], [0.9, &"move_down", "crouch"], [0.6, &"", ""],
		[0.05, [&"move_up", &"attack"], "up"], [0.9, &"", "up"],
		# Fast mash: a press every ~4 frames for 1 s (no target, so every hit whiffs).
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.03, &"attack", "mash"], [0.03, &"", "mash"], [0.03, &"attack", "mash"], [0.03, &"", "mash"],
		[0.8, &"", "mash"],
		[0.1, &"jump", "air"], [0.3, &"", "air"], [0.05, &"attack", "air"], [1.2, &"", "air"],
	]


func _spawn_target() -> void:
	var walker := (load("res://scenes/enemies/walker.tscn") as PackedScene).instantiate()
	walker.set("enemy_id", &"capture_dummy")
	walker.set("max_health", 999)
	walker.set("contact_damage", 0)
	walker.set("walk_speed", 0.0)
	walker.set("start_facing", -1)
	add_child(walker)
	walker.global_position = START_POSITION + Vector2(-600.0, 0.0)
	_target = walker


func _on_step_start(tag: String) -> void:
	_tag = tag
	if tag == "target" and _target != null:
		_target.global_position = _player.global_position + Vector2(62.0, 0.0)


## Vertical set. Starts on the flat stretch (x 1144-2048): runs right 1 s, then jumps in place and
## alternates directions so she never leaves it.
func _air_steps() -> Array:
	return [
		[1.0, &""], [1.0, &"move_right"], [1.0, &""],
		# Standing full jump (held) and its landing recovery.
		[0.7, &"jump"], [1.6, &""],
		# Tap jump, then a running jump and a running landing.
		[0.05, &"jump"], [1.4, &""],
		[0.5, &"move_right"], [0.7, [&"move_right", &"jump"]], [0.7, &"move_right"], [1.0, &""],
		# Double jump: jump, release, press again near the apex (held both times).
		[0.7, &"move_left"], [0.15, [&"move_left", &"jump"]], [0.2, &"move_left"],
		[0.9, [&"move_left", &"jump"]], [1.0, &"move_left"], [1.4, &""],
		# Standing double jump.
		[0.4, &"jump"], [0.1, &""], [0.9, &"jump"], [1.6, &""],
		# Crouch, hold, stand up; crouch attack and back to the crouch; stand up.
		[0.3, &""], [1.0, &"move_down"], [0.8, &""], [0.6, &""],
		[0.5, &"move_down"], [0.05, [&"move_down", &"attack"], "crouch"], [0.9, &"move_down"], [0.5, &"move_down"],
		[0.05, [&"move_down", &"attack"], "crouch"], [0.9, &"move_down"], [0.8, &""], [1.0, &""],
	]


func _locomotion_steps() -> Array:
	return [
		[1.5, &""], [2.0, &"move_right"], [1.0, &""],
		[1.5, &"move_left"], [1.5, &"move_right"], [0.2, &""],
		[1.0, &"move_right"], [1.0, &""],
		# Reversal while running: a stick that crosses zero (3 frames), a reversal
		# pressed while the skid has already started, and a plain stop.
		[1.0, &"move_left"], [0.05, &""], [1.0, &"move_right"], [0.8, &""],
		[1.0, &"move_right"], [0.1, &""], [0.8, &"move_left"], [1.0, &""],
		[1.0, &"move_left"], [1.5, &""],
		# Jump from idle, then a running jump (takeoff and landing dust).
		[0.1, &"jump"], [1.0, &""], [0.6, &"move_right"],
		[0.1, [&"move_right", &"jump"]], [0.7, &"move_right"], [1.0, &""],
		# Jump and dash set. It first runs left to the middle of the flat stretch and
		# alternates directions so she never leaves it (x 1144-2048): standing full
		# jump (held), landing recovery, tap jump, held running jump, ground dash
		# from rest, dash from a run (left), air dash (left).
		[3.0, &"move_left"], [1.0, &""],
		[0.7, &"jump"], [1.2, &""],
		[0.05, &"jump"], [1.2, &""],
		[0.5, &"move_right"], [0.7, [&"move_right", &"jump"]], [0.6, &"move_right"], [1.0, &""],
		[0.1, &"dash"], [1.2, &""],
		[0.6, &"move_left"], [0.1, [&"move_left", &"dash"]], [0.5, &"move_left"], [1.0, &""],
		[0.15, &"jump"], [0.1, &""], [0.1, &"dash"], [1.2, &""],
	]


func _find_player(node: Node) -> Player:
	if node is Player:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _process(_delta: float) -> void:
	if _log == null or _player == null:
		return
	var screen := _player.get_global_transform_with_canvas().origin
	var anim := String(_sprite.animation) if _sprite != null else ""
	var aframe := _sprite.frame if _sprite != null else -1
	_log.store_line("%d,%.1f,%.1f,%.1f,%.1f,%.1f,%s,%d,%d,%s" % [_frame, screen.x, screen.y,
		_player.global_position.x, _player.global_position.y, _player.velocity.x, anim, aframe, _index, _tag])
	_frame += 1


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if _index >= _steps.size():
		_release()
		if _log != null:
			_log.close()
			_log = null
		get_tree().quit()
		return
	_time += delta
	var step: Array = _steps[_index]
	var step_tag: String = step[2] if step.size() > 2 else ""
	if step_tag != _tag:
		_on_step_start(step_tag)
	var wanted: Array = step[1] if step[1] is Array else ([] if step[1] == &"" else [step[1]])
	if _held != wanted:
		_release()
		_held = wanted
		for action: StringName in _held:
			Input.action_press(action)
	if _time >= float(step[0]):
		_time = 0.0
		_index += 1


func _release() -> void:
	for action: StringName in _held:
		Input.action_release(action)
	_held = []

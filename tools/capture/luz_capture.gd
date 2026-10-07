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
## stop, idle 1 s. Input goes through Input.action_press/release like a player.

const LEVEL_PATH := "res://scenes/levels/greece/level_greece.tscn"
const LEVEL_FALLBACK := "res://scenes/levels/greece_level.tscn"
## Start on a long flat stretch of the Greece level (x 1144-2048, floor y -414).
const START_POSITION := Vector2(1250.0, -440.0)
## [seconds, action to press (""=none), ...] built in _ready.
var _steps: Array = []
var _time := 0.0
var _index := 0
var _held: StringName = &""
var _player: Player
var _sprite: AnimatedSprite2D
var _log: FileAccess
var _frame := 0


func _ready() -> void:
	var path := LEVEL_PATH if ResourceLoader.exists(LEVEL_PATH) else LEVEL_FALLBACK
	add_child((load(path) as PackedScene).instantiate())
	_steps = [
		[1.5, &""], [2.0, &"move_right"], [1.0, &""],
		[1.5, &"move_left"], [1.5, &"move_right"], [0.2, &""],
		[1.0, &"move_right"], [1.0, &""],
	]
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
	# Per-frame track (frame, screen x/y, world x/y, velocity x, animation, frame
	# index) so extract.py can follow Luz with the close-up crop.
	var out := OS.get_environment("LUZ_CAPTURE_OUT")
	if out != "":
		_log = FileAccess.open(out.path_join("track.csv"), FileAccess.WRITE)
		_log.store_line("frame,sx,sy,wx,wy,vx,anim,aframe")


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
	_log.store_line("%d,%.1f,%.1f,%.1f,%.1f,%.1f,%s,%d" % [_frame, screen.x, screen.y,
		_player.global_position.x, _player.global_position.y, _player.velocity.x, anim, aframe])
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
	if _held != step[1]:
		_release()
		_held = step[1]
		if _held != &"":
			Input.action_press(_held)
	if _time >= float(step[0]):
		_time = 0.0
		_index += 1


func _release() -> void:
	if _held != &"":
		Input.action_release(_held)
	_held = &""

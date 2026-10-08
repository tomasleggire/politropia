@tool
class_name ShadowOwl
extends Flyer

## Library owl that hunts Luz by flying into her, like the book flyer.

const SHEET := preload("res://assets/art/library/enemies/shadow_owl_atlas.png")
## The source has six aligned rows, but individual owls spill across the
## nominal 10-column grid. These per-sprite X bounds keep adjacent frames out.
const ROW_TOPS := [0.0, 170.0, 340.0, 510.0, 680.0, 850.0]
const ROW_HEIGHTS := [170.0, 170.0, 170.0, 170.0, 170.0, 174.0]
const FRAME_X_RANGES := [
	[Vector2i(20, 168), Vector2i(187, 324), Vector2i(344, 483), Vector2i(505, 635), Vector2i(658, 796), Vector2i(811, 935), Vector2i(936, 1068), Vector2i(1073, 1215), Vector2i(1234, 1359), Vector2i(1391, 1512)],
	[Vector2i(22, 153), Vector2i(184, 339), Vector2i(360, 489), Vector2i(507, 643), Vector2i(656, 786), Vector2i(799, 936), Vector2i(946, 1062), Vector2i(1082, 1203), Vector2i(1217, 1357), Vector2i(1373, 1509)],
	[Vector2i(14, 168), Vector2i(180, 333), Vector2i(344, 501), Vector2i(510, 657), Vector2i(671, 797), Vector2i(811, 946), Vector2i(960, 1080), Vector2i(1100, 1237), Vector2i(1250, 1377), Vector2i(1391, 1518)],
	[Vector2i(31, 214), Vector2i(248, 470), Vector2i(482, 659), Vector2i(686, 873), Vector2i(891, 1062), Vector2i(1066, 1226), Vector2i(1230, 1377), Vector2i(1390, 1518)],
	[Vector2i(17, 156), Vector2i(174, 326), Vector2i(332, 466), Vector2i(481, 666), Vector2i(670, 797), Vector2i(816, 973), Vector2i(979, 1132), Vector2i(1162, 1280)],
	[Vector2i(20, 155), Vector2i(194, 327), Vector2i(368, 501)]
]

enum AttackPhase { APPROACH, WINDUP, DIVE, CHARGE, RECOVER }

@export_group("Attack")
@export var attack_trigger_distance := 180.0
@export var windup_duration := 0.7
@export var dive_duration := 0.35
@export var dive_speed := 85.0
@export var charge_speed := 260.0
@export var charge_duration := 0.4
@export var recover_duration := 0.6

var _owl_sprite: AnimatedSprite2D
@onready var _attack_sfx: AudioStreamPlayer2D = $AttackSfx
var _attack_phase := AttackPhase.APPROACH
var _phase_left := 0.0
var _charge_direction := Vector2.RIGHT


func _ready() -> void:
	super._ready()
	_owl_sprite = $Visual/AnimatedSprite2D as AnimatedSprite2D
	_owl_sprite.sprite_frames = _make_sprite_frames()
	_play_owl_animation(&"hover")


func _think(delta: float) -> void:
	super._think(delta)
	if _mode == Mode.IDLE and _owl_sprite.animation != &"hover":
		_play_owl_animation(&"hover")
	elif _mode == Mode.RETURN and _owl_sprite.animation != &"fly":
		_play_owl_animation(&"fly")


func _engaged_think(delta: float) -> void:
	var to_player := _player_center() - get_body_center()
	_face_x(to_player.x)
	match _attack_phase:
		AttackPhase.APPROACH:
			super._engaged_think(delta)
			if to_player.length() <= attack_trigger_distance:
				_start_phase(AttackPhase.WINDUP, windup_duration, &"windup")
		AttackPhase.WINDUP:
			velocity = velocity.move_toward(Vector2.ZERO, chase_acceleration * delta)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_start_phase(AttackPhase.DIVE, dive_duration, &"dive")
		AttackPhase.DIVE:
			var dive_direction := to_player.normalized()
			velocity = velocity.move_toward(dive_direction * dive_speed, chase_acceleration * delta)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_charge_direction = to_player.normalized()
				if _charge_direction.length_squared() < 0.001:
					_charge_direction = Vector2(float(_facing), 0.0)
				_start_phase(AttackPhase.CHARGE, charge_duration, &"charge")
		AttackPhase.CHARGE:
			velocity = _charge_direction * charge_speed
			_face_x(_charge_direction.x)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_start_phase(AttackPhase.RECOVER, recover_duration, &"recover")
		AttackPhase.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, chase_acceleration * delta)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_attack_phase = AttackPhase.APPROACH
				_play_owl_animation(&"fly")


func _on_engaged() -> void:
	super._on_engaged()
	_start_phase(AttackPhase.WINDUP, windup_duration, &"windup")


func make_corpse_at(at: Vector2, facing: int) -> void:
	super.make_corpse_at(at, facing)
	_play_owl_animation(&"death")


func _reset_ai() -> void:
	super._reset_ai()
	_attack_phase = AttackPhase.APPROACH
	_phase_left = 0.0
	_charge_direction = Vector2.RIGHT
	_play_owl_animation(&"fly")


func _start_phase(phase: AttackPhase, duration: float, animation: StringName) -> void:
	_attack_phase = phase
	_phase_left = duration
	_play_owl_animation(animation)
	if phase == AttackPhase.CHARGE:
		_attack_sfx.play()


func _play_owl_animation(name: StringName) -> void:
	if _owl_sprite == null or _owl_sprite.sprite_frames == null:
		return
	if _owl_sprite.animation != name:
		_owl_sprite.play(name)


func _make_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	_add_animation(frames, &"fly", 0, 0, 10, 10.0, true)
	_add_animation(frames, &"hover", 1, 0, 10, 10.0, true)
	_add_animation(frames, &"windup", 1, 0, 10, 10.0, false)
	_add_animation(frames, &"dive", 2, 0, 10, 14.0, false)
	_add_animation(frames, &"charge", 3, 0, 8, 15.0, false)
	_add_animation(frames, &"recover", 4, 0, 5, 10.0, false)
	_add_animation(frames, &"death", 4, 5, 3, 12.0, false)
	_add_animation(frames, &"death", 5, 0, 3, 12.0, false)
	return frames


func _add_animation(
	frames: SpriteFrames,
	name: StringName,
	row: int,
	first_column: int,
	count: int,
	fps: float,
	loop: bool
) -> void:
	if not frames.has_animation(name):
		frames.add_animation(name)
		frames.set_animation_speed(name, fps)
		frames.set_animation_loop(name, loop)
	for column in range(first_column, first_column + count):
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEET
		var bounds: Vector2i = FRAME_X_RANGES[row][column]
		atlas.region = Rect2(
			Vector2(float(bounds.x), ROW_TOPS[row]),
			Vector2(float(bounds.y - bounds.x), ROW_HEIGHTS[row])
		)
		atlas.filter_clip = true
		frames.add_frame(name, atlas)

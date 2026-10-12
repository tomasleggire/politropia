class_name DoubleJumpReward
extends Area2D

## Pickup that grants Luz the double jump. A BossArena drops it where the boss
## fell; it can also be placed by hand. Touching it calls `unlock_double_jump()`
## on the player, then it frees itself. Placeholder look: a pale glowing
## diamond with small wings, bobbing gently.

signal collected(player: Node)

const PLAYER_GROUP := &"player"
const UNLOCK_METHOD := &"unlock_double_jump"
const APPEAR_START_SCALE := 0.05

@export_group("Feel")
@export var bob_height := 5.0
@export var bob_period := 1.6
@export var appear_time := 0.4

var _collected := false

@onready var _visual: Node2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_start_bob()
	_start_appear()


func is_collected() -> bool:
	return _collected


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group(PLAYER_GROUP) or not body.has_method(UNLOCK_METHOD):
		return
	_collected = true
	body.call(UNLOCK_METHOD)
	collected.emit(body)
	queue_free()


func _start_bob() -> void:
	var half := maxf(bob_period, 0.1) * 0.5
	var tween := create_tween().set_loops()
	tween.tween_property(_visual, "position:y", -bob_height, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "position:y", bob_height, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_appear() -> void:
	if appear_time <= 0.0:
		return
	_visual.scale = Vector2.ONE * APPEAR_START_SCALE
	create_tween().tween_property(_visual, "scale", Vector2.ONE, appear_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

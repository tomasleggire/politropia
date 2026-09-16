class_name Player
extends CharacterBody2D

## Controlador lateral por impulsos. Cada swipe suma momentum al movimiento actual.

signal respawned

@export_category("Impulsos")
@export var max_horizontal_speed := 540.0
@export var max_upward_speed := 720.0
@export var horizontal_impulse := 330.0
@export var upward_impulse := 610.0

@export_category("Peso")
@export var ground_drag := 1600.0
@export var air_drag := 85.0
@export var gravity_rise := 1420.0
@export var gravity_fall := 2050.0
@export var gravity_apex := 820.0
@export var apex_threshold := 80.0
@export var max_fall_speed := 1050.0
@export var coyote_time := 0.12
@export var drop_through_time := 0.20

@export_category("Teclado de prueba")
@export var keyboard_speed := 300.0
@export var keyboard_acceleration := 1800.0
@export var keyboard_jump_speed := 560.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sfx_land: AudioStreamPlayer = $SfxLand
@onready var _sfx_foot: AudioStreamPlayer = $SfxFoot
@onready var _sfx_jump: AudioStreamPlayer = $SfxJump

var _facing := 1
var _coyote_left := 0.0
var _drop_left := 0.0
var _landing_left := 0.0
var _footstep_left := 0.0
var _was_on_floor := false
var _spawn_position := Vector2.ZERO


func _ready() -> void:
	_spawn_position = global_position
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	var grounded := is_on_floor()
	_coyote_left = coyote_time if grounded else maxf(_coyote_left - delta, 0.0)

	_apply_keyboard_fallback(delta, grounded)
	_apply_natural_drag(delta, grounded)
	_apply_gravity(delta)

	var fall_speed_before_move := velocity.y
	move_and_slide()
	if not _was_on_floor and is_on_floor() and fall_speed_before_move > 150.0:
		_landing_left = 0.08
		_sfx_land.play()
	_was_on_floor = is_on_floor()

	_update_facing()
	_update_footsteps(delta)
	_update_animation()


## swipe_pixels usa coordenadas de pantalla: derecha +X, abajo +Y.
## duration_seconds agrega una influencia pequeña de velocidad sin reemplazar la distancia.
func apply_swipe(swipe_pixels: Vector2, duration_seconds: float) -> void:
	var length := swipe_pixels.length()
	if length < 16.0:
		return
	# Un solo salto y sin redireccionar en el aire: una vez que saltás, el
	# swipe no hace nada hasta que aterrizás. Más adelante habrá mejoras que
	# permitan control aéreo; por ahora el salto compromete a la trayectoria.
	if not (is_on_floor() or _coyote_left > 0.0):
		return

	var speed := length / maxf(duration_seconds, 0.04)
	var speed_factor := remap(clampf(speed, 250.0, 2200.0), 250.0, 2200.0, 0.90, 1.12)
	var x_strength := pow(clampf(absf(swipe_pixels.x) / 240.0, 0.0, 1.0), 0.82)
	var y_strength := pow(clampf(absf(swipe_pixels.y) / 220.0, 0.0, 1.0), 0.82)

	if absf(swipe_pixels.x) >= 10.0:
		var impulse_x := signf(swipe_pixels.x) * horizontal_impulse * x_strength * speed_factor
		velocity.x = clampf(velocity.x + impulse_x, -max_horizontal_speed, max_horizontal_speed)
		_facing = 1 if impulse_x > 0.0 else -1

	if swipe_pixels.y <= -30.0:
		velocity.y = maxf(
			velocity.y - upward_impulse * y_strength * speed_factor,
			-max_upward_speed
		)
		_coyote_left = 0.0
		_landing_left = 0.0
		_sfx_jump.play()
	elif swipe_pixels.y >= 30.0 and _standing_on_one_way():
		_begin_drop_through()


func _apply_keyboard_fallback(delta: float, grounded: bool) -> void:
	var axis := Input.get_axis(&"move_left", &"move_right")
	if not is_zero_approx(axis):
		velocity.x = move_toward(velocity.x, axis * keyboard_speed, keyboard_acceleration * delta)
	if Input.is_action_just_pressed(&"jump") and (grounded or _coyote_left > 0.0):
		velocity.y = -keyboard_jump_speed
		_coyote_left = 0.0
		_sfx_jump.play()
	if Input.is_action_just_pressed(&"drop_down"):
		_begin_drop_through()


func _apply_natural_drag(delta: float, grounded: bool) -> void:
	if not is_zero_approx(Input.get_axis(&"move_left", &"move_right")):
		return
	var drag := ground_drag if grounded else air_drag
	velocity.x = move_toward(velocity.x, 0.0, drag * delta)


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		return
	var gravity := gravity_rise
	if absf(velocity.y) < apex_threshold:
		gravity = gravity_apex
	elif velocity.y > 0.0:
		gravity = gravity_fall
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _update_timers(delta: float) -> void:
	_landing_left = maxf(_landing_left - delta, 0.0)
	if _drop_left > 0.0:
		_drop_left -= delta
		if _drop_left <= 0.0:
			set_collision_mask_value(2, true)


func _begin_drop_through() -> void:
	if not is_on_floor() or _drop_left > 0.0 or not _standing_on_one_way():
		return
	set_collision_mask_value(2, false)
	_drop_left = drop_through_time
	global_position.y += 5.0


func _standing_on_one_way() -> bool:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision.get_normal().y > -0.7:
			continue
		var collider := collision.get_collider() as CollisionObject2D
		if collider != null and collider.get_collision_layer_value(2):
			return true
	return false


func set_checkpoint(checkpoint: Vector2) -> void:
	_spawn_position = checkpoint


func respawn() -> void:
	set_collision_mask_value(2, true)
	_drop_left = 0.0
	velocity = Vector2.ZERO
	global_position = _spawn_position
	respawned.emit()


func _update_facing() -> void:
	if absf(velocity.x) > 24.0:
		_facing = 1 if velocity.x > 0.0 else -1
	_sprite.flip_h = _facing < 0


func _update_footsteps(delta: float) -> void:
	if not is_on_floor() or absf(velocity.x) < 70.0:
		_footstep_left = 0.0
		return
	_footstep_left -= delta
	if _footstep_left <= 0.0:
		_sfx_foot.play()
		_footstep_left = clampf(0.30 - absf(velocity.x) / 2600.0, 0.12, 0.26)


func _update_animation() -> void:
	if not is_on_floor():
		_play_animation(&"jump" if velocity.y < 40.0 else &"fall")
	elif _landing_left > 0.0:
		_play_animation(&"land")
	elif absf(velocity.x) > 35.0:
		_play_animation(&"walk")
		_sprite.speed_scale = clampf(absf(velocity.x) / 220.0, 0.7, 1.8)
	else:
		_play_animation(&"idle")
		_sprite.speed_scale = 1.0


func _play_animation(animation_name: StringName) -> void:
	if _sprite.animation != animation_name:
		_sprite.play(animation_name)

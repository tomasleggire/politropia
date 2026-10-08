class_name BookFragmentPedestal
extends Node2D

const INTERACTABLE_GROUP := &"interactable"
const FRAGMENT_SCENES := [
	preload("res://scenes/world/fragmento_libro.tscn"),
	preload("res://scenes/world/fragmento_libro_2.tscn"),
	preload("res://scenes/world/fragmento_libro_3.tscn"),
	preload("res://scenes/world/fragmento_libro_4.tscn"),
]
const FRAGMENT_OFFSETS := [
	Vector2(-12, -16),
	Vector2(12, -16),
	Vector2(-12, 8),
	Vector2(12, 8),
]
const REASSEMBLY_OFFSETS := [
	Vector2(-6, -4),
	Vector2(6, -4),
	Vector2(-6, 4),
	Vector2(6, 4),
]
const GLOW_HALF_CYCLE := 1.5
const LIGHT_ALPHA_BY_FRAGMENT := [0.48, 0.62, 0.78, 0.95]
const LIGHT_STRENGTH_BY_FRAGMENT := [0.48, 0.64, 0.82, 1.0]
const SIDE_AURA_ALPHA_BY_FRAGMENT := [0.28, 0.4, 0.54, 0.68]
const ORBIT_DURATION := 1.8

@onready var _area: Area2D = $InteractionArea
@onready var _prompt: InteractionPrompt = $InteractionPrompt
@onready var _book_marker: Marker2D = $Marker2D
@onready var _activation_glow: Sprite2D = $ActivationGlow
@onready var _emanating_light: Sprite2D = $EmanatingLight
@onready var _side_aura_left: Sprite2D = $SideAuraLeft
@onready var _side_aura_right: Sprite2D = $SideAuraRight
@onready var _completed_book: Sprite2D = $CompletedBook
@onready var _orbit_sparks: GPUParticles2D = $OrbitSparks
@onready var _joining_sparks: GPUParticles2D = $JoiningSparks
@onready var _reveal_flash: GPUParticles2D = $RevealFlash
@onready var _completion_pulse: Sprite2D = $CompletionPulse

var _player: Player
var _fragments_placed := 0
var _fragment_nodes: Array[Node2D] = []
var _reconstruction_started := false
var _book_reconstructed := false
var _glow_pulse: Tween
var _glow_appear: Tween
var _emanating_light_tween: Tween
var _side_auras_tween: Tween
var _completion_pulse_tween: Tween


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_completed_book.visible = false
	_completion_pulse.visible = false
	_completed_book.position = _book_marker.position + Vector2(0, -8)
	_orbit_sparks.emitting = false
	_joining_sparks.emitting = false
	_reveal_flash.emitting = false
	add_to_group(INTERACTABLE_GROUP)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_prompt.hide_prompt()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	TouchControls.set_interact_available(self, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and request_interact():
		get_viewport().set_input_as_handled()


## Place one fragment per keyboard or touch interaction.
func request_interact() -> bool:
	if _reconstruction_started or _fragments_placed >= FRAGMENT_SCENES.size() or not is_instance_valid(_player):
		return false
	var fragment := FRAGMENT_SCENES[_fragments_placed].instantiate() as Node2D
	fragment.position = _book_marker.position + FRAGMENT_OFFSETS[_fragments_placed]
	add_child(fragment)
	_fragment_nodes.append(fragment)
	_fragments_placed += 1
	_prompt.hide_prompt()
	_play_activation_glow()
	_update_emanating_light()
	_update_side_auras()
	_refresh_prompt()
	if _fragments_placed == FRAGMENT_SCENES.size():
		call_deferred("reconstruir_libro")
	return true


## Run once, after all four fragments have been placed on the lectern.
func reconstruir_libro() -> void:
	if _reconstruction_started or _book_reconstructed or _fragments_placed != FRAGMENT_SCENES.size():
		return
	_reconstruction_started = true
	_prompt.hide_prompt()
	_refresh_prompt()
	if _glow_pulse != null:
		_glow_pulse.kill()
	if _glow_appear != null:
		_glow_appear.kill()
	if _side_auras_tween != null:
		_side_auras_tween.kill()
	_side_aura_left.visible = true
	_side_aura_right.visible = true
	var aura_surge := create_tween().set_parallel(true)
	aura_surge.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	aura_surge.tween_property(_side_aura_left, "modulate:a", 0.88, 0.65)
	aura_surge.tween_property(_side_aura_right, "modulate:a", 0.88, 0.65)
	aura_surge.tween_property(_side_aura_left, "scale", Vector2(0.92, 0.92), 0.65)
	aura_surge.tween_property(_side_aura_right, "scale", Vector2(0.92, 0.92), 0.65)
	_activation_glow.visible = true
	_activation_glow.modulate.a = 0.72
	_orbit_sparks.emitting = true
	var center := _book_marker.position + Vector2(0, -18)
	var orbit_positions: Array[Vector2] = []
	for i in range(_fragment_nodes.size()):
		var fragment := _fragment_nodes[i]
		if fragment.has_method("stop_idle_motion"):
			fragment.call("stop_idle_motion")
		var start_angle := TAU * float(i) / float(_fragment_nodes.size())
		var orbit_position := center + Vector2.from_angle(start_angle) * 24.0
		orbit_positions.append(orbit_position)
	var rise := create_tween().set_parallel(true)
	rise.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in range(_fragment_nodes.size()):
		rise.tween_property(_fragment_nodes[i], "position", orbit_positions[i], 0.5)
		rise.tween_property(_fragment_nodes[i], "scale", Vector2(1.12, 1.12), 0.5)
	await rise.finished

	var orbit := create_tween().set_parallel(true)
	for i in range(_fragment_nodes.size()):
		orbit.tween_method(_set_orbit_progress.bind(i, center), 0.0, 1.0, ORBIT_DURATION).set_trans(Tween.TRANS_LINEAR)
	await orbit.finished
	_orbit_sparks.emitting = false

	_joining_sparks.emitting = true
	_joining_sparks.restart()
	var converge := create_tween().set_parallel(true)
	converge.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in range(_fragment_nodes.size()):
		converge.tween_property(_fragment_nodes[i], "position", center + REASSEMBLY_OFFSETS[i], 0.65)
		converge.tween_property(_fragment_nodes[i], "scale", Vector2.ONE, 0.65)
		converge.tween_property(_fragment_nodes[i], "rotation", 0.0, 0.65)
	await converge.finished
	await get_tree().create_timer(0.18).timeout

	_reveal_flash.emitting = true
	_reveal_flash.restart()
	for fragment in _fragment_nodes:
		fragment.visible = false
	_completed_book.position = _book_marker.position + Vector2(0, -42)
	_completed_book.visible = true
	await get_tree().create_timer(0.45).timeout

	var landing := create_tween()
	var final_book_position := _book_marker.position + Vector2(0, -8)
	landing.tween_property(_completed_book, "position", final_book_position, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	landing.tween_property(_completed_book, "position:y", final_book_position.y + 4.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	landing.tween_property(_completed_book, "position:y", final_book_position.y, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await landing.finished
	_reveal_flash.emitting = false
	_book_reconstructed = true
	_start_completed_effects()


func _start_completed_effects() -> void:
	_play_completion_pulse()
	_activation_glow.visible = true
	_start_activation_glow_pulse(0.72, 0.98)
	if _emanating_light_tween != null:
		_emanating_light_tween.kill()
	var light_material := _emanating_light.material as ShaderMaterial
	light_material.set_shader_parameter("strength", 1.35)
	_emanating_light_tween = create_tween()
	_emanating_light_tween.tween_property(_emanating_light, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var spark_material := _orbit_sparks.process_material as ParticleProcessMaterial
	spark_material.initial_velocity_min = 10.0
	spark_material.initial_velocity_max = 27.0
	spark_material.scale_min = 0.035
	spark_material.scale_max = 0.075
	_orbit_sparks.amount = 34
	_orbit_sparks.emitting = true
	_reveal_flash.emitting = true
	_reveal_flash.restart()

	_side_auras_tween = create_tween().set_loops()
	_side_auras_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_side_auras_tween.tween_property(_side_aura_left, "scale", Vector2(1.42, 2.1), 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_right, "scale", Vector2(1.42, 2.1), 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_left, "modulate:a", 1.0, 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_right, "modulate:a", 1.0, 1.0)
	_side_auras_tween.tween_property(_side_aura_left, "scale", Vector2(1.22, 1.85), 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_right, "scale", Vector2(1.22, 1.85), 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_left, "modulate:a", 0.94, 1.0)
	_side_auras_tween.parallel().tween_property(_side_aura_right, "modulate:a", 0.94, 1.0)

func _play_completion_pulse() -> void:
	var pulse_material := _completion_pulse.material as ShaderMaterial
	pulse_material.set_shader_parameter("progress", 0.0)
	_completion_pulse.position = _book_marker.position
	_completion_pulse.modulate = Color.WHITE
	_completion_pulse.visible = true
	_completion_pulse_tween = create_tween().set_parallel(true)
	_completion_pulse_tween.tween_method(_set_completion_pulse_progress, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_completion_pulse_tween.tween_property(_completion_pulse, "modulate:a", 0.0, 0.9).from(1.0)
	_completion_pulse_tween.chain().tween_callback(_completion_pulse.hide)


func _set_completion_pulse_progress(value: float) -> void:
	var pulse_material := _completion_pulse.material as ShaderMaterial
	pulse_material.set_shader_parameter("progress", value)

func _set_orbit_progress(progress: float, fragment_index: int, center: Vector2) -> void:
	var angle := TAU * 1.2 * progress + TAU * float(fragment_index) / float(_fragment_nodes.size())
	_fragment_nodes[fragment_index].position = center + Vector2.from_angle(angle) * 24.0
	_fragment_nodes[fragment_index].rotation = sin(progress * TAU * 1.2) * 0.07


func _update_emanating_light() -> void:
	if _emanating_light_tween != null:
		_emanating_light_tween.kill()
	_emanating_light.visible = true
	var index := _fragments_placed - 1
	var target_alpha: float = LIGHT_ALPHA_BY_FRAGMENT[index]
	var light_material := _emanating_light.material as ShaderMaterial
	light_material.set_shader_parameter("strength", LIGHT_STRENGTH_BY_FRAGMENT[index])
	_emanating_light_tween = create_tween()
	_emanating_light_tween.tween_property(_emanating_light, "modulate:a", target_alpha, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _update_side_auras() -> void:
	if _side_auras_tween != null:
		_side_auras_tween.kill()
	var index := _fragments_placed - 1
	var target_alpha: float = SIDE_AURA_ALPHA_BY_FRAGMENT[index]
	var target_scale := 0.48 + 0.09 * float(index)
	_side_aura_left.visible = true
	_side_aura_right.visible = true
	_side_auras_tween = create_tween().set_parallel(true)
	_side_auras_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_side_auras_tween.tween_property(_side_aura_left, "modulate:a", target_alpha, 0.8)
	_side_auras_tween.tween_property(_side_aura_right, "modulate:a", target_alpha, 0.8)
	_side_auras_tween.tween_property(_side_aura_left, "scale", Vector2.ONE * target_scale, 0.8)
	_side_auras_tween.tween_property(_side_aura_right, "scale", Vector2.ONE * target_scale, 0.8)


func _play_activation_glow() -> void:
	if _glow_pulse != null:
		_glow_pulse.kill()
	if _glow_appear != null:
		_glow_appear.kill()
	var was_visible := _activation_glow.visible
	_activation_glow.visible = true
	var glow_high_alpha := 0.32 + 0.1 * float(_fragments_placed - 1)
	var glow_low_alpha := glow_high_alpha * 0.625
	if not was_visible:
		_activation_glow.modulate.a = 0.0
	_glow_appear = create_tween()
	if was_visible:
		_glow_appear.tween_property(_activation_glow, "modulate:a", glow_high_alpha, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_glow_appear.tween_property(_activation_glow, "modulate:a", glow_low_alpha, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_glow_appear.tween_callback(_start_activation_glow_pulse.bind(glow_low_alpha, glow_high_alpha))
	else:
		_glow_appear.tween_property(_activation_glow, "modulate:a", glow_low_alpha, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_glow_appear.tween_callback(_start_activation_glow_pulse.bind(glow_low_alpha, glow_high_alpha))


func _start_activation_glow_pulse(low_alpha: float, high_alpha: float) -> void:
	_glow_pulse = create_tween().set_loops()
	_glow_pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_pulse.tween_property(_activation_glow, "modulate:a", high_alpha, GLOW_HALF_CYCLE).from(low_alpha)
	_glow_pulse.tween_property(_activation_glow, "modulate:a", low_alpha, GLOW_HALF_CYCLE).from(high_alpha)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		_refresh_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_refresh_prompt()


func _refresh_prompt() -> void:
	var available := _fragments_placed < FRAGMENT_SCENES.size() and is_instance_valid(_player) and not _reconstruction_started
	if available and not TouchControls.visible:
		_prompt.show_prompt()
	else:
		_prompt.hide_prompt()
	TouchControls.set_interact_available(self, available)

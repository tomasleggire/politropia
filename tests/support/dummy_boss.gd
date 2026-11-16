class_name DummyBoss
extends BossEnemy

## Minimal BossEnemy for tests: two trivial attacks, a record of every hook call and
## switches to steer the fight (`auto_attack`, `root_layer_value`).

enum Attack { POKE, SLAM }

@export_group("Dummy")
@export var poke_telegraph := 0.1
@export var active_time := 0.1
@export var recover_time := 0.2
@export var weights := PackedFloat32Array([1.0, 1.0])
## Off: the fight loop never starts an attack by itself; tests call `start_attack`.
@export var auto_attack := false
## What `_root_layer` returns (a multi-part boss uses 0).
@export var root_layer_value := Enemy.ENEMY_LAYER

var events: Array[String] = []
var entered_phases: Array[int] = []
var stun_count := 0
var stun_ended_count := 0
var hazard_clears := 0
var intro_count := 0
var refuse_hits := false


func _choose_next_action() -> int:
	return _draw_attack(weights) if auto_attack else NO_ATTACK


func _telegraph_time(attack_id: int) -> float:
	return poke_telegraph if attack_id == Attack.POKE else 0.5


func _active_time(_attack_id: int) -> float:
	return active_time


func _recover_time(_attack_id: int) -> float:
	return recover_time


func _begin_attack_phase(attack_id: int, phase_id: AttackPhase) -> void:
	events.append("begin:%d:%d" % [attack_id, phase_id])


func _end_attack_phase(attack_id: int, phase_id: AttackPhase) -> void:
	events.append("end:%d:%d" % [attack_id, phase_id])


func _on_phase_entered(phase_id: int) -> void:
	entered_phases.append(phase_id)


func _on_stunned(_duration: float) -> void:
	stun_count += 1


func _on_stun_ended() -> void:
	stun_ended_count += 1


func _on_intro(_duration: float) -> void:
	intro_count += 1


func _clear_hazards() -> void:
	hazard_clears += 1


func _accepts_hit(_damage: int, _source_position: Vector2) -> bool:
	return not refuse_hits


func _root_layer() -> int:
	return root_layer_value

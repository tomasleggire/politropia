class_name BossTestHub
extends Node2D

## Demo scaffolding: the small room that leads to the three boss test rooms.
## Delete it with its door in library zone 1 once the bosses live in real levels.
##
## Entering the hub makes the three TEST bosses fightable again, so a fight can be
## retried by walking out of the boss room and back in. Only the `test_` ids are
## forgotten: the real bosses (Artemis and the ones placed in real levels) keep
## their defeat.

const TEST_BOSS_IDS: Array[StringName] = [
	&"test_boombox_teacher",
	&"test_blind_beast",
	&"test_hydra",
]
const BOSS_PROGRESS_PATH := "/root/BossProgress"
const ENEMY_REGISTRY_PATH := "/root/EnemyRegistry"


func _ready() -> void:
	forget_test_bosses()


## Forgets the defeat of every test boss, in BossProgress and in the enemy registry
## (the corpse the registry keeps until the next rest or death).
func forget_test_bosses() -> void:
	var progress := get_node_or_null(BOSS_PROGRESS_PATH)
	var registry := get_node_or_null(ENEMY_REGISTRY_PATH)
	for boss_id in TEST_BOSS_IDS:
		if progress != null:
			progress.forget(boss_id)
		if registry != null:
			registry.forget(boss_id)

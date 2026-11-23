extends Area2D

const QUEST_PROGRESS_PATH := "/root/BlindQuestProgress"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
		
	var progress := get_node_or_null(QUEST_PROGRESS_PATH)
	if progress == null:
		push_warning("No se encontró BlindQuestProgress")
		return
		progress.call("collect_required_book")
		queue_free()

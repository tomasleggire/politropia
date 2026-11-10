extends Node

## Single-slot autosave. Only checkpoint-backed progress is written to disk.

const SAVE_PATH := "user://politropia_save.dat"
const SAVE_VERSION := 1


func has_save() -> bool:
	return not _read_payload().is_empty()


func begin_new_game(initial_scene_path: String) -> bool:
	delete_save()
	if initial_scene_path.is_empty() or not ResourceLoader.exists(initial_scene_path):
		push_error("SaveService: initial scene does not exist: %s" % initial_scene_path)
		return false
	return _write_payload(_build_payload(initial_scene_path))


## Called by StillnessDesk after the checkpoint is activated at the ritual peak.
func save_checkpoint() -> bool:
	if not CheckpointService.has_active_checkpoint():
		return false
	var scene_path := CheckpointService.get_active_scene_path()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("SaveService: cannot save an invalid checkpoint scene: %s" % scene_path)
		return false
	return _write_payload(_build_payload(scene_path))


func continue_game() -> bool:
	var payload := _read_payload()
	if payload.is_empty():
		return false
	var scene_path: String = payload["scene_path"]
	var saved_checkpoint: Variant = payload.get("checkpoint", {})
	var has_saved_checkpoint := false
	if saved_checkpoint is Dictionary:
		var saved_checkpoint_id: Variant = saved_checkpoint.get("active_id", "")
		var saved_checkpoint_scene: Variant = saved_checkpoint.get("scene_path", "")
		if saved_checkpoint_id is String and not saved_checkpoint_id.is_empty():
			if saved_checkpoint_scene is String and not saved_checkpoint_scene.is_empty():
				scene_path = saved_checkpoint_scene
				has_saved_checkpoint = true
	var packed_scene := ResourceLoader.load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("SaveService: could not load saved scene resource: %s" % scene_path)
		return false
	_restore_progress(payload)
	if has_saved_checkpoint and CheckpointService.has_active_checkpoint():
		CheckpointService.queue_pending_restore()
	var transition_cover := _create_transition_cover()
	_fade_transition_cover_after_scene_load(transition_cover)
	var error := get_tree().change_scene_to_packed(packed_scene)
	if error != OK:
		transition_cover.get_parent().queue_free()
		CheckpointService.clear_pending_restore()
		push_error("SaveService: could not load saved scene (%d)." % error)
		return false
	return true


func _create_transition_cover() -> ColorRect:
	var layer := CanvasLayer.new()
	layer.name = "ContinueTransitionCover"
	layer.layer = 125
	add_child(layer)
	var cover := ColorRect.new()
	cover.name = "Cover"
	cover.color = Color.BLACK
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cover)
	return cover


func _fade_transition_cover_after_scene_load(cover: ColorRect) -> void:
	await get_tree().scene_changed
	await get_tree().process_frame
	if not is_instance_valid(cover):
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(cover, "color:a", 0.0, 0.3)
	await tween.finished
	if is_instance_valid(cover) and cover.get_parent() != null:
		cover.get_parent().queue_free()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
		var error := DirAccess.remove_absolute(absolute_path)
		if error != OK:
			push_error("SaveService: could not delete the old save (%d)." % error)


func _build_payload(scene_path: String) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"scene_path": scene_path,
		"checkpoint": CheckpointService.to_dict(),
		"progress": {
			"abilities": AbilityProgress.to_dict(),
			"bosses": BossProgress.to_dict(),
			"fragments": FragmentProgress.to_dict(),
			"map": MapProgress.to_dict(),
			"secrets": SecretProgress.to_dict(),
			"collectibles": Collectibles.to_dict(),
			"blind_quest": BlindQuestProgress.to_dict(),
		},
	}


func _write_payload(payload: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: could not open the save file for writing (%d)." % FileAccess.get_open_error())
		return false
	file.store_var(payload)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("SaveService: could not finish writing the save file (%d)." % error)
		return false
	return true


func _read_payload() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = file.get_var(false)
	file.close()
	if not value is Dictionary:
		return {}
	var payload: Dictionary = value
	if int(payload.get("version", 0)) != SAVE_VERSION:
		return {}
	var scene_path: Variant = payload.get("scene_path", "")
	var checkpoint: Variant = payload.get("checkpoint", {})
	if not scene_path is String or not checkpoint is Dictionary:
		return {}
	if not ResourceLoader.exists(scene_path):
		return {}
	var active_id: Variant = checkpoint.get("active_id", "")
	if active_id is String and not active_id.is_empty():
		var checkpoint_scene: Variant = checkpoint.get("scene_path", "")
		if not checkpoint_scene is String or not ResourceLoader.exists(checkpoint_scene):
			return {}
	if not payload.get("progress", {}) is Dictionary:
		return {}
	return payload


func _restore_progress(payload: Dictionary) -> void:
	var checkpoint: Variant = payload.get("checkpoint", {})
	CheckpointService.from_dict(checkpoint if checkpoint is Dictionary else {})
	var progress: Variant = payload.get("progress", {})
	if not progress is Dictionary:
		return
	AbilityProgress.from_dict(_section(progress, "abilities"))
	BossProgress.from_dict(_section(progress, "bosses"))
	FragmentProgress.from_dict(_section(progress, "fragments"))
	MapProgress.from_dict(_section(progress, "map"))
	SecretProgress.from_dict(_section(progress, "secrets"))
	Collectibles.from_dict(_section(progress, "collectibles"))
	BlindQuestProgress.from_dict(_section(progress, "blind_quest"))


func _section(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	return value if value is Dictionary else {}

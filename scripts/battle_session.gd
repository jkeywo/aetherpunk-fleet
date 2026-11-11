extends Node
## Session preparation and detached result handoff; authored content remains in ContentStore.
var last_result: Dictionary = {}
var editor_playtest: bool = false
var preparation_draft: Dictionary = {}
var prepared_content: Dictionary = {}
var encounter_content: Dictionary = {}
var encounter_fingerprint := ""


func battle_content(saved: Dictionary) -> Dictionary:
	return saved.duplicate(true) if editor_playtest or prepared_content.is_empty() else prepared_content.duplicate(true)


func record_result(summary: Dictionary) -> void:
	last_result = summary.duplicate(true)


func clear_result() -> void:
	last_result.clear()

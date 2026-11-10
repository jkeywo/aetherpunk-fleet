extends Node
## In-memory handoff between a completed battle and its result screen.

var last_result: Dictionary = {}


func record_result(summary: Dictionary) -> void:
	last_result = summary.duplicate(true)


func clear_result() -> void:
	last_result.clear()

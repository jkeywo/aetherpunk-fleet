extends Node
## Saved project content and editor navigation state. Drafts are owned by the editor.

const Catalog = preload("res://scripts/content_catalog.gd")
var path: String = "res://data/content.json"
var saved: Dictionary = {}
var last_error: String = ""
var editor_state: Dictionary = {}
var migration_pending := false


func _ready() -> void:
	reload_content()


func reload_content() -> bool:
	var result := Catalog.read_document(path)
	if not result.ok:
		last_error = result.error
		return false
	saved = result.document.duplicate(true)
	migration_pending = result.get("migrated", false)
	last_error = ""
	return true


func snapshot() -> Dictionary:
	return saved.duplicate(true)


func save_content(draft: Dictionary) -> bool:
	var errors := Catalog.validate(draft)
	if not errors.is_empty():
		last_error = "\n".join(errors)
		return false
	draft = Catalog.migrate(draft)
	last_error = Catalog.save_document(path, draft)
	if not last_error.is_empty():
		return false
	saved = draft.duplicate(true)
	migration_pending = false
	return true

extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size = Vector2i(1280,800)
	var store_node = root.get_node("ContentStore")
	store_node.saved = fixture.duplicate(true)
	store_node.path = "user://fleet_editor_test.json"
	store_node.editor_state = {}
	var project_hash := FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	var e = current_scene
	await flush()
	expect(e.tabs.get_tab_count() == 4 and not e.is_dirty(), "Four authoring tabs not clean.")
	e.fields.hull.value = 88
	expect(store_node.saved.leviathans[0].hull == 70 and e.preview_widget.snapshot.enemies[0].hull == 88, "Enemy preview saved or stale.")
	e.tabs.current_tab = 1
	await flush()
	e.fields.hull.value = 31
	expect(e.preview_widget.snapshot.ships[0].hull == 31, "Ship preview stale.")
	expect(e.setup_controls.has("captain_0") and e.setup_controls.has("level_0"), "Preparation fields missing.")
	e.tabs.current_tab = 2
	await flush()
	expect(e.preview_widget != null and e.selected_entry().tier == 1, "Captain preview missing.")
	e.tabs.current_tab = 3
	await flush()
	e.fields.name.text = "Edited Brace"
	e.fields.name.text_changed.emit("Edited Brace")
	e.fields.cost.value = 0
	expect(e.preview_widget.info.name == "Edited Brace" and e.preview_widget.info.cost == 0, "Card preview stale.")
	for point in Geometry.POSITIONS: e.fields["position_" + point].button_pressed = false
	expect(not e._save() and "Cannot save" in e.status.text, "Invalid draft saved.")
	e.fields.position_front.button_pressed = true
	var before: int = e.draft.cards.size()
	e._duplicate_entry("cards")
	expect(e.draft.cards.size() == before + 1 and e.selected_entry().id != "brace", "Duplicate lost stable IDs.")
	e._delete_entry("cards")
	expect(e.draft.cards.size() == before, "Unused duplicate deletion blocked.")
	e._new_entry("captains")
	expect(e.draft.captains.size() == 4 and e.draft.cards.size() == before + 1, "New captain pair missing.")
	e._revert()
	expect(not e.is_dirty() and e.draft.captains.size() == 3, "Revert failed.")
	e.tabs.current_tab = 1
	await flush()
	e.fields.hull.value = 31
	expect(e._save() and not e.is_dirty(), "Save failed.")
	e.fields.hull.value = 32
	expect(e.is_dirty() and e.selected_entry().hull == 32 and store_node.saved.ships[0].hull == 31, "Post-save form detached from new draft.")
	expect(e._save() and Catalog.read_document(store_node.path).document.ships[0].hull == 32, "Post-save edit did not persist.")
	e._delete_entry("ships")
	expect(e.draft.ships.size() == 3 and "referenc" in e.status.text.to_lower(), "Referenced ship deleted.")
	e.searches.ships.text = "Kestrel"
	e.searches.ships.text_changed.emit("Kestrel")
	expect(e.browsers.ships.item_count == 1, "Search failed.")
	e.searches.ships.text = ""
	e.test_button.pressed.emit()
	await scene_changed
	var ui = current_scene
	ui.feedback.duration_scale = 0.01
	expect(ui.state.ships[0].max_hull == 32 and root.get_node("BattleSession").editor_playtest, "Playtest ignored saved draft.")
	ui.get_node("%GearButton").pressed.emit()
	ui.menu.id_pressed.emit(1)
	await scene_changed
	e = current_scene
	expect(e.tabs.current_tab == 1 and not e.is_dirty(), "Return lost editor context.")
	e.fields.name.text_changed.emit("Unsaved")
	e._request_menu()
	expect(e.leave_dialog.visible, "Dirty leave dialog missing.")
	e.leave_dialog.canceled.emit()
	e.leave_dialog.hide()
	expect(e.is_dirty(), "Cancel discarded draft.")
	e._request_menu()
	e.leave_dialog.custom_action.emit("discard")
	await scene_changed
	expect(current_scene.name == "MainMenu" and FileAccess.get_sha256("res://data/content.json") == project_hash, "Discard or test file isolation failed.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_node.path))
	done("Live editor and preparation")

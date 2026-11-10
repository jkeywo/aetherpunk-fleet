extends "res://tests/support/v2_test.gd"


func buttons_with_text(node: Node, text: String) -> Array:
	var result: Array = []
	if node is Button and node.text == text:
		result.append(node)
	for child in node.get_children():
		result.append_array(buttons_with_text(child, text))
	return result


func _run() -> void:
	var content_store: Node = root.get_node("ContentStore")
	content_store.saved = fixture.duplicate(true)
	content_store.migration_pending = false
	content_store.editor_state = {}
	content_store.path = "user://diamond_editor_test.json"
	var project_hash := FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	current_scene.get_node("%EditorButton").pressed.emit()
	await scene_changed
	var editor = current_scene
	expect(editor.fields.has("starting_stance") and editor.preview_widget != null, "Stance editor/live preview missing.")
	editor.fields.hull.value = 88
	expect(editor.preview_widget.snapshot.monster_hull == 88 and content_store.saved.leviathans[0].hull == 70, "Live leviathan preview saved the draft or did not update.")
	var lev: Dictionary = editor.selected_entry()
	editor._new_stance(lev)
	expect(lev.stances.size() == 7 and editor.editing_stance != lev.starting_stance, "New stance failed.")
	editor._delete_stance(lev)
	expect(lev.stances.size() == 6, "Unused stance deletion failed.")
	editor.tabs.current_tab = 1
	await flush()
	editor.fields.hull.value = 31
	var unit_preview = editor.preview_widget
	expect(unit_preview.snapshot.ships[0].hull == 31, "Live ship hull did not update.")
	editor.tabs.current_tab = 2
	await flush()
	editor.fields.cost.value = 0
	editor.fields.name.text = "Live Brace"
	editor.fields.name.text_changed.emit("Live Brace")
	expect(editor.preview_widget.info.cost == 0 and editor.preview_widget.labels.name.text == "Live Brace", "Card face did not update live.")
	editor.fields.position_front.button_pressed = false
	expect(not editor.preview_widget.info.allowed_positions.has("front"), "Live permitted positions stale.")
	for point in Geometry.POSITIONS:
		editor.fields["position_" + point].button_pressed = false
	expect(editor.preview_widget != null and editor.preview_widget.info.allowed_positions.is_empty(), "Incomplete draft hid the live preview.")
	editor.save_button.pressed.emit()
	expect("Cannot save" in editor.status.text, "Invalid positions were saved.")
	editor.fields.position_front.button_pressed = true
	var rules: Array = buttons_with_text(editor.forms.cards, "Add Rule")
	rules[0].pressed.emit()
	expect(editor.selected_entry().on_play.size() == 1 and "If at least" in editor.preview_widget.info.effect, "On-play authoring/preview missing.")
	rules = buttons_with_text(editor.forms.cards, "Add Rule")
	rules[1].pressed.emit()
	rules = buttons_with_text(editor.forms.cards, "Add Rule")
	rules[2].pressed.emit()
	expect(editor.selected_entry().modifiers.size() == 1 and editor.selected_entry().triggers.size() == 1, "Circle bonus/trigger authoring missing.")
	expect("Once/turn" in editor.preview_widget.info.effect, "Trigger text not reflected in live card.")
	var serialized_before := JSON.stringify(editor.draft)
	editor.preview_expanded = true
	editor.preview_tags[1] = "Attack"
	editor._live_preview()
	expect(JSON.stringify(editor.draft) == serialized_before, "Preview context mutated content.")
	expect(editor.setup_controls.has("point_0") and editor.setup_controls.has("enemy_point"), "Position setup controls missing.")
	expect(editor.is_dirty(), "Editor changes did not mark draft dirty.")
	editor.save_button.pressed.emit()
	expect(not editor.is_dirty() and content_store.saved.version == 2, "Explicit version-2 save failed.")
	expect(Catalog.read_document(content_store.path).ok, "Saved editor content did not load.")
	editor.test_button.pressed.emit()
	await scene_changed
	var battle = current_scene
	battle.feedback.duration_scale = 0.02
	expect(battle.state.monster_hull == 88 and battle.state.ships[0].max_hull == 31, "Playtest ignored saved content.")
	expect(root.get_node("BattleSession").editor_playtest, "Playtest origin lost.")
	field_key(battle, "brace").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.play_order.size() == 1 and battle.state.monster_hull == 87, "Authored conditional play effect did not resolve.")
	battle.get_node("%GearButton").pressed.emit()
	battle.menu.id_pressed.emit(1)
	await scene_changed
	editor = current_scene
	expect(editor.name == "Editor" and editor.tabs.current_tab == 2, "Return to Editor lost context.")
	expect(editor.preview_widget.info.name == "Live Brace" and not editor.is_dirty(), "Returning lost saved preview.")
	editor.fields.name.text = "Unsaved"
	editor.fields.name.text_changed.emit("Unsaved")
	editor._request_menu()
	expect(editor.leave_dialog.visible, "Dirty navigation bypassed protection.")
	editor.leave_dialog.get_cancel_button().pressed.emit()
	await flush()
	expect(current_scene == editor and editor.is_dirty(), "Cancel lost draft.")
	editor._request_menu()
	editor.leave_dialog.custom_action.emit("discard")
	await scene_changed
	expect(current_scene.name == "MainMenu", "Discard did not return to menu.")
	expect(FileAccess.get_sha256("res://data/content.json") == project_hash, "Editor tests rewrote project content.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(content_store.path))
	done("Live editor integration")

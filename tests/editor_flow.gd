extends SceneTree
## Operates native editor widgets; all saves are isolated to a temporary user-data file.

const Catalog = preload("res://scripts/content_catalog.gd")
var checks := 0
var failures := 0
var store: Node
var project_hash: String


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _flush() -> void:
	await process_frame
	await process_frame


func _text(control: LineEdit, value: String) -> void:
	control.text = value
	control.text_changed.emit(value)


func _choose(control: OptionButton, value: String) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index) == value:
			control.select(index)
			control.item_selected.emit(index)
			return
	expect(false, "Missing dropdown value: " + value)


func _select_entry(editor, kind: String, id: String) -> void:
	var list: ItemList = editor.browsers[kind]
	for index in list.item_count:
		if list.get_item_metadata(index) == id:
			list.select(index)
			list.item_selected.emit(index)
			return
	expect(false, "Missing list entry: " + id)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var result := _find_button(child, text)
		if result != null:
			return result
	return null


func _card(key: String) -> Button:
	for button in current_scene.get_node("%Hand").get_children():
		if current_scene.state.card_keys[button.get_meta("uid")] == key:
			return button
	return null


func _run() -> void:
	store = root.get_node("ContentStore")
	store.saved = Catalog.normalized(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gdd_content.json")))
	store.path = "user://editor_ui_tests/content.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://editor_ui_tests"))
	expect(store.save_content(store.saved), "Could not create isolated editor save.")
	project_hash = FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	current_scene.get_node("%EditorButton").pressed.emit()
	await scene_changed
	var editor = current_scene
	expect(editor.name == "Editor" and editor.tabs.get_tab_count() == 3, "Main-menu editor entry or tabs missing.")
	expect(not editor.is_dirty(), "Fresh editor started dirty.")
	expect(editor.fields.has("starting_reaction") and editor.fields.has("starting_intent"), "Leviathan start controls missing.")
	editor.fields.hull.value = 77
	editor.effect_controls[0].amount.value = 5
	expect(editor.draft.leviathans[0].hull == 77 and editor.draft.leviathans[0].reactions[0].effects[0].amount == 5, "Leviathan widgets did not edit rules.")

	editor.tabs.current_tab = 1
	await _flush()
	editor.fields.hull.value = 31
	expect(editor.is_dirty() and store.saved.ships[0].hull == 28, "Ship draft mutated saved content.")
	editor.revert_button.pressed.emit()
	expect(editor.fields.hull.value == 28 and not editor.is_dirty(), "Revert did not restore saved definitions.")
	# Reapply the desired edits after testing Revert.
	editor.fields.hull.value = 31
	editor.fields.copies_brace.value = 3
	expect(editor.draft.ships[0].loadout[0].card == "brace" and editor.draft.ships[0].loadout[0].count == 3, "Loadout count did not update in place.")

	editor.toolbars.ships["new"].pressed.emit()
	var new_ship: String = editor.selected_entry().id
	expect(editor.draft.ships.size() == 4, "New Ship failed.")
	editor.toolbars.ships["delete"].pressed.emit()
	expect(Catalog.index_by_id(editor.draft.ships, new_ship) < 0, "Unused ship could not be deleted.")
	_select_entry(editor, "ships", "bastion")
	editor.toolbars.ships["duplicate"].pressed.emit()
	var copy: Dictionary = editor.selected_entry()
	expect(copy.id != "bastion" and copy.loadout.size() == 3, "Ship duplicate failed.")
	for slot in copy.loadout:
		var owned: Dictionary = editor.draft.cards[Catalog.index_by_id(editor.draft.cards, slot.card)]
		expect(owned.owner == copy.id, "Duplicated ship retained another ship's card ownership.")
	editor.toolbars.ships["delete"].pressed.emit()
	expect("Owning ship of card" in editor.status.text, "Referenced ship deletion was not explained.")

	editor.tabs.current_tab = 0
	await _flush()
	_select_entry(editor, "leviathans", "stormmaw")
	editor.fields.hull.value = 77
	editor.effect_controls[0].amount.value = 5
	editor.toolbars.leviathans["delete"].pressed.emit()
	expect("selected leviathan" in editor.status.text, "Selected leviathan deletion was not blocked.")
	editor.toolbars.leviathans["new"].pressed.emit()
	var new_lev: String = editor.selected_entry().id
	_find_button(editor.forms.leviathans, "Remove").pressed.emit()
	expect("at least one" in editor.status.text, "Final monster behaviour deletion was not blocked.")
	_find_button(editor.forms.leviathans, "Add Reaction").pressed.emit()
	var lev: Dictionary = editor.selected_entry()
	expect(lev.reactions.size() == 2, "Adding reaction failed.")
	var replacement_id: String = lev.reactions[1].id
	_choose(editor.fields.starting_reaction, replacement_id)
	_find_button(editor.forms.leviathans, "Remove").pressed.emit()
	expect(lev.reactions.size() == 1 and lev.starting_reaction == replacement_id, "Editing/deleting monster behaviours broke starting IDs.")
	_choose(editor.setup_controls.leviathan, new_lev)
	editor.toolbars.leviathans["delete"].pressed.emit()
	expect(Catalog.index_by_id(editor.draft.leviathans, new_lev) >= 0, "Referenced new leviathan was deleted.")
	_choose(editor.setup_controls.leviathan, "stormmaw")
	editor.toolbars.leviathans["delete"].pressed.emit()
	expect(Catalog.index_by_id(editor.draft.leviathans, new_lev) < 0, "Unused leviathan deletion failed.")

	editor.tabs.current_tab = 2
	await _flush()
	_select_entry(editor, "cards", "broadside")
	_text(editor.fields.name, "Thunder Cannon")
	editor.fields.cost.value = 1
	editor.fields.pays.value = 3
	editor.fields.rank_1.button_pressed = false
	editor.fields.tag_Movement.button_pressed = true
	editor.effect_controls[0].amount.value = 11
	_find_button(editor.forms.cards, "Add Effect").pressed.emit()
	_choose(editor.effect_controls[1].kind, "guard")
	await _flush()
	editor.effect_controls[1].up.pressed.emit()
	expect(editor.selected_entry().effects[0].kind == "guard", "Effect reordering failed.")
	expect("11 damage" in editor.fields.preview.text and "4 guard" in editor.fields.preview.text, "Generated preview did not reflect composed effects.")
	_text(editor.searches.cards, "Thunder")
	expect(editor.browsers.cards.item_count == 1, "Card search failed.")
	editor.toolbars.cards["duplicate"].pressed.emit()
	var duplicate_id: String = editor.selected_entry().id
	expect(duplicate_id != "broadside", "Duplicate did not allocate a stable new ID.")
	editor.toolbars.cards["delete"].pressed.emit()
	expect(Catalog.index_by_id(editor.draft.cards, duplicate_id) < 0, "Unreferenced card could not be deleted.")
	_select_entry(editor, "cards", "broadside")
	editor.toolbars.cards["delete"].pressed.emit()
	expect("Loadout of Kestrel" in editor.status.text and "fixed opening hand" in editor.status.text, "Card deletion omitted reference explanations.")
	editor.toolbars.cards["new"].pressed.emit()
	var temporary_card: String = editor.selected_entry().id
	editor.effect_controls[0].remove.pressed.emit()
	expect(editor.selected_entry().effects.is_empty(), "Remove Effect failed.")
	_find_button(editor.forms.cards, "Add Effect").pressed.emit()
	expect(editor.selected_entry().effects.size() == 1, "Adding an effect to an empty list failed.")
	editor.toolbars.cards["delete"].pressed.emit()
	expect(Catalog.index_by_id(editor.draft.cards, temporary_card) < 0, "New unused card could not be deleted.")
	_select_entry(editor, "cards", "broadside")

	# Save must reject invalid drafts without touching the previously saved file.
	var before := FileAccess.get_file_as_string(store.path)
	editor.fields.rank_2.button_pressed = false
	editor.save_button.pressed.emit()
	expect("Cannot save" in editor.status.text and "permitted rank" in editor.status.text, "Validation did not identify the invalid card.")
	expect(FileAccess.get_file_as_string(store.path) == before, "Rejected editor save changed the file.")
	editor.fields.rank_2.button_pressed = true
	editor.save_button.pressed.emit()
	expect(not editor.is_dirty() and store.reload_content(), "Valid editor save/reload failed.")
	expect(store.saved.ships[0].hull == 31 and store.saved.cards[3].name == "Thunder Cannon", "Saved editor fields did not persist.")

	# Fixed/random mode and duplicate fleet choices are controlled in the shared setup.
	_choose(editor.setup_controls.ship_1, "bastion")
	await _flush()
	expect(not Catalog.validate(editor.draft).is_empty(), "Duplicate formation choice accepted.")
	_choose(editor.setup_controls.ship_1, "kestrel")
	await _flush()
	editor.setup_controls.fixed_hand.button_pressed = false
	await _flush()
	expect(not editor.draft.setup.fixed_hand, "Random opening-hand toggle failed.")
	editor.setup_controls.fixed_hand.button_pressed = true
	await _flush()
	expect(editor.setup_controls.has("opening_6") and Catalog.validate(editor.draft).is_empty(), "Fixed opening-hand controls did not restore.")

	editor.test_button.pressed.emit()
	await scene_changed
	var battle = current_scene
	battle.feedback.duration_scale = 0.02
	expect(battle.name == "Game" and battle.get_node("%ReturnToEditor").visible, "Playtest entry or editor return missing.")
	expect(battle.state.ships[0].max_hull == 31 and battle.state.monster_hull == 77, "Playtest ignored saved hull values.")
	expect(battle.state.deck.size() == 12 and battle.state.hand.size() == 7, "Playtest ignored flexible loadout counts.")
	_card("broadside").pressed.emit()
	_card("brace").pressed.emit()
	expect("77 → 66" in battle.get_node("%Inspection").text, "Playtest preview ignored edited damage.")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.monster_hull == 66 and battle.state.ships[1].hull == 19 and battle.state.ships[1].guard == 0, "Edited card effects or reaction damage did not resolve.")
	var detached_state = battle.state
	battle.get_node("%ReturnToEditor").pressed.emit()
	await scene_changed
	editor = current_scene
	expect(editor.name == "Editor" and editor.tabs.current_tab == 2 and editor.selected_entry().id == "broadside", "Return to Editor lost editing context.")
	expect(not editor.is_dirty() and editor.fields.name.text == "Thunder Cannon", "Returning from playtest lost saved content.")
	editor.tabs.current_tab = 1
	await _flush()
	_select_entry(editor, "ships", "bastion")
	editor.fields.hull.value = 32
	editor.save_button.pressed.emit()
	expect(detached_state.ships[0].max_hull == 31, "Saved edit mutated a previous battle snapshot.")
	editor.test_button.pressed.emit()
	await scene_changed
	current_scene.get_node("%WinButton").pressed.emit()
	await scene_changed
	expect(current_scene.summary.starting_hull == 70, "Edited fleet hull did not reach result totals.")
	var result_return: Node = current_scene.primary_button.get_parent().get_node_or_null("ReturnToEditor")
	expect(result_return != null, "Playtest results omitted Return to Editor.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.get_node("%ReturnToEditor").visible and current_scene.state.ships[0].max_hull == 32, "Playtest retry lost editor origin or saved content.")
	current_scene.get_node("%LossButton").pressed.emit()
	await scene_changed
	current_scene.primary_button.get_parent().get_node("ReturnToEditor").pressed.emit()
	await scene_changed
	editor = current_scene

	# Cancel keeps the draft, Discard leaves without saving, Save & Leave persists it.
	editor.tabs.current_tab = 2
	await _flush()
	_select_entry(editor, "cards", "broadside")
	_text(editor.fields.name, "Unsaved Name")
	editor.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	expect(editor.leave_dialog.visible and editor.leave_destination == "quit", "Window close bypassed unsaved-change protection.")
	editor.leave_dialog.get_cancel_button().pressed.emit()
	await _flush()
	expect(current_scene == editor and not auto_accept_quit, "Cancel window close lost the editor or its close handler.")
	_find_button(editor, "Main Menu").pressed.emit()
	expect(editor.leave_dialog.visible, "Dirty navigation did not show Save/Discard/Cancel.")
	editor.leave_dialog.get_cancel_button().pressed.emit()
	await _flush()
	expect(current_scene == editor and editor.fields.name.text == "Unsaved Name", "Cancel discarded the draft.")
	_find_button(editor, "Main Menu").pressed.emit()
	editor.leave_dialog.custom_action.emit("discard")
	await scene_changed
	expect(current_scene.name == "MainMenu", "Discard did not leave the editor.")
	expect(auto_accept_quit, "Editor left a window-close override active in the main menu.")
	current_scene.get_node("%EditorButton").pressed.emit()
	await scene_changed
	editor = current_scene
	expect(editor.fields.name.text == "Thunder Cannon", "Discard persisted unsaved changes.")
	editor.fields.cost.value = 2
	_find_button(editor, "Main Menu").pressed.emit()
	editor.leave_dialog.get_ok_button().pressed.emit()
	await scene_changed
	expect(current_scene.name == "MainMenu" and store.saved.cards[3].cost == 2, "Save & Leave failed.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.state.ships[0].max_hull == 32 and current_scene.state.definitions.cards.broadside.cost == 2, "Start Game did not use the saved editor setup.")
	expect(not current_scene.get_node("%ReturnToEditor").visible, "Normal Start Game retained playtest navigation.")
	expect(FileAccess.get_sha256("res://data/content.json") == project_hash, "Editor tests changed project content.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	print("Editor UI: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)

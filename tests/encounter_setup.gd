extends "res://tests/support/v3_test.gd"

func drag(control: Control, destination: Control) -> void:
	var origin := control.get_global_transform_with_canvas() * (control.size / 2)
	await motion(origin)
	await mouse(origin, true)
	await motion(origin + Vector2(0, -60), true)
	expect(root.gui_is_dragging(), "Monster drag did not start.")
	var point := destination.get_global_transform_with_canvas() * (destination.size / 2)
	await motion(point, true)
	await mouse(point, false)
	await flush()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var store = root.get_node("ContentStore")
	store.saved = fixture.duplicate(true)
	var original: Dictionary = store.saved.duplicate(true)
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	current_scene.launch_button.pressed.emit()
	await scene_changed
	var setup = current_scene
	await flush()
	expect(setup.name == "EncounterSetup", "Fleet preparation skipped encounter setup.")
	expect(setup.difficulty_picker.item_count == 10 and setup.draft.setup.encounter_stars == 6, "Difficulty selector did not offer 1–10 stars with the legacy three-card default.")
	setup.difficulty_picker.select(8)
	setup.difficulty_picker.item_selected.emit(8)
	expect(setup.draft.setup.encounter_stars == 9 and "4" in setup.row_preview.text, "Selecting nine stars did not preview four cards.")
	var roster := setup.find_child("MonsterRoster", true, false) as Control
	var id: String = setup.slots[0]
	var option: Button = roster.get_child(Catalog.index_by_id(fixture.leviathans, id))
	await drag(option, setup.formation.widgets[2])
	expect(setup.slots[0] == id and setup.slots[2] == id, "Roster drag did not add a duplicate.")
	expect(setup.selected_slot == 2 and setup.inspector.get_child_count() > 5, "Placed monster details did not open.")
	var upper: String = setup.slots[1]
	await drag(setup.formation.widgets[2], setup.formation.widgets[1])
	expect(setup.slots[1] == id and setup.slots[2] == upper, "Placed monsters did not swap.")
	setup._back()
	await scene_changed
	current_scene.launch_button.pressed.emit()
	await scene_changed
	setup = current_scene
	expect(setup.slots[0] == id and setup.slots[1] == id and setup.draft.setup.encounter_stars == 9, "Returning to Fleet lost encounter edits or difficulty.")
	setup.start_button.pressed.emit()
	await scene_changed
	var battle = current_scene.state
	expect(battle.enemy_row.size() == 4 and current_scene.stance_panel.buttons.size() == 4, "Nine-star Custom Battle did not display four cards.")
	var first: int = battle.enemy_formation[0]
	var second: int = battle.enemy_formation[1]
	expect(first != second and battle.enemies[first].id == id and battle.enemies[second].id == id, "Battle did not create independent monsters.")
	var expected_cards := 0
	for entry in battle.enemies[first].stance_loadout:
		expected_cards += int(entry.count)
	for index in [first, second]:
		expect(battle.stance_cards.filter(func(card): return card.owner == -1 - index).size() == expected_cards, "Duplicate lost its own stance cards.")
	expect(store.saved == original, "Encounter setup modified authored content.")
	change_scene_to_file("res://scenes/encounter_setup.tscn")
	await scene_changed
	setup = current_scene
	var rear_drop := {"encounter": setup.get_instance_id(), "monster": id, "origin": -1}
	setup._drop(Vector2.ZERO, rear_drop, 3)
	setup._select_slot(0)
	setup._remove_selected()
	expect(setup.slots[0] == id and setup.slots[3].is_empty(), "Rear monster did not advance after removing Front.")
	while setup.slots.any(func(slot): return slot != ""):
		setup._select_slot(setup.slots.find_custom(func(slot): return slot != ""))
		setup._remove_selected()
	expect(setup.start_button.disabled and setup.draft.setup.enemies.is_empty(), "Empty encounter can start.")
	setup._drop(Vector2.ZERO, rear_drop, 3)
	expect(setup.slots[0] == id and setup.slots[3].is_empty() and setup.selected_slot == 0, "A lone enemy dropped into Rear did not move to Front.")
	done("Encounter setup")

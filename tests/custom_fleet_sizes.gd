extends "res://tests/support/v3_test.gd"

func _run() -> void:
	root.size = Vector2i(1024, 640)
	var store = root.get_node("ContentStore")
	store.saved = Catalog.read_document("res://data/content.json").document
	var saved: Dictionary = store.saved.duplicate(true)
	for count in range(1, 5):
		change_scene_to_file("res://scenes/fleet_preparation.tscn")
		await scene_changed
		var prep = current_scene
		prep._reset()
		if count < 3:
			for index in 3 - count:
				prep._unassign({"preparation": prep.get_instance_id(), "kind": "ship", "ship": prep.draft.setup.fleet[index].ship}, "ship")
		elif count == 4:
			var point: int = prep.formation.snapshot.formation.find(-1)
			prep._drop_at(Vector2.ZERO, {"preparation": prep.get_instance_id(), "kind": "ship", "ship": "breakwater"}, point)
			expect(prep.launch_button.disabled, "An occupied ship without a captain could launch.")
			prep._show_ship_info(3)
			await flush()
			expect(prep.deck_cards.get_child_count() == 2 and prep.deck_cards.is_visible_in_tree(), "Ship cards disappeared without a captain.")
			expect(not prep.ship_info_dialog.get_ok_button().visible, "Ship info still has a bottom Close button.")
			prep.ship_info_dialog.hide()
			prep._drop_at(Vector2.ZERO, {"preparation": prep.get_instance_id(), "kind": "captain", "captain": "mara"}, point)
			expect(prep.deck_cards.get_child_count() == 3, "Assigned captain card is missing from the ship preview.")
		expect(not prep.launch_button.disabled, "Fleet of %d cannot continue." % count)
		prep.launch_button.pressed.emit()
		await scene_changed
		current_scene.start_button.pressed.emit()
		await scene_changed
		var state = current_scene.state
		expect(state.ships.size() == count and state.hand.size() == 4 + count, "Fleet of %d launched with incorrect ships or opening hand." % count)
	expect(store.saved == saved, "Custom Battle modified authored content.")
	done("Custom fleet sizes and ship cards")

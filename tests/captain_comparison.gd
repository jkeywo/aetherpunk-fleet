extends "res://tests/support/v3_test.gd"
func column_for(prep, id: String) -> Node:
	for column in prep.captain_comparison.get_children():
		if column.get_meta("captain_id") == id: return column
	return null
func assignment(column: Node) -> Button:
	for child in column.get_children():
		if child.has_meta("assign_captain"): return child
	return null
func _run() -> void:
	root.size = Vector2i(1280,800)
	var store_node = root.get_node("ContentStore")
	store_node.saved = fixture.duplicate(true)
	var saved := JSON.stringify(store_node.saved)
	var file_hash := FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	var prep = current_scene
	var before := JSON.stringify(prep.draft)
	prep._show_captains()
	await flush()
	expect(prep.captain_dialog.visible and prep.captain_comparison.get_child_count() == 3, "Comparison does not show all three captains.")
	expect(JSON.stringify(prep.draft) == before, "Opening captain comparison changed choices.")
	for captain in prep.draft.captains:
		var column := column_for(prep,captain.id)
		var face: Control = column.get_children().filter(func(child): return child.has_meta("card_id"))[0]
		var passive: Label = column.get_children().filter(func(child): return child.has_meta("captain_passive"))[0]
		expect(face.get_meta("card_id") == captain.card and face.get_meta("copies") == 2 and face.owner_info.name == "Bastion", "Captain card pair not previewed as selected ship.")
		expect(passive.text == R.rule_text(captain.passive,"Bastion"), "Captain passive missing or names the previous ship.")
	expect(assignment(column_for(prep,"iona")).disabled, "Current captain is not marked assigned.")
	var other := -1
	for i in prep.draft.setup.fleet.size():
		if prep.draft.setup.fleet[i].captain == "voss": other = i
	assignment(column_for(prep,"voss")).pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].captain == "voss" and prep.draft.setup.fleet[other].captain == "iona", "Comparison assignment failed to swap occupied captains.")
	expect(assignment(column_for(prep,"voss")).disabled and not assignment(column_for(prep,"iona")).disabled, "Assigned statuses did not refresh.")
	expect(prep.deck_cards.get_children()[1].get_children().back().get_meta("card_id") == "evasive_orders", "Assignment did not update selected ship's actual deck preview.")
	# Additional authored captains remain browsable and can be assigned from the bench.
	var extra: Dictionary = prep.draft.captains[0].duplicate(true)
	extra.id = "spare_captain"
	extra.name = "Spare Captain"
	extra.card = "spare_orders"
	var extra_card: Dictionary = card_def(prep.draft,"field_orders").duplicate(true)
	extra_card.id = extra.card
	extra_card.owner = extra.id
	prep.draft.captains.append(extra)
	prep.draft.cards.append(extra_card)
	prep._show_captains()
	await flush()
	expect(prep.captain_comparison.get_child_count() == 4 and prep.captain_comparison.size.x > prep.captain_comparison.get_parent().size.x, "Additional captains cannot be scrolled side by side.")
	assignment(column_for(prep,extra.id)).pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].captain == extra.id and Catalog.validate(prep._candidate()).is_empty(), "Unassigned captain could not be assigned cleanly.")
	prep.captain_dialog.hide()
	prep.selected_ship = 1
	prep._render()
	prep._show_captains()
	await flush()
	expect("Kestrel" in prep.captain_dialog.title and column_for(prep,"iona").get_children().filter(func(child): return child.has_meta("card_id"))[0].owner_info.name == "Kestrel", "Comparison retained the previous selected ship.")
	root.size = Vector2i(1024,640)
	prep._show_captains()
	await flush()
	expect(prep.captain_dialog.size.x <= prep.get_viewport_rect().size.x, "Captain comparison exceeds smaller viewport.")
	expect(JSON.stringify(store_node.saved) == saved and FileAccess.get_sha256("res://data/content.json") == file_hash, "Captain comparison changed saved content.")
	done("Captain comparison and assignment")

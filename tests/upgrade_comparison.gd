extends "res://tests/support/v3_test.gd"
func branch(prep, id: String) -> Node:
	for column in prep.upgrade_comparison.get_children():
		if column.get_meta("branch_id") == id: return column
	return null
func choose_button(column: Node) -> Button:
	for child in column.get_children():
		if child.has_meta("choose_branch"): return child
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
	prep._change(1,0,"level")
	var before := JSON.stringify(prep.draft)
	prep._show_upgrades("two")
	await flush()
	expect(prep.upgrade_dialog.visible and prep.upgrade_comparison.get_child_count() == 2, "Level 2 comparison does not show both branches.")
	expect(JSON.stringify(prep.draft) == before, "Opening comparison changed preparation choices.")
	var ship: Dictionary = prep.draft.ships[Catalog.index_by_id(prep.draft.ships, prep.draft.setup.fleet[0].ship)]
	for package in ship.levels.two:
		var column := branch(prep,package.id)
		var faces: Array = column.get_children().filter(func(child): return child.has_meta("card_id"))
		expect(faces.size() == 1 and faces[0].get_meta("card_id") == package.card and not faces[0].labels.rules.text.is_empty(), "Unchosen branch card/rules missing.")
		expect(not choose_button(column).disabled, "Level 2 branch cannot be chosen from level 1.")
	choose_button(branch(prep, ship.levels.two[1].id)).pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].level == 2 and prep.draft.setup.fleet[0].level_2 == ship.levels.two[1].id, "Choosing branch failed to raise level and assign it.")
	expect(choose_button(branch(prep,ship.levels.two[1].id)).disabled, "Current branch is not marked Selected.")
	prep._show_upgrades("three")
	await flush()
	expect(prep.upgrade_comparison.get_child_count() == 3, "Level 3 comparison hides blocked options.")
	var blocked: String = ship.levels.two[1].blocks
	expect(choose_button(branch(prep,blocked)).disabled, "Blocked branch can be selected.")
	before = JSON.stringify(prep.draft)
	prep._choose_upgrade("three",blocked)
	expect(JSON.stringify(prep.draft) == before, "Blocked branch bypassed selection guard.")
	var legal: String = ship.levels.three.filter(func(package): return package.id != blocked)[0].id
	choose_button(branch(prep,legal)).pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].level == 3 and prep.draft.setup.fleet[0].level_3 == legal and "8 cards" in prep.deck_summary.text, "Level 3 selection did not update actual deck preview.")
	prep.upgrade_dialog.hide()
	prep._change(1,0,"level")
	prep._show_upgrades("three")
	await flush()
	expect(prep.upgrade_comparison.get_children().all(func(column): return choose_button(column).disabled), "Level 3 selection allowed before Level 2 choice.")
	root.size = Vector2i(1024,640)
	prep._show_upgrades("three")
	await flush()
	expect(prep.upgrade_dialog.size.x <= prep.get_viewport_rect().size.x and prep.upgrade_comparison.size.x <= prep.upgrade_dialog.size.x, "Comparison does not fit smaller viewport side by side.")
	expect(JSON.stringify(store_node.saved) == saved and FileAccess.get_sha256("res://data/content.json") == file_hash, "Branch comparison edited saved content.")
	done("Upgrade branch comparison")

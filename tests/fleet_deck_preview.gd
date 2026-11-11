extends "res://tests/support/v3_test.gd"
func faces(node: Node) -> Array:
	var result: Array = []
	if node.has_meta("card_id"): result.append(node)
	for child in node.get_children(): result.append_array(faces(child))
	return result
func matches_deck(prep) -> bool:
	var compiled := Catalog.compile(prep._candidate())
	var expected: Dictionary = {}
	for index in compiled.ships.size():
		for pair in compiled.ships[index].loadout:
			var key := "%d/%s" % [index,pair.card]
			expected[key] = expected.get(key,0) + pair.count
	var actual: Dictionary = {}
	for face in faces(prep.fleet_deck_body):
		actual["%d/%s" % [face.get_meta("ship_index"),face.get_meta("card_id")]] = face.get_meta("copies")
	return expected == actual
func _run() -> void:
	root.size = Vector2i(1280,800)
	var store_node = root.get_node("ContentStore")
	store_node.saved = fixture.duplicate(true)
	var saved := JSON.stringify(store_node.saved)
	var file_hash := FileAccess.get_sha256("res://data/content.json")
	change_scene_to_file("res://scenes/fleet_preparation.tscn")
	await scene_changed
	var prep = current_scene
	await flush()
	expect(prep.preparation_tabs.get_tab_count() == 2 and prep.preparation_tabs.get_tab_title(1) == "Fleet Deck", "Preparation tabs missing.")
	expect(matches_deck(prep) and "18 cards" in prep.fleet_deck_summary.text, "Fleet deck omits starter, captain or upgrade pairs.")
	var before := JSON.stringify(prep.draft)
	var bar: TabBar = prep.preparation_tabs.get_tab_bar()
	var tab_point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(1).get_center()
	await motion(tab_point)
	await mouse(tab_point,true)
	await mouse(tab_point,false)
	await flush()
	expect(prep.fleet_deck_body.is_visible_in_tree() and not prep.formation.is_visible_in_tree(), "Fleet Deck tab did not replace setup view.")
	expect(JSON.stringify(prep.draft) == before, "Tab navigation changed fleet choices.")
	var owner := -1
	var type := -1
	var ordered := true
	for face in faces(prep.fleet_deck_body):
		var next_owner: int = face.get_meta("ship_index")
		var next_type: int = R.TYPES.find(face.info.type)
		if next_owner < owner or (next_owner == owner and next_type < type): ordered = false
		owner = next_owner
		type = next_type
		expect(face.owner_info.name == prep.draft.ships[Catalog.index_by_id(prep.draft.ships,prep.draft.setup.fleet[owner].ship)].name and not face.labels.rules.text.is_empty(), "Deck card lost owning ship or rules.")
	expect(ordered, "Fleet deck not grouped by ship then primary type.")
	prep._change(3,0,"level")
	await flush()
	expect(prep.preparation_tabs.current_tab == 1 and matches_deck(prep) and "20 cards" in prep.fleet_deck_summary.text, "Upgrades did not refresh full deck or changed tabs.")
	prep._change("rook",0,"captain")
	await flush()
	expect(matches_deck(prep) and faces(prep.fleet_deck_body).any(func(face): return face.get_meta("ship_index") == 0 and face.get_meta("card_id") == "command_barrage"), "Captain swap did not refresh full fleet ownership.")
	prep._change("assault",0,"level_2")
	await flush()
	expect(matches_deck(prep) and faces(prep.fleet_deck_body).any(func(face): return face.get_meta("ship_index") == 0 and face.get_meta("card_id") == "advance"), "Branch change did not replace upgrade in full deck.")
	prep.preparation_tabs.current_tab = 0
	await flush()
	expect(prep.formation.is_visible_in_tree() and prep.selected_ship == 0, "Returning to setup lost selected ship.")
	prep._reset()
	await flush()
	expect(matches_deck(prep) and "18 cards" in prep.fleet_deck_summary.text, "Reset left stale full-deck cards.")
	# Imported loadouts may repeat a design and use uneven counts.
	prep.draft.setup.fixed_hand = false
	prep.draft.ships[0].legacy_loadout = [{"card":"brace","count":3},{"card":"brace","count":2}]
	prep._render()
	await flush()
	var merged: Array = faces(prep.fleet_deck_body).filter(func(face): return face.get_meta("ship_index") == 0)
	expect(matches_deck(prep) and merged.size() == 1 and merged[0].get_meta("copies") == 5, "Repeated imported designs were not aggregated with accurate copy counts.")
	root.size = Vector2i(1024,640)
	prep.preparation_tabs.current_tab = 1
	await flush()
	expect(prep.launch_button.is_visible_in_tree() and prep.launch_button.get_global_rect().end.y <= prep.get_viewport_rect().size.y, "Deck tab obscures Launch in smaller windows.")
	expect(JSON.stringify(store_node.saved) == saved and FileAccess.get_sha256("res://data/content.json") == file_hash, "Full deck preview changed saved content.")
	var expected_keys: Array = Catalog.compile(prep._candidate()).deck_keys.duplicate()
	prep.launch_button.pressed.emit()
	await scene_changed
	current_scene.start_button.pressed.emit()
	await scene_changed
	expect(current_scene.state.init_error == "" and current_scene.state.card_keys == expected_keys, "Launching from Fleet Deck did not use the previewed assembled deck.")
	done("Tabbed fleet deck preview")

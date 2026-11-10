extends "res://tests/support/v3_test.gd"
func column_for(prep, id: String) -> Node:
	for column in prep.ship_comparison.get_children():
		if column.get_meta("ship_id") == id: return column
	return null
func tagged(column: Node, key: String) -> Node:
	for child in column.get_children():
		if child.has_meta(key): return child
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
	prep._show_ships()
	await flush()
	expect(prep.ship_dialog.visible and prep.ship_comparison.get_child_count() == 3, "Ship comparison does not show all three ships.")
	expect(JSON.stringify(prep.draft) == before, "Opening ship comparison changed choices.")
	for ship in prep.draft.ships:
		var column := column_for(prep,ship.id)
		var stats: String = tagged(column,"ship_stats").text
		var face = tagged(column,"card_id")
		var mechanism: String = tagged(column,"ship_mechanism").text
		expect("Hull %d / Armour %d" % [ship.hull,ship.armour] in stats and "Weapon %d / %s" % [ship.weapon.damage,ship.weapon.range] in stats and ship.resource.name in stats, "Base stats missing or polluted by selected upgrades.")
		expect(face.get_meta("card_id") == ship.starter and face.get_meta("copies") == 2 and face.owner_info.name == ship.name, "Starter pair or owning ship styling missing.")
		expect(ship.resource.rules.all(func(rule): return R.rule_text(rule,ship.name) in mechanism), "Unique resource loop or optional boost missing.")
	expect(tagged(column_for(prep,"bastion"),"choose_ship").disabled, "Current ship is not marked selected.")
	var profiles: Array = prep.draft.setup.fleet.map(func(slot): return [slot.captain,slot.level,slot.position])
	tagged(column_for(prep,"kestrel"),"choose_ship").pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].ship == "kestrel" and prep.draft.setup.fleet[1].ship == "bastion", "Choosing occupied ship did not swap unique fleet assignments.")
	expect(prep.draft.setup.fleet.map(func(slot): return [slot.captain,slot.level,slot.position]) == profiles, "Ship comparison silently moved captains or levels between slots.")
	expect(tagged(column_for(prep,"kestrel"),"choose_ship").disabled and "Kestrel" in prep.deck_summary.text, "Selected status and actual deck preview did not update.")
	# Additional authored ships can be browsed and replace the current slot.
	var extra: Dictionary = prep.draft.ships[0].duplicate(true)
	extra.id = "spare_ship"
	extra.name = "Spare Ship"
	extra.starter = "spare_starter"
	for tier in ["two","three"]:
		for package in extra.levels[tier]: package.card = extra.starter
	var extra_card: Dictionary = card_def(prep.draft,"brace").duplicate(true)
	extra_card.id = extra.starter
	extra_card.owner = extra.id
	prep.draft.ships.append(extra)
	prep.draft.cards.append(extra_card)
	prep._show_ships()
	await flush()
	expect(prep.ship_comparison.get_child_count() == 4 and prep.ship_comparison.size.x > prep.ship_comparison.get_parent().size.x, "Extra ships cannot be browsed horizontally.")
	tagged(column_for(prep,extra.id),"choose_ship").pressed.emit()
	await flush()
	expect(prep.draft.setup.fleet[0].ship == extra.id and Catalog.validate(prep._candidate()).is_empty(), "Choosing bench ship did not produce a legal fleet.")
	prep.ship_dialog.hide()
	prep.selected_ship = 2
	prep._render()
	prep._show_ships()
	await flush()
	expect(prep.draft.setup.fleet[2].position.capitalize() in prep.ship_dialog.title and tagged(column_for(prep,prep.draft.setup.fleet[2].ship),"choose_ship").disabled, "Comparison retained the previous selected position.")
	root.size = Vector2i(1024,640)
	prep._show_ships()
	await flush()
	expect(prep.ship_dialog.size.x <= prep.get_viewport_rect().size.x, "Ship comparison exceeds smaller viewport.")
	expect(JSON.stringify(store_node.saved) == saved and FileAccess.get_sha256("res://data/content.json") == file_hash, "Ship comparison changed saved content.")
	done("Ship comparison and fleet selection")

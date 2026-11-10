extends "res://tests/support/v3_test.gd"

func effect_count(design: Dictionary) -> int:
	var count := 0
	for ability in design.rules: count += ability.effects.size() + ability.modifiers.size()
	return count

func _run() -> void:
	var loaded := Catalog.read_document("res://data/content.json")
	expect(loaded.ok and Catalog.validate(loaded.document).is_empty(), "Simplified live content is invalid.")
	var doc: Dictionary = loaded.document
	for ship in doc.ships:
		expect(effect_count(card_def(doc, ship.starter)) == 1, "Starter should have one effect: " + ship.name)
		for level in ["two", "three"]:
			for branch in ship.levels[level]:
				expect(effect_count(card_def(doc, branch.card)) == (2 if level == "two" else 3), "Upgrade effect budget incorrect: " + branch.card)
	for captain in doc.captains:
		expect(effect_count(card_def(doc, captain.card)) == captain.tier, "Captain effect budget does not match tier: " + captain.name)
	await open_battle(doc)
	var b = current_scene
	all_in_hand(b.state)
	var original: Array = b.state.hand.duplicate()
	b._render()
	await flush()
	var previous_owner := -1
	var previous_type := -1
	var ordered := true
	for face in b.hand_view.get_children():
		var design: Dictionary = b.state.card(face.get_meta("uid"))
		var card_type: int = R.TYPES.find(design.type)
		if design.owner < previous_owner or (design.owner == previous_owner and card_type < previous_type): ordered = false
		previous_owner = design.owner
		previous_type = card_type
	expect(ordered and b.hand_view.get_child_count() == original.size(), "Displayed hand is not grouped by ship then type.")
	expect(b.state.hand == original, "Presentation sort changed the underlying hand order.")
	for id in b.state.ships.size():
		var tooltip: String = b.allies.target_widget(id).tooltip_text
		expect("Unique mechanic / " + b.state.ships[id].resource_name in tooltip and "Optional boost" in tooltip and "Spend 2 personal resource" in tooltip, "Ship hover does not explain its resource loop and boost.")
	var display_ids: Array = b.hand_view.get_children().map(func(face): return face.get_meta("uid"))
	var front: int = b.state.formation[0]
	b.state.formation[0] = b.state.formation[1]
	b.state.formation[1] = front
	b._render()
	await flush()
	expect(display_ids == b.hand_view.get_children().map(func(face): return face.get_meta("uid")), "Moving ships needlessly reordered the hand groups.")
	# The editor's new starter/captain and upgrade cards follow the same progression.
	change_scene_to_file("res://scenes/editor.tscn")
	await scene_changed
	var editor = current_scene
	expect(effect_count(editor._new_card("test", "bastion")) == 1, "New card is not simple by default.")
	expect(effect_count(editor._new_card("test", "bastion", 2)) == 2 and effect_count(editor._new_card("test", "bastion", 3)) == 3, "Editor upgrade templates do not scale complexity.")
	editor._new_entry("ships")
	var authored: Dictionary = editor.draft.ships.back()
	expect(Catalog.validate(editor.draft).is_empty(), "New ship templates created invalid content.")
	var correct := effect_count(card_def(editor.draft, authored.starter)) == 1
	for tier in ["two", "three"]:
		for branch in authored.levels[tier]: correct = correct and effect_count(card_def(editor.draft, branch.card)) == (2 if tier == "two" else 3)
	expect(correct, "New ship branches reused the one-effect starter instead of upgrade cards.")
	done("Hand order, card complexity and ship mechanisms")

extends "res://tests/support/v2_test.gd"

func _run() -> void:
	var loaded := Catalog.read_document("res://data/content.json")
	expect(loaded.ok, "Saved example content failed validation.")
	if not loaded.ok:
		done("Circle example cards")
		return
	var doc: Dictionary = loaded.document
	var b = State.new(7, doc)
	expect(b.init_error == "", "Example battle failed to initialize.")
	expect(b.card_keys.size() == 18, "Examples should preserve the 18-card deck.")
	for ship in doc.ships:
		var count := 0
		for entry in ship.loadout:
			count += entry.count
		expect(count == 6, "Examples changed a ship's six-card contribution.")
	var opening := ["aether_conduit", "resonant_bulwark", "arc_echo", "convergence_bolt", "broadside", "brace", "relay"]
	expect(b.hand.map(func(uid): return b.card_keys[uid]) == opening, "Example opening hand changed.")
	for id in opening.slice(0, 4):
		expect(uid_for(b, id) >= 0, "Example missing from opening hand: " + id)
	expect(b.play(uid_for(b, "aether_conduit"), [], -1, -1, 0) == "", "Conduit failed at North.")
	expect(b.ships[2].guard == 2, "Conduit's immediate guard failed.")
	var bolt := uid_for(b, "convergence_bolt")
	expect(b.effective_cost(bolt, 1) == 0 and b.effective_cost(bolt, 2) == 1, "Conduit discount must require adjacency.")
	expect(b.play(uid_for(b, "resonant_bulwark"), [], -1, -1, 1) == "", "Bulwark failed at East.")
	var echo := uid_for(b, "arc_echo")
	var preview := b.preview(echo, [], -1, -1, 2)
	expect(preview.ok and "70 → 66" in preview.text and "2 card trigger(s)" in preview.text, "Example chain preview is incorrect.")
	expect(b.monster_hull == 70 and b.used_triggers.is_empty(), "Preview consumed an example trigger.")
	expect(b.play(echo, [], -1, -1, 2) == "", "Arc Echo failed at South.")
	expect(b.monster_hull == 66 and b.ships[1].guard == 3, "Damage → guard → damage example chain failed.")
	var triggered: Array = b.feedback_events.filter(func(event): return event.kind == "card_triggered")
	expect(triggered.size() == 2 and triggered[0].uid == b.circle[1] and triggered[1].uid == echo, "Example chain source order incorrect.")
	expect(b.used_triggers.size() == 2 and not b.expanded, "Example triggers or expansion timing incorrect.")
	preview = b.preview(bolt, [], -1, -1, 3)
	expect(preview.ok and "66 → 56" in preview.text and "Unlocks five" in preview.text, "Conditional shot/expansion preview incorrect.")
	expect(b.play(bolt, [], -1, -1, 3) == "", "Discounted Convergence Bolt failed at West.")
	expect(b.monster_hull == 56 and b.expanded, "Bolt should deal 10 damage and expand the circle.")
	expect(b.used_triggers.size() == 2 and conserved(b), "Example reused a trigger or lost a card.")
	var broadside := uid_for(b, "broadside")
	expect(b.effective_cost(broadside, 4) == 1 and b.effective_cost(broadside, 6) == 2, "Expanded centre/corner adjacency discount incorrect.")
	expect(b.play(broadside, [uid_for(b, "brace")], -1, -1, 4) == "", "Expanded-centre follow-up failed.")
	expect(b.monster_hull == 45 and b.used_triggers.size() == 2, "Used example chains fired again on the follow-up.")
	b.end_phase()
	expect(b.used_triggers.is_empty() and not b.expanded and b.play_order.is_empty() and conserved(b), "Example cards did not clean up at turn start.")
	b = State.new(7, doc)
	b.play(uid_for(b, "aether_conduit"), [], -1, -1, 0)
	bolt = uid_for(b, "convergence_bolt")
	expect(b.validate(bolt, [], -1, -1, 2) != "", "Nonadjacent bolt was incorrectly free.")
	expect(b.play(bolt, [uid_for(b, "brace")], -1, -1, 2) == "" and b.monster_hull == 67, "Nonadjacent bolt should deal only 3 damage.")
	done("Circle example cards")

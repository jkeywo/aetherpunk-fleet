extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var b = State.new(4, fixture)
	expect(b.stance_cards.size() == 11 and b.enemy_row.size() == 3 and b.stance_deck.size() == 8, "Weighted shared deck sizes wrong.")
	for owner in [-1, -2, -3]:
		expect(b.stance_cards.filter(func(card): return card.owner == owner).size() == {-1: 6, -2: 3, -3: 2}[owner], "Enemy weight ignored.")
	expect(b.enemy_row.duplicate().size() == 3 and b.enemy_row[0] != b.enemy_row[1] and b.enemy_row[1] != b.enemy_row[2], "Active row duplicated a physical card.")
	var doc := neutral(true)
	for enemy in doc.leviathans:
		enemy.stance_loadout[0].count = 3
		enemy.stances[0].effects = [attack(1, 1, "Long", "chosen_ally")]
		enemy.default_action = [attack(1, 1, "Long", "chosen_ally")]
	b = State.new(3, doc)
	var boss: Array = []
	for uid in b.stance_cards.size():
		if b.stance_cards[uid].owner == -1: boss.append(uid)
	b.enemy_row = boss
	b.stance_deck = range(b.stance_cards.size()).filter(func(uid): return not boss.has(uid))
	b.stance_discard.clear()
	b.end_phase()
	var activations: Array = b.feedback_events.filter(func(e): return e.kind == "intent_triggered")
	expect(activations.size() == 5 and activations.filter(func(e): return "weaker default" in e.title).size() == 2, "Repeated owner did not act three times plus inactive defaults.")
	expect(b.ships[0].hull == 24 and b.ships[1].hull == 19, "Matching-position/rear-to-front enemy targeting wrong.")
	expect(b.enemy_row.size() == 3 and b.phase == "refresh", "Replacement cards added extra activations or failed to refill.")
	doc = neutral(true)
	for enemy in doc.leviathans:
		enemy.stances[0].reactions = [{"id": "counter", "name": "Counter", "category": "Retaliation", "conditions": {"kind": "card_matches", "target": "event_card", "card_type": "Guard"}, "effects": [attack(1, 1, "Long", "chosen_ally")]}]
	b = State.new(3, doc)
	b.enemy_row = [0, 3, 6]
	b.stance_deck = [1, 2, 4, 5, 7, 8]
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	var reactions: Array = b.feedback_events.filter(func(e): return e.kind == "reaction_triggered")
	expect(reactions.size() == 3, "Each represented enemy did not react once.")
	expect(reactions[0].stance_uid == 0 and reactions[1].stance_uid == 3 and reactions[2].stance_uid == 6, "Enemy reaction formation order wrong.")
	expect(not b.enemy_row.has(0) and not b.enemy_row.has(3) and not b.enemy_row.has(6), "Reaction cards were not discarded/replaced.")
	expect(b.ships[0].hull == 26 and b.ships[1].hull == 19, "New row cards reacted again to the same action.")
	b = State.new(3, doc)
	b.enemy_row = [0, 1, 2]
	b.stance_deck = [3, 4, 5, 6, 7, 8]
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	expect(b.feedback_events.filter(func(e): return e.kind == "reaction_triggered").size() == 1, "One owner reacted from multiple row cards.")
	# Confuse reveals a new owner but the replacement cannot react to this action.
	card_def(doc, "brace").rules[0].effects = [{"kind": "confuse", "target": "chosen_stance"}]
	b = State.new(3, doc)
	b.enemy_row = [0, 1, 2]
	b.stance_deck = [3, 4, 5, 6, 7, 8]
	b.play(uid_for(b, "brace"), [], -1, -1, 0, {"stance": 0})
	expect(b.enemy_row.any(func(uid): return b.stance_cards[uid].owner == -2), "Confuse did not reveal replacement.")
	reactions = b.feedback_events.filter(func(e): return e.kind == "reaction_triggered")
	expect(reactions.size() == 1 and reactions[0].stance_uid == 1, "Newly confused/reaction replacement responded to its revealing action.")
	# Stun only the selected visible rule; other owners remain dangerous.
	doc = neutral(true)
	for enemy in doc.leviathans:
		enemy.stances[0].reactions = [{"id": "counter", "name": "Counter", "category": "Retaliation", "conditions": {"kind": "card_matches", "target": "event_card", "card_type": "Guard"}, "effects": [attack(1, 1, "Long", "chosen_ally")]}]
	card_def(doc, "brace").rules[0].effects = [{"kind": "stun", "target": "chosen_reaction"}]
	b = State.new(3, doc)
	b.enemy_row = [0, 3, 6]
	b.stance_deck = [1, 2, 4, 5, 7, 8]
	b.play(uid_for(b, "brace"), [], -1, -1, 0, {"reaction": "0/counter"})
	expect(b.stunned.has("0/counter") and b.enemy_row.has(0), "Stun did not suppress/retain the selected rule.")
	expect(b.feedback_events.filter(func(e): return e.kind == "reaction_triggered").size() == 2, "Stun disabled all enemies instead of one visible reaction.")
	b.end_phase()
	expect(b.stunned.is_empty(), "Stun did not expire at fleet phase end.")
	doc = neutral(true)
	card_def(doc, "broadside").rules[0].effects = [attack(999)]
	b = State.new(3, doc)
	b.enemy_row = [0, 3, 6]
	b.stance_deck = [1, 2, 4, 5, 7, 8]
	b.play(uid_for(b, "broadside"), [], -1, -1, 0, {"enemy": -2})
	expect(b.enemies[1].hull == 0 and b.enemy_formation[1] == -1, "Enemy defeat did not preserve an empty slot.")
	for pile in [b.enemy_row, b.stance_deck, b.stance_discard]:
		expect(not pile.any(func(uid): return b.stance_cards[uid].owner == -2), "Defeated owner remained in shared deck.")
	expect(b.enemy_row.size() == 3 and b.outcome == "", "Other enemies did not continue after a defeat.")
	# Rear short attacks skip rather than silently becoming ranged.
	doc = neutral()
	doc.setup.enemies[0].position = "rear"
	doc.leviathans[0].stances[0].effects = [attack(9, 1, "Short", "chosen_ally")]
	b = State.new(1, doc)
	b.end_phase()
	expect(b.ships.all(func(ship): return ship.hull == ship.max_hull), "Rear enemy originated a short attack.")
	b = State.new(1, neutral())
	b.formation = [-1, -1, -1, 0]
	b.ships[1].hull = 0
	b.ships[2].hull = 0
	expect(b._enemy_target(-1, "Short") == -999 and b._enemy_target(-1, "Long") == 0, "Enemy fallback targeted rear at short range.")
	done("Shared enemy row")

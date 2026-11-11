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
	var stance_owners := activations.filter(func(e): return e.has("stance_uid")).map(func(e): return e.presentation.owner)
	var default_owners := activations.filter(func(e): return not e.has("stance_uid")).map(func(e): return e.presentation.owner)
	expect(stance_owners == [-1, -1, -1] and default_owners == [-2, -3], "Only enemies without a stance activation should use a default action, once each.")
	expect(b.ships[0].hull == 24 and b.ships[1].hull == 19, "Matching-position/rear-to-front enemy targeting wrong.")
	expect(b.enemy_row.size() == 3 and b.phase == "refresh", "Replacement cards added extra activations or failed to refill.")
	var reveals: Array = b.feedback_events.filter(func(e): return e.kind == "stance_changed")
	expect(reveals.size() == 1 and b.feedback_events.find(reveals[0]) > b.feedback_events.find(activations.back()), "Enemy row did not refill as a batch after the default actions.")
	for event in activations:
		expect(event.board.stance_row.all(func(stance): return stance.owner == -1), "Replacement was visible during an enemy action.")
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
	expect(b.ships[0].hull == 25 and b.ships[1].hull == 20, "Each enemy should react once against the triggering ship.")
	b = State.new(3, doc)
	b.enemy_row = [0, 1, 2]
	b.stance_deck = [3, 4, 5, 6, 7, 8]
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	expect(b.feedback_events.filter(func(e): return e.kind == "reaction_triggered").size() == 1, "One owner reacted from multiple row cards.")
	var targeting_doc := neutral()
	var stance: Dictionary = targeting_doc.leviathans[0].stances[0]
	stance.effects = [attack(1, 1, "Long", "chosen_ally")]
	stance.reactions = [{"id":"counter","name":"Counter","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(2, 1, "Long", "chosen_ally")]}]
	b = State.new(3, targeting_doc)
	var broadside: int = uid_for(b, "broadside")
	var aim: Dictionary = b.reaction_preview(b.enemy_row[0], {"uid":broadside})
	expect("Reaction" in aim.notes.get(1, "") and "Intent" in aim.notes.get(0, ""), "Hover preview did not distinguish the card owner from the enemy-phase target.")
	expect(b.play(broadside, [], -1, -1, 0) == "" and b.ships[1].hull == 18 and b.ships[0].hull == 28, "Reaction did not hit the ship that played the card.")
	stance.reactions[0].effects[0].target = "fleet_front"
	b = State.new(3, targeting_doc)
	expect(b.play(uid_for(b, "broadside"), [], -1, -1, 0) == "" and b.ships[0].hull == 26 and b.ships[1].hull == 20, "Explicit reaction target was ignored.")
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
	expect(b.enemies[1].hull == 0 and b.enemy_formation == [0, 2, -1, -1], "With two survivors, the Rear enemy should move into the vacated Upper slot.")
	for pile in [b.enemy_row, b.stance_deck, b.stance_discard]:
		expect(not pile.any(func(uid): return b.stance_cards[uid].owner == -2), "Defeated owner remained in shared deck.")
	expect(b.enemy_row.size() == 3 and b.outcome == "", "Other enemies did not continue after a defeat.")
	# A missing default action should not present an empty enemy action card.
	doc = neutral(true)
	b = State.new(3, doc)
	b.enemy_row = [0, 1, 2]
	b.stance_deck = [3, 4, 5, 6, 7, 8]
	b.end_phase()
	expect(not b.feedback_events.any(func(e): return e.kind == "intent_triggered" and not e.has("stance_uid")), "Enemies without default effects showed a default action.")
	# Rear short attacks skip rather than silently becoming ranged.
	doc = neutral()
	doc.setup.enemies[0].position = "rear"
	doc.setup.enemies.append({"enemy": doc.leviathans[1].id, "position": "front"})
	doc.setup.enemies.append({"enemy": doc.leviathans[2].id, "position": "upper"})
	doc.leviathans[0].stances[0].effects = [attack(9, 1, "Short", "chosen_ally")]
	b = State.new(1, doc)
	b.enemy_row = [0, 1, 2]
	b.end_phase()
	expect(b.ships.all(func(ship): return ship.hull == ship.max_hull), "Rear enemy originated a short attack.")
	b = State.new(1, neutral())
	b.formation = [-1, -1, -1, 0]
	b.ships[1].hull = 0
	b.ships[2].hull = 0
	expect(b._enemy_target(-1, "Short") == -999 and b._enemy_target(-1, "Long") == 0, "Enemy fallback targeted rear at short range.")
	done("Shared enemy row")

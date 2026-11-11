extends "res://tests/support/v3_test.gd"
func _run() -> void:
	_payment()
	_damage()
	_persistence_and_mana()
	_hand_refill()
	_order_and_chains()
	done("Combat rules v3")

func _payment() -> void:
	var doc := neutral()
	card_def(doc, "broadside").cost = 2
	card_def(doc, "broadside").rules[0].effects = [attack(7)]
	var b = State.new(7, doc)
	var uid := uid_for(b, "broadside")
	var payer := uid_for(b, "brace")
	var original := JSON.stringify(b.board_snapshot())
	expect(b.play(uid, []) != "", "Unpaid card accepted.")
	expect(b.play(uid, [uid]) != "" and b.play(uid, [payer, payer]) != "", "Self/duplicate payment accepted.")
	expect(b.play(uid, [999]) != "" and JSON.stringify(b.board_snapshot()) == original, "Rejected payment mutated state.")
	var seed: int = b.rng.state
	var preview: Dictionary = b.preview(uid, [payer], -1, -1, 0)
	expect(preview.ok and "70 → 63" in preview.text and b.rng.state == seed, "Damage preview wrong or consumed RNG.")
	expect(b.play(uid, [payer], -1, -1, 0) == "" and b.monster_hull == 63, "Paid attack failed.")
	expect(b.circle[0] == uid and b.discard == [payer] and conserved(b), "Played/payment card locations wrong.")
	expect(b.play(uid_for(b, "strafe"), [], -1, -1, 0) != "", "Occupied circle slot accepted.")
	b = State.new(7, doc)
	b.mana = 1
	uid = uid_for(b, "broadside")
	expect(b.validate(uid, [], -1, -1, 0, {"crystals": 2}) != "", "Overspent crystals.")
	expect(b.play(uid, [uid_for(b, "strafe")], -1, -1, 0, {"crystals": 1}) == "" and b.mana == 0, "Mixed card/crystal payment failed.")
	expect(conserved(b), "Crystal payment lost a card.")

func _damage() -> void:
	var doc := neutral()
	card_def(doc, "broadside").rules[0].effects = [attack(4, 3)]
	var b = State.new(1, doc)
	b.enemies[0].armour = 2
	b.enemies[0].guard = 2
	b.cover[4] = 3
	b.play(uid_for(b, "broadside"), [], -1, -1, 0)
	# First hit: C3, A1. Second: A2 S2. Third: A2 hull2.
	expect(b.monster_hull == 68 and b.enemies[0].guard == 0 and b.cover[4] == 0, "Cover → armour → shields → hull per-hit order wrong.")
	var hits: Array = b.feedback_events.filter(func(e): return e.kind == "damage")
	expect(hits.size() == 3 and hits[0].cover_absorbed == 3 and hits[0].armour_absorbed == 1 and hits[1].shields_absorbed == 2, "Per-hit metrics incorrect.")
	var r := R.rule("passive")
	r.id = "bonus"
	r.modifiers = [{"kind": "attack_damage", "target": "self_card", "amount": 2}]
	card_def(doc, "broadside").rules[1] = r
	b = State.new(1, doc)
	b.enemies[0].armour = 2
	b.play(uid_for(b, "broadside"), [], -1, -1, 0)
	expect(b.monster_hull == 62, "Generic bonus applied to every hit instead of first hit.")
	card_def(doc, "broadside").rules[1].modifiers[0].kind = "per_hit_damage"
	b = State.new(1, doc)
	b.enemies[0].armour = 2
	b.play(uid_for(b, "broadside"), [], -1, -1, 0)
	expect(b.monster_hull == 58, "Explicit per-hit bonus did not apply to every hit.")
	doc = neutral(true)
	card_def(doc, "broadside").rules[0].effects = [attack(10, 3)]
	b = State.new(1, doc)
	b.enemies[0].hull = 3
	b.play(uid_for(b, "broadside"), [], -1, -1, 0, {"enemy": -1})
	expect(b.enemies[0].hull == 0 and b.enemies[1].hull == 20 and b.enemies[2].hull == 12, "Volley retargeted after target defeat.")
	expect(b.feedback_events.filter(func(e): return e.kind == "damage").size() == 1, "Dead target took remaining hits.")
	doc = neutral()
	card_def(doc, "broadside").rules[0].effects = [attack(3, 1, "Short")]
	b = State.new(1, doc)
	b.formation = [0, -1, 2, 1]
	expect(b.play(uid_for(b, "broadside"), [], -1, -1, 0) != "", "Short attack originated from rear.")
	b = State.new(1, doc)
	b.enemy_position = 3
	expect(b.play(uid_for(b, "broadside"), [], -1, -1, 0) != "", "Short attack targeted rear.")
	card_def(doc, "broadside").rules[0].effects.insert(0, {"kind": "move", "target": "owner", "destination": "chosen_slot", "guard": 0})
	b = State.new(1, doc)
	b.formation = [0, -1, 2, 1]
	expect(b.play(uid_for(b, "broadside"), [], 1, -1, 0) == "" and b.monster_hull == 67, "Move-before-attack did not validate new position.")

func _persistence_and_mana() -> void:
	var b = State.new(1, neutral())
	all_in_hand(b)
	for point in 9: expect(b.play(b.hand[0], [], -1, -1, point) == "", "Circle placement failed.")
	expect(b.expanded and conserved(b), "Expansion or conservation failed.")
	var retained: int = b.circle[8]
	b.persistence[retained] = 1
	b.cover[0] = 4
	b.ships[0].guard = 3
	b.end_phase()
	expect(b.phase == "refresh" and b.mana == 1 and b.round_number == 2, "Retention mana or turn transition wrong.")
	expect(b.circle[8] == retained and b.persistence[retained] == 0 and b.expanded, "Last persistence token did not buy an extra round/retain expansion.")
	expect(b.cover[0] == 0 and b.ships[0].guard == 0 and conserved(b), "Temporary defences did not expire.")
	b.refresh([])
	b.end_phase()
	expect(b.play_order.is_empty() and not b.expanded and not b.persistence.has(retained), "Zero-token card did not leave at following cleanup.")
	b.refresh([])
	b.hand = b.hand.slice(0, 1)
	b.mana = 1
	b.end_phase()
	expect(b.mana == 0, "Unused mana carried over or one card earned retention reward.")
	var doc := neutral()
	doc.setup.mana_capacity = 3
	doc.setup.mana_reward = 2
	b = State.new(1, doc)
	b.end_phase()
	expect(b.mana == 2, "Configured mana generation/capacity ignored.")

func _hand_refill() -> void:
	var doc := neutral()
	card_def(doc, "brace").rules[0].effects = [{"kind": "draw", "amount": 3}]
	var b = State.new(1, doc)
	expect(b.play(uid_for(b, "brace"), [], -1, -1, 0) == "" and b.hand.size() == 9, "Draw effect was capped by the refill limit.")
	b.end_phase()
	var retained: Array = b.hand.duplicate()
	expect(b.refresh() == "" and b.hand == retained and conserved(b), "Refill discarded or added cards while already over the limit.")

	b = State.new(1, neutral())
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	b.play(uid_for(b, "broadside"), [], -1, -1, 1)
	b.ships[2].hull = 0
	b.end_phase()
	expect(b.refresh() == "" and b.hand.size() == 6 and conserved(b), "Refill did not draw up to six with two surviving ships.")


func _order_and_chains() -> void:
	var doc := neutral()
	card_def(doc, "brace").rules[1] = rule("echo", "hull_damaged", [attack(1)], "adjacent")
	card_def(doc, "broadside").rules = [rule("play", "on_play", [attack(1)]), rule("echo", "hull_damaged", [attack(1)], "adjacent")]
	var b = State.new(1, doc)
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	b.play(uid_for(b, "broadside"), [], -1, -1, 1)
	expect(b.monster_hull == 67, "Finite reciprocal chain failed.")
	var count: int = b.used_triggers.size()
	b.play(uid_for(b, "broadside"), [], -1, -1, 3)
	expect(b.monster_hull == 63 and b.used_triggers.size() <= count + 1, "Card did not refresh its per-action limit or recursive loop ran.")
	doc = neutral()
	card_def(doc, "broadside").cost = 1
	card_def(doc, "broadside").rules[0].effects = [attack(2)]
	card_def(doc, "brace").rules[1] = rule("discard", "discarded", [attack(3)], "self_card", "any")
	b = State.new(1, doc)
	b.play(uid_for(b, "broadside"), [uid_for(b, "brace")], -1, -1, 0)
	var hits: Array = b.feedback_events.filter(func(e): return e.kind == "damage")
	expect(b.monster_hull == 65 and hits.size() == 2, "Committed mana discard response did not run after card.")
	var kinds: Array = b.feedback_events.map(func(e): return e.kind)
	expect(kinds.find("damage") < kinds.find("cards_discarded") and kinds.find("cards_discarded") < kinds.find("card_triggered"), "Payment discard resolved before main effect.")
	expect(conserved(b), "Discard response broke conservation.")

extends "res://tests/support/v2_test.gd"


func _run() -> void:
	var b = State.new(7, fixture)
	expect(b.init_error == "" and b.formation == [0, 1, -1, 2], "Starting diamond assignment incorrect.")
	var attack := uid_for(b, "broadside")
	var payer := uid_for(b, "brace")
	var initial: Array = b.hand.duplicate()
	expect(b.play(attack, []) != "", "Unpaid card accepted.")
	expect(b.play(attack, [attack]) != "", "Card paid for itself.")
	expect(b.play(attack, [payer, payer]) != "", "Duplicate payment accepted.")
	expect(b.play(attack, [999]) != "", "Missing payment accepted.")
	expect(b.hand == initial and b.monster_hull == 70, "Rejected action mutated state.")
	var rng_before: int = b.rng.state
	var preview: Dictionary = b.preview(attack, [payer], -1, -1, 0)
	expect(preview.ok and "70 → 61" in preview.text, "Known damage preview incorrect.")
	expect(b.rng.state == rng_before and b.hand == initial, "Preview changed RNG or hand.")
	expect(b.play(attack, [payer], -1, -1, 0) == "", "Valid attack rejected.")
	expect(b.monster_hull == 61 and b.circle[0] == attack and not b.discard.has(attack), "Played card did not remain in circle.")
	expect(b.discard == [payer] and conserved(b), "Payment conservation incorrect.")
	expect(b.play(uid_for(b, "escort"), [], 1, -1, 0) != "", "Occupied slot accepted.")

	b = State.new(7, fixture)
	expect(b.play(-1, [uid_for(b, "escort")], 12) == "", "Move into empty adjacent slot failed.")
	expect(b.formation == [-1, 1, 0, 2] and b.ships[0].hull == 25, "Movement or reaction incorrect.")
	expect(b.stance_index != 0 and b.play_order.is_empty(), "Basic action did not advance stance, or occupied circle.")
	b = State.new(7, fixture)
	expect(b.play(uid_for(b, "brace"), [uid_for(b, "tow")], -1, -1, 0) == "", "Brace failed.")
	expect(b.ships[0].guard == 8, "Guard amount incorrect.")
	b.end_phase()
	expect(b.ships[0].hull == 28 and b.ships[0].guard == 0, "Guard block/expiry incorrect.")
	expect(b.phase == "refresh" and b.round_number == 2 and b.circle.all(func(uid): return uid < 0), "Circle cleanup/round incorrect.")
	expect(b.refresh([]) == "" and b.hand.size() == 7 and conserved(b), "Retain/refill incorrect.")
	_test_geometry()
	_test_circle()
	_test_chains()
	_test_death()
	_test_reactions_and_healing()
	done("Diamond combat rules")


func _test_geometry() -> void:
	expect(Geometry.neighbours(0).size() == 2, "Original circle degree incorrect.")
	expect(Geometry.neighbours(0, true).size() == 5 and Geometry.neighbours(0, true).has(1), "Original links lost at expansion.")
	expect(Geometry.neighbours(4, true).size() == 4, "Centre should have four neighbours.")
	for corner in range(5, 9):
		expect(Geometry.neighbours(corner, true).size() == 2, "Corner should have two neighbours.")
	expect(Geometry.unit_neighbours(0) == [1, 2] and not Geometry.unit_neighbours(0).has(3), "Formation links incorrect.")


func _test_circle() -> void:
	var doc := neutral()
	var b = State.new(1, doc)
	all_in_hand(b)
	for slot in 9:
		expect(b.play(b.hand[0], [], -1, -1, slot) == "", "Free circle placement failed.")
		expect(b.expanded == (slot >= 3), "Expansion occurred at wrong occupancy.")
	expect(b.validate(b.hand[0], []) != "", "Full circle allowed another card.")
	expect(conserved(b), "Circle placements lost cards.")
	expect(b.play(-1, [b.hand[0]], 12) == "", "Full circle blocked a basic manoeuvre.")
	b.end_phase()
	expect(not b.expanded and b.play_order.is_empty() and b.used_triggers.is_empty(), "Circle did not contract and reset.")
	expect(conserved(b), "Circle cleanup lost cards.")
	var extra: Array = b.hand.slice(0, maxi(0, b.hand.size() - 7))
	expect(b.refresh(extra) == "" and b.hand.size() == 7, "Refresh failed after large hand.")

	doc = neutral()
	card_def(doc, "salvo").tags = ["Movement"]
	doc.leviathans[0].stances[0].reactions = [{"id": "r", "name": "Test reaction", "trigger": {"kind": "tag", "tag": "Movement"}, "effects": []}]
	b = State.new(1, doc)
	for key in ["advance", "tow", "escort"]:
		b.play(uid_for(b, key), [], -1, -1, b.first_slot())
	b.play(uid_for(b, "salvo"), [], -1, -1, 3)
	var kinds: Array = b.feedback_events.map(func(event): return event.kind)
	expect(kinds.find("circle_expanded") >= 0 and kinds.find("circle_expanded") < kinds.find("reaction_triggered"), "Expansion must precede enemy reaction.")
	expect(kinds.count("reaction_triggered") == 1 and kinds.count("stance_changed") == 1, "Single stance chained to the same action.")


func _test_chains() -> void:
	var doc := neutral()
	var host := card_def(doc, "advance")
	var echo := card_def(doc, "tow")
	host.triggers = [trigger("echo", "damage", [{"kind": "damage_monster", "amount": 1}])]
	echo.effects = [{"kind": "damage_monster", "amount": 1}]
	echo.triggers = [trigger("echo", "damage", [{"kind": "damage_monster", "amount": 1}])]
	var b = State.new(2, doc)
	b.play(uid_for(b, "advance"), [], -1, -1, 0)
	b.play(uid_for(b, "tow"), [], -1, -1, 1)
	expect(b.monster_hull == 67 and b.used_triggers.size() == 2, "Finite chained triggers incorrect.")
	expect(b.history.filter(func(line): return line.begins_with("Card trigger:")).size() == 2, "Trigger fired repeatedly in a cycle.")
	b.play(uid_for(b, "escort"), [], -1, -1, 2)
	expect(b.used_triggers.size() == 2, "A trigger fired again on another card this turn.")

	doc = neutral()
	host = card_def(doc, "advance")
	host.modifiers = [{"stat": "cost", "amount": 2, "tag": "", "condition": {"tag": "", "min": 0}},
		{"stat": "damage", "amount": 2, "tag": "", "condition": {"tag": "", "min": 0}}]
	echo = card_def(doc, "tow")
	echo.cost = 2
	echo.effects = [{"kind": "damage_monster", "amount": 3}]
	echo.on_play = [{"condition": {"tag": "Attack", "min": 1}, "effects": [{"kind": "damage_monster", "amount": 4}]}]
	b = State.new(1, doc)
	b.play(uid_for(b, "advance"), [], -1, -1, 0)
	var uid := uid_for(b, "tow")
	expect(b.effective_cost(uid, 1) == 0 and b.effective_cost(uid, 2) == 2, "Adjacency cost modifier incorrect.")
	var quote: Dictionary = b.preview(uid, [], -1, -1, 1)
	expect(quote.ok and "70 → 59" in quote.text, "Bonus preview incorrect.")
	b.play(uid, [], -1, -1, 1)
	expect(b.monster_hull == 59, "Conditional and ongoing damage bonuses incorrect.")

	doc = neutral()
	host = card_def(doc, "advance")
	host.triggers = [trigger("draw", "played", [{"kind": "draw_discard", "amount": 2, "discard": 2}, {"kind": "damage_monster", "amount": 3}])]
	b = State.new(3, doc)
	b.play(uid_for(b, "advance"), [], -1, -1, 0)
	b.play(uid_for(b, "tow"), [], -1, -1, 1)
	expect(b.phase == "discard" and b.monster_hull == 70, "Triggered discard did not suspend later effects.")
	b.discard_for_relay(b.hand[0])
	expect(b.phase == "discard" and b.monster_hull == 70, "First discard resumed too early.")
	b.discard_for_relay(b.hand[0])
	expect(b.phase == "fleet" and b.monster_hull == 67 and b.used_triggers.size() == 1, "Trigger continuation or usage incorrect.")
	expect(conserved(b), "Paused chain lost card instances.")

	doc = neutral()
	host = card_def(doc, "brace")
	host.triggers = [trigger("copy", "damage", [{"kind": "damage_monster", "amount": 1}])]
	card_def(doc, "broadside").effects = [{"kind": "damage_monster", "amount": 1}]
	b = State.new(4, doc)
	all_in_hand(b)
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	b.play(uid_for(b, "brace"), [], -1, -1, 3)
	b.play(uid_for(b, "escort"), [], -1, -1, 1)
	b.play(uid_for(b, "patch"), [], -1, -1, 2)
	b.play(uid_for(b, "broadside"), [], -1, -1, 4)
	expect(b.monster_hull == 67 and b.used_triggers.size() == 2, "Physical copies did not have independent once-per-turn triggers.")


func _test_death() -> void:
	var doc := neutral()
	doc.leviathans[0].stances[0].effects = [{"kind": "damage_ship", "target": "upper", "amount": 3}]
	var b = State.new(1, doc)
	b.ships[1].hull = 1
	b.end_phase()
	expect(b.formation == [0, -1, -1, 2], "Destroyed unit collapsed the diamond.")
	b.refresh([])
	expect(b.play(uid_for(b, "broadside"), []) != "", "Destroyed owner played a card.")
	expect(b.play(-1, [uid_for(b, "broadside")], 12) == "", "Destroyed owner's card could not pay.")
	doc = fixture.duplicate(true)
	var c := card_def(doc, "strafe")
	c.cost = 0
	doc.setup.opening_hand[0] = "strafe"
	b = State.new(1, doc)
	b.monster_hull = 3
	b.ships[1].hull = 1
	b.play(uid_for(b, "strafe"), [], 0, -1, 0)
	expect(b.outcome == "victory" and b.ships[1].hull == 1, "Lethal action allowed a reaction.")


func _test_reactions_and_healing() -> void:
	var b = State.new(1, fixture)
	b.stance_index = 3
	b.ships[1].hull = 18
	expect(b.play(uid_for(b, "patch"), [uid_for(b, "escort")], 1, -1, 0) == "", "Repair action rejected.")
	expect(b.ships[1].hull == 17, "Capped repair or healing reaction incorrect.")
	b = State.new(1, fixture)
	b.stance_index = 3
	b.play(uid_for(b, "patch"), [uid_for(b, "escort")], 1, -1, 0)
	expect(b.ships[1].hull == 20 and b.stance_index == 3, "Zero healing triggered a reaction.")
	b = State.new(1, fixture)
	b.formation = [1, 0, -1, 2]
	expect(b.play(uid_for(b, "salvo"), [uid_for(b, "brace"), uid_for(b, "broadside")]) != "", "Acting-position restriction ignored.")
	var doc := neutral()
	doc.leviathans[0].stances[0].reactions = [
		{"id": "first", "name": "First", "trigger": {"kind": "tag_position", "tag": "Movement", "positions": ["upper"]}, "effects": [{"kind": "damage_ship", "target": "actor", "amount": 2}]},
		{"id": "second", "name": "Second", "trigger": {"kind": "tag", "tag": "Movement"}, "effects": [{"kind": "damage_ship", "target": "actor", "amount": 9}]}]
	b = State.new(1, doc)
	b.play(-1, [uid_for(b, "escort")], 11)
	expect(b.ships[0].hull == 26, "Final-position trigger or reaction priority incorrect.")
	expect(b.feedback_events.filter(func(event): return event.kind == "reaction_triggered").size() == 1, "Multiple reactions fired for one action.")
	doc = neutral()
	card_def(doc, "advance").modifiers = [{"stat": "cost", "amount": 2, "tag": "", "condition": {"tag": "", "min": 0}}]
	card_def(doc, "tow").cost = 2
	doc.leviathans[0].stances[0].reactions = [{"id": "cost", "name": "Cost", "trigger": {"kind": "cost", "threshold": 2}, "effects": [{"kind": "damage_ship", "target": "actor", "amount": 1}]}]
	b = State.new(1, doc)
	b.play(uid_for(b, "advance"), [], -1, -1, 0)
	b.play(uid_for(b, "tow"), [], -1, -1, 1)
	expect(b.ships[2].hull == 17, "Discount changed printed-cost reaction eligibility.")

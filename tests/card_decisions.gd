extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var doc := neutral()
	card_def(doc, "brace").rules[0].effects = [{"kind": "draw", "amount": 2}, {"kind": "discard", "amount": 1}, attack(3)]
	card_def(doc, "broadside").rules[1] = rule("discard", "discarded", [attack(2)], "self_card", "any")
	var b = State.new(5, doc)
	var uid := uid_for(b, "brace")
	expect(b.play(uid, [], -1, -1, 0) == "" and b.phase == "discard", "Draw/discard did not pause remaining effects.")
	expect(b.monster_hull == 70 and b.hand.size() == 8 and conserved(b), "Effects continued before mandatory discard or cards were lost.")
	var discarded := uid_for(b, "broadside")
	expect(b.discard_for_relay(discarded) == "" and b.phase == "fleet" and b.monster_hull == 65, "Queue did not resume or discard response failed.")
	expect(b.discard.has(discarded) and conserved(b), "Mandatory discard conservation failed.")
	expect(b.discard_for_relay(discarded) != "", "Discard accepted outside decision.")
	doc = neutral()
	card_def(doc, "brace").rules[0].effects = [{"kind": "scry", "look": 4, "take": 1}, attack(2)]
	b = State.new(1, doc)
	var seed: int = b.rng.state
	var original := JSON.stringify(b.board_snapshot())
	var preview: Dictionary = b.preview(uid_for(b, "brace"), [], -1, -1, 0)
	expect(preview.ok and preview.uncertain and b.rng.state == seed and JSON.stringify(b.board_snapshot()) == original, "Scry preview revealed/mutated hidden state.")
	expect(b.play(uid_for(b, "brace"), [], -1, -1, 0) == "" and b.phase == "scry" and b.pending.revealed.size() == 4, "Scry did not reveal the requested deck prefix.")
	expect(b.monster_hull == 70 and conserved(b), "Post-scry effects ran before choices.")
	var shown: Array = b.pending.revealed.duplicate()
	var deck_before: Array = b.deck.duplicate()
	expect(b.choose_scry([], shown, []) != "" and b.phase == "scry", "Incorrect take count accepted.")
	expect(b.choose_scry([shown[0]], [shown[0]], shown.slice(2)) != "", "Duplicate scry assignment accepted.")
	var top: Array = [shown[3], shown[1]]
	expect(b.choose_scry([shown[2]], top, [shown[0]]) == "" and b.monster_hull == 68, "Scry did not resume effects.")
	expect(b.hand.has(shown[2]) and b.deck.slice(0, 2) == top and b.discard.back() == shown[0] and b.deck.slice(2) == deck_before, "Scry hand/top/discard order wrong.")
	expect(conserved(b), "Scry lost/duplicated physical cards.")
	# Top-discard passives never discount their own committed transaction.
	doc = neutral()
	card_def(doc, "broadside").cost = 2
	var r := R.rule("passive", [], "discard_top")
	r.id = "top"
	r.modifiers = [{"kind": "cost", "target": "all_cards", "amount": 1}]
	card_def(doc, "brace").rules[1] = r
	b = State.new(1, doc)
	expect(b.effective_cost(uid_for(b, "broadside"), 0) == 2, "Hand passive applied before discard.")
	b.play(uid_for(b, "broadside"), [uid_for(b, "brace")], -1, -1, 0, {"locked_cost": 2})
	expect(b.effective_cost(uid_for(b, "broadside"), 1) == 1, "New top-discard passive did not affect the next play.")
	var another: int = uid_for(b, "patch")
	b.hand.erase(another)
	b.discard.append(another)
	expect(b.effective_cost(uid_for(b, "broadside"), 1) == 2, "Buried top-discard passive remained active.")
	# Automatic circle cleanup does not emit deliberate discard events.
	doc = neutral()
	card_def(doc, "brace").rules[1] = rule("discard", "discarded", [attack(50)], "self_card", "any")
	b = State.new(1, doc)
	b.play(uid_for(b, "brace"), [], -1, -1, 0)
	b.end_phase()
	expect(b.monster_hull == 70 and b.phase == "refresh", "Circle cleanup fired On Discard.")
	b = State.new(1, doc)
	b.end_phase()
	b.refresh([uid_for(b, "brace")])
	expect(b.monster_hull == 20, "Optional refresh discard failed to fire deliberate discard ability.")
	# Empty deck scry may reshuffle discard, but never invents extra copies.
	b = State.new(1, neutral())
	b.discard = b.deck.duplicate()
	b.deck.clear()
	b.effect_scry({"look": 99, "take": 1}, {"owner": 0, "uid": -1, "event": {}, "ancestry": []})
	expect(b.phase == "scry" and b.pending.revealed.size() == 11 and conserved(b), "Scry reshuffle or available-card clamp failed.")
	done("Card decisions and discard timing")

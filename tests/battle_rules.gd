extends SceneTree
const State = preload("res://scripts/battle_state.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func make_state(keys: Array, reaction: int = 0):
	var battle = State.new(12345)
	var available: Array = []
	for uid in battle.card_keys.size():
		available.append(uid)
	battle.hand.clear()
	for key in keys:
		for uid in available:
			if battle.card_keys[uid] == key:
				battle.hand.append(uid)
				available.erase(uid)
				break
	battle.deck = available
	battle.discard.clear()
	battle.reaction_index = reaction
	battle.reaction_deck = []
	for index in 6:
		if index != reaction:
			battle.reaction_deck.append(index)
	battle.history.clear()
	return battle


func uid_for(battle, key: String) -> int:
	for uid in battle.hand:
		if battle.card_keys[uid] == key:
			return uid
	return -1


func play_key(battle, key: String, pay_keys: Array = [], target: int = -1) -> String:
	var pay: Array = []
	for payer in pay_keys:
		for uid in battle.hand:
			if battle.card_keys[uid] == payer and not pay.has(uid):
				pay.append(uid)
				break
	return battle.play(uid_for(battle, key), pay, target)


func conserved(battle) -> bool:
	var all: Array = battle.hand + battle.deck + battle.discard + battle.held
	var seen: Dictionary = {}
	for uid in all:
		seen[uid] = true
	return all.size() == 18 and seen.size() == 18


func _run() -> void:
	_payment_and_preview()
	_worked_sequence()
	_effects_and_reactions()
	_relay()
	_destruction()
	_rounds()
	print("Battle rules: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _payment_and_preview() -> void:
	var b = make_state(["broadside", "advance", "tow"])
	var action := uid_for(b, "broadside")
	var first := uid_for(b, "advance")
	var second := uid_for(b, "tow")
	var before: Array = b.hand.duplicate()
	expect(b.play(action, [first]) != "", "Insufficient payment was accepted.")
	expect(b.hand == before and b.monster_hull == 70, "Rejected action mutated state.")
	expect(b.play(action, [action]) != "", "Action paid for itself.")
	expect(b.play(action, [first, first]) != "", "Duplicate payment accepted.")
	expect(b.play(action, [999]) != "", "Missing payment accepted.")
	expect(b.play(999, []) != "", "Missing action accepted.")
	var random_before: int = b.rng.state
	var preview: Dictionary = b.preview(action, [first, second])
	expect(preview.ok and "70 → 61" in preview.text, "Damage preview incorrect.")
	expect(b.hand == before and b.rng.state == random_before, "Preview changed real state or RNG.")
	expect(b.play(action, [first, second]) == "", "Valid attack rejected.")
	expect(b.monster_hull == 61 and b.discard.size() == 3 and b.hand.is_empty(), "Payment or effect incorrect.")
	expect(b.reaction_index == 0 and b.ships[1].hull == 20, "Payment Movement tags triggered a reaction.")
	expect(conserved(b), "Card conservation failed after payment.")
	b = make_state(["advance", "advance", "brace"])
	var action_copy: int = b.hand[0]
	var retained_copy: int = b.hand[1]
	expect(b.play(action_copy, [uid_for(b, "brace")], 1) == "", "Overpayment rejected.")
	expect(b.hand.has(retained_copy) and not b.hand.has(action_copy), "Identical card instances confused.")
	expect(b.discard.size() == 2 and b.ships[0].hull == 25, "Overpaid movement resolution incorrect.")
	b = make_state(["strafe", "brace"])
	expect(b.play(uid_for(b, "strafe"), [uid_for(b, "brace")], 0) != "", "Free action accepted payment.")
	expect(play_key(b, "strafe", [], 0) == "" and b.monster_hull == 67, "Free card did not resolve.")


func _worked_sequence() -> void:
	var b = State.new(7)
	b.reaction_deck = [1, 2, 3, 4, 5]
	var move_uid := uid_for(b, "advance")
	var pay_uid := uid_for(b, "tow")
	var preview: Dictionary = b.preview(move_uid, [pay_uid], 1)
	expect(preview.ok and "Buffeting Wings triggers" in preview.text, "Reaction absent from preview.")
	expect(not "Violent Recoil" in preview.text and b.reaction_index == 0, "Preview revealed a hidden replacement.")
	expect(play_key(b, "advance", ["tow"], 1) == "", "Worked movement failed.")
	expect(b.formation == [1, 0, 2] and b.ships[0].hull == 25, "Movement must precede the reaction.")
	expect(b.reaction_index == 1 and b.reaction_discard == [0], "Reaction not replaced exactly once.")
	expect(b.play(-1, [uid_for(b, "escort")], 11) == "", "Basic manoeuvre failed.")
	expect(b.formation == [0, 1, 2] and b.reaction_index == 1, "Nonqualifying action replaced a reaction.")
	expect(play_key(b, "salvo", ["brace", "broadside"]) == "", "Worked salvo failed.")
	expect(b.monster_hull == 52 and b.ships[1].hull == 16, "Salvo or recoil damage incorrect.")
	expect(b.hand.size() == 1 and b.card(b.hand[0]).name == "Emergency Patch", "Worked hand incorrect.")
	expect(conserved(b), "Worked sequence lost cards.")


func _effects_and_reactions() -> void:
	var b = make_state(["brace", "tow"], 5)
	b.reaction_deck = [0, 1, 2, 3, 4]
	expect(play_key(b, "brace", ["tow"]) == "", "Brace failed.")
	expect(b.ships[0].guard == 8 and b.formation == [2, 1, 0], "Guard or Tail Sweep failed.")
	expect(b.reaction_index == 0 and b.ships[0].hull == 28, "Reaction replacement chained.")
	b = make_state(["tow", "escort"])
	expect(play_key(b, "tow", ["escort"], 1) == "", "Tow failed.")
	expect(b.formation == [0, 2, 1], "Tow swapped wrong pair.")
	expect(b.ships[2].hull == 17 and b.ships[2].guard == 0 and b.ships[1].guard == 2, "Tow guard must precede wing damage.")
	b = make_state(["escort", "tow"], 0)
	expect(play_key(b, "escort", ["tow"], 0) != "", "Escort targeted its own ship.")
	expect(play_key(b, "escort", ["tow"], 1) == "" and b.ships[1].guard == 6, "Escort guard failed.")
	b = make_state(["patch", "escort"], 3)
	b.ships[1].hull = 18
	expect(play_key(b, "patch", ["escort"], 1) == "", "Repair failed.")
	expect(b.ships[1].hull == 17 and b.reaction_index != 3, "Capped repair or Aether Scent failed.")
	b = make_state(["patch", "escort"], 3)
	expect(play_key(b, "patch", ["escort"], 1) == "", "Full-hull repair should be legal.")
	expect(b.ships[1].hull == 20 and b.reaction_index == 3, "Zero healing triggered Aether Scent.")
	b = make_state(["broadside", "brace"], 4)
	b.ships[0].guard = 1
	expect(play_key(b, "broadside", ["brace"]) == "", "Static attack failed.")
	expect(b.ships[0].hull == 27 and b.ships[1].hull == 18 and b.ships[2].hull == 16, "Static did not apply individual guard.")
	b = make_state(["strafe"], 2)
	expect(play_key(b, "strafe", [], 0) == "" and b.ships[1].hull == 16, "Lunge must inspect actor's final rank.")
	b = make_state(["salvo", "brace", "tow"])
	b.formation = [1, 0, 2]
	expect(play_key(b, "salvo", ["brace", "tow"]) != "" and b.monster_hull == 70, "Rank restriction ignored.")
	b = make_state(["advance", "brace"])
	expect(play_key(b, "advance", ["brace"], 2) != "", "Nonadjacent movement accepted.")
	b = make_state(["brace", "tow"], 5)
	b.formation = [0]
	b.ships[0].guard = 0
	b.ships[1].hull = 0
	b.ships[2].hull = 0
	expect(play_key(b, "brace", ["tow"]) == "" and b.ships[0].guard == 5, "Lone-ship Tail Sweep incorrect.")


func _relay() -> void:
	var b = make_state(["relay", "escort"])
	var relay := uid_for(b, "relay")
	var relay_discard := uid_for(b, "escort")
	var available: Array = b.deck.duplicate()
	b.discard = available
	b.deck.clear()
	expect(play_key(b, "relay") == "", "Relay failed.")
	expect(b.phase == "discard" and b.hand.size() == 3, "Relay did not draw and request discard.")
	expect(not b.hand.has(relay) and b.held == [relay], "Relay drew its own held action.")
	expect(b.end_phase() != "" and b.play(relay_discard, []) != "", "Pending discard did not block other actions.")
	expect(b.discard_for_relay(999) != "", "Invalid Relay discard accepted.")
	expect(b.discard_for_relay(relay_discard) == "", "Relay discard failed.")
	expect(b.phase == "fleet" and b.hand.size() == 2 and b.discard.has(relay), "Relay did not finish.")
	expect(conserved(b), "Relay reshuffle lost or duplicated cards.")
	b = make_state(["relay"])
	b.deck.clear()
	b.discard.clear()
	expect(play_key(b, "relay") == "" and b.phase == "fleet" and b.hand.is_empty(), "Empty-pile Relay should finish without a discard.")
	expect(b.discard.size() == 1, "Relay re-drew itself from an otherwise empty pool.")


func _destruction() -> void:
	var b = make_state(["strafe", "broadside", "patch"], 0)
	b.ships[1].hull = 2
	expect(play_key(b, "strafe", [], 0) == "", "Destruction action failed.")
	expect(b.formation == [0, 2] and b.ships[1].hull == 0, "Destroyed ship did not leave formation.")
	expect(play_key(b, "broadside", ["patch"]) != "", "Destroyed owner played a card.")
	b.ships[0].hull = 20
	expect(play_key(b, "patch", ["broadside"], 0) == "", "Destroyed owner's card could not pay.")
	b = make_state(["strafe"], 0)
	b.monster_hull = 3
	b.ships[1].hull = 1
	expect(play_key(b, "strafe", [], 0) == "" and b.outcome == "victory", "Lethal hit did not win before reaction.")
	expect(b.ships[1].hull == 1 and b.reaction_index == 0, "Dead monster retaliated.")
	b = make_state(["broadside", "brace"], 4)
	for ship in b.ships:
		ship.hull = 1
	expect(play_key(b, "broadside", ["brace"]) == "" and b.outcome == "defeat", "Simultaneous reaction destruction did not lose.")
	expect(b.formation.is_empty(), "Simultaneous casualties were not all removed.")


func _rounds() -> void:
	var b = State.new(99)
	b.ships[0].guard = 5
	expect(b.end_phase() == "" and b.ships[0].hull == 26, "Intent or guard failed.")
	expect(b.phase == "refresh" and b.ships[0].guard == 0 and b.round_number == 2, "Round transition failed.")
	var retained: int = b.hand[0]
	var dropped: int = b.hand[1]
	expect(b.refresh([dropped, dropped]) != "", "Duplicate refresh discard accepted.")
	expect(b.refresh([dropped]) == "" and b.hand.size() == 7 and b.hand.has(retained), "Retention or refill failed.")
	expect(conserved(b) and b.phase == "fleet", "Refresh broke card conservation.")
	b = State.new(2)
	b.round_number = 4
	b.end_phase()
	expect(b.ships[0].hull == 20, "Round-four escalation incorrect.")
	b = State.new(2)
	b.intent_index = 2
	b.end_phase()
	expect(b.formation == [2, 1, 0] and b.ships[0].hull == 25 and b.ships[2].hull == 15, "Storm Front incorrect.")
	b = State.new(2)
	b.intent_index = 3
	b.end_phase()
	expect(b.formation == [2, 0, 1] and b.ships[2].hull == 12, "Hunting Dive incorrect.")
	b = State.new(2)
	b.intent_index = 1
	b.formation = [0]
	b.ships[1].hull = 0
	b.ships[2].hull = 0
	b.end_phase()
	expect(b.ships[0].hull == 24, "Forked Lightning hit a lone survivor twice.")

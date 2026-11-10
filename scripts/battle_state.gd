extends RefCounted
## Rules and state, independent of the battle view. Card instances use unique integer IDs.

const Setup = preload("res://data/battle_setup.gd")
var ships: Array = []
var formation: Array = [0, 1, 2]
var card_keys: Array = []
var hand: Array = []
var deck: Array = []
var discard: Array = []
var held: Array = []
var monster_hull: int = 70
var reaction_index: int = 0
var reaction_deck: Array = []
var reaction_discard: Array = []
var intent_index: int = 0
var intent_deck: Array = []
var intent_discard: Array = []
var round_number: int = 1
var phase: String = "fleet"
var outcome: String = ""
var pending: Dictionary = {}
var history: Array = []
var rng := RandomNumberGenerator.new()
## Ordered public presentation events from the last successful operation.
var feedback_events: Array = []


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	ships = Setup.SHIPS.duplicate(true)
	for ship in ships:
		ship["max_hull"] = ship.hull
		ship["guard"] = 0
	for key in Setup.CARDS:
		for copy in Setup.COPIES_PER_CARD:
			card_keys.append(key)
			deck.append(card_keys.size() - 1)
	for key in Setup.OPENING_HAND:
		for uid in deck:
			if card_keys[uid] == key:
				hand.append(uid)
				deck.erase(uid)
				break
	_shuffle(deck)
	reaction_deck = [1, 2, 3, 4, 5]
	intent_deck = [1, 2, 3]
	_shuffle(reaction_deck)
	_shuffle(intent_deck)
	history.append("Round 1: fleet phase. Buffeting Wings is active.")


func card(uid: int) -> Dictionary:
	return Setup.CARDS[card_keys[uid]]


func choices(uid: int) -> Array:
	var result: Array = []
	var key: String = "manoeuvre" if uid == -1 else card_keys[uid]
	var owner: int = 0 if uid == -1 else card(uid).owner
	if key in ["patch", "escort"]:
		for ship_id in formation:
			if key == "patch" or ship_id != owner:
				result.append({"value": ship_id, "label": ships[ship_id].name})
	elif key in ["advance", "strafe"]:
		var rank: int = formation.find(owner)
		if rank >= 0:
			for neighbour in [rank - 1, rank + 1]:
				if neighbour >= 0 and neighbour < formation.size():
					var other: int = formation[neighbour]
					result.append({"value": other, "label": "Swap with " + ships[other].name})
	elif key == "tow":
		for rank in maxi(0, formation.size() - 1):
			var first: int = formation[rank]
			var second: int = formation[rank + 1]
			result.append({"value": first, "label": "%s ↔ %s" % [ships[first].name, ships[second].name]})
	elif key == "manoeuvre":
		for rank in maxi(0, formation.size() - 1):
			var first: int = formation[rank]
			var second: int = formation[rank + 1]
			result.append({"value": 10 + first * 3 + second, "label": "%s → swap with %s" % [ships[first].name, ships[second].name]})
			result.append({"value": 10 + second * 3 + first, "label": "%s → swap with %s" % [ships[second].name, ships[first].name]})
	return result


func payment_total(payment: Array) -> int:
	var total := 0
	for uid in payment:
		if hand.has(uid):
			total += int(card(uid).pays)
	return total


func validate(uid: int, payment: Array, target: int = -1) -> String:
	if outcome != "" or phase != "fleet":
		return "Finish the current step before playing another action."
	if uid != -1 and not hand.has(uid):
		return "That card is no longer in hand."
	var cost: int = 1 if uid == -1 else card(uid).cost
	if uid != -1:
		var info := card(uid)
		var rank: int = formation.find(info.owner) + 1
		if rank == 0:
			return "Its ship is destroyed; this card can still pay for other actions."
		if not info.allowed_ranks.has(rank):
			return "%s requires ranks %s." % [info.name, info.ranks]
	var seen: Array = []
	for payer in payment:
		if payer == uid or not hand.has(payer) or seen.has(payer):
			return "Payment must use distinct other cards from your hand."
		seen.append(payer)
	if cost == 0 and not payment.is_empty():
		return "This action is free. Remove the payment cards."
	if payment_total(payment) < cost:
		return "Choose payment: %d / %d resources." % [payment_total(payment), cost]
	var options := choices(uid)
	var key: String = "manoeuvre" if uid == -1 else card_keys[uid]
	if key in ["patch", "escort", "advance", "strafe", "tow", "manoeuvre"]:
		var valid_target := false
		for option in options:
			valid_target = valid_target or option.value == target
		if not valid_target:
			return "Choose a valid target or neighbouring pair."
	return ""


func play(uid: int, payment: Array, target: int = -1) -> String:
	var error := validate(uid, payment, target)
	if error != "":
		return error
	feedback_events.clear()
	held = payment.duplicate()
	if uid != -1:
		held.append(uid)
	for spent in held:
		hand.erase(spent)
	var name_text: String = "Basic manoeuvre" if uid == -1 else card(uid).name
	var cost: int = 1 if uid == -1 else card(uid).cost
	history.append("%s — paid %d for cost %d; excess %d lost." % [
		name_text, _held_payment(payment), cost, _held_payment(payment) - cost])
	_record("card_played", {"uid": uid, "payment": payment.duplicate(), "title": name_text})
	var event := _effect(uid, target, false)
	if uid != -1 and card_keys[uid] == "relay" and not hand.is_empty():
		pending = event
		phase = "discard"
		history.append("Signal Relay: choose one card from hand to discard.")
	else:
		_finish(event)
	return ""


func discard_for_relay(uid: int) -> String:
	if phase != "discard" or not hand.has(uid):
		return "Choose a card from hand to finish Signal Relay."
	feedback_events.clear()
	hand.erase(uid)
	discard.append(uid)
	_record("cards_discarded", {"uids": [uid], "reason": "Signal Relay discard"})
	history.append("Signal Relay discarded " + card(uid).name + ".")
	var event := pending.duplicate(true)
	pending.clear()
	phase = "fleet"
	_finish(event)
	return ""


func _held_payment(payment: Array) -> int:
	var total := 0
	for uid in payment:
		total += int(card(uid).pays)
	return total


func _effect(uid: int, target: int, preview_only: bool) -> Dictionary:
	var key: String = "manoeuvre" if uid == -1 else card_keys[uid]
	var actor: int = int((target - 10) / 3) if uid == -1 else card(uid).owner
	var event := {"actor": actor, "damage": 0, "healed": 0, "target": target,
		"cost": 1 if uid == -1 else card(uid).cost,
		"tags": ["Movement"] if uid == -1 else card(uid).tag_ids}
	match key:
		"advance", "strafe", "broadside", "salvo":
			var amount: int = {"advance": 4, "strafe": 3, "broadside": 9, "salvo": 14}[key]
			event.damage = mini(amount, monster_hull)
			monster_hull -= int(event.damage)
			history.append("Stormmaw takes %d damage." % event.damage)
			_record("damage", {"target": -1, "amount": event.damage, "blocked": 0})
			if key in ["advance", "strafe"]:
				_swap(actor, target)
		"brace":
			_gain_guard(actor, 8)
			history.append(ships[actor].name + " gains 8 guard.")
		"escort":
			_gain_guard(target, 6)
			history.append(ships[target].name + " gains 6 guard.")
		"patch":
			event.healed = mini(4, int(ships[target].max_hull) - int(ships[target].hull))
			ships[target].hull += int(event.healed)
			_record("repair", {"target": target, "amount": event.healed})
			history.append("%s restores %d hull." % [ships[target].name, event.healed])
		"manoeuvre":
			_swap(actor, (target - 10) % 3)
		"tow":
			var next: int = formation[formation.find(target) + 1]
			_swap(target, next)
			if key == "tow":
				_gain_guard(target, 2)
				_gain_guard(next, 2)
				history.append("Both swapped ships gain 2 guard.")
		"relay":
			if not preview_only:
				_draw(2)
				history.append("Signal Relay draws up to two cards.")
	return event


func _finish(event: Dictionary, preview_only: bool = false) -> void:
	var spent: Array = held.duplicate()
	discard.append_array(held)
	held.clear()
	if not spent.is_empty():
		_record("cards_discarded", {"uids": spent, "reason": "Action resolved"})
	_cleanup()
	if outcome != "":
		return
	if _triggers(event):
		history.append("Reaction: " + Setup.REACTIONS[reaction_index].name + ".")
		_record("reaction_triggered", {"index": reaction_index, "title": Setup.REACTIONS[reaction_index].name})
		_react(event)
		_cleanup()
		if not preview_only:
			reaction_discard.append(reaction_index)
			if reaction_deck.is_empty():
				reaction_deck = reaction_discard.duplicate()
				reaction_discard.clear()
				_shuffle(reaction_deck)
			reaction_index = reaction_deck.pop_front()
			history.append("New reaction: " + Setup.REACTIONS[reaction_index].name + ".")
			_record("reaction_revealed", {"index": reaction_index, "title": Setup.REACTIONS[reaction_index].name})


func _triggers(event: Dictionary) -> bool:
	match reaction_index:
		0: return event.tags.has("Movement")
		1: return event.damage >= 8
		2: return event.tags.has("Attack") and formation.find(event.actor) == 0
		3: return event.healed > 0
		4: return event.cost >= 2
		5: return event.tags.has("Guard")
	return false


func _react(event: Dictionary) -> void:
	match reaction_index:
		0: _damage(event.actor, 3)
		1, 2: _damage(event.actor, 4)
		3: _damage(event.target, 3)
		4:
			for ship_id in formation:
				_damage(ship_id, 2)
		5:
			if formation.size() == 1:
				_damage(formation[0], 3)
			else:
				_swap(formation.front(), formation.back())


func _damage(ship_id: int, amount: int) -> void:
	var blocked: int = mini(ships[ship_id].guard, amount)
	ships[ship_id].guard -= blocked
	var lost: int = mini(ships[ship_id].hull, amount - blocked)
	ships[ship_id].hull -= lost
	history.append("%s: %d hull damage, %d blocked." % [ships[ship_id].name, lost, blocked])
	_record("damage", {"target": ship_id, "amount": lost, "blocked": blocked})


func _swap(first: int, second: int) -> void:
	var a: int = formation.find(first)
	var b: int = formation.find(second)
	formation[a] = second
	formation[b] = first
	history.append("%s swaps with %s." % [ships[first].name, ships[second].name])
	_record("movement", {"first": first, "second": second})


func _cleanup() -> void:
	for ship_id in formation.duplicate():
		if ships[ship_id].hull <= 0:
			formation.erase(ship_id)
			history.append(ships[ship_id].name + " is destroyed.")
			_record("destroyed", {"target": ship_id, "title": ships[ship_id].name})
	if formation.is_empty():
		outcome = "defeat"
	elif monster_hull <= 0:
		outcome = "victory"
	if outcome != "":
		phase = "finished"


func end_phase() -> String:
	if phase != "fleet" or outcome != "":
		return "Finish the current action first."
	feedback_events.clear()
	history.append("Enemy intent: " + Setup.INTENTS[intent_index].name + ".")
	_record("intent_triggered", {"index": intent_index, "title": Setup.INTENTS[intent_index].name})
	var extra: int = maxi(0, round_number - 3)
	match intent_index:
		0:
			_damage(formation.front(), 7 + extra)
		1:
			var targets: Array = [formation.front()]
			if formation.size() > 1:
				targets.append(formation.back())
			for ship_id in targets:
				_damage(ship_id, 4 + extra)
		2:
			for ship_id in formation:
				_damage(ship_id, 3 + extra)
			_cleanup()
			if formation.size() >= 2:
				_swap(formation.front(), formation.back())
		3:
			var target: int = formation.back()
			_damage(target, 6 + extra)
			_cleanup()
			if formation.has(target):
				formation.erase(target)
				formation.push_front(target)
				_record("movement", {"first": target})
	_cleanup()
	for ship_id in ships.size():
		var expired: int = ships[ship_id].guard
		ships[ship_id].guard = 0
		if expired > 0:
			_record("guard", {"target": ship_id, "amount": -expired, "reason": "Guard expired"})
	if outcome == "":
		round_number += 1
		phase = "refresh"
		history.append("Choose optional discards, then refill to seven.")
	return ""


func refresh(optional_discards: Array) -> String:
	if phase != "refresh":
		return "The hand can only refresh between rounds."
	var seen: Array = []
	for uid in optional_discards:
		if not hand.has(uid) or seen.has(uid):
			return "Choose distinct cards from hand to discard."
		seen.append(uid)
	feedback_events.clear()
	for uid in optional_discards:
		hand.erase(uid)
		discard.append(uid)
	if not optional_discards.is_empty():
		_record("cards_discarded", {"uids": optional_discards.duplicate(), "reason": "Refresh discard"})
	_draw(maxi(0, 7 - hand.size()))
	intent_discard.append(intent_index)
	if intent_deck.is_empty():
		intent_deck = intent_discard.duplicate()
		intent_discard.clear()
		_shuffle(intent_deck)
	intent_index = intent_deck.pop_front()
	phase = "fleet"
	history.append("Round %d: fleet phase." % round_number)
	return ""


func _draw(amount: int) -> void:
	var drawn: Array = []
	for index in amount:
		if deck.is_empty() and not discard.is_empty():
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck)
		if deck.is_empty():
			break
		var uid: int = deck.pop_front()
		hand.append(uid)
		drawn.append(uid)
	if not drawn.is_empty():
		_record("cards_drawn", {"uids": drawn})


func _shuffle(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var value: Variant = items[index]
		items[index] = items[other]
		items[other] = value


func preview(uid: int, payment: Array, target: int = -1) -> Dictionary:
	var error := validate(uid, payment, target)
	if error != "":
		return {"ok": false, "text": error}
	# Simulate only public effects. Never draw cards, reveal replacements, or consume real RNG.
	var simulation = get_script().new(0)
	simulation.ships = ships.duplicate(true)
	simulation.formation = formation.duplicate()
	simulation.card_keys = card_keys.duplicate()
	simulation.monster_hull = monster_hull
	simulation.reaction_index = reaction_index
	simulation.history.clear()
	var event: Dictionary = simulation._effect(uid, target, true)
	var triggers: bool = simulation._triggers(event) and simulation.monster_hull > 0
	simulation._finish(event, true)
	var lines: Array = []
	var action_name: String = "Basic manoeuvre" if uid == -1 else card(uid).name
	var cost: int = 1 if uid == -1 else card(uid).cost
	lines.append("%s — pay %d / %d; excess %d lost." % [action_name, payment_total(payment), cost, payment_total(payment) - cost])
	lines.append("Stormmaw %d → %d hull." % [monster_hull, simulation.monster_hull])
	var order_names: Array = []
	for ship_id in simulation.formation:
		order_names.append(simulation.ships[ship_id].name)
	lines.append("Formation: " + " → ".join(order_names) + ".")
	for ship_id in ships.size():
		var before: Dictionary = ships[ship_id]
		var after: Dictionary = simulation.ships[ship_id]
		if before.hull != after.hull or before.guard != after.guard:
			lines.append("%s: hull %d → %d, guard %d → %d." % [
				before.name, before.hull, after.hull, before.guard, after.guard])
	if simulation.outcome != "":
		lines.append(simulation.outcome.to_upper() + ".")
	elif triggers:
		lines.append(Setup.REACTIONS[reaction_index].name + " triggers; replacement is unknown.")
	else:
		lines.append("Current reaction does not trigger.")
	if uid != -1 and card_keys[uid] == "relay":
		lines.append("Draw up to 2 unknown cards, then choose 1 discard. Draws can reshuffle the discard pile.")
	return {"ok": true, "text": "  ".join(lines)}



func board_snapshot() -> Dictionary:
	return {"ships": ships.duplicate(true), "formation": formation.duplicate(),
		"monster_hull": monster_hull, "reaction_index": reaction_index,
		"hand_size": hand.size(), "deck_size": deck.size(), "discard_size": discard.size()}


func _record(kind: String, details: Dictionary = {}) -> void:
	var entry := details.duplicate(true)
	entry["kind"] = kind
	entry["board"] = board_snapshot()
	feedback_events.append(entry)


func _gain_guard(ship_id: int, amount: int) -> void:
	ships[ship_id].guard += amount
	_record("guard", {"target": ship_id, "amount": amount, "reason": "Guard gained"})

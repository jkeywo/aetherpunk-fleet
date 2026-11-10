extends RefCounted
## Detached content-driven combat state. No card or leviathan identity controls rules.

const Catalog = preload("res://scripts/content_catalog.gd")
var document: Dictionary = {}
var definitions: Dictionary = {}
var init_error: String = ""
var ships: Array = []
var formation: Array = [0, 1, 2]
var card_keys: Array = []
var hand: Array = []
var deck: Array = []
var discard: Array = []
var held: Array = []
var monster_hull: int = 0
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
var feedback_events: Array = []
var rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1, content: Dictionary = {}) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	document = content.duplicate(true)
	if document.is_empty():
		var loaded := Catalog.read_document("res://data/content.json")
		if not loaded.ok:
			init_error = loaded.error
			phase = "invalid"
			return
		document = loaded.document
	var errors := Catalog.validate(document)
	if not errors.is_empty():
		init_error = "\n".join(errors)
		phase = "invalid"
		return
	definitions = Catalog.compile(document)
	ships = definitions.ships.duplicate(true)
	for ship in ships:
		ship["max_hull"] = int(ship.hull)
		ship.hull = int(ship.hull)
		ship["guard"] = 0
		for slot in ship.loadout:
			for copy in int(slot.count):
				card_keys.append(slot.card)
				deck.append(card_keys.size() - 1)
	monster_hull = definitions.monster.hull
	if definitions.fixed_hand:
		for key in definitions.opening_hand:
			for uid in deck:
				if card_keys[uid] == key:
					hand.append(uid)
					deck.erase(uid)
					break
	_shuffle(deck)
	if not definitions.fixed_hand:
		_draw(7)
		feedback_events.clear()
	reaction_index = definitions.starting_reaction
	intent_index = definitions.starting_intent
	for index in definitions.reactions.size():
		if index != reaction_index:
			reaction_deck.append(index)
	for index in definitions.intents.size():
		if index != intent_index:
			intent_deck.append(index)
	_shuffle(reaction_deck)
	_shuffle(intent_deck)
	history.append("Round 1: fleet phase. %s is active." % definitions.reactions[reaction_index].name)


func card(uid: int) -> Dictionary:
	return definitions.cards[card_keys[uid]]


func choice_flags(uid: int) -> Dictionary:
	var flags := {"ally": false, "movement": false, "adjacent": false, "pair": false, "other_only": false}
	if uid == -1:
		flags.movement = true
		return flags
	for effect in card(uid).effects:
		if effect.kind == "repair" or (effect.kind == "guard" and effect.target == "ally"):
			flags.ally = true
		if effect.kind == "guard" and effect.get("exclude_actor", false) and effect.target == "ally":
			flags.other_only = true
		if effect.kind == "swap_adjacent":
			flags.adjacent = true
			flags.movement = true
		if effect.kind == "swap_pair_guard":
			flags.pair = true
			flags.movement = true
	return flags


func choices(uid: int, group: String = "primary") -> Array:
	var flags := choice_flags(uid)
	var result: Array = []
	var owner: int = 0 if uid == -1 else card(uid).owner
	if group == "primary" and flags.ally:
		for ship_id in formation:
			if not flags.other_only or ship_id != owner:
				result.append({"value": ship_id, "label": ships[ship_id].name})
		return result
	if group == "movement" and not (flags.ally and flags.movement):
		return []
	if not flags.movement:
		return []
	if uid == -1:
		for rank in maxi(0, formation.size() - 1):
			var a: int = formation[rank]
			var b: int = formation[rank + 1]
			result.append({"value": 10 + a * 3 + b, "label": "%s → swap with %s" % [ships[a].name, ships[b].name]})
			result.append({"value": 10 + b * 3 + a, "label": "%s → swap with %s" % [ships[b].name, ships[a].name]})
	elif flags.adjacent:
		var rank: int = formation.find(owner)
		if rank >= 0:
			for neighbour in [rank - 1, rank + 1]:
				if neighbour >= 0 and neighbour < formation.size():
					var other: int = formation[neighbour]
					result.append({"value": other, "label": "Swap with " + ships[other].name})
	else:
		for rank in maxi(0, formation.size() - 1):
			var a: int = formation[rank]
			var b: int = formation[rank + 1]
			result.append({"value": a, "label": "%s ↔ %s" % [ships[a].name, ships[b].name]})
	return result


func _choice_exists(options: Array, value: int) -> bool:
	for option in options:
		if option.value == value:
			return true
	return false


func _context(uid: int, target: int, movement: int) -> Dictionary:
	var flags := choice_flags(uid)
	var actor: int = int((target - 10) / 3) if uid == -1 else card(uid).owner
	var move: int = movement if flags.ally else target
	var pair: Array = []
	if uid == -1:
		pair = [actor, (target - 10) % 3]
	elif flags.adjacent:
		pair = [actor, move]
	elif flags.pair and formation.has(move):
		var rank: int = formation.find(move)
		if rank + 1 < formation.size():
			pair = [move, formation[rank + 1]]
	var effects: Array = [{"kind": "swap_adjacent"}] if uid == -1 else card(uid).effects.duplicate(true)
	return {"actor": actor, "target": target if flags.ally else -1, "pair": pair, "damage": 0, "healed": 0,
		"cost": 1 if uid == -1 else int(card(uid).cost),
		"tags": ["Movement"] if uid == -1 else card(uid).tag_ids.duplicate(),
		"effects": effects, "next_step": 0, "discard_remaining": 0,
		"title": "Basic manoeuvre" if uid == -1 else card(uid).name}


func validate(uid: int, payment: Array, target: int = -1, movement: int = -1) -> String:
	if outcome != "" or phase != "fleet":
		return "Finish the current step before playing another action."
	if uid != -1 and not hand.has(uid):
		return "That card is no longer in hand."
	var cost: int = 1 if uid == -1 else int(card(uid).cost)
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
	var flags := choice_flags(uid)
	if (flags.ally or flags.movement) and not _choice_exists(choices(uid), target):
		return "Choose a valid ship or neighbouring pair."
	if flags.ally and flags.movement and not _choice_exists(choices(uid, "movement"), movement):
		return "Choose a valid movement."
	# Validate against the formation produced by every preceding movement effect.
	var context := _context(uid, target, movement)
	var order: Array = formation.duplicate()
	for effect in context.effects:
		if effect.kind in ["swap_adjacent", "swap_pair_guard"]:
			if context.pair.size() != 2:
				return "Choose a neighbouring pair."
			var a: int = order.find(context.pair[0])
			var b: int = order.find(context.pair[1])
			if a < 0 or b < 0 or absi(a - b) != 1:
				return "Movement requires ships that are adjacent at that step."
			order[a] = context.pair[1]
			order[b] = context.pair[0]
	return ""


func play(uid: int, payment: Array, target: int = -1, movement: int = -1) -> String:
	var error := validate(uid, payment, target, movement)
	if error != "":
		return error
	feedback_events.clear()
	held = payment.duplicate()
	if uid != -1:
		held.append(uid)
	for spent in held:
		hand.erase(spent)
	var context := _context(uid, target, movement)
	history.append("%s — paid %d for cost %d; excess %d lost." % [
		context.title, _held_payment(payment), context.cost, _held_payment(payment) - int(context.cost)])
	_record("card_played", {"uid": uid, "payment": payment.duplicate(), "title": context.title})
	_run_action(context)
	return ""


func _run_action(context: Dictionary, preview_only: bool = false) -> void:
	while context.next_step < context.effects.size():
		var effect: Dictionary = context.effects[context.next_step]
		context.next_step += 1
		match effect.kind:
			"damage_monster":
				var actual: int = mini(int(effect.amount), monster_hull)
				monster_hull -= actual
				context.damage += actual
				history.append("%s takes %d damage." % [definitions.monster.name, actual])
				_record("damage", {"target": -1, "amount": actual, "blocked": 0})
			"guard":
				_gain_guard(context.actor if effect.target == "actor" else context.target, int(effect.amount))
			"repair":
				var healed: int = mini(int(effect.amount), int(ships[context.target].max_hull) - int(ships[context.target].hull))
				ships[context.target].hull += healed
				context.healed += healed
				_record("repair", {"target": context.target, "amount": healed})
				history.append("%s restores %d hull." % [ships[context.target].name, healed])
			"swap_adjacent", "swap_pair_guard":
				_swap(context.pair[0], context.pair[1])
				if effect.kind == "swap_pair_guard":
					for ship_id in context.pair:
						_gain_guard(ship_id, int(effect.amount))
			"draw_discard":
				if not preview_only:
					_draw(int(effect.amount))
					context.discard_remaining = mini(int(effect.discard), hand.size())
					if context.discard_remaining > 0:
						pending = context
						phase = "discard"
						history.append("%s: choose %d card(s) to discard." % [context.title, context.discard_remaining])
						return
	_finish(context, preview_only)


func discard_for_relay(uid: int) -> String:
	# Retained API name for existing callers; supports any draw/discard effect.
	if phase != "discard" or not hand.has(uid):
		return "Choose a card from hand to finish the action."
	feedback_events.clear()
	hand.erase(uid)
	discard.append(uid)
	_record("cards_discarded", {"uids": [uid], "reason": "Effect discard"})
	history.append("Discarded " + card(uid).name + ".")
	pending.discard_remaining -= 1
	if pending.discard_remaining <= 0:
		var context := pending.duplicate(true)
		pending.clear()
		phase = "fleet"
		_run_action(context)
	return ""


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
		var name_text: String = definitions.reactions[reaction_index].name
		history.append("Reaction: " + name_text + ".")
		_record("reaction_triggered", {"index": reaction_index, "title": name_text})
		_monster_effects(definitions.reactions[reaction_index].effects, event)
		_cleanup()
		if not preview_only:
			reaction_discard.append(reaction_index)
			if reaction_deck.is_empty():
				reaction_deck = reaction_discard.duplicate()
				reaction_discard.clear()
				_shuffle(reaction_deck)
			reaction_index = reaction_deck.pop_front()
			name_text = definitions.reactions[reaction_index].name
			history.append("New reaction: " + name_text + ".")
			_record("reaction_revealed", {"index": reaction_index, "title": name_text})


func _triggers(event: Dictionary) -> bool:
	var trigger: Dictionary = definitions.reactions[reaction_index].trigger_definition
	match trigger.kind:
		"tag": return event.tags.has(trigger.tag)
		"damage": return event.damage >= trigger.threshold
		"tag_rank": return event.tags.has(trigger.tag) and formation.find(event.actor) + 1 == int(trigger.rank)
		"healed": return event.healed >= trigger.threshold
		"cost": return event.cost >= trigger.threshold
	return false


func _monster_effects(effects: Array, context: Dictionary, escalation: int = 0) -> void:
	var rear_target: int = -1
	for effect in effects:
		match effect.kind:
			"damage_ship":
				var targets: Array = []
				match effect.target:
					"actor":
						if formation.has(context.get("actor", -1)):
							targets = [context.actor]
					"repaired":
						if context.get("healed", 0) > 0 and formation.has(context.get("target", -1)):
							targets = [context.target]
					"front": targets = [formation.front()]
					"rear":
						rear_target = formation.back()
						targets = [rear_target]
					"ends":
						targets = [formation.front()]
						if formation.size() > 1:
							targets.append(formation.back())
					"all": targets = formation.duplicate()
				for ship_id in targets:
					_damage(ship_id, int(effect.amount) + escalation)
			"swap_ends":
				if formation.size() > 1:
					_swap(formation.front(), formation.back())
				elif int(effect.amount) > 0:
					_damage(formation.front(), int(effect.amount) + escalation)
			"rear_to_front":
				var target: int = rear_target if rear_target >= 0 else int(formation.back())
				if formation.has(target):
					formation.erase(target)
					formation.push_front(target)
					_record("movement", {"first": target})
		_cleanup()
		if outcome != "":
			break


func end_phase() -> String:
	if phase != "fleet" or outcome != "":
		return "Finish the current action first."
	feedback_events.clear()
	var name_text: String = definitions.intents[intent_index].name
	history.append("Enemy intent: " + name_text + ".")
	_record("intent_triggered", {"index": intent_index, "title": name_text})
	_monster_effects(definitions.intents[intent_index].effects, {}, maxi(0, round_number - 3))
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


func preview(uid: int, payment: Array, target: int = -1, movement: int = -1) -> Dictionary:
	var error := validate(uid, payment, target, movement)
	if error != "":
		return {"ok": false, "text": error}
	var simulation = get_script().new(0, document)
	simulation.ships = ships.duplicate(true)
	simulation.formation = formation.duplicate()
	simulation.card_keys = card_keys.duplicate()
	simulation.monster_hull = monster_hull
	simulation.reaction_index = reaction_index
	simulation.history.clear()
	var context := _context(uid, target, movement)
	var initial_reaction: int = reaction_index
	simulation._run_action(context, true)
	var triggers: bool = simulation.history.any(func(line): return line.begins_with("Reaction: "))
	var lines: Array = []
	var cost: int = context.cost
	lines.append("%s — pay %d / %d; excess %d lost." % [context.title, payment_total(payment), cost, payment_total(payment) - cost])
	lines.append("%s %d → %d hull." % [definitions.monster.name, monster_hull, simulation.monster_hull])
	var order_names: Array = []
	for ship_id in simulation.formation:
		order_names.append(simulation.ships[ship_id].name)
	lines.append("Formation: " + " → ".join(order_names) + ".")
	for ship_id in ships.size():
		var before: Dictionary = ships[ship_id]
		var after: Dictionary = simulation.ships[ship_id]
		if before.hull != after.hull or before.guard != after.guard:
			lines.append("%s: hull %d → %d, guard %d → %d." % [before.name, before.hull, after.hull, before.guard, after.guard])
	if simulation.outcome != "":
		lines.append(simulation.outcome.to_upper() + ".")
	elif triggers:
		lines.append(definitions.reactions[initial_reaction].name + " triggers; replacement is unknown.")
	else:
		lines.append("Current reaction does not trigger.")
	for effect in context.effects:
		if effect.kind == "draw_discard":
			lines.append("Draw up to %d unknown cards, then choose %d discard(s) if able. Draws can reshuffle the discard pile." % [effect.amount, effect.discard])
	return {"ok": true, "text": "  ".join(lines)}


func payment_total(payment: Array) -> int:
	var total := 0
	for uid in payment:
		if hand.has(uid):
			total += int(card(uid).pays)
	return total


func _held_payment(payment: Array) -> int:
	var total := 0
	for uid in payment:
		total += int(card(uid).pays)
	return total


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


func result_summary(reported_outcome: String = "") -> Dictionary:
	var result: String = outcome if reported_outcome.is_empty() else reported_outcome
	if result not in ["victory", "defeat"]:
		return {}
	var fleet: Array = []
	var remaining := 0
	var maximum := 0
	var survivors := 0
	for ship in ships:
		var alive: bool = ship.hull > 0
		remaining += int(ship.hull)
		maximum += int(ship.max_hull)
		if alive:
			survivors += 1
		fleet.append({"name": ship.name, "role": ship.role, "color": ship.color,
			"hull": ship.hull, "max_hull": ship.max_hull, "alive": alive})
	return {"outcome": result, "ships": fleet, "survivors": survivors,
		"remaining_hull": remaining, "starting_hull": maximum,
		"hull_percent": roundi(100.0 * remaining / maxi(1, maximum)),
		"rounds": round_number, "is_test": result != outcome}

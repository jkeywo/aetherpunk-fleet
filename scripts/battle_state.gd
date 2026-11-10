extends RefCounted
## Four persistent unit positions, resident circle cards, finite event chains, and stance decks.
const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
var document: Dictionary = {}
var definitions: Dictionary = {}
var init_error := ""
var ships: Array = []
var formation: Array = [-1, -1, -1, -1]
var enemy_position := 0
var card_keys: Array = []
var hand: Array = []
var deck: Array = []
var discard: Array = []
var held: Array = []
var circle: Array = [-1, -1, -1, -1, -1, -1, -1, -1, -1]
var expanded := false
var play_order: Array = []
var used_triggers: Dictionary = {}
var tasks: Array = []
var root_context: Dictionary = {}
var pending: Dictionary = {}
var monster_hull := 0
var stance_index := 0
var stance_deck: Array = []
var stance_discard: Array = []
var round_number := 1
var phase := "fleet"
var outcome := ""
var history: Array = []
var feedback_events: Array = []
var rng := RandomNumberGenerator.new()
var _preview_only := false
var _preview_available := 0
var _preview_hand := 0


func _init(seed_value: int = -1, content: Dictionary = {}) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	if content.is_empty():
		var read := Catalog.read_document("res://data/content.json")
		if not read.ok:
			init_error = read.error
			phase = "invalid"
			return
		content = read.document
	var errors := Catalog.validate(content)
	if not errors.is_empty():
		init_error = "\n".join(errors)
		phase = "invalid"
		return
	document = Catalog.migrate(content)
	definitions = Catalog.compile(document)
	ships = definitions.ships.duplicate(true)
	for id in ships.size():
		var ship: Dictionary = ships[id]
		ship["max_hull"] = int(ship.hull)
		ship.hull = int(ship.hull)
		ship["guard"] = 0
		ship["recovery"] = 0
		ship["last_position"] = Geometry.POSITIONS.find(definitions.positions[id])
		formation[Geometry.POSITIONS.find(definitions.positions[id])] = id
		for slot in ship.loadout:
			for copy in int(slot.count):
				card_keys.append(slot.card)
				deck.append(card_keys.size() - 1)
	enemy_position = Geometry.POSITIONS.find(definitions.enemy_position)
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
	stance_index = definitions.starting_stance
	for index in definitions.stances.size():
		if index != stance_index:
			stance_deck.append(index)
	_shuffle(stance_deck)
	feedback_events.clear()
	history.append("Round 1. Stance: " + stance().name)


func stance() -> Dictionary:
	return definitions.stances[stance_index]


func alive_ids() -> Array:
	var ids: Array = []
	for id in formation:
		if id >= 0:
			ids.append(id)
	return ids


func card(uid: int) -> Dictionary:
	return definitions.cards[card_keys[uid]]


func first_slot() -> int:
	for slot in (9 if expanded else 4):
		if circle[slot] < 0:
			return slot
	return -1


func adjacent_cards(slot: int, proposed_uid: int = -1, proposed_slot: int = -1) -> Array:
	var result: Array = []
	for adjacent in Geometry.neighbours(slot, expanded):
		var uid: int = circle[adjacent]
		if adjacent == proposed_slot and uid < 0:
			uid = proposed_uid
		if uid >= 0:
			result.append(card(uid))
	return result


func condition_matches(condition: Dictionary, slot: int, proposed_uid: int = -1, proposed_slot: int = -1) -> bool:
	return Geometry.condition_matches(condition, adjacent_cards(slot, proposed_uid, proposed_slot))


func bonus(stat: String, uid: int, slot: int) -> int:
	if uid < 0 or slot < 0:
		return 0
	var total := 0
	for adjacent in Geometry.neighbours(slot, expanded):
		var source: int = circle[adjacent]
		if source < 0:
			continue
		for modifier in card(source).get("modifiers", []):
			if modifier.stat == stat and (modifier.get("tag", "") == "" or card(uid).tag_ids.has(modifier.tag)):
				if condition_matches(modifier.condition, adjacent, uid, slot):
					total += int(modifier.amount)
	return total


func effective_cost(uid: int, slot: int = -1) -> int:
	if uid < 0:
		return 1
	if slot < 0:
		slot = first_slot()
	return maxi(0, int(card(uid).cost) - bonus("cost", uid, slot))


func active_effects(uid: int, slot: int) -> Array:
	if uid < 0:
		return [{"kind": "swap_adjacent"}]
	var effects: Array = card(uid).effects.duplicate(true)
	for rule in card(uid).get("on_play", []):
		if condition_matches(rule.condition, slot):
			effects.append_array(rule.effects.duplicate(true))
	return effects


func choice_flags(uid: int, slot: int = -1) -> Dictionary:
	if slot < 0:
		slot = first_slot()
	var flags := {"ally": false, "movement": uid == -1, "adjacent": uid == -1, "pair": false, "other_only": false}
	for effect in active_effects(uid, slot):
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


func choices(uid: int, group: String = "primary", slot: int = -1) -> Array:
	var flags := choice_flags(uid, slot)
	var result: Array = []
	var owner: int = -1 if uid < 0 else card(uid).owner
	if group == "primary" and flags.ally:
		for id in alive_ids():
			if not flags.other_only or id != owner:
				result.append({"value": id, "label": ships[id].name})
		return result
	if group == "movement" and not (flags.ally and flags.movement):
		return []
	if not flags.movement:
		return []
	if uid < 0:
		for id in alive_ids():
			for point in Geometry.unit_neighbours(formation.find(id)):
				result.append({"value": 10 + id * 4 + point, "label": "%s → %s" % [ships[id].name, Geometry.POSITION_NAMES[point]]})
	elif flags.adjacent:
		var origin: int = formation.find(owner)
		if origin >= 0:
			for point in Geometry.unit_neighbours(origin):
				if not flags.pair or formation[point] >= 0:
					result.append({"value": point, "label": "Move / swap → " + Geometry.POSITION_NAMES[point]})
	else:
		for link in Geometry.UNIT_LINKS:
			if formation[link[0]] >= 0 and formation[link[1]] >= 0:
				result.append({"value": 100 + link[0] * 4 + link[1], "label": "%s ↔ %s" % [ships[formation[link[0]]].name, ships[formation[link[1]]].name]})
	return result


func _choice_exists(options: Array, value: int) -> bool:
	return options.any(func(option): return option.value == value)


func _context(uid: int, target: int, movement: int, slot: int) -> Dictionary:
	var flags := choice_flags(uid, slot)
	var actor: int = int((target - 10) / 4) if uid < 0 else int(card(uid).owner)
	var move: int = movement if flags.ally else target
	var points: Array = []
	if uid < 0:
		points = [formation.find(actor), (target - 10) % 4]
	elif flags.adjacent:
		points = [formation.find(actor), move]
	elif flags.pair:
		points = [int((move - 100) / 4), (move - 100) % 4]
	return {"uid": uid, "slot": slot, "actor": actor, "event_actor": actor, "target": target if flags.ally else -1,
		"points": points, "cost": 1 if uid < 0 else int(card(uid).cost), "damage": 0, "healed": 0,
		"tags": ["Movement"] if uid < 0 else card(uid).tag_ids.duplicate(), "next_step": 0, "discard_remaining": 0,
		"title": "Basic manoeuvre" if uid < 0 else card(uid).name, "effects": active_effects(uid, slot), "announced": true}


func validate(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1) -> String:
	if outcome != "" or phase != "fleet":
		return "Finish the current resolution before playing."
	if uid >= 0 and not hand.has(uid):
		return "That card is no longer in hand."
	if uid >= 0:
		if slot < 0:
			slot = first_slot()
		if slot < 0:
			return "The circle is full. End the phase or use a basic manoeuvre."
		if slot >= (9 if expanded else 4) or circle[slot] >= 0:
			return "Choose an empty unlocked circle slot."
		var point: int = formation.find(card(uid).owner)
		if point < 0:
			return "Its ship is destroyed; the card can still be payment."
		if not card(uid).allowed_positions.has(Geometry.POSITIONS[point]):
			return "Acting ship must occupy: " + card(uid).ranks
	var seen: Array = []
	for payer in payment:
		if payer == uid or not hand.has(payer) or seen.has(payer):
			return "Pay with distinct other cards from hand."
		seen.append(payer)
	var cost := effective_cost(uid, slot)
	if cost == 0 and not payment.is_empty():
		return "This action is free; remove payment cards."
	if payment_total(payment) < cost:
		return "Payment %d / %d. Select other cards to pay." % [payment_total(payment), cost]
	var flags := choice_flags(uid, slot)
	if (flags.ally or flags.movement) and not _choice_exists(choices(uid, "primary", slot), target):
		return "Choose a valid ship or adjacent destination."
	if flags.ally and flags.movement and not _choice_exists(choices(uid, "movement", slot), movement):
		return "Choose a valid movement."
	return ""


func play(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1) -> String:
	if uid >= 0 and slot < 0:
		slot = first_slot()
	var error := validate(uid, payment, target, movement, slot)
	if error != "":
		return error
	var cost := effective_cost(uid, slot)
	var context := _context(uid, target, movement, slot)
	root_context = context.duplicate(true)
	feedback_events.clear()
	held = payment.duplicate()
	for payer in held:
		hand.erase(payer)
	if uid >= 0:
		hand.erase(uid)
		circle[slot] = uid
		play_order.append(uid)
	tasks = [context]
	_preview_available = deck.size() + discard.size()
	_preview_hand = hand.size()
	history.append("%s: paid %d / %d." % [context.title, _held_payment(payment), cost])
	_record("card_played", {"uid": uid, "slot": slot, "payment": payment.duplicate(), "title": context.title})
	if uid >= 0:
		_event("played", uid, context.actor, 1)
	_drain()
	return ""


func _event(kind: String, source: int, actor: int, amount: int) -> void:
	if source < 0 or not circle.has(source):
		return
	var source_slot: int = circle.find(source)
	for host in play_order:
		if host == source or not Geometry.neighbours(source_slot, expanded).has(circle.find(host)):
			continue
		for rule in card(host).get("triggers", []):
			var key := "%d/%s" % [host, rule.id]
			if used_triggers.has(key) or rule.event != kind or amount < int(rule.threshold):
				continue
			if rule.get("tag", "") != "" and not card(source).tag_ids.has(rule.tag):
				continue
			if not condition_matches(rule.condition, circle.find(host)):
				continue
			used_triggers[key] = "queued"
			tasks.append({"uid": host, "slot": circle.find(host), "actor": int(card(host).owner), "event_actor": actor,
				"source_uid": source, "source_event": kind, "source_amount": amount,
				"target": actor, "points": [], "effects": rule.effects.duplicate(true), "next_step": 0, "discard_remaining": 0,
				"title": card(host).name + " / " + rule.get("name", rule.id), "trigger_key": key, "announced": false})


func _drain() -> void:
	while not tasks.is_empty():
		var context: Dictionary = tasks.pop_front()
		if not context.announced:
			context.announced = true
			used_triggers[context.trigger_key] = "fired"
			history.append("Card trigger: " + context.title)
			_record("card_triggered", {"uid": context.uid, "title": context.title,
				"source_uid": context.source_uid, "source_event": context.source_event, "source_amount": context.source_amount})
		while context.next_step < context.effects.size():
			var effect: Dictionary = context.effects[context.next_step]
			context.next_step += 1
			if _apply_effect(effect, context):
				pending = context
				phase = "discard"
				return
	_finish_root()


func _apply_effect(effect: Dictionary, context: Dictionary) -> bool:
	var uid: int = context.uid
	var slot: int = context.slot
	var amount: int = int(effect.get("amount", 0))
	match effect.kind:
		"damage_monster":
			var actual: int = mini(monster_hull, amount + bonus("damage", uid, slot))
			monster_hull -= actual
			root_context.damage += actual
			history.append("%s takes %d damage." % [definitions.monster.name, actual])
			_record("damage", {"target": -1, "amount": actual, "blocked": 0})
			_event("damage", uid, context.actor, actual)
		"guard", "repair":
			var target: int = context.actor
			if effect.get("target") == "event_actor":
				target = context.event_actor
			elif effect.kind == "guard" and effect.target == "ally":
				target = context.target
			elif effect.kind == "repair" and not context.has("trigger_key"):
				target = context.target
			if target < 0 or ships[target].hull <= 0:
				return false
			if effect.kind == "guard":
				amount += bonus("guard", uid, slot)
				_gain_guard(target, amount)
				_event("guard", uid, context.actor, amount)
			else:
				var healed: int = mini(int(ships[target].max_hull) - int(ships[target].hull), amount + bonus("healing", uid, slot))
				ships[target].hull += healed
				root_context.healed += healed
				if healed > 0:
					root_context.target = target
				_record("repair", {"target": target, "amount": healed})
				_event("repair", uid, context.actor, healed)
		"swap_adjacent", "swap_pair_guard":
			var points: Array = context.points
			_swap_points(points[0], points[1])
			_event("movement", uid, context.actor, 1)
			if effect.kind == "swap_pair_guard":
				for point in points:
					if formation[point] >= 0:
						_gain_guard(formation[point], amount + bonus("guard", uid, slot))
						_event("guard", uid, context.actor, amount + bonus("guard", uid, slot))
		"draw_discard":
			if _preview_only:
				var drawn: int = mini(amount, _preview_available)
				_preview_available -= drawn
				_preview_hand += drawn
				_event("draw", uid, context.actor, drawn)
				var dropped: int = mini(int(effect.discard), _preview_hand)
				_preview_hand -= dropped
				_preview_available += dropped
				for index in dropped:
					_event("discard", uid, context.actor, 1)
			else:
				var before: int = hand.size()
				_draw(amount)
				_event("draw", uid, context.actor, hand.size() - before)
				context.discard_remaining = mini(int(effect.discard), hand.size())
				if context.discard_remaining > 0:
					return true
	return false


func discard_for_relay(uid: int) -> String:
	if phase != "discard" or not hand.has(uid):
		return "Choose a hand card to finish the effect."
	feedback_events.clear()
	hand.erase(uid)
	discard.append(uid)
	_record("cards_discarded", {"uids": [uid], "reason": "Effect discard"})
	_event("discard", pending.uid, pending.actor, 1)
	pending.discard_remaining -= 1
	if pending.discard_remaining <= 0:
		var context := pending.duplicate(true)
		pending.clear()
		phase = "fleet"
		tasks.push_front(context)
		_drain()
	return ""


func _finish_root() -> void:
	var spent: Array = held.duplicate()
	discard.append_array(held)
	held.clear()
	if not spent.is_empty():
		_record("cards_discarded", {"uids": spent, "reason": "Payment"})
	if not expanded and circle.slice(0, 4).all(func(uid): return uid >= 0):
		expanded = true
		_record("circle_expanded", {"title": "Magic circle expanded / five new slots"})
	_cleanup()
	if outcome != "":
		return
	for rule in stance().reactions:
		if _reaction_matches(rule.trigger, root_context):
			history.append("Reaction: " + rule.name)
			_record("reaction_triggered", {"title": rule.name})
			_monster_effects(rule.effects, root_context)
			if not _preview_only and outcome == "":
				_advance_stance()
			break


func _reaction_matches(trigger: Dictionary, event: Dictionary) -> bool:
	match trigger.kind:
		"tag": return event.tags.has(trigger.tag)
		"damage": return event.damage >= int(trigger.threshold)
		"healed": return event.healed >= int(trigger.threshold)
		"cost": return event.cost >= int(trigger.threshold)
		"tag_position":
			var point: int = formation.find(event.actor)
			return point >= 0 and event.tags.has(trigger.tag) and trigger.positions.has(Geometry.POSITIONS[point])
	return false


func _advance_stance() -> void:
	stance_discard.append(stance_index)
	if stance_deck.is_empty():
		stance_deck = stance_discard.duplicate()
		stance_discard.clear()
		_shuffle(stance_deck)
	stance_index = stance_deck.pop_front()
	history.append("New stance: " + stance().name)
	_record("stance_changed", {"title": stance().name})


func _target_ids(target: String, context: Dictionary) -> Array:
	var alive := alive_ids()
	if alive.is_empty():
		return []
	match target:
		"actor": return [context.actor] if alive.has(context.get("actor", -1)) else []
		"repaired": return [context.target] if context.get("healed", 0) > 0 and alive.has(context.get("target", -1)) else []
		"front": return [alive.front()]
		"rear": return [alive.back()]
		"upper": return [formation[1]] if formation[1] >= 0 else []
		"lower": return [formation[2]] if formation[2] >= 0 else []
		"sides":
			return [formation[1], formation[2]].filter(func(id): return id >= 0)
		"ends": return [alive.front(), alive.back()] if alive.size() > 1 else [alive.front()]
		"all": return alive
	return []


func _monster_effects(effects: Array, context: Dictionary, escalation: int = 0) -> void:
	var rear_target := -1
	for effect in effects:
		var alive := alive_ids()
		if alive.is_empty():
			break
		match effect.kind:
			"damage_ship":
				var targets := _target_ids(effect.target, context)
				if effect.target == "rear" and not targets.is_empty():
					rear_target = targets[0]
				for id in targets:
					_damage(id, int(effect.amount) + escalation)
			"swap_ends":
				if alive.size() > 1:
					_swap_points(formation.find(alive.front()), formation.find(alive.back()))
				elif int(effect.amount) > 0:
					_damage(alive.front(), int(effect.amount) + escalation)
			"rear_to_front":
				var id: int = rear_target if rear_target >= 0 else int(alive.back())
				if formation.has(id):
					_swap_points(formation.find(id), 0)
		_cleanup()
		if outcome != "":
			break


func _swap_points(a: int, b: int) -> void:
	var id: int = formation[a]
	formation[a] = formation[b]
	formation[b] = id
	_record("movement", {"first": id})


func _cleanup() -> void:
	for point in formation.size():
		var id: int = formation[point]
		if id >= 0 and ships[id].hull <= 0:
			formation[point] = -1
			ships[id].guard = 0
			ships[id].recovery = 0
			ships[id].last_position = point
			history.append(ships[id].name + " destroyed.")
			_record("destroyed", {"target": id, "title": ships[id].name})
	if alive_ids().is_empty():
		outcome = "defeat"
	elif monster_hull <= 0:
		outcome = "victory"
	if outcome != "":
		phase = "finished"


func end_phase() -> String:
	if phase != "fleet" or outcome != "":
		return "Finish the current action first."
	feedback_events.clear()
	_record("intent_triggered", {"title": stance().name})
	_monster_effects(stance().effects, {}, maxi(0, round_number - 3))
	for id in ships.size():
		var expired: int = ships[id].guard
		ships[id].guard = 0
		if expired > 0:
			_record("guard", {"target": id, "amount": -expired, "reason": "Guard expired"})
	if outcome == "":
		_advance_stance()
		var old: Array = play_order.duplicate()
		discard.append_array(old)
		circle.fill(-1)
		play_order.clear()
		used_triggers.clear()
		expanded = false
		if not old.is_empty():
			_record("cards_discarded", {"uids": old, "reason": "Circle cleanup"})
		round_number += 1
		phase = "refresh"
		_record("circle_reset", {"title": "New turn / circle cleared"})
	return ""


func refresh(optional_discards: Array) -> String:
	if phase != "refresh":
		return "Refresh is available between rounds."
	var seen: Array = []
	for uid in optional_discards:
		if not hand.has(uid) or seen.has(uid):
			return "Choose distinct hand cards."
		seen.append(uid)
	feedback_events.clear()
	for uid in optional_discards:
		hand.erase(uid)
		discard.append(uid)
	if not optional_discards.is_empty():
		_record("cards_discarded", {"uids": optional_discards.duplicate(), "reason": "Refresh discard"})
	_draw(maxi(0, 7 - hand.size()))
	phase = "fleet"
	return ""


func preview(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1) -> Dictionary:
	var error := validate(uid, payment, target, movement, slot)
	if error != "":
		return {"ok": false, "text": error, "contributors": contributing_cards(uid, slot),
			"contribution_details": contribution_details(uid, slot)}
	var sim = get_script().new(0, document)
	for key in ["ships", "formation", "card_keys", "hand", "deck", "discard", "held", "circle", "play_order", "used_triggers"]:
		sim.set(key, get(key).duplicate(true))
	sim.monster_hull = monster_hull
	sim.stance_index = stance_index
	sim.expanded = expanded
	sim._preview_only = true
	sim.history.clear()
	sim.play(uid, payment, target, movement, slot)
	var lines: Array = ["Cost %d / paid %d. %s hull %d → %d." % [effective_cost(uid, slot), payment_total(payment), definitions.monster.name, monster_hull, sim.monster_hull]]
	for id in ships.size():
		if ships[id].hull != sim.ships[id].hull or ships[id].guard != sim.ships[id].guard:
			lines.append("%s: hull %d → %d, guard %d → %d." % [ships[id].name, ships[id].hull, sim.ships[id].hull, ships[id].guard, sim.ships[id].guard])
	var triggers: Array = sim.history.filter(func(line): return line.begins_with("Card trigger:"))
	lines.append("%d card trigger(s)." % triggers.size())
	for event in sim.feedback_events:
		if event.kind == "reaction_triggered":
			lines.append(event.title + " triggers; next stance is hidden.")
	if sim.expanded and not expanded:
		lines.append("Unlocks five circle slots after the allied chain.")
	if sim.outcome != "":
		lines.append(sim.outcome.to_upper())
	lines.append("Drawn cards and replacement stances remain unknown.")
	return {"ok": true, "text": " ".join(lines), "contributors": contributing_cards(uid, slot, sim.used_triggers),
		"contribution_details": contribution_details(uid, slot, sim.used_triggers)}


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


func board_snapshot() -> Dictionary:
	return {"ships": ships.duplicate(true), "formation": formation.duplicate(), "basic_actions": definitions.basic_actions.duplicate(), "enemy_position": enemy_position,
		"monster_hull": monster_hull, "stance_index": stance_index, "circle": circle.duplicate(), "expanded": expanded,
		"play_order": play_order.duplicate(), "used_triggers": used_triggers.duplicate(true),
		"hand_size": hand.size(), "deck_size": deck.size(), "discard_size": discard.size()}


func contributing_cards(uid: int, slot: int, simulated_used: Dictionary = {}) -> Array:
	return contribution_details(uid, slot, simulated_used).keys()


func contribution_details(uid: int, slot: int, simulated_used: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if uid < 0 or uid >= card_keys.size():
		return result
	if slot < 0:
		slot = first_slot()
	if slot < 0 or slot >= (9 if expanded else 4) or circle[slot] >= 0:
		return result
	var relevant: Array = ["cost"] if int(card(uid).cost) > 0 else []
	for effect in active_effects(uid, slot):
		var stat: String = {"damage_monster": "damage", "guard": "guard", "swap_pair_guard": "guard", "repair": "healing"}.get(effect.kind, "")
		if stat != "" and not relevant.has(stat):
			relevant.append(stat)
	for adjacent in Geometry.neighbours(slot, expanded):
		var source: int = circle[adjacent]
		if source < 0:
			continue
		var reasons: Array = []
		for modifier in card(source).get("modifiers", []):
			if int(modifier.amount) <= 0 or not relevant.has(modifier.stat):
				continue
			if (modifier.get("tag", "") == "" or card(uid).tag_ids.has(modifier.tag)) and condition_matches(modifier.condition, adjacent, uid, slot):
				reasons.append(("%s%d %s" % ["−" if modifier.stat == "cost" else "+", modifier.amount, modifier.stat]))
		for rule in card(uid).get("on_play", []):
			if int(rule.condition.get("min", 0)) > 0 and condition_matches(rule.condition, slot):
				if rule.condition.get("tag", "") == "" or card(source).tag_ids.has(rule.condition.tag):
					reasons.append("Enables on-play: " + Catalog.effects_text(rule.effects))
		for rule in card(source).get("triggers", []):
			var key := "%d/%s" % [source, rule.id]
			if simulated_used.has(key) and not used_triggers.has(key):
				reasons.append("Will trigger: " + str(rule.get("name", rule.id)))
		if not reasons.is_empty():
			result[source] = reasons
	return result


func validate_basic(uid: int, recipient: int) -> String:
	if phase != "fleet" or outcome != "":
		return "Basic actions are available during the fleet phase."
	if not hand.has(uid) or uid < 0:
		return "Discard a card from your hand for this basic action."
	if recipient < 0 or recipient >= ships.size():
		return "Choose a player ship."
	var actor: int = card(uid).owner
	if actor == recipient:
		if ships[actor].hull > 0 and ships[actor].hull >= ships[actor].max_hull:
			return "This ship is already at full hull."
		if ships[actor].hull <= 0 and not formation.has(-1):
			return "Revival requires an empty formation position."
		return ""
	if ships[actor].hull <= 0 or not formation.has(actor):
		return "A defeated ship can only recover itself."
	if ships[recipient].hull <= 0 or not formation.has(recipient):
		return "Only living ships can swap positions."
	if not Geometry.unit_neighbours(formation.find(actor)).has(formation.find(recipient)):
		return "Swap requires an adjacent player ship."
	return ""


func play_basic(uid: int, recipient: int) -> String:
	var error := validate_basic(uid, recipient)
	if error != "":
		return error
	var actor: int = card(uid).owner
	var repair: bool = actor == recipient
	var title: String = ("Basic Repair / " if repair else "Basic Swap / ") + ships[actor].name
	feedback_events.clear()
	hand.erase(uid)
	held = [uid]
	root_context = {"uid": -1, "actor": actor, "target": recipient, "damage": 0, "healed": 0,
		"tags": ["Repair"] if repair else ["Movement"], "cost": 0, "title": title}
	history.append("%s: discarded %s." % [title, card(uid).name])
	_record("basic_action", {"uid": uid, "target": recipient, "source": actor,
		"action": "repair" if repair else "swap", "title": title})
	if repair:
		var amount: int = int(definitions.basic_actions.repair)
		if ships[actor].hull > 0:
			var healed: int = mini(amount, int(ships[actor].max_hull) - int(ships[actor].hull))
			ships[actor].hull += healed
			root_context.healed = healed
			history.append("%s restores %d hull." % [ships[actor].name, healed])
			_record("repair", {"target": actor, "amount": healed})
		else:
			var threshold: int = int(definitions.basic_actions.revive_threshold)
			var before: int = int(ships[actor].get("recovery", 0))
			ships[actor].recovery = mini(threshold, before + amount)
			history.append("%s recovery %d / %d." % [ships[actor].name, ships[actor].recovery, threshold])
			_record("revive_progress", {"target": actor, "amount": int(ships[actor].recovery) - before,
				"threshold": threshold, "title": ships[actor].name})
			if ships[actor].recovery >= threshold:
				var point: int = int(ships[actor].get("last_position", -1))
				if point < 0 or formation[point] >= 0:
					point = formation.find(-1)
				formation[point] = actor
				ships[actor].hull = mini(threshold, int(ships[actor].max_hull))
				ships[actor].guard = 0
				ships[actor].recovery = 0
				root_context.healed = int(ships[actor].hull)
				history.append("%s revived at %s with %d hull." % [ships[actor].name, Geometry.POSITION_NAMES[point], ships[actor].hull])
				_record("revived", {"target": actor, "amount": ships[actor].hull, "title": ships[actor].name})
	else:
		_swap_points(formation.find(actor), formation.find(recipient))
	_finish_root()
	return ""


func basic_preview(uid: int, recipient: int) -> Dictionary:
	var error := validate_basic(uid, recipient)
	if error != "":
		return {"ok": false, "text": error, "action": ""}
	var actor: int = card(uid).owner
	var title: String
	if actor != recipient:
		title = "Swap %s ↔ %s" % [ships[actor].name, ships[recipient].name]
	elif ships[actor].hull > 0:
		var healed: int = mini(int(definitions.basic_actions.repair), int(ships[actor].max_hull) - int(ships[actor].hull))
		title = "Repair %s: +%d hull (%d → %d)" % [ships[actor].name, healed, ships[actor].hull, ships[actor].hull + healed]
	else:
		var progress: int = int(ships[actor].get("recovery", 0))
		var threshold: int = int(definitions.basic_actions.revive_threshold)
		var next: int = mini(threshold, progress + int(definitions.basic_actions.repair))
		title = "Recover %s: %d → %d / %d" % [ships[actor].name, progress, next, threshold]
		if next >= threshold:
			var point: int = int(ships[actor].get("last_position", -1))
			if point < 0 or formation[point] >= 0:
				point = formation.find(-1)
			title += ". REVIVE with %d hull at %s" % [mini(threshold, int(ships[actor].max_hull)), Geometry.POSITION_NAMES[point]]
	var sim = get_script().new(0, document)
	for key in ["ships", "formation", "card_keys", "hand", "deck", "discard", "held", "circle", "play_order", "used_triggers"]:
		sim.set(key, get(key).duplicate(true))
	sim.monster_hull = monster_hull
	sim.stance_index = stance_index
	sim.expanded = expanded
	sim._preview_only = true
	sim.play_basic(uid, recipient)
	var text: String = title + ". Discard " + card(uid).name + "; no extra payment. Ignores printed cost, effects, and position restrictions."
	for event in sim.feedback_events:
		if event.kind == "reaction_triggered":
			text += " REACTION: " + event.title + "; next stance hidden."
	for id in ships.size():
		if sim.ships[id].hull != ships[id].hull:
			text += " %s final hull: %d → %d." % [ships[id].name, ships[id].hull, sim.ships[id].hull]
	if sim.ships[recipient].hull <= 0:
		text += " %s is defeated (recovery %d / %d)." % [ships[recipient].name, sim.ships[recipient].get("recovery", 0), definitions.basic_actions.revive_threshold]
	if sim.outcome != "":
		text += " " + sim.outcome.to_upper() + "."
	return {"ok": true, "text": text, "action": "Repair / Recover" if actor == recipient else "Swap Ships"}

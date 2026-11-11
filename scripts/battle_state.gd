extends RefCounted
## Deterministic world + bounded FIFO rule executor. All ability mechanics dispatch through Rules.
const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
var document: Dictionary = {}
var definitions: Dictionary = {}
var init_error := ""
var ships: Array = []
var enemies: Array = []
var formation: Array = [-1, -1, -1, -1]
var enemy_formation: Array = [-1, -1, -1, -1]
var cover: Array = [0, 0, 0, 0, 0, 0, 0, 0]
var card_keys: Array = []
var hand: Array = []
var deck: Array = []
var discard: Array = []
var held: Array = []
var circle: Array = [-1, -1, -1, -1, -1, -1, -1, -1, -1]
var play_order: Array = []
var persistence: Dictionary = {}
var expanded := false
var mana := 0
var earned_mana := 0
var enemy_row: Array = []
var stance_cards: Array = []
var stance_deck: Array = []
var stance_discard: Array = []
var stunned: Dictionary = {}
var round_number := 1
var phase := "fleet"
var outcome := ""
var history: Array = []
var feedback_events: Array = []
var tasks: Array = []
var pending: Dictionary = {}
var root_context: Dictionary = {}
var used_triggers: Dictionary = {}
var used_turn: Dictionary = {}
var action_id := 0
var hit_id := 0
var rng := RandomNumberGenerator.new()
var _mode := ""
var _stage := ""
var _reaction_owners: Array = []
var _eligible_row: Array = []
var _activation_row: Array = []
var _spent_intent_stances: Array = []
var _activated: Array = []
var _defaults: Array = []
var _preview_only := false
var _preview_virtual_hand := 0
var _uncertain := false
var _stat_stack: Array = []
var monster_hull: int:
	get: return int(enemies[0].hull) if not enemies.is_empty() else 0
	set(value):
		if not enemies.is_empty(): enemies[0].hull = value
var enemy_position: int:
	get: return position_of(-1)
	set(value):
		var old := enemy_formation.find(0)
		if old >= 0: enemy_formation[old] = -1
		if value in range(4): enemy_formation[value] = 0
var stance_index: int:
	get:
		if enemy_row.is_empty(): return 0
		return int(stance_cards[enemy_row[0]].index)
	set(value):
		if not enemy_row.is_empty(): stance_cards[enemy_row[0]].index = value


const Difficulty = preload("res://scripts/encounter_difficulty.gd")
var campaign_options: Dictionary = {}
var enemy_row_capacity := 3


func _init(seed_value: int = -1, content: Dictionary = {}, options: Dictionary = {}) -> void:
	campaign_options = options.duplicate(true)
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	if content.is_empty():
		var loaded := Catalog.read_document("res://data/content.json")
		if not loaded.ok:
			init_error = loaded.error
			phase = "invalid"
			return
		content = loaded.document
	var errors := Catalog.validate(content)
	if not errors.is_empty():
		init_error = "\n".join(errors)
		phase = "invalid"
		return
	document = Catalog.migrate(content)
	definitions = Catalog.compile(document)
	enemy_row_capacity = Difficulty.visible_enemy_cards(int(definitions.setup.get("encounter_stars", Difficulty.DEFAULT_STARS)))
	for i in definitions.ships.size():
		var ship: Dictionary = definitions.ships[i].duplicate(true)
		ship["mechanic_text"] = "\n".join(ship.resource.rules.map(func(rule): return Rules.rule_text(rule, ship.name)))
		ship["resource_name"] = ship.resource.name
		ship["resource_capacity"] = int(ship.resource.capacity)
		ship["resource"] = 0
		ship["base_hull"] = int(ship.hull)
		ship["max_hull"] = int(ship.hull)
		ship["guard"] = 0
		ship["recovery"] = 0
		ship["last_position"] = Geometry.POSITIONS.find(definitions.positions[i])
		ships.append(ship)
		formation[ship.last_position] = i
	for i in definitions.enemies.size():
		var enemy: Dictionary = definitions.enemies[i].duplicate(true)
		enemy["base_hull"] = int(enemy.hull)
		enemy["max_hull"] = int(enemy.hull)
		enemy["guard"] = 0
		enemy["resource"] = 0
		enemy["resource_capacity"] = 0
		enemy["active_rules"] = []
		enemies.append(enemy)
		enemy_formation[enemy.position] = i
		for entry in enemy.stance_loadout:
			for copy in int(entry.count):
				var uid := stance_cards.size()
				stance_cards.append({"owner": -1 - i, "index": Catalog.index_by_id(enemy.stances, entry.stance)})
				stance_deck.append(uid)
	Geometry.normalize_formation(formation)
	Geometry.normalize_formation(enemy_formation)
	for i in ships.size():
		ships[i].max_hull = stat(i, "max_hull")
		var initial_hulls: Dictionary = campaign_options.get("starting_hull", {})
		ships[i].hull = clampi(int(initial_hulls.get(ships[i].id, ships[i].max_hull)), 1, int(ships[i].max_hull))
		ships[i]["starting_max_hull"] = ships[i].max_hull
	card_keys = definitions.deck_keys.duplicate()
	for uid in card_keys.size(): deck.append(uid)
	if definitions.fixed_hand:
		for id in definitions.opening_hand:
			for uid in deck:
				if card_keys[uid] == id:
					hand.append(uid)
					deck.erase(uid)
					break
	_shuffle(deck)
	if not definitions.fixed_hand: _draw(hand_refill_limit(), {})
	_shuffle(stance_deck)
	_fill_row()
	feedback_events.clear()
	history.append("Round 1. Up to %d visible enemy cards. Inactive enemies use weaker defaults." % enemy_row_capacity)
	root_context = {"owner": -999, "uid": -1, "damage": {}, "metrics": {}, "healed": 0, "printed_cost": 0, "ancestry": []}
	_stage = "initial_start"
	_mode = "start"
	_emit("turn_start", root_context, {"actor": -999, "amount": 1})
	_drain()
	feedback_events.clear()


func unit(id: int) -> Dictionary:
	if id >= 0: return ships[id] if id < ships.size() else {}
	var index := -1 - id
	return enemies[index] if index < enemies.size() else {}


func card(uid: int) -> Dictionary:
	return definitions.cards.get(card_keys[uid], {}) if uid >= 0 and uid < card_keys.size() else {}


func position_of(id: int) -> int:
	return formation.find(id) if id >= 0 else enemy_formation.find(-1 - id)


func alive_ids(enemy: bool = false) -> Array:
	var result: Array = []
	for id in (enemy_formation if enemy else formation):
		if id >= 0 and int(unit(-1 - id if enemy else id).get("hull", 0)) > 0:
			result.append(-1 - id if enemy else id)
	return result


func hand_refill_limit() -> int:
	return 4 + alive_ids().size()


func first_slot() -> int:
	for point in (9 if expanded else 4):
		if circle[point] < 0: return point
	return -1


func stance() -> Dictionary:
	return row_card(enemy_row[0]) if not enemy_row.is_empty() else {"name": "No enemy cards", "reactions": [], "effects": []}


func row_card(uid: int) -> Dictionary:
	if uid < 0 or uid >= stance_cards.size(): return {}
	var physical: Dictionary = stance_cards[uid]
	var owner: Dictionary = unit(physical.owner)
	if int(physical.index) < 0 or int(physical.index) >= owner.get("stances", []).size(): return {}
	var definition: Dictionary = owner.stances[int(physical.index)].duplicate(true)
	definition["uid"] = uid
	definition["owner"] = physical.owner
	definition["owner_name"] = owner.name
	definition["owner_visual"] = _enemy_visual(physical.owner)
	return definition


func _fill_row(previous: Array = []) -> void:
	if _preview_only:
		_uncertain = true
		return
	var initial_size := enemy_row.size()
	while enemy_row.size() < enemy_row_capacity:
		if stance_deck.is_empty():
			stance_deck = stance_discard.filter(func(uid): return unit(stance_cards[uid].owner).hull > 0)
			stance_discard.clear()
			_shuffle(stance_deck)
		if stance_deck.is_empty(): break
		var index := 0
		var replacement_slot := enemy_row.size() - initial_size
		if campaign_options.get("vary_stance_replacements", false) and replacement_slot < previous.size():
			var retired: Dictionary = stance_cards[previous[replacement_slot]]
			var different := stance_deck.find_custom(func(uid):
				var candidate: Dictionary = stance_cards[uid]
				return candidate.index != retired.index or unit(candidate.owner).id != unit(retired.owner).id
			)
			if different >= 0: index = different
		var uid: int = stance_deck.pop_at(index)
		if unit(stance_cards[uid].owner).hull > 0: enemy_row.append(uid)


func _replace_row(uid: int, after_reaction: bool = false) -> void:
	if not enemy_row.has(uid): return
	_eligible_row.erase(uid)
	_activation_row.erase(uid)
	var point := enemy_row.find(uid)
	enemy_row.remove_at(point)
	if unit(stance_cards[uid].owner).hull > 0: stance_discard.append(uid)
	if _mode == "enemy":
		_spent_intent_stances.append(uid)
		return
	# Replacements occupy the vacated column, not the end of the row.
	var remaining := enemy_row.size()
	var replacement := -1
	_fill_row([uid])
	if enemy_row.size() > remaining:
		replacement = enemy_row.pop_back()
		enemy_row.insert(mini(point, enemy_row.size()), replacement)
	for key in stunned.keys():
		if str(key).begins_with(str(uid) + "/"): stunned.erase(key)
	var feedback := {"title": "Enemy row replacement" if not _preview_only else "Replacement remains hidden"}
	if after_reaction: feedback["incoming_uid"] = replacement
	_record("stance_changed", feedback)


func context_neighbours(c: Dictionary) -> Array:
	var slot: int = circle.find(c.get("uid", -1))
	if slot < 0: slot = int(c.get("slot", -1))
	if slot < 0: slot = circle.find(c.get("event", {}).get("uid", -1))
	var result: Array = []
	if slot < 0: return result
	for point in Geometry.neighbours(slot, expanded):
		var uid: int = circle[point]
		if point == c.get("proposed_slot", -2) and uid < 0: uid = int(c.get("proposed_uid", -1))
		if uid >= 0: result.append(card(uid))
	return result


func are_adjacent_cards(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and circle.has(a) and circle.has(b) and Geometry.neighbours(circle.find(a), expanded).has(circle.find(b))


func targets(selector: String, c: Dictionary) -> Array:
	var event: Dictionary = c.get("event", {})
	match selector:
		"owner": return [c.owner] if not unit(c.get("owner", -999)).is_empty() else []
		"event_actor": return [event.actor] if not unit(event.get("actor", -999)).is_empty() else []
		"area_target": return [c.area_target] if not unit(c.get("area_target", -999)).is_empty() else []
		"event_target": return [event.target] if not unit(event.get("target", -999)).is_empty() else []
		"chosen_ally": return [c.ally] if not unit(c.get("ally", -999)).is_empty() else []
		"chosen_pair_first": return [c.pair_first] if c.get("pair_first", -1) >= 0 else []
		"chosen_pair_second": return [c.pair_second] if c.get("pair_second", -1) >= 0 else []
		"fleet_front": return alive_ids().slice(0, 1)
		"fleet_rear": return alive_ids().slice(-1) if not alive_ids().is_empty() else []
		"fleet_ends":
			var living := alive_ids()
			return [living.front(), living.back()] if living.size() > 1 else living
		"fleet_middle": return [formation[1], formation[2]].filter(func(id): return id >= 0)
		"chosen_enemy": return [c.enemy] if not unit(c.get("enemy", -999)).is_empty() else []
		"all_allies": return alive_ids()
		"all_enemies": return alive_ids(true)
		"source_slot":
			var point := position_of(c.get("owner", -999))
			return [point + (4 if int(c.get("owner", 0)) < 0 else 0)] if point >= 0 else []
		"event_slot":
			var point: int = int(event.get("position", -1))
			return [point + (4 if int(event.get("actor", 0)) < 0 else 0)] if point >= 0 else []
		"chosen_slot": return [c.slot_target] if c.get("slot_target", -1) in range(8) else []
		"self_card": return [c.uid] if int(c.get("uid", -1)) >= 0 else []
		"chosen_circle_card": return [c.circle_target] if int(c.get("circle_target", -1)) >= 0 else []
		"adjacent_cards":
			var slot: int = circle.find(c.get("uid", -1))
			if slot < 0: slot = c.get("slot", -1)
			var result: Array = []
			if slot >= 0:
				for point in Geometry.neighbours(slot, expanded):
					if circle[point] >= 0: result.append(circle[point])
					elif point == c.get("proposed_slot", -2): result.append(c.proposed_uid)
			return result
		"all_cards": return card_keys.map(func(_id): return 0) if false else range(card_keys.size())
		"chosen_stance": return [c.stance_target] if enemy_row.has(c.get("stance_target", -1)) else []
		"event_stance": return [event.stance_uid] if enemy_row.has(event.get("stance_uid", -1)) else []
		"chosen_reaction": return [c.reaction_target] if str(c.get("reaction_target", "")) != "" else []
		"event_reaction": return [event.get("reaction_key", "")] if event.has("reaction_key") else []
		"area_reaction":
			for token in enemy_row:
				if int(stance_cards[token].owner) != int(c.get("area_target", -999)): continue
				for reaction in row_card(token).reactions:
					var key := str(token) + "/" + str(reaction.id)
					if not stunned.has(key): return [key]
			return []
	return []


func selected(spec: Dictionary, c: Dictionary, include_disabled_allies: bool = false) -> Array:
	var result: Array = []
	var selector: String = spec.get("target", "owner")
	var candidates := range(ships.size()) if include_disabled_allies and selector == "all_allies" else targets(selector, c)
	for id in candidates:
		var filtered := c.duplicate(true)
		filtered["state"] = self
		filtered["event"] = c.get("event", {}).duplicate(true)
		filtered.event["target"] = id
		if spec.get("target") in ["self_card", "chosen_circle_card", "adjacent_cards"]:
			filtered["uid"] = id
		if spec.get("exclude_owner", "No") == "Yes" and id == c.owner: continue
		if Rules.condition(spec.get("filter", {"kind": "always"}), filtered): result.append(id)
	return result


func _card_zone(rule: Dictionary, uid: int, event: Dictionary) -> bool:
	match rule.get("zone", "circle"):
		"circle": return circle.has(uid)
		"discard_top": return not discard.is_empty() and discard.back() == uid
		"hand": return hand.has(uid)
		"discard": return discard.has(uid)
		"any": return hand.has(uid) or discard.has(uid) or circle.has(uid) or event.get("uid", -1) == uid
	return false


func _sources(event: Dictionary = {}) -> Array:
	var result: Array = []
	var ids: Array = play_order + hand + discard
	if int(event.get("uid", -1)) >= 0 and not ids.has(event.uid): ids.append(event.uid)
	var visited: Array = []
	for uid in ids:
		if visited.has(uid): continue
		visited.append(uid)
		var data := card(uid)
		for rule in data.get("rules", []):
			if _card_zone(rule, uid, event):
				result.append({"key": "%d/%s" % [uid, rule.id], "uid": uid, "owner": int(data.owner), "rule": rule, "slot": circle.find(uid), "title": data.name})
	for i in ships.size():
		if ships[i].hull <= 0: continue
		for index in ships[i].active_rules.size():
			var rule: Dictionary = ships[i].active_rules[index]
			result.append({"key": "ship:%d:%d/%s" % [i, index, rule.id], "uid": -1, "owner": i, "rule": rule, "slot": -1, "title": ships[i].name + " / " + str(rule.get("name", rule.id))})
	return result


func _modifier_sources(query: Dictionary) -> Array:
	var result: Array = []
	for source in _sources():
		if source.rule.get("trigger", {}).get("kind") != "passive": continue
		var c := query.duplicate(true)
		c.merge(source, true)
		c["state"] = self
		if Rules.condition(source.rule.get("conditions", {"kind": "always"}), c):
			result.append(c)
	return result


func _bonus(stat_name: String, recipient: int, query: Dictionary = {}, card_recipient: bool = false) -> int:
	var total := 0
	for source in _modifier_sources(query):
		for modifier in source.rule.get("modifiers", []):
			if modifier.kind != stat_name: continue
			var is_card_target: bool = modifier.get("target", "owner") in ["adjacent_cards", "self_card", "all_cards"]
			if card_recipient != is_card_target and modifier.get("target") != "fleet": continue
			if modifier.get("target", "owner") == "fleet":
				if card_recipient or recipient != -999: continue
			elif not targets(modifier.get("target", "owner"), source).has(recipient): continue
			if card_recipient:
				var recipient_card := card(recipient)
				if modifier.get("card_type", "") != "" and recipient_card.get("type", "") != modifier.card_type: continue
				if modifier.get("trait", "") != "" and not recipient_card.get("traits", []).has(modifier.trait): continue
			total += Rules.number(modifier.get("amount", 0), source)
	return total


func stat(id: int, name_text: String, query: Dictionary = {}) -> int:
	var u := unit(id)
	if u.is_empty(): return 0
	var base: int = int(u.get(name_text, 0))
	if name_text == "weapon_damage": base = int(u.weapon.damage)
	if name_text == "max_hull": base = int(u.get("base_hull", u.get("max_hull", 1)))
	var key := str(id) + "/" + name_text
	if _stat_stack.has(key): return base
	_stat_stack.append(key)
	var total := base + _bonus(name_text, id, query)
	_stat_stack.erase(key)
	return maxi(0, total)


func fleet_stat(name_text: String) -> int:
	var base: int = int(definitions.setup.get(name_text, 0))
	return maxi(0, base + _bonus("mana_generation" if name_text == "mana_reward" else name_text, -999))


func weapon_range(id: int, query: Dictionary = {}) -> String:
	var result: String = unit(id).get("weapon", {}).get("range", "Long")
	for source in _modifier_sources(query):
		for modifier in source.rule.get("modifiers", []):
			if modifier.kind == "weapon_range" and targets(modifier.get("target", "owner"), source).has(id):
				result = modifier.get("range", "Long")
	return result


func effective_cost(uid: int, slot: int = -1) -> int:
	if uid < 0: return 1
	if slot < 0: slot = first_slot()
	var c := {"uid": uid, "owner": int(card(uid).owner), "slot": slot, "proposed_uid": uid, "proposed_slot": slot, "event": {"kind": "on_play", "uid": uid, "actor": int(card(uid).owner), "card": card(uid)}}
	return maxi(0, int(card(uid).cost) - _bonus("cost", uid, c, true))


func _context(uid: int, target: int, movement: int, slot: int, options: Dictionary = {}) -> Dictionary:
	var owner: int = int(card(uid).owner) if uid >= 0 else int((target - 10) / 4)
	var flags := choice_flags(uid, slot, options)
	var slot_target: int = options.get("slot", movement if flags.ally else target)
	if uid < 0: slot_target = (target - 10) % 4
	var result := {"owner": owner, "actor": owner, "uid": uid, "slot": slot, "ally": target if flags.ally else -999,
		"enemy": options.get("enemy", -999), "slot_target": slot_target, "circle_target": options.get("circle", -1), "stance_target": options.get("stance", -1), "reaction_target": options.get("reaction", ""), "boosts": options.get("boosts", []).duplicate(), "event": {}, "ancestry": []}
	if flags.pair:
		var pair_value: int = movement if flags.ally else target
		if pair_value >= 100:
			result["pair_first"] = formation[int((pair_value - 100) / 4)]
			result["pair_second"] = formation[(pair_value - 100) % 4]
	if result.enemy == -999 and alive_ids(true).size() == 1: result.enemy = alive_ids(true)[0]
	return result


func active_effects(uid: int, slot: int = -1, options: Dictionary = {}) -> Array:
	if uid < 0: return [{"kind": "move", "target": "owner", "destination": "chosen_slot", "guard": 0}]
	var c := {"state": self, "owner": int(card(uid).owner), "uid": uid, "slot": slot, "proposed_slot": slot, "proposed_uid": uid,
		"event": {"kind": "on_play", "uid": uid, "actor": int(card(uid).owner), "card": card(uid)}}
	var result: Array = []
	for rule in card(uid).rules:
		if rule.trigger.kind == "on_play" and (Rules.condition(rule.get("conditions", {"kind": "always"}), c) or "position" in JSON.stringify(rule.get("conditions", {}))):
			result.append_array(rule.get("effects", []))
	for source in _sources(c.event):
		if source.uid >= 0 or not source.rule.get("optional", false) or not options.get("boosts", []).has(source.key): continue
		result.append_array(source.rule.effects)
	return result


func choice_flags(uid: int, slot: int = -1, options: Dictionary = {}) -> Dictionary:
	var flags := {"ally": false, "movement": uid < 0, "adjacent": uid < 0, "enemy": false, "circle": false, "stance": false, "reaction": false, "slot": false, "recovery": false, "swap": false, "pair": false, "exclude_owner": false}
	for effect in Rules.effect_tree(active_effects(uid, slot, options)):
		for key in ["target", "first", "second"]:
			match effect.get(key, ""):
				"chosen_ally": flags.ally = true
				"chosen_enemy": flags.enemy = true
				"chosen_circle_card": flags.circle = true
				"chosen_stance": flags.stance = true
				"chosen_reaction": flags.reaction = true
				"chosen_slot": flags.slot = true
		if effect.kind == "move" and effect.get("destination", "") == "chosen_slot":
			flags.movement = true
			flags.adjacent = true
		if effect.kind in ["repair", "recovery"] and effect.get("target", "owner") == "chosen_ally": flags.recovery = true
		if effect.kind == "swap": flags.swap = true
		if effect.get("exclude_owner", "No") == "Yes": flags.exclude_owner = true
		if effect.get("pair_choice", "No") == "Yes": flags.pair = true; flags.movement = true
	if flags.enemy and alive_ids(true).size() == 1: flags.enemy = false
	return flags


func choices(uid: int, group: String = "primary", slot: int = -1, options: Dictionary = {}) -> Array:
	var flags := choice_flags(uid, slot, options)
	var result: Array = []
	var owner: int = int(card(uid).owner) if uid >= 0 else -1
	if group == "enemy" and flags.enemy:
		for id in alive_ids(true): result.append({"value": id, "label": unit(id).name + " / " + Geometry.POSITION_NAMES[position_of(id)]})
	elif group == "primary" and flags.ally:
		for id in (range(ships.size()) if flags.recovery else alive_ids()):
			if flags.exclude_owner and id == owner: continue
			if flags.swap and not flags.pair and (id == owner or not Geometry.unit_neighbours(position_of(owner)).has(position_of(id))): continue
			result.append({"value": id, "label": ships[id].name})
	elif (group == "primary" and flags.movement and not flags.ally) or (group == "movement" and flags.movement and flags.ally):
		if uid < 0:
			for id in alive_ids():
				for point in Geometry.unit_neighbours(position_of(id)):
					result.append({"value": 10 + id * 4 + point, "label": ships[id].name + " → " + Geometry.POSITION_NAMES[point]})
		elif flags.pair:
			for first in 4:
				if formation[first] < 0: continue
				for second in Geometry.unit_neighbours(first):
					if second <= first or formation[second] < 0: continue
					result.append({"value": 100 + first * 4 + second, "label": Geometry.POSITION_NAMES[first] + " ↔ " + Geometry.POSITION_NAMES[second]})
		elif position_of(owner) >= 0:
			for point in Geometry.unit_neighbours(position_of(owner)):
				result.append({"value": point, "label": "Move / swap → " + Geometry.POSITION_NAMES[point]})
	elif group == "slot" and flags.slot and not flags.movement:
		for point in 4: result.append({"value": point, "label": Geometry.POSITION_NAMES[point] + " cover"})
	elif group == "circle" and flags.circle:
		for token in play_order:
			result.append({"value": token, "label": card(token).name})
		if uid >= 0 and not play_order.has(uid): result.append({"value": uid, "label": card(uid).name + " / incoming"})
	elif group == "stance" and flags.stance:
		for token in enemy_row: result.append({"value": token, "label": row_card(token).owner_name + " / " + row_card(token).name})
	elif group == "reaction" and flags.reaction:
		for token in enemy_row:
			for reaction in row_card(token).reactions:
				var key := str(token) + "/" + str(reaction.id)
				if not stunned.has(key): result.append({"value": key, "label": row_card(token).owner_name + " / " + reaction.name})
	return result


func _has_choice(list: Array, value: Variant) -> bool:
	return list.any(func(item): return typeof(item.value) == typeof(value) and item.value == value)


func payment_total(payment: Array) -> int:
	var total := 0
	for uid in payment:
		if hand.has(uid): total += int(card(uid).pays)
	return total


func _path_error(uid: int, c: Dictionary) -> String:
	var points: Array = formation.duplicate()
	var context := c.duplicate(true)
	context["state"] = self
	context["predicted_formation"] = points
	context["event"] = {"kind": "on_play", "uid": uid, "actor": c.owner, "card": card(uid)}
	for source in boost_options(uid, c):
		if not c.boosts.has(source.key): continue
		var error := _effect_path(source.rule.effects, context, points)
		if error != "": return error
	if uid < 0: return _effect_path(active_effects(uid), context, points)
	for rule in card(uid).rules:
		if rule.trigger.kind != "on_play" or not Rules.condition(rule.get("conditions", {"kind": "always"}), context): continue
		var error := _effect_path(rule.effects, context, points)
		if error != "": return error
	return ""


func _effect_path(effects: Array, c: Dictionary, points: Array) -> String:
	var owner: int = c.owner
	for effect in effects:
		var from := -1
		var to := -1
		if effect.kind == "move":
			var actor: int = c.ally if effect.get("target") == "chosen_ally" else owner
			from = points.find(actor)
			to = c.slot_target if effect.get("destination", "chosen_slot") == "chosen_slot" else Geometry.POSITIONS.find(effect.destination)
			if from < 0 or not Geometry.unit_neighbours(from).has(to): return "Choose an adjacent movement destination for each ordered movement."
		elif effect.kind == "swap":
			var first := targets(effect.get("first", "owner"), c)
			var second := targets(effect.get("second", "chosen_ally"), c)
			if first.is_empty() or second.is_empty(): return "Choose both ships to swap."
			from = points.find(first[0])
			to = points.find(second[0])
			if from < 0 or not Geometry.unit_neighbours(from).has(to): return "Those ships are not adjacent after preceding effects."
		elif effect.kind in ["swap_ends", "rear_to_front"]:
			var occupied: Array = []
			for point in points.size():
				if points[point] >= 0: occupied.append(point)
			if occupied.size() > 1:
				from = occupied.back()
				to = occupied.front() if effect.kind == "swap_ends" else 0
		elif effect.kind in ["attack", "beam", "explosion"]:
			var range_text: String = weapon_range(owner, c) if effect.get("range", "weapon") == "weapon" else effect.range
			if range_text == "Short" and (points.find(owner) == 3 or (effect.kind != "beam" and c.enemy != -999 and position_of(c.enemy) == 3)):
				return "Short attacks cannot originate from Rear or target Rear."
		if from >= 0 and to >= 0:
			var other: int = points[to]
			points[to] = points[from]
			points[from] = other
			Geometry.normalize_formation(points)
	return ""


func validate(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1, options: Dictionary = {}) -> String:
	if phase != "fleet" or outcome != "": return "Finish the current resolution first."
	if uid >= 0:
		if not hand.has(uid): return "That card is no longer in hand."
		if slot < 0: slot = first_slot()
		if slot < 0: return "The magic circle is full."
		if slot >= (9 if expanded else 4) or circle[slot] >= 0: return "Choose an empty unlocked circle slot."
		var point := position_of(int(card(uid).owner))
		if point < 0 or unit(card(uid).owner).hull <= 0: return "Its ship is defeated; use its cards for recovery or payment."
		if not card(uid).allowed_positions.has(Geometry.POSITIONS[point]): return "Acting ship must occupy " + card(uid).ranks + "."
	var seen: Array = []
	for payer in payment:
		if payer == uid or not hand.has(payer) or seen.has(payer): return "Pay with distinct other hand cards."
		seen.append(payer)
	var crystals: int = int(options.get("crystals", 0))
	if crystals < 0 or crystals > mana: return "Not enough temporary mana crystals."
	var cost: int = int(options.get("locked_cost", effective_cost(uid, slot)))
	if cost < 0: return "Mana cost cannot be negative."
	if cost == 0 and (not payment.is_empty() or crystals > 0): return "This action is free; remove payment."
	if payment_total(payment) + crystals < cost: return "Payment %d / %d. Click other cards or crystals to pay." % [payment_total(payment) + crystals, cost]
	var flags := choice_flags(uid, slot, options)
	if (flags.ally or flags.movement) and not _has_choice(choices(uid, "primary", slot, options), target): return "Choose a valid allied ship or movement."
	if flags.ally and flags.movement and not _has_choice(choices(uid, "movement", slot, options), movement): return "Choose a valid movement."
	for group in ["enemy", "circle", "stance", "reaction", "slot"]:
		var list := choices(uid, group, slot, options)
		if not list.is_empty() and not _has_choice(list, options.get(group, -999)): return "Choose a valid " + group + " target."
		if flags.get(group, false) and list.is_empty() and group in ["stance", "reaction"]: return "No eligible visible " + group + " target."
	var c := _context(uid, target, movement, slot, options)
	var error := _path_error(uid, c)
	if error != "": return error
	return _validate_boosts(uid, c, options.get("boosts", []))


func _validate_boosts(uid: int, c: Dictionary, selected: Array) -> String:
	var total: Dictionary = {}
	var found: Array = []
	for source in boost_options(uid, c):
		if not selected.has(source.key): continue
		found.append(source.key)
		for cost in source.rule.costs:
			var amount: int = Rules.number(cost.get("amount", 0), source)
			total[source.owner] = int(total.get(source.owner, 0)) + amount
	if found.size() != selected.size(): return "Choose only eligible boosts."
	for owner in total:
		if unit(owner).get("resource", 0) < total[owner]: return "Not enough " + unit(owner).resource_name + " for selected boosts."
	return ""


func hand_count() -> int:
	return hand.size() + _preview_virtual_hand if _preview_only else hand.size()


func boost_options(uid: int, c: Dictionary = {}) -> Array:
	var owner: int = int(card(uid).owner) if uid >= 0 else int(c.get("owner", -1))
	var event := {"kind": "on_play", "uid": uid, "actor": owner, "target": c.get("ally", owner), "card": {"type": c.basic_type, "traits": c.get("basic_traits", [])} if c.has("basic_type") else (card(uid) if uid >= 0 else {"type": "Manoeuvre", "traits": ["Movement"]}), "amount": 1}
	var result: Array = []
	var available := _sources(event)
	if uid >= 0 and not c.has("basic_type"):
		for rule in card(uid).rules:
			var key := "%d/%s" % [uid, rule.id]
			if rule.get("optional", false) and not available.any(func(source): return source.key == key):
				available.append({"key": key, "uid": uid, "owner": owner, "rule": rule, "slot": c.get("slot", -1), "title": card(uid).name})
	for source in available:
		if c.has("basic_type") and source.uid >= 0: continue
		if source.owner != owner or not source.rule.get("optional", false): continue
		if source.rule.get("limit") == "once_per_turn" and used_turn.has(source.key): continue
		var context: Dictionary = c.duplicate(true)
		context.merge(source, true)
		context["state"] = self
		context["event"] = event.duplicate(true)
		var trigger_kind: String = source.rule.trigger.kind
		var possible: bool = trigger_kind == "on_play"
		if trigger_kind == "attack_started": possible = Rules.effect_tree(active_effects(uid, c.get("slot", first_slot()))).any(func(e): return e.kind in ["attack", "beam"])
		if trigger_kind == "moved": possible = uid < 0 or Rules.effect_tree(active_effects(uid, c.get("slot", first_slot()))).any(func(e): return e.kind in ["move", "swap"])
		if trigger_kind == "repaired": possible = c.has("basic_type") or Rules.effect_tree(active_effects(uid, c.get("slot", first_slot()))).any(func(e): return e.kind in ["repair", "recovery"])
		context.event.kind = trigger_kind
		if possible and Rules.matches(source.rule.trigger, context) and Rules.condition(source.rule.get("conditions", {"kind": "always"}), context):
			result.append(context)
	return result


func _start_action(context: Dictionary, mode: String = "player") -> void:
	action_id += 1
	used_triggers.clear()
	root_context = context.duplicate(true)
	root_context["damage"] = {}
	root_context["metrics"] = {}
	root_context["healed"] = 0
	root_context["player_healed"] = 0
	root_context["played_from"] = position_of(context.owner)
	root_context["played_card"] = int(context.get("uid",-1)) >= 0 and not context.get("basic",false)
	root_context["printed_cost"] = int(card(context.uid).cost) if int(context.get("uid", -1)) >= 0 else 0
	_mode = mode
	_stage = "allied"
	tasks.clear()
	pending.clear()
	_eligible_row = enemy_row.duplicate()
	_reaction_owners = alive_ids(true)


func play(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1, options: Dictionary = {}) -> String:
	if uid >= 0 and slot < 0: slot = first_slot()
	var error := validate(uid, payment, target, movement, slot, options)
	if error != "": return error
	var c := _context(uid, target, movement, slot, options)
	feedback_events.clear()
	_start_action(c)
	held = payment.duplicate()
	for payer in held: hand.erase(payer)
	mana -= int(options.get("crystals", 0))
	if int(options.get("crystals", 0)) > 0: _record("mana", {"amount": -int(options.crystals), "title": "Mana crystal spent"})
	if uid >= 0:
		hand.erase(uid)
		circle[slot] = uid
		play_order.append(uid)
	history.append(("Play " + card(uid).name if uid >= 0 else "Basic manoeuvre") + ": payment committed.")
	_record("card_played", {"uid": uid, "slot": slot, "payment": payment.duplicate(), "title": card(uid).name if uid >= 0 else "Basic manoeuvre"})
	_reserve_boosts(uid, c, options.get("boosts", []))
	if uid >= 0:
		_emit("on_play", c, {"uid": uid, "card": card(uid), "amount": 1})
	else:
		_prepend([{"kind": "effect", "spec": {"kind": "move", "target": "owner", "destination": "chosen_slot", "guard": 0}, "ctx": c}])
	_drain()
	return ""


func _reserve_boosts(uid: int, c: Dictionary, selected: Array) -> void:
	for source in boost_options(uid, c):
		if not selected.has(source.key): continue
		source.event = {"kind": source.rule.trigger.kind, "uid": uid, "actor": c.owner, "target": c.get("ally", c.owner), "card": card(uid) if uid >= 0 else {"type": c.get("basic_type", "Support")}, "amount": 1}
		source["ancestry"] = [source.key]
		var paid := true
		for cost in source.rule.get("costs", []):
			if not pay_resource(cost, source): paid = false
		if paid:
			used_triggers[source.key] = "queued"
			if source.rule.get("limit") == "once_per_turn": used_turn[source.key] = true
			tasks.append({"kind": "rule", "ctx": source, "prepaid": true})


func _usage_key(source: Dictionary, event: Dictionary) -> String:
	var limit: String = source.rule.get("limit", "once_per_action")
	return source.key + ("/hit:" + str(event.get("hit_id", hit_id)) if limit == "once_per_hit" else "")


func _emit(kind: String, c: Dictionary, extra: Dictionary = {}) -> void:
	var event := {"kind": kind, "uid": c.get("uid", -1), "actor": c.get("owner", -999), "target": c.get("enemy", c.get("ally", -999)), "amount": 1, "card": card(c.get("uid", -1)), "position": position_of(c.get("owner", -999))}
	event.merge(extra, true)
	var main: Array = []
	var later: Array = []
	for source in _sources(event):
		if source.rule.get("trigger", {}).get("kind") == "passive" or source.rule.get("optional", false): continue
		var ctx := c.duplicate(true)
		ctx.merge(source, true)
		# A triggered rule is a fresh source, outside its cause's area envelope.
		for key in ["attack_style", "area_range", "area_target", "attack_presentation", "origin_marker"]: ctx.erase(key)
		ctx["state"] = self
		ctx["event"] = event.duplicate(true)
		var ancestry: Array = c.get("ancestry", [])
		if ancestry.has(source.key): continue
		var key := _usage_key(source, event)
		var turn_limited: bool = source.rule.get("limit") == "once_per_turn"
		if used_triggers.has(key) or (turn_limited and used_turn.has(source.key)): continue
		if not Rules.matches(source.rule.trigger, ctx): continue
		var own_play: bool = kind == "on_play" and source.uid == event.uid and source.uid >= 0
		if not own_play and not Rules.condition(source.rule.get("conditions", {"kind": "always"}), ctx): continue
		if not _can_pay_costs(source.rule.get("costs", []), ctx): continue
		used_triggers[key] = "queued"
		if turn_limited: used_turn[source.key] = true
		ctx["ancestry"] = ancestry.duplicate()
		ctx.ancestry.append(source.key)
		ctx["usage_key"] = key
		var job := {"kind": "rule", "ctx": ctx, "prepaid": false}
		if own_play: main.append(job)
		else: later.append(job)
	tasks.append_array(main + later)


func _can_pay_costs(costs: Array, c: Dictionary) -> bool:
	var total: Dictionary = {}
	for cost in costs:
		for id in targets(cost.get("target", "owner"), c):
			total[id] = int(total.get(id, 0)) + Rules.number(cost.get("amount", 0), c)
	for id in total:
		if int(unit(id).get("resource", 0)) < total[id]: return false
	return true


func _prepend(jobs: Array) -> void:
	for index in range(jobs.size() - 1, -1, -1): tasks.push_front(jobs[index])


func _effect_jobs(effects: Array, c: Dictionary, present_enemy_effects: bool = false, presented_rule_id: String = "") -> Array:
	var result: Array = []
	for index in effects.size():
		var job := {"kind": "effect", "spec": effects[index], "ctx": c}
		if present_enemy_effects: job["enemy_effect_index"] = index
		if not presented_rule_id.is_empty() and effects.size() > 1:
			job["card_effect_index"] = index
			job["card_rule_id"] = presented_rule_id
		result.append(job)
	return result


func _drain() -> void:
	var budget := 0
	while outcome == "" and phase not in ["discard", "scry"]:
		budget += 1
		if budget > 10000:
			init_error = "Rule resolution exceeded its safety budget. Inspect cyclic content."
			phase = "invalid"
			tasks.clear()
			return
		if tasks.is_empty():
			if not _advance_stage(): break
			continue
		var job: Dictionary = tasks.pop_front()
		var c: Dictionary = job.get("ctx", {})
		c["state"] = self
		match job.kind:
			"rule":
				var rule: Dictionary = c.rule
				var is_main_play: bool = rule.trigger.kind == "on_play" and int(c.get("uid", -1)) >= 0 and c.event.get("uid", -2) == c.uid
				if is_main_play and not job.get("prepaid", false) and not Rules.condition(rule.get("conditions", {"kind": "always"}), c): continue
				if not job.get("prepaid", false):
					if not _can_pay_costs(rule.get("costs", []), c): continue
					for cost in rule.get("costs", []): Rules.descriptor("cost", cost.kind).handler.call(cost, c)
				used_triggers[c.get("usage_key", c.key)] = "fired"
				var triggered_card: bool = c.uid >= 0 and not is_main_play
				if triggered_card:
					history.append("Card trigger: " + c.title + " / " + str(rule.get("name", rule.id)))
					_record("card_triggered", {"uid": c.uid, "source_uid": c.event.get("uid", -1), "source_event": c.event.get("kind", ""), "source_amount": c.event.get("amount", 0), "rule_key":c.key, "rule_id":rule.id, "rule_text":Rules.rule_text(rule,unit(c.owner).name), "title": c.title + " / " + str(rule.get("name", rule.id))})
				elif is_main_play:
					_record("card_rule_started", {"uid": c.uid, "rule_id": rule.id})
				elif c.uid < 0:
					_record("ship_rule", {"target": c.owner, "rule_key":c.key, "rule_text":Rules.rule_text(rule,unit(c.owner).name), "title": c.title})
				var presented: bool = is_main_play or (triggered_card and circle.has(c.uid))
				var effects := _effect_jobs(rule.get("effects", []), c, false, rule.id if presented else "")
				if presented:
					effects.append({"kind": "card_rule_finished", "uid": c.uid, "return_to_circle": triggered_card})
				_prepend(effects)
			"card_rule_finished":
				_record("card_rule_finished", {"uid": job.uid, "return_to_circle": job.return_to_circle})
			"area_visual": _record("area_attack", {"style":job.style, "presentation":job.presentation, "origin_marker":job.origin_marker, "attacker":int(c.owner), "target":job.target, "targets":job.targets})
			"effect":
				if job.has("enemy_effect_index"):
					_record("enemy_effect_started", {"index": job.enemy_effect_index})
				elif job.has("card_effect_index"):
					_record("card_effect_started", {"uid": c.uid, "rule_id": job.card_rule_id, "index": job.card_effect_index})
				elif not c.has("area_target"):
					_focus_effect()
				Rules.execute(job.spec, c)
			"hit": _hit(job, c)
			"reaction_done":
				_record("enemy_effect_finished")
				_replace_row(job.stance_uid, true)
				_emit("reaction_resolved", c, {"category": job.category, "stance_uid": job.stance_uid, "reaction_key": job.reaction_key, "amount": 1})
			"activation_done":
				_replace_row(job.stance_uid)
				_record("enemy_effect_finished", {"stance_uid": job.stance_uid})
			"default_done": _record("enemy_effect_finished")
		_cleanup()
	if outcome != "":
		_finish_terminal_payment()
	# Pending decisions must not retain a strong reference back to this RefCounted state.
	for queued in tasks:
		queued.get("ctx", {}).erase("state")
	if pending.get("context") is Dictionary: pending.context.erase("state")


func _advance_stage() -> bool:
	if _enemies_defeated() and held.is_empty() and _stage != "allied":
		outcome = "victory"
		phase = "finished"
		return false
	match _stage:
		"initial_start":
			_stage = ""
			_mode = ""
			return false
		"allied":
			_stage = "payments"
			var spent: Array = held.duplicate()
			held.clear()
			discard.append_array(spent)
			if not spent.is_empty():
				_record("cards_discarded", {"uids": spent, "reason": "Basic action cost" if root_context.get("basic", false) else "Mana payment"})
				for uid in spent:
					_emit_discard(uid, "basic" if root_context.get("basic", false) else "mana", root_context)
			return true
		"payments":
			if not expanded and circle.slice(0, 4).all(func(uid): return uid >= 0):
				expanded = true
				_record("circle_expanded", {"title": "Magic circle expanded / five new slots"})
			_stage = "reactions"
			return true
		"reactions":
			while not _reaction_owners.is_empty():
				var owner: int = _reaction_owners.pop_front()
				if unit(owner).hull <= 0: continue
				for uid in _eligible_row:
					if not enemy_row.has(uid) or stance_cards[uid].owner != owner: continue
					for reaction in row_card(uid).reactions:
						var key := str(uid) + "/" + str(reaction.id)
						if stunned.has(key): continue
						var event := {"kind": "action_completed", "uid": root_context.get("uid", -1), "actor": root_context.owner, "target": root_context.get("ally", -999), "card": root_context.get("event_card", card(root_context.get("uid", -1))), "played_card": root_context.get("played_card",false), "played_from": root_context.get("played_from",-1), "player_healed": root_context.get("player_healed",0), "hull_damage": int(root_context.damage.get(owner, 0)), "healed": root_context.healed, "printed_cost": root_context.printed_cost, "amount": 1}
						var c := root_context.duplicate(true)
						event.merge(root_context.get("metrics", {}).get(owner, {}), true)
						event.target = owner if root_context.get("metrics", {}).has(owner) else (root_context.get("enemy", -999) if root_context.get("enemy", -999) != -999 else root_context.get("ally", -999))
						c["owner"] = owner
						c["uid"] = -1
						c["event"] = event
						c["state"] = self
						c["reaction_actor"] = event.actor
						c["ally"] = event.actor
						c["ancestry"] = []
						if not Rules.condition(reaction.conditions, c): continue
						history.append(row_card(uid).owner_name + " reaction: " + reaction.name)
						_record("reaction_triggered", {"title": row_card(uid).owner_name + " / " + reaction.name, "stance_uid": uid, "reaction_key": key, "presentation": {"owner_name": row_card(uid).owner_name, "owner_visual": _enemy_visual(owner), "owner": owner, "name": reaction.name, "custom_trigger": reaction.get("custom_trigger",false), "stance_name": row_card(uid).name, "conditions": reaction.conditions, "effects": reaction.effects}})
						tasks.append_array(_effect_jobs(reaction.effects, c, true))
						tasks.append({"kind": "reaction_done", "ctx": c, "stance_uid": uid, "category": reaction.get("category", ""), "reaction_key": key})
						return true
			_stage = ""
			_mode = ""
			return false
		"enemy":
			while not _activation_row.is_empty():
				var uid: int = _activation_row.pop_front()
				if not enemy_row.has(uid): continue
				var row := row_card(uid)
				var owner: int = row.owner
				if unit(owner).hull <= 0: continue
				_next_enemy_action()
				_activated.append(owner)
				_record("intent_triggered", {"title": row.owner_name + " / " + row.name, "stance_uid": uid, "presentation": {"owner_name": row.owner_name, "owner_visual": _enemy_visual(owner), "owner": owner, "name": row.name, "effects": row.effects}})
				var c := _enemy_context(owner)
				tasks.append_array(_effect_jobs(row.effects, c, true))
				tasks.append({"kind": "activation_done", "ctx": c, "stance_uid": uid})
				return true
			_stage = "defaults"
			_defaults = alive_ids(true).filter(func(owner): return not _activated.has(owner))
			return true
		"defaults":
			while not _defaults.is_empty():
				var owner: int = _defaults.pop_front()
				var enemy := unit(owner)
				if enemy.hull <= 0 or enemy.default_action.is_empty(): continue
				_next_enemy_action()
				_record("intent_triggered", {"title": enemy.name + " / weaker default action", "presentation": {"owner_name": enemy.name, "owner_visual": _enemy_visual(owner), "owner": owner, "name": "Default action", "effects": enemy.default_action}})
				tasks.append_array(_effect_jobs(enemy.default_action, _enemy_context(owner), true))
				tasks.append({"kind":"default_done","ctx":_enemy_context(owner)})
				return true
			_fill_row(_spent_intent_stances)
			_spent_intent_stances.clear()
			_record("stance_changed", {"title": "Enemy row refilled", "batch_refill": true})
			_round_cleanup()
			return true
		"turn_start":
			_stage = ""
			phase = "refresh"
			return false
		"refresh_discard":
			_stage = "refresh_draw"
			_draw(maxi(0, hand_refill_limit() - hand.size()), root_context)
			return true
		"refresh_draw":
			_stage = ""
			phase = "fleet"
			return false
		"turn_end":
			_stage = "enemy"
			return true
	return false


func _enemy_context(owner: int) -> Dictionary:
	return {"owner": owner, "uid": -1, "slot": -1, "ally": _enemy_target(owner, weapon_range(owner)), "enemy": -999, "event": {}, "ancestry": [], "slot_target": position_of(owner) + 4, "circle_target": -1, "stance_target": -1, "reaction_target": ""}


func _next_enemy_action() -> void:
	action_id += 1
	used_triggers.clear()


func _emit_discard(uid: int, reason: String, c: Dictionary) -> void:
	var context := c.duplicate(true)
	context["uid"] = uid
	context["owner"] = int(card(uid).owner)
	_emit("discarded", context, {"reason": reason, "uid": uid, "card": card(uid), "actor": card(uid).owner, "amount": 1})


func _enemy_target(owner: int, range_text: String) -> int:
	var origin := position_of(owner)
	if origin < 0 or (range_text == "Short" and origin == 3): return -999
	var matching: int = 0 if origin == 3 else origin
	var candidates: Array = [matching, 0, 1, 2, 3]
	for point in candidates:
		if range_text == "Short" and point == 3: continue
		if formation[point] >= 0 and unit(formation[point]).hull > 0: return formation[point]
	return -999


func _enemy_effect_target(c: Dictionary, range_text: String) -> int:
	if c.has("reaction_actor"): return int(c.reaction_actor)
	return _enemy_target(int(c.owner), range_text)


func _attack_presentation(p: Dictionary, owner: int, shape: String = "ranged") -> String:
	var style: String = p.get("presentation", "auto")
	return ("melee" if owner < 0 else shape) if style == "auto" else style


func _area_range(p: Dictionary, c: Dictionary) -> String:
	if c.get("area_range") == "Short": return "Short"
	return weapon_range(c.owner, c) if p.get("range", "weapon") == "weapon" else p.range


func _area_legal(owner: int, target: int, range_text: String) -> bool:
	return unit(target).get("hull", 0) > 0 and (range_text != "Short" or (position_of(owner) != 3 and position_of(target) != 3))


func _focus_effect(units: Array = [], slots: Array = [], circle_slots: Array = [], stances: Array = []) -> void:
	if not _preview_only:
		_record("effect_focus", {"units": units, "slots": slots, "circle_slots": circle_slots, "stances": stances})


func effect_beam(p: Dictionary, c: Dictionary) -> bool:
	var origin := position_of(c.owner)
	if origin < 0 or unit(c.owner).get("hull", 0) <= 0: return false
	var points: Array = [0, 3] if origin in [0, 3] else [origin]
	var opposing: Array = enemy_formation if int(c.owner) >= 0 else formation
	var victims: Array = []
	for point in points:
		if opposing[point] < 0: continue
		var target: int = -1 - int(opposing[point]) if int(c.owner) >= 0 else int(opposing[point])
		if _area_legal(c.owner, target, _area_range(p, c)): victims.append(target)
	if victims.is_empty(): return false
	_record("area_attack", {"style":"beam", "presentation":_attack_presentation(p, c.owner, "beam"), "origin_marker":p.get("origin_marker", "attack"), "attacker":int(c.owner), "targets":victims.duplicate(), "target":victims[0]})
	var ctx := c.duplicate(true)
	ctx["attack_style"] = "beam"
	return effect_attack(p, ctx, victims)


func effect_explosion(p: Dictionary, c: Dictionary) -> bool:
	var configured: Dictionary = Rules.fresh("effect", "explosion").merged(p, true)
	p = configured
	if unit(c.owner).get("hull", 0) <= 0: return false
	var range_text := _area_range(p, c)
	var centres: Array = selected(p.merged({"target":p.get("target", "chosen_enemy")}), c)
	if int(c.owner) < 0 and p.get("target", "chosen_enemy") in ["chosen_ally", "chosen_enemy"]:
		var target := _enemy_effect_target(c, range_text)
		centres = [target] if target != -999 else []
	var jobs: Array = []
	for centre in centres:
		if not _area_legal(c.owner, centre, range_text): continue
		var opposing: Array = enemy_formation if int(centre) < 0 else formation
		var neighbours: Array = []
		for point in Geometry.unit_neighbours(position_of(centre)):
			if opposing[point] < 0: continue
			var target: int = -1 - int(opposing[point]) if int(centre) < 0 else int(opposing[point])
			if _area_legal(c.owner, target, range_text): neighbours.append(target)
		# Freeze affected identities before the primary effects can move or defeat anything.
		jobs.append({"kind":"area_visual", "ctx":c, "style":"explosion", "presentation":_attack_presentation(p, c.owner, "explosion"), "origin_marker":p.get("origin_marker", "attack"), "target":centre, "targets":[centre] + neighbours})
		for target in [centre] + neighbours:
			var ctx := c.duplicate(true)
			ctx["area_target"] = target
			ctx["attack_style"] = "explosion"
			ctx["area_range"] = range_text
			jobs.append_array(_effect_jobs(p.get("main_effects" if target == centre else "adjacent_effects", []), ctx))
	_prepend(jobs)
	return false


func effect_attack(p: Dictionary, c: Dictionary, locked_targets: Variant = null) -> bool:
	var owner: int = c.owner
	if unit(owner).get("hull", 0) <= 0: return false
	var range_text: String = weapon_range(owner, c) if p.get("range", "weapon") == "weapon" else p.range
	var targets_list: Array = selected(p.merged({"target": p.get("target", "chosen_enemy")}), c) if locked_targets == null else locked_targets
	if c.get("area_range") == "Short": range_text = "Short"
	if locked_targets == null and owner < 0 and p.get("target", "chosen_ally") in ["chosen_ally", "chosen_enemy"]:
		var target := _enemy_effect_target(c, range_text)
		targets_list = [target] if target != -999 else []
	elif locked_targets == null and targets_list.is_empty() and owner >= 0 and not p.has("filter") and p.get("target", "chosen_enemy") != "area_target":
		var fallback: int = int(c.get("event", {}).get("target", -999))
		if fallback < 0 and not unit(fallback).is_empty() and unit(fallback).hull > 0: targets_list = [fallback]
		else:
			for target in alive_ids(true):
				if range_text != "Short" or (position_of(owner) != 3 and position_of(target) != 3):
					targets_list = [target]
					break
	var damage: int = Rules.number(p.get("damage", {"kind": "weapon_damage", "target": "owner"}), c)
	var extra: int = _bonus("attack_damage", owner, c) + (_bonus("attack_damage", c.uid, c, true) if int(c.get("uid", -1)) >= 0 else 0)
	var each: int = _bonus("per_hit_damage", owner, c) + (_bonus("per_hit_damage", c.uid, c, true) if int(c.get("uid", -1)) >= 0 else 0)
	var count: int = maxi(1, Rules.number(p.get("hits", 1), c) + _bonus("hit_count", owner, c) + (_bonus("hit_count", c.uid, c, true) if int(c.get("uid", -1)) >= 0 else 0))
	var all_jobs: Array = []
	var legal_targets := targets_list.filter(func(target): return _area_legal(owner, target, range_text))
	if locked_targets == null and not c.has("area_target"): _focus_effect(legal_targets)
	for target in legal_targets:
		_emit("attack_started", c, {"target": target, "amount": 1})
		var jobs: Array = []
		var visual_context := c.duplicate(true)
		visual_context["attack_presentation"] = _attack_presentation(p, owner, c.get("attack_style", "ranged"))
		visual_context["origin_marker"] = p.get("origin_marker", "attack")
		# An explicitly styled child attack can have its own animation inside a blast.
		if locked_targets == null and p.get("presentation", "auto") != "auto": visual_context.erase("attack_style")
		for i in count:
			jobs.append({"kind": "hit", "ctx": visual_context.duplicate(true), "target": target, "damage": damage + each + (extra if i == 0 else 0), "index": i + 1, "total": count})
		all_jobs.append_array(jobs)
	_prepend(all_jobs)
	return false


func _hit(job: Dictionary, c: Dictionary) -> void:
	var target: int = job.target
	var u := unit(target)
	if u.get("hull", 0) <= 0: return
	hit_id += 1
	var point := position_of(target)
	var cover_point := point + (4 if target < 0 else 0)
	var enemy_bonus := int(campaign_options.get("enemy_hit_bonus", 0)) if int(c.owner) < 0 else 0
	var incoming: int = maxi(0, int(job.damage) + enemy_bonus + (maxi(0, round_number - 3) if int(c.owner) < 0 and _mode == "enemy" else 0))
	var cover_absorbed: int = mini(int(cover[cover_point]), incoming) if point >= 0 else 0
	if point >= 0: cover[cover_point] -= cover_absorbed
	var remaining := incoming - cover_absorbed
	var armour_absorbed: int = mini(stat(target, "armour", c), remaining)
	remaining -= armour_absorbed
	var shields_absorbed: int = mini(int(u.guard), remaining)
	u.guard -= shields_absorbed
	remaining -= shields_absorbed
	var hull_lost: int = mini(int(u.hull), remaining)
	u.hull -= hull_lost
	if _mode == "player" and target < 0:
		root_context.damage[target] = int(root_context.damage.get(target, 0)) + hull_lost
	var metrics := {"attacker": int(c.owner), "incoming_damage": incoming, "target": target, "amount": hull_lost, "hull_damage": hull_lost, "cover_absorbed": cover_absorbed, "armour_absorbed": armour_absorbed, "shields_absorbed": shields_absorbed, "blocked": cover_absorbed + armour_absorbed + shields_absorbed, "hit_id": hit_id, "hit_index": job.index, "hit_total": job.total, "attack_style": c.get("attack_style", ""), "presentation":c.get("attack_presentation", "ranged"), "origin_marker":c.get("origin_marker", "attack")}
	if _mode == "player" and target < 0:
		if not root_context.has("metrics"): root_context["metrics"] = {}
		if not root_context.metrics.has(target): root_context.metrics[target] = {}
		for metric in ["hull_damage", "cover_absorbed", "armour_absorbed", "shields_absorbed", "blocked"]:
			root_context.metrics[target][metric] = int(root_context.metrics[target].get(metric, 0)) + int(metrics[metric])
	_record("damage", metrics)
	history.append("%s hit %d/%d: cover %d, armour %d, shields %d, hull %d." % [u.name, job.index, job.total, cover_absorbed, armour_absorbed, shields_absorbed, hull_lost])
	_emit("hit_resolved", c, metrics.merged({"amount": 1}, true))
	for pair in [["cover_absorbed", cover_absorbed], ["armour_absorbed", armour_absorbed], ["shields_absorbed", shields_absorbed], ["hull_damaged", hull_lost]]:
		if pair[1] > 0:
			var event := metrics.duplicate()
			event.amount = pair[1]
			_emit(pair[0], c, event)


func effect_unit(kind: String, p: Dictionary, c: Dictionary, present_targets: bool = true) -> bool:
	var repairs := kind in ["repair", "recovery"]
	var recipients := selected(p, c, repairs)
	if present_targets and not c.has("area_target"):
		var affected := recipients.filter(func(id): return not unit(id).is_empty() and (unit(id).hull > 0 or (repairs and id >= 0)))
		_focus_effect(affected)
	for id in recipients:
		var u := unit(id)
		if u.is_empty(): continue
		var amount := Rules.number(p.get("amount", 0), c)
		if repairs:
			amount += _bonus("repair_amount", id, c) + (_bonus("repair_amount", c.uid, c, true) if int(c.get("uid", -1)) >= 0 else 0)
		if u.hull <= 0:
			if repairs and id >= 0 and amount > 0: _recover(id, amount, c)
			continue
		match kind:
			"add_shields":
				amount += _bonus("shield_amount", id, c) + (_bonus("shield_amount", c.uid, c, true) if int(c.get("uid", -1)) >= 0 else 0)
				u.guard += amount
				_record("guard", {"target": id, "amount": amount, "reason": "Shields gained"})
				if amount > 0: _emit("shields_added", c, {"target": id, "amount": amount})
			"repair", "recovery":
				var healed: int = mini(amount, int(u.max_hull) - int(u.hull))
				u.hull += healed
				_record("repair", {"target": id, "amount": healed})
				if healed > 0:
					root_context.healed = int(root_context.get("healed", 0)) + healed
					if id >= 0: root_context["player_healed"] = int(root_context.get("player_healed",0)) + healed
					root_context["ally"] = id
					_emit("repaired", c, {"target": id, "actor": c.owner, "amount": healed, "healed": healed})
			"gain_resource", "spend_resource":
				var previous: int = int(u.resource)
				u.resource = mini(stat(id, "resource_capacity", c), previous + amount) if kind == "gain_resource" else maxi(0, previous - amount)
				if u.resource != previous:
					_record("resource", {"target": id, "amount": int(u.resource) - previous, "title": u.get("resource_name", "Charge")})
					_emit("resource_changed", c, {"target": id, "actor": id, "amount": absi(int(u.resource) - previous)})
	return false


func pay_resource(p: Dictionary, c: Dictionary) -> bool:
	var units := selected(p, c)
	if units.is_empty(): return false
	var amount := Rules.number(p.get("amount", 0), c)
	for id in units:
		if unit(id).hull <= 0 or int(unit(id).resource) < amount: return false
	effect_unit("spend_resource", p, c, false)
	return true


func effect_cover(p: Dictionary, c: Dictionary) -> bool:
	var amount := Rules.number(p.get("amount", 0), c)
	var slots := selected(p.merged({"target": p.get("target", "source_slot")}), c).filter(func(point): return point >= 0 and point < 8)
	if not c.has("area_target"): _focus_effect([], slots)
	for point in slots:
		cover[point] += amount
		_record("cover", {"position": point, "amount": amount, "title": "Slot cover"})
	return false


func _swap_points(a: int, b: int, c: Dictionary = {}) -> void:
	if a not in range(4) or b not in range(4) or a == b: return
	var first: int = formation[a]
	var second: int = formation[b]
	if not c.has("area_target"): _focus_effect([], [a, b])
	formation[a] = second
	formation[b] = first
	_record("movement", {"first": first})
	for id in [first, second]:
		if id >= 0 and not c.is_empty(): _emit("moved", c, {"actor": id, "target": id, "position": position_of(id), "amount": 1})


func effect_move(p: Dictionary, c: Dictionary) -> bool:
	for actor in selected(p, c):
		if actor < 0 or unit(actor).hull <= 0: continue
		var destination: int = c.get("slot_target", -1) if p.get("destination", "chosen_slot") == "chosen_slot" else Geometry.POSITIONS.find(p.destination)
		var origin := position_of(actor)
		if not Geometry.unit_neighbours(origin).has(destination): continue
		var other: int = formation[destination]
		_swap_points(origin, destination, c)
		if Rules.number(p.get("guard", 0), c) > 0:
			for id in [actor, other]:
				if id >= 0: effect_unit("add_shields", {"target": "event_target", "amount": p.guard}, c.merged({"event": {"target": id}}, true), false)
	return false


func effect_swap(p: Dictionary, c: Dictionary) -> bool:
	var first := targets(p.get("first", "owner"), c)
	var second := targets(p.get("second", "chosen_ally"), c)
	if first.is_empty() or second.is_empty(): return false
	var a: int = first[0]
	var b: int = second[0]
	if a < 0 or b < 0 or unit(a).hull <= 0 or unit(b).hull <= 0 or not Geometry.unit_neighbours(position_of(a)).has(position_of(b)): return false
	_swap_points(position_of(a), position_of(b), c)
	for id in [a, b]:
		if Rules.number(p.get("guard", 0), c) > 0: effect_unit("add_shields", {"target": "event_target", "amount": p.guard}, c.merged({"event": {"target": id}}, true), false)
	return false


func effect_swap_ends(p: Dictionary, c: Dictionary) -> bool:
	var alive := alive_ids()
	if alive.size() > 1: _swap_points(position_of(alive.front()), position_of(alive.back()), c)
	elif alive.size() == 1 and Rules.number(p.get("fallback_damage", 0), c) > 0:
		if not c.has("area_target"): _focus_effect(alive)
		_prepend([{"kind": "hit", "ctx": c, "target": alive[0], "damage": Rules.number(p.fallback_damage, c), "index": 1, "total": 1}])
	return false


func effect_rear_front(_p: Dictionary, c: Dictionary) -> bool:
	var alive := alive_ids()
	if not alive.is_empty(): _swap_points(position_of(alive.back()), 0, c)
	return false


func _draw(amount: int, c: Dictionary) -> void:
	if _preview_only:
		_preview_virtual_hand += mini(amount, deck.size() + discard.size())
		_uncertain = true
		return
	var drawn: Array = []
	for i in amount:
		if deck.is_empty() and not discard.is_empty():
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck)
		if deck.is_empty(): break
		var uid: int = deck.pop_front()
		hand.append(uid)
		drawn.append(uid)
	if not drawn.is_empty():
		_record("cards_drawn", {"uids": drawn})
		if not c.is_empty(): _emit("cards_drawn", c, {"amount": drawn.size()})


func effect_draw(p: Dictionary, c: Dictionary) -> bool:
	_draw(Rules.number(p.get("amount", 1), c), c)
	return false


func effect_discard(p: Dictionary, c: Dictionary) -> bool:
	var count := mini(Rules.number(p.get("amount", 1), c), hand.size() + _preview_virtual_hand)
	if count <= 0: return false
	if _preview_only:
		_preview_virtual_hand -= count
		_uncertain = true
		return false
	pending = {"kind": "discard", "discard_remaining": count, "title": card(c.get("uid", -1)).get("name", unit(c.owner).name), "context": c.duplicate(true)}
	phase = "discard"
	return true


func discard_for_relay(uid: int) -> String:
	if phase != "discard" or not hand.has(uid): return "Choose a hand card for the mandatory discard."
	feedback_events.clear()
	hand.erase(uid)
	discard.append(uid)
	_record("cards_discarded", {"uids": [uid], "reason": "Effect discard"})
	_emit_discard(uid, "effect", pending.context)
	pending.discard_remaining -= 1
	if pending.discard_remaining == 0:
		pending.clear()
		phase = "fleet"
		_drain()
	return ""


func effect_scry(p: Dictionary, c: Dictionary) -> bool:
	if _preview_only:
		_uncertain = true
		return false
	var requested := Rules.number(p.get("look", 3), c)
	var revealed: Array = []
	while revealed.size() < requested:
		if deck.is_empty():
			if discard.is_empty(): break
			deck = discard.duplicate()
			discard.clear()
			_shuffle(deck)
		revealed.append(deck.pop_front())
	var count := revealed.size()
	if count <= 0: return false
	pending = {"kind": "scry", "revealed": revealed, "take": mini(Rules.number(p.get("take", 1), c), count), "title": "Scry: choose cards, order the rest", "context": c.duplicate(true)}
	phase = "scry"
	_record("scry", {"title": pending.title})
	return true


func choose_scry(take: Array, top: Array, rejected: Array) -> String:
	if phase != "scry": return "No scry decision is pending."
	if take.size() != int(pending.take): return "Choose exactly %d cards for your hand." % pending.take
	var all: Array = take + top + rejected
	var unique: Array = []
	for uid in all:
		if not pending.revealed.has(uid) or unique.has(uid): return "Assign each revealed card exactly once."
		unique.append(uid)
	if all.size() != pending.revealed.size(): return "Assign every revealed card to hand, top, or discard."
	feedback_events.clear()
	var c: Dictionary = pending.context
	hand.append_array(take)
	deck = top + deck
	discard.append_array(rejected)
	if not take.is_empty():
		_record("cards_drawn", {"uids": take.duplicate()})
		_emit("cards_drawn", c, {"amount": take.size()})
	if not rejected.is_empty():
		_record("cards_discarded", {"uids": rejected.duplicate(), "reason": "Scry discard"})
		for uid in rejected: _emit_discard(uid, "effect", c)
	pending.clear()
	phase = "fleet"
	_drain()
	return ""


func effect_stun(p: Dictionary, c: Dictionary) -> bool:
	var keys := targets(p.get("target", "chosen_reaction"), c)
	if not c.has("area_target"):
		_focus_effect([], [], [], keys.map(func(key): return int(str(key).get_slice("/", 0))).filter(func(uid): return enemy_row.has(uid)))
	for key in keys:
		var parts: PackedStringArray = str(key).split("/")
		if parts.size() != 2 or not enemy_row.has(int(parts[0])): continue
		for reaction in row_card(int(parts[0])).reactions:
			if reaction.id == parts[1]:
				stunned[key] = true
				_record("stunned", {"title": reaction.name + " suppressed until fleet phase ends", "reaction_key": key})
	return false


func unit_stunned(id: int) -> bool:
	for key in stunned:
		if stance_cards[int(str(key).split("/")[0])].owner == id: return true
	return false


func effect_confuse(p: Dictionary, c: Dictionary) -> bool:
	var cards := targets(p.get("target", "chosen_stance"), c).filter(func(uid): return enemy_row.has(uid))
	if not c.has("area_target"): _focus_effect([], [], [], cards)
	for uid in cards:
		if enemy_row.has(uid):
			_record("confused", {"title": row_card(uid).owner_name + " / " + row_card(uid).name})
			_replace_row(uid)
	return false


func effect_persistence(p: Dictionary, c: Dictionary) -> bool:
	var cards := selected(p.merged({"target": p.get("target", "self_card")}), c)
	if not c.has("area_target"):
		_focus_effect([], [], cards.map(func(uid): return circle.find(uid)).filter(func(slot): return slot >= 0))
	for uid in cards:
		if circle.has(uid):
			persistence[uid] = int(persistence.get(uid, 0)) + Rules.number(p.get("amount", 1), c)
			_record("persistence", {"uid": uid, "amount": Rules.number(p.get("amount", 1), c), "title": "Persistence " + str(persistence[uid])})
	return false


func effect_mana(p: Dictionary, c: Dictionary) -> bool:
	var before := mana
	mana = mini(fleet_stat("mana_capacity"), mana + Rules.number(p.get("amount", 1), c))
	if mana != before: _record("mana", {"amount": mana - before, "title": "Mana crystal gained"})
	return false


func basic_targets() -> Array:
	var result: Array = range(ships.size()) + alive_ids(true)
	for point in 4:
		if formation[point] < 0: result.append(100 + point)
	return result


func validate_basic(uid: int, recipient: int) -> String:
	if phase != "fleet" or outcome != "": return "Basic actions are available during the fleet phase."
	if not hand.has(uid) or uid < 0: return "Discard a card from your hand."
	if recipient < 0:
		var attacker: int = card(uid).owner
		if ships[attacker].hull <= 0: return "A defeated ship can only recover itself."
		if recipient not in alive_ids(true): return "Choose a living enemy."
		if not _area_legal(attacker, recipient, weapon_range(attacker)): return "Short weapons cannot fire from or target Rear."
		return ""
	if recipient >= 100:
		var destination := recipient - 100
		if destination not in range(4) or formation[destination] >= 0: return "Choose an empty player position."
		var mover: int = card(uid).owner
		if ships[mover].hull <= 0: return "A defeated ship can only recover itself."
		return "" if Geometry.unit_neighbours(position_of(mover)).has(destination) else "Move requires an adjacent empty position."
	if recipient >= ships.size(): return "Choose a player ship."
	var actor: int = card(uid).owner
	if actor == recipient:
		if ships[actor].hull > 0 and ships[actor].hull >= ships[actor].max_hull: return "This ship is already at full hull."
		return "" if ships[actor].hull > 0 or formation.has(-1) else "Revival requires an empty position."
	if ships[actor].hull <= 0: return "A defeated ship can only recover itself."
	if ships[recipient].hull <= 0: return "Only living ships can swap."
	if not Geometry.unit_neighbours(position_of(actor)).has(position_of(recipient)): return "Swap requires an adjacent player ship."
	return ""


func _recovery_position(id: int) -> int:
	var point: int = ships[id].get("last_position", -1)
	if point < 0 or formation[point] >= 0: point = formation.find(-1)
	return point


func _recover(id: int, amount: int, c: Dictionary) -> void:
	var ship: Dictionary = ships[id]
	var threshold: int = definitions.basic_actions.revive_threshold
	var before: int = ship.get("recovery", 0)
	ship.recovery = mini(threshold, before + amount)
	_record("revive_progress", {"target": id, "amount": ship.recovery - before, "threshold": threshold, "title": ship.name})
	if ship.recovery < threshold: return
	var point := _recovery_position(id)
	if point < 0: return
	formation[point] = id
	ship.hull = mini(Catalog.REVIVED_HULL, ship.max_hull)
	ship.guard = 0
	ship.recovery = 0
	ship.resource = 0
	root_context.healed = int(root_context.get("healed", 0)) + int(ship.hull)
	root_context["player_healed"] = int(root_context.get("player_healed",0)) + int(ship.hull)
	root_context["ally"] = id
	_record("revived", {"target": id, "amount": ship.hull, "title": ship.name})
	_emit("revived", c, {"target": id, "actor": id, "amount": 1})
	_emit("repaired", c, {"target": id, "actor": c.owner, "amount": int(ship.hull), "healed": int(ship.hull)})


func play_basic(uid: int, recipient: int, options: Dictionary = {}) -> String:
	var error := validate_basic(uid, recipient)
	if error != "": return error
	var actor: int = card(uid).owner
	var repair: bool = actor == recipient
	var attack := recipient < 0
	var empty_move: bool = recipient >= 100
	var basic_type := "Attack" if attack else ("Support" if repair else "Manoeuvre")
	var traits := ["Repair"] if repair else ([] if attack else ["Movement"])
	var action := "attack" if attack else ("repair" if repair else ("move" if empty_move else "swap"))
	var c := {"owner": actor, "uid": -1, "slot": -1, "ally": actor if empty_move or attack else recipient, "enemy": recipient if attack else -999, "slot_target": recipient - 100 if empty_move else position_of(recipient), "event": {}, "ancestry": [], "boosts": options.get("boosts", []), "basic_type": basic_type, "basic_traits": traits, "basic": true}
	error = _validate_boosts(uid, c, options.get("boosts", []))
	if error != "": return error
	feedback_events.clear()
	_start_action(c)
	root_context["basic"] = true
	root_context["event_card"] = {"type": basic_type, "traits": traits}
	hand.erase(uid)
	held = [uid]
	_record("basic_action", {"uid": uid, "target": actor if empty_move else recipient, "position": c.slot_target, "source": actor, "action": action, "title": "Basic %s / %s" % [action.capitalize(), ships[actor].name]})
	_reserve_boosts(uid, c, options.get("boosts", []))
	if attack:
		tasks.append({"kind": "effect", "spec": {"kind": "attack", "target": "chosen_enemy", "range": "weapon", "damage": {"kind":"basic_weapon_damage"}}, "ctx": c})
	elif repair:
		tasks.append({"kind": "effect", "spec": {"kind": "repair", "target": "owner", "amount": definitions.basic_actions.repair}, "ctx": c})
	elif empty_move:
		tasks.append({"kind": "effect", "spec": {"kind": "move", "target": "owner", "destination": "chosen_slot", "guard": 0}, "ctx": c})
	else:
		tasks.append({"kind": "effect", "spec": {"kind": "swap", "first": "owner", "second": "chosen_ally", "guard": 0}, "ctx": c})
	_drain()
	return ""


func _cleanup() -> void:
	for id in range(ships.size()):
		ships[id].max_hull = maxi(1, stat(id, "max_hull"))
		ships[id].hull = mini(ships[id].hull, ships[id].max_hull)
		ships[id].resource = mini(ships[id].resource, stat(id, "resource_capacity"))
	for point in 4:
		var id: int = formation[point]
		if id >= 0 and ships[id].hull <= 0:
			formation[point] = -1
			ships[id].last_position = point
			ships[id].guard = 0
			ships[id].resource = 0
			ships[id].recovery = 0
			_record("disabled", {"target": id, "title": ships[id].name})
		var enemy_id: int = enemy_formation[point]
		if enemy_id >= 0 and enemies[enemy_id].hull <= 0:
			enemy_formation[point] = -1
			enemies[enemy_id].guard = 0
			var owner: int = -1 - enemy_id
			enemy_row = enemy_row.filter(func(uid): return stance_cards[uid].owner != owner)
			stance_deck = stance_deck.filter(func(uid): return stance_cards[uid].owner != owner)
			stance_discard = stance_discard.filter(func(uid): return stance_cards[uid].owner != owner)
			for key in stunned.keys():
				if stance_cards[int(str(key).split("/")[0])].owner == owner: stunned.erase(key)
			_record("destroyed", {"target": owner, "title": enemies[enemy_id].name, "enemy": true})
			if _mode != "enemy": _fill_row()
	_correct_formation(formation, false)
	_correct_formation(enemy_formation, true)
	mana = mini(mana, fleet_stat("mana_capacity"))
	if ships.all(func(ship): return ship.hull <= 0): outcome = "defeat"
	elif _enemies_defeated() and _mode == "": outcome = "victory"
	if outcome != "":
		phase = "finished"
		tasks.clear()


func _correct_formation(points: Array, enemy: bool) -> void:
	var move := Geometry.normalize_formation(points)
	if move.x < 0: return
	var index: int = points[move.y]
	var id := -1 - index if enemy else index
	var offset := 4 if enemy else 0
	history.append("%s moves to %s." % [unit(id).name, Geometry.POSITION_NAMES[move.y]])
	_focus_effect([], [move.x + offset, move.y + offset])
	_record("movement", {"first": id, "automatic": true})
	_emit("moved", {"owner": id, "uid": -1}, {"actor": id, "target": id, "position": move.y})


func _enemies_defeated() -> bool:
	return alive_ids(true).is_empty()


func _finish_terminal_payment() -> void:
	if not held.is_empty():
		var spent := held.duplicate()
		discard.append_array(held)
		held.clear()
		_record("cards_discarded", {"uids": spent, "reason": "Committed payment"})


func end_phase() -> String:
	if phase != "fleet" or outcome != "" or _stage != "": return "Finish the current action first."
	feedback_events.clear()
	action_id += 1
	used_triggers.clear()
	earned_mana = fleet_stat("mana_reward") if hand.size() >= int(definitions.setup.retain_threshold) else 0
	mana = 0
	stunned.clear()
	_mode = "enemy"
	_stage = "turn_end"
	_activation_row = enemy_row.duplicate()
	_spent_intent_stances.clear()
	_activated.clear()
	root_context = {"owner": alive_ids()[0], "uid": -1, "damage": {}, "healed": 0, "printed_cost": 0, "event": {}, "ancestry": []}
	_emit("turn_end", root_context, {"actor": -999, "amount": 1})
	_drain()
	return ""


func _round_cleanup() -> void:
	for id in alive_ids() + alive_ids(true):
		var amount: int = unit(id).guard
		unit(id).guard = 0
		if amount > 0: _record("guard", {"target": id, "amount": -amount, "reason": "Shields expired"})
	for point in 8:
		if cover[point] > 0:
			var amount: int = cover[point]
			cover[point] = 0
			_record("cover", {"position": point, "amount": -amount, "title": "Cover expired"})
	var old: Array = []
	for uid in play_order.duplicate():
		if int(persistence.get(uid, 0)) > 0:
			persistence[uid] -= 1
			_record("persistence", {"uid": uid, "amount": -1, "title": "Persisted for another round"})
		else:
			old.append(uid)
			circle[circle.find(uid)] = -1
			play_order.erase(uid)
			persistence.erase(uid)
	discard.append_array(old)
	if not old.is_empty(): _record("cards_discarded", {"uids": old, "reason": "Circle cleanup / no discard triggers"})
	if play_order.is_empty(): expanded = false
	round_number += 1
	used_turn.clear()
	used_triggers.clear()
	mana = mini(fleet_stat("mana_capacity"), earned_mana)
	earned_mana = 0
	_record("circle_reset", {"title": "New turn / persistence retained " + str(play_order.size()) + " card(s)"})
	_record("mana", {"amount": mana, "title": "Retention mana"})
	_stage = "turn_start"
	_mode = ""
	_emit("turn_start", root_context, {"actor": -999, "amount": 1})


func refresh(optional_discards: Array = []) -> String:
	if phase != "refresh": return "Refresh is only available between rounds."
	if not optional_discards.is_empty(): return "Cards can only be discarded for a cost or an effect. Retained cards stay in hand at refill."
	feedback_events.clear()
	action_id += 1
	used_triggers.clear()
	phase = "fleet"
	_stage = "refresh_discard"
	_drain()
	return ""


func _simulation() -> Variant:
	var sim = get_script().new(0, document, campaign_options)
	for key in ["ships", "enemies", "formation", "enemy_formation", "cover", "card_keys", "hand", "deck", "discard", "held", "circle", "play_order", "persistence", "enemy_row", "stance_cards", "stance_deck", "stance_discard", "stunned", "used_turn", "used_triggers"]:
		sim.set(key, get(key).duplicate(true))
	sim.phase = phase
	sim.outcome = outcome
	sim.tasks.clear()
	sim.pending.clear()
	sim._stage = ""
	sim.round_number = round_number
	sim.mana = mana
	sim.expanded = expanded
	sim._preview_only = true
	sim.history.clear()
	return sim


func preview(uid: int, payment: Array, target: int = -1, movement: int = -1, slot: int = -1, options: Dictionary = {}) -> Dictionary:
	var error := validate(uid, payment, target, movement, slot, options)
	var details := contribution_details(uid, slot)
	if error != "": return {"ok": false, "text": error, "contributors": details.keys(), "contribution_details": details}
	var sim = _simulation()
	sim.play(uid, payment, target, movement, slot, options)
	details = contribution_details(uid, slot, sim.used_triggers)
	var lines: Array = ["Cost %d / paid %d." % [int(options.get("locked_cost", effective_cost(uid, slot))), payment_total(payment) + int(options.get("crystals", 0))]]
	lines.append_array(_preview_changes(sim))
	if sim.expanded and not expanded: lines.append("Unlocks five circle slots after the allied chain.")
	for event in sim.feedback_events:
		if event.kind == "reaction_triggered": lines.append("REACTION: " + event.title + "; replacement hidden.")
	lines.append("Hidden draws and replacements are not revealed.")
	return {"ok": true, "text": " ".join(lines), "contributors": details.keys(), "contribution_details": details, "uncertain": sim._uncertain}


func _preview_changes(sim) -> Array:
	var lines: Array = []
	for id in alive_ids() + alive_ids(true):
		var a := unit(id)
		var b: Dictionary = sim.unit(id)
		if a.hull != b.hull: lines.append("%s hull %d → %d." % [a.name, a.hull, b.hull])
		if a.guard != b.guard: lines.append("%s shields %d → %d." % [a.name, a.guard, b.guard])
		if a.get("resource", 0) != b.get("resource", 0): lines.append("%s %s %d → %d." % [a.name, a.get("resource_name", "resource"), a.resource, b.resource])
	if sim.outcome != "": lines.append(sim.outcome.to_upper())
	return lines


func basic_preview(uid: int, recipient: int, options: Dictionary = {}) -> Dictionary:
	var error := validate_basic(uid, recipient)
	if error != "": return {"ok": false, "text": error, "action": ""}
	var actor: int = card(uid).owner
	var title: String
	if recipient < 0: title = "%s attacks %s with its %s weapon (%d basic damage)" % [ships[actor].name, unit(recipient).name, weapon_range(actor).to_lower(), Rules.basic_weapon_damage(stat(actor, "weapon_damage"))]
	elif recipient >= 100: title = "Move %s → %s" % [ships[actor].name, Geometry.POSITION_NAMES[recipient - 100]]
	elif actor != recipient: title = "Swap %s ↔ %s" % [ships[actor].name, ships[recipient].name]
	elif ships[actor].hull > 0:
		var amount: int = mini(int(definitions.basic_actions.repair) + _bonus("repair_amount", actor), int(ships[actor].max_hull) - int(ships[actor].hull))
		title = "Repair %s: +%d hull" % [ships[actor].name, amount]
	else:
		title = "Recover " + ships[actor].name
	var sim = _simulation()
	error = sim.play_basic(uid, recipient, options)
	if error != "": return {"ok": false, "text": error, "action": ""}
	for event in sim.feedback_events:
		if event.kind == "revived" and event.target == actor:
			title += ". REVIVE with %d hull" % event.amount
			break
	var text: String = title + ". Discard " + card(uid).name + "; no extra mana payment. Printed cost/effects/position restrictions are ignored. "
	text += " ".join(_preview_changes(sim))
	for event in sim.feedback_events:
		if event.kind == "reaction_triggered": text += " REACTION: " + event.title + "; replacement hidden."
	if recipient >= 0 and recipient < 100 and sim.ships[recipient].hull <= 0: text += " Disabled ship recovery %d / %d." % [sim.ships[recipient].recovery, definitions.basic_actions.revive_threshold]
	return {"ok": true, "text": text, "action": "Attack" if recipient < 0 else ("Repair / Recover" if actor == recipient else ("Move Ship" if recipient >= 100 else "Swap Ships"))}


func contribution_details(uid: int, slot: int, simulated: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if uid < 0 or card(uid).is_empty(): return result
	if slot < 0: slot = first_slot()
	if slot < 0 or slot >= (9 if expanded else 4): return result
	var c := {"owner": card(uid).owner, "uid": uid, "slot": slot, "proposed_slot": slot, "proposed_uid": uid, "event": {"kind": "on_play", "uid": uid, "actor": card(uid).owner, "card": card(uid)}, "state": self}
	for point in Geometry.neighbours(slot, expanded):
		var source_uid: int = circle[point]
		if source_uid < 0: continue
		var reasons: Array = []
		for source in _modifier_sources(c):
			if source.uid != source_uid: continue
			for modifier in source.rule.get("modifiers", []):
				if not targets(modifier.get("target", "owner"), source).has(uid): continue
				if modifier.get("card_type", "") != "" and card(uid).type != modifier.card_type: continue
				if modifier.get("trait", "") != "" and not card(uid).traits.has(modifier.trait): continue
				if modifier.kind == "cost" and int(card(uid).cost) == 0: continue
				reasons.append(Rules.text("modifier", modifier, unit(source.owner).name))
		for rule in card(uid).rules:
			var condition: Dictionary = rule.get("conditions", {"kind": "always"})
			if condition.get("kind") == "adjacent" and Rules.condition(condition, c) and Rules._matches_card(card(source_uid), condition):
				reasons.append("Enables on-play: " + Rules.text("condition", condition, unit(card(uid).owner).name))
		for rule in card(source_uid).rules:
			var key := "%d/%s" % [source_uid, rule.id]
			if simulated.has(key): reasons.append("Will trigger: " + str(rule.get("name", rule.id)))
		if not reasons.is_empty(): result[source_uid] = reasons
	return result


func contributing_cards(uid: int, slot: int, simulated: Dictionary = {}) -> Array:
	return contribution_details(uid, slot, simulated).keys()


func _display_units(list: Array, enemy: bool = false) -> Array:
	var result: Array = []
	for i in list.size():
		var source: Dictionary = list[i]
		var id: int = -1 - i if enemy else i
		var copy: Dictionary = source.duplicate(true)
		copy.armour = stat(id, "armour")
		copy.weapon.damage = stat(id, "weapon_damage")
		copy.weapon.range = weapon_range(id)
		copy.resource_capacity = stat(id, "resource_capacity")
		if enemy:
			copy["default_text"] = Catalog.effects_text(source.default_action, source.name)
			copy["row_activations"] = enemy_row.filter(func(uid): return stance_cards[uid].owner == id).size()
		for key in ["active_rules", "levels", "loadout", "legacy_loadout", "stances", "stance_loadout", "default_action", "rules"]:
			copy.erase(key)
		result.append(copy)
	return result


func board_snapshot() -> Dictionary:
	var row: Array = []
	for uid in enemy_row: row.append(row_card(uid))
	return {"ships": _display_units(ships), "enemies": _display_units(enemies, true), "formation": formation.duplicate(), "enemy_formation": enemy_formation.duplicate(), "enemy_position": enemy_position,
		"monster_hull": monster_hull, "stance_index": stance_index, "stance_row": row, "stunned": stunned.duplicate(), "cover": cover.duplicate(), "basic_actions": definitions.get("basic_actions", DEFAULT_BASIC_RULES()).duplicate(),
		"circle": circle.duplicate(), "expanded": expanded, "play_order": play_order.duplicate(), "persistence": persistence.duplicate(), "used_triggers": used_triggers.duplicate(),
		"mana": mana, "mana_capacity": fleet_stat("mana_capacity"), "hand_size": hand.size(), "deck_size": deck.size(), "discard_size": discard.size(), "scry_size": pending.get("revealed", []).size()}


func DEFAULT_BASIC_RULES() -> Dictionary: return {"repair": 2, "revive_threshold": 4}


func _record(kind: String, details: Dictionary = {}) -> void:
	var event := details.duplicate(true)
	event.kind = kind
	event["board"] = board_snapshot()
	feedback_events.append(event)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value: Variant = list[i]
		list[i] = list[j]
		list[j] = value


func reaction_preview(uid: int, action: Dictionary = {}) -> Dictionary:
	if not enemy_row.has(uid): return {}
	var row := row_card(uid)
	var notes: Dictionary = {}
	var lines: Array = [row.owner_name + " / " + row.name,"If triggered now (current defences):"]
	var behaviours: Array = row.reactions.duplicate(true)
	behaviours.append({"name":"Enemy phase","effects":row.effects,"conditions":{"kind":"always"}})
	var played_uid: int = action.get("uid", -1)
	var actor: int = card(played_uid).get("owner", action.get("actor", -999))
	if actor < 0 and not row.reactions.is_empty():
		lines.append("Reactions target the triggering ship by default.")
	for index in behaviours.size():
		var behaviour: Dictionary = behaviours[index]
		var is_reaction: bool = index < row.reactions.size()
		var sim = _simulation()
		var c: Dictionary = sim._enemy_context(row.owner)
		c.event = {"actor":actor,"target":action.get("target",-999),"uid":played_uid,"card":card(played_uid)}
		if is_reaction:
			c.reaction_actor = actor
			c.ally = actor
		sim._start_action(c,"hover")
		sim._stage=""
		sim.tasks=sim._effect_jobs(behaviour.effects,c)
		sim._drain()
		lines.append(behaviour.name + ": " + Catalog.effects_text(behaviour.effects, row.owner_name))
		for event in sim.feedback_events:
			if event.kind in ["damage","guard","repair","resource"]:
				var id: int=event.target
				var summary := ""
				if event.kind=="damage": summary=("Reaction " if is_reaction else "Intent ")+"−%d hull" % event.hull_damage + (" / −%d shields" % event.shields_absorbed if event.shields_absorbed>0 else "")
				else: summary="+%d %s" % [event.amount,{"guard":"shields","repair":"hull","resource":"resource"}.get(event.kind,event.kind)]
				notes[id]=str(notes.get(id,""))+("\n" if notes.has(id) else "")+summary
			elif event.kind=="movement":
				for point in 4:
					if sim.formation[point]!=formation[point]:
						if sim.formation[point]>=0: notes[sim.formation[point]]="Move → "+Geometry.POSITION_NAMES[point]
						elif formation[point]>=0: notes[formation[point]]="Displaced from "+Geometry.POSITION_NAMES[point]
			elif event.kind=="cover":
				var point: int=event.position
				var id: int=formation[point] if point<4 else (-1-enemy_formation[point-4] if enemy_formation[point-4]>=0 else -999)
				if id!=-999: notes[id]="+%d cover" % event.amount
	return {"source":row.owner,"notes":notes,"text":"\n".join(lines)}



func result_summary(reported: String = "") -> Dictionary:
	var result: String = outcome if reported == "" else reported
	if result not in ["victory", "defeat"]: return {}
	var fleet: Array = []
	var hull := 0
	var maximum := 0
	var survivors := 0
	for ship in ships:
		hull += int(ship.hull)
		maximum += int(ship.get("starting_max_hull", ship.max_hull))
		if ship.hull > 0: survivors += 1
		var summary_ship: Dictionary = {"id": ship.id, "name": ship.name, "role": ship.role, "color": ship.color, "hull": ship.hull, "max_hull": ship.get("starting_max_hull", ship.max_hull) if ship.hull <= 0 else ship.max_hull, "alive": ship.hull > 0, "captain": ship.captain.name, "level": ship.level}
		if ship.has("visual_rig"): summary_ship["visual_rig"] = ship.visual_rig.duplicate(true)
		fleet.append(summary_ship)
	return {"outcome": result, "ships": fleet, "survivors": survivors, "remaining_hull": hull, "starting_hull": maximum, "hull_percent": roundi(100.0 * hull / maxi(1, maximum)), "rounds": round_number, "is_test": result != outcome, "enemies_remaining": alive_ids(true).size()}


func trigger_preview(uid: int, payment: Array = [], target: int = -1, movement: int = -1, slot: int = -1, options: Dictionary = {}, basic_recipient: int = -999) -> Dictionary:
	var result: Dictionary={"reactions":[],"cards":{},"ships":{},"provisional":false,"uncertain":false}
	if phase!="fleet" or outcome!="" or uid<0 or not hand.has(uid):return result
	var sim=_simulation()
	var error: String
	if basic_recipient != -999:
		error=sim.play_basic(uid,basic_recipient,options)
	else:
		if slot<0:slot=first_slot()
		if slot<0:return result
		var chosen:=options.duplicate(true)
		# Simulate only the player's known payment choices, never invent discard chains.
		# A detached cost override allows unpaid actions to preview their own effects.
		var crystals: int=int(chosen.get("crystals",0))
		var due: int=int(chosen.get("locked_cost",effective_cost(uid,slot)))
		result.provisional=payment_total(payment)+crystals<due
		chosen.locked_cost=payment_total(payment)+crystals
		for group in ["primary","movement","enemy","circle","stance","reaction","slot"]:
			var available:=choices(uid,group,slot,chosen)
			if available.is_empty():continue
			var current: Variant=target if group=="primary" else (movement if group=="movement" else chosen.get(group,-999))
			if not _has_choice(available,current):
				var unset: bool=current in [-1,-999] if group in ["primary","movement"] else current==-999
				if not unset:return result
				result.provisional=true
				current=available[0].value
			if group=="primary":target=int(current)
			elif group=="movement":movement=int(current)
			else:chosen[group]=current
		error=sim.play(uid,payment,target,movement,slot,chosen)
	if error!="":return result
	return _trigger_cues(sim,result)

func turn_trigger_preview() -> Dictionary:
	var result: Dictionary={"reactions":[],"cards":{},"ships":{},"provisional":false,"uncertain":false}
	if phase!="fleet" or outcome!="":return result
	var sim=_simulation()
	if sim.end_phase()!="":return result
	return _trigger_cues(sim,result)

func _trigger_cues(sim, result: Dictionary) -> Dictionary:
	result.uncertain=sim._uncertain or sim.phase in ["scry","discard"]
	for event in sim.feedback_events:
		if event.kind=="reaction_triggered" and not result.reactions.has(event.reaction_key):result.reactions.append(event.reaction_key)
		elif event.kind=="card_triggered":
			var source: int=event.uid
			if not result.cards.has(source):result.cards[source]=[]
			var description: String=event.get("rule_text",event.title)
			if not result.cards[source].has(description):result.cards[source].append(description)
		elif event.kind=="ship_rule":
			var owner: int=event.target
			if not result.ships.has(owner):result.ships[owner]=[]
			var description: String=event.get("rule_text",event.title)
			if not result.ships[owner].has(description):result.ships[owner].append(description)
	return result


func _enemy_visual(owner: int) -> Dictionary:
	var data: Dictionary = unit(owner)
	var visual: Dictionary = {"id":data.get("id",""), "position":position_of(owner)}
	if data.has("visual_rig"): visual["visual_rig"] = data.visual_rig.duplicate(true)
	return visual

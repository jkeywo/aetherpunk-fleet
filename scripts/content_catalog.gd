extends RefCounted
const V2 = preload("res://scripts/content_v2.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const TYPES = Rules.TYPES
const DEFAULT_BASIC_RULES := {"repair": 2, "revive_threshold": 4}


static func normalized(value: Variant) -> Variant: return V2.normalized(value)
static func index_by_id(entries: Array, id: String) -> int: return V2.index_by_id(entries, id)
static func basic_rules(doc: Dictionary) -> Dictionary: return doc.get("setup", {}).get("basic_actions", DEFAULT_BASIC_RULES).duplicate(true)


static func empty_document() -> Dictionary:
	return {"version": 3, "ships": [], "captains": [], "cards": [], "leviathans": [], "setup": {"fleet": [], "enemies": [], "fixed_hand": false, "opening_hand": [], "basic_actions": DEFAULT_BASIC_RULES.duplicate(), "mana_capacity": 1, "mana_reward": 1, "retain_threshold": 2}}


static func convert_effect(effect: Dictionary, monster: bool = false) -> Array:
	var amount: Variant = effect.get("amount", 0)
	var target: String = {"actor": "owner", "ally": "chosen_ally", "event_actor": "event_actor", "repaired": "event_target", "all": "all_allies", "front": "fleet_front", "rear": "fleet_rear", "ends": "fleet_ends", "middle": "fleet_middle"}.get(effect.get("target", ""), "chosen_ally")
	if monster and effect.get("target") == "actor": target = "event_actor"
	match effect.get("kind", ""):
		"damage_monster": return [{"kind": "attack", "target": "chosen_enemy", "damage": amount, "hits": 1, "range": "Long"}]
		"damage_ship": return [{"kind": "attack", "target": "all_allies" if effect.get("target") == "all" else target, "damage": amount, "hits": 1, "range": "Long"}]
		"guard": return [{"kind": "add_shields", "target": target, "amount": amount, "exclude_owner": "Yes" if effect.get("exclude_actor", false) else "No"}]
		"repair": return [{"kind": "repair", "target": target if effect.has("target") else "chosen_ally", "amount": amount}]
		"swap_adjacent": return [{"kind": "move", "target": "owner", "destination": "chosen_slot", "guard": 0}]
		"swap_pair_guard": return [{"kind": "swap", "first": "chosen_pair_first", "second": "chosen_pair_second", "pair_choice": "Yes", "guard": amount}]
		"draw_discard": return [{"kind": "draw", "amount": amount}, {"kind": "discard", "amount": effect.get("discard", 0)}]
		"swap_ends": return [{"kind": "swap_ends", "fallback_damage": amount}]
		"rear_to_front": return [{"kind": "rear_to_front"}]
	return [effect.duplicate(true)] if not monster else []


static func converted(effects: Array, monster: bool = false) -> Array:
	var result: Array = []
	for effect in effects:
		result.append_array(convert_effect(effect, monster))
	return result


static func legacy_condition(condition: Dictionary) -> Dictionary:
	return {"kind": "adjacent", "trait": condition.get("tag", ""), "minimum": condition.get("min", 0)}


static func legacy_reaction(source: Dictionary) -> Dictionary:
	var t: Dictionary = source.trigger
	var conditions: Array = []
	match t.kind:
		"tag", "tag_position":
			conditions.append({"kind": "card_matches", "target": "event_card", "trait": t.tag})
			if t.kind == "tag_position":
				var points: Array = []
				for point in t.positions:
					points.append({"kind": "position", "target": "event_actor", "position": point})
				conditions.append({"kind": "any", "items": points})
		"damage": conditions.append({"kind": "metric_at_least", "metric": "hull_damage", "amount": t.threshold})
		"healed": conditions.append({"kind": "metric_at_least", "metric": "healed", "amount": t.threshold})
		"cost": conditions.append({"kind": "metric_at_least", "metric": "printed_cost", "amount": t.threshold})
	return {"id": source.id, "name": source.name, "category": "Disruption" if t.kind == "tag" else "Retaliation", "conditions": {"kind": "all", "items": conditions}, "effects": converted(source.effects, true)}


static func migrate(source: Dictionary) -> Dictionary:
	var doc: Dictionary = normalized(source)
	if doc.get("version") == 3:
		return doc
	doc = V2.migrate(doc)
	doc.version = 3
	doc["captains"] = []
	for card in doc.cards:
		card["type"] = "Attack" if card.tags.has("Attack") else ("Guard" if card.tags.has("Guard") else ("Manoeuvre" if card.tags.has("Movement") else "Support"))
		card["traits"] = card.tags.duplicate()
		var rules: Array = []
		var play := Rules.rule("on_play", converted(card.effects))
		play.id = "play"
		rules.append(play)
		for i in card.get("on_play", []).size():
			var r := Rules.rule("on_play", converted(card.on_play[i].effects))
			r.id = "conditional_" + str(i)
			r.conditions = legacy_condition(card.on_play[i].condition)
			rules.append(r)
		for i in card.get("modifiers", []).size():
			var m: Dictionary = card.modifiers[i]
			var r := Rules.rule("passive")
			r.id = "bonus_" + str(i)
			r.conditions = legacy_condition(m.condition)
			r.modifiers = [{"kind": {"damage": "attack_damage", "guard": "shield_amount", "healing": "repair_amount"}.get(m.stat, m.stat), "target": "adjacent_cards", "amount": m.amount, "card_type": "", "trait": m.get("tag", "")}]
			if r.modifiers[0].kind == "shield_amount":
				r.modifiers[0].kind = "shield_amount"
			rules.append(r)
		for t in card.get("triggers", []):
			var mapping := {"played": "adjacent_card_played", "damage": "hull_damaged", "guard": "shields_added", "repair": "repaired", "draw": "cards_drawn", "discard": "discarded", "movement": "moved"}
			var r := Rules.rule(mapping.get(t.event, t.event), converted(t.effects))
			r.id = t.id
			r.name = t.name
			r.trigger = {"kind": mapping.get(t.event, t.event), "subject": "adjacent", "minimum": t.threshold}
			r.conditions = {"kind": "all", "items": [legacy_condition(t.condition), {"kind": "card_matches", "target": "event_card", "trait": t.get("tag", "")}]}
			rules.append(r)
		card["rules"] = rules
		card["legacy_import"] = true
		for key in ["effects", "on_play", "modifiers", "triggers", "tags"]:
			card.erase(key)
	for ship in doc.ships:
		ship["armour"] = 0
		ship["weapon"] = {"damage": 4, "range": "Long"}
		ship["resource"] = {"name": "Charge", "capacity": 6, "rules": []}
		ship["rules"] = []
		ship["starter"] = ship.loadout[0].card
		ship["legacy_loadout"] = ship.loadout.duplicate(true)
		ship.erase("loadout")
		ship["levels"] = {"two": [], "three": []}
		for level in ["two", "three"]:
			for i in (2 if level == "two" else 3):
				var passive := Rules.rule("passive", [], "ship")
				passive.id = "passive"
				passive.modifiers = [{"kind": "armour", "target": "owner", "amount": 0}]
				ship.levels[level].append({"id": level + "_" + str(i), "name": "Imported " + level + " " + str(i + 1), "card": ship.starter, "rule": Rules.rule("turn_start", [{"kind": "gain_resource", "target": "owner", "amount": 0}], "ship"), "passive": passive, "blocks": "three_" + str(i)})
		var captain_id: String = "legacy_captain_" + ship.id
		var passive := Rules.rule("passive", [], "captain")
		passive.id = "passive"
		passive.modifiers = [{"kind": "armour", "target": "owner", "amount": 0}]
		doc.captains.append({"id": captain_id, "name": ship.name + " Captain", "tier": 1, "card": ship.starter, "passive": passive, "legacy_import": true})
	for monster in doc.leviathans:
		monster["armour"] = 0
		monster["weapon"] = {"damage": 4, "range": "Long"}
		monster["default_action"] = [{"kind": "attack", "target": "chosen_ally", "damage": 2, "hits": 1, "range": "Long"}]
		monster["stance_loadout"] = []
		for stance in monster.stances:
			var reactions: Array = []
			for reaction in stance.reactions:
				reactions.append(legacy_reaction(reaction))
			stance.reactions = reactions
			stance.effects = converted(stance.effects, true)
			monster.stance_loadout.append({"stance": stance.id, "count": 1})
	var old: Dictionary = doc.setup
	old["fleet"] = []
	for i in old.ships.size():
		old.fleet.append({"ship": old.ships[i], "captain": "legacy_captain_" + str(old.ships[i]), "level": 1, "level_2": "", "level_3": "", "position": old.positions[i]})
	old["enemies"] = [{"enemy": old.leviathan, "position": old.enemy_position}]
	old["mana_capacity"] = 1
	old["mana_reward"] = 1
	old["retain_threshold"] = 2
	old["basic_actions"] = basic_rules(doc)
	for key in ["ships", "positions", "leviathan", "enemy_position"]:
		old.erase(key)
	return doc


static func _integer(v: Variant, minimum: int = 0) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v == floor(v) and v >= minimum


static func _entries(doc: Dictionary, key: String, errors: Array) -> Dictionary:
	var result: Dictionary = {}
	if not doc.get(key) is Array:
		errors.append(key + " must be a list.")
		return result
	for entry in doc[key]:
		if not entry is Dictionary:
			errors.append(key + " entries must be objects.")
			continue
		var id: String = str(entry.get("id", ""))
		if not entry.get("id") is String or id.is_empty() or result.has(id):
			errors.append(key + ": IDs must be nonempty and unique.")
		if not entry.get("name") is String or str(entry.get("name", "")).strip_edges().is_empty():
			errors.append(key + " " + id + " needs a name.")
		result[id] = entry
	return result


static func _rules(list: Variant, where: String, errors: Array) -> void:
	if not list is Array:
		errors.append(where + " must be a rule list.")
		return
	var seen: Array = []
	for r in list:
		var context := "card" if where.begins_with("Card ") else ("captain" if where.begins_with("Captain ") else ("upgrade" if where.begins_with("Upgrade ") else "ship"))
		Rules.validate_rule(r, where, errors, context)
		if r is Dictionary:
			if seen.has(r.get("id", "")):
				errors.append(where + ": rule IDs must be unique within their source.")
			seen.append(r.get("id", ""))


static func validate(source: Variant) -> Array:
	if not source is Dictionary:
		return ["Content must be an object."]
	if source.get("version") == 1 or source.get("version") == 2:
		return V2.validate(source)
	if source.get("version") != 3:
		return ["Unsupported content version; expected 1, 2, or 3."]
	var errors: Array = []
	var ships := _entries(source, "ships", errors)
	var cards := _entries(source, "cards", errors)
	var captains := _entries(source, "captains", errors)
	var monsters := _entries(source, "leviathans", errors)
	for id in cards:
		var card: Dictionary = cards[id]
		if card.get("type") not in TYPES or not _integer(card.get("cost")) or not _integer(card.get("pays"), 1):
			errors.append("Card " + id + ": choose a primary type, nonnegative cost, and positive mana production.")
		if not card.get("traits") is Array or not card.get("positions") is Array or card.get("positions", []).is_empty():
			errors.append("Card " + id + ": needs traits and permitted acting positions.")
		else:
			for trait_name in card.traits:
				if not trait_name is String: errors.append("Card " + id + ": traits must be text.")
			for point in card.positions:
				if point not in Geometry.POSITIONS: errors.append("Card " + id + ": invalid acting position.")
		if not ships.has(card.get("owner", "")) and not captains.has(card.get("owner", "")):
			errors.append("Card " + id + ": owning ship/captain does not exist.")
		_rules(card.get("rules"), "Card " + id, errors)
		if card.get("rules") is Array and not card.get("legacy_import", false):
			if not card.rules.any(func(r): return r is Dictionary and r.get("trigger", {}) is Dictionary and r.get("trigger", {}).get("kind") == "on_play"):
				errors.append("Card " + id + ": include an On Play rule.")
			for r in card.rules:
				if r is Dictionary and r.get("zone", "circle") not in ["circle", "hand", "discard", "discard_top", "any"]:
					errors.append("Card " + id + ": use a card zone (circle, hand, discard, discard_top, any).")
		if not card.get("legacy_import", false) and (not card.get("rules") is Array or card.rules.size() < 1 or card.rules.size() > 3):
			errors.append("Card " + id + ": author 1–3 rule blocks including On Play.")
	for id in ships:
		var ship: Dictionary = ships[id]
		if not ship.get("role") is String or not ship.get("color") is String: errors.append("Ship " + id + ": configure role text and colour.")
		_validate_unit(ship, "Ship " + id, errors)
		if not ship.get("resource") is Dictionary or not _integer(ship.get("resource", {}).get("capacity"), 1) or (not ship.get("resource", {}).get("name") is String or str(ship.get("resource", {}).get("name", "")).is_empty()):
			errors.append("Ship " + id + ": name its resource and set a positive capacity.")
		if not ship.get("resource") is Dictionary: continue
		_rules(ship.get("resource", {}).get("rules", []), "Resource " + id, errors)
		_rules(ship.get("rules", []), "Ship " + id, errors)
		_check_card(cards, ship.get("starter", ""), id, "Ship " + id + " starter", errors)
		if ship.get("starter_two","")!="":
			_check_card(cards,ship.starter_two,id,"Ship "+id+" second starter",errors)
			if ship.starter_two==ship.starter:errors.append("Ship "+id+": choose two distinct starter designs.")
		if ship.has("legacy_loadout"):
			if not ship.legacy_loadout is Array: errors.append("Ship " + id + ": invalid legacy loadout.")
			else:
				for slot in ship.legacy_loadout:
					if not slot is Dictionary: errors.append("Invalid loadout entry."); continue
					_check_card(cards, slot.get("card", ""), id, "Ship " + id + " loadout", errors)
					if not _integer(slot.get("count"), 1): errors.append("Loadout counts must be positive integers.")
		var levels: Variant = ship.get("levels")
		if not levels is Dictionary or not levels.get("two") is Array or not levels.get("three") is Array:
			errors.append("Ship " + id + ": needs level-2 and level-3 packages.")
			continue
		if levels.two.size() != 2 or levels.three.size() != 3:
			errors.append("Ship " + id + ": author exactly two level-2 and three level-3 options.")
		var all_ids: Array = []
		for tier in ["two", "three"]:
			for package in levels[tier]:
				if not package is Dictionary: errors.append("Invalid upgrade package."); continue
				var package_id: String = str(package.get("id", ""))
				if package_id.is_empty() or all_ids.has(package_id): errors.append("Upgrade IDs must be nonempty and unique per ship.")
				all_ids.append(package_id)
				_check_card(cards, package.get("card", ""), id, "Upgrade " + package_id, errors)
				_rules([package.get("rule"), package.get("passive")], "Upgrade " + package_id, errors)
		var blocked: Array = []
		for package in levels.two:
			if not package is Dictionary: continue
			var block: String = package.get("blocks", "")
			if index_by_id(levels.three, block) < 0 or blocked.has(block):
				errors.append("Level-2 packages must block different valid level-3 choices.")
			blocked.append(block)
	for id in captains:
		var captain: Dictionary = captains[id]
		if not _integer(captain.get("tier"), 1) or captain.get("tier", 0) > 3:
			errors.append("Captain " + id + ": tier must be 1–3.")
		_check_card(cards, captain.get("card", ""), "" if captain.get("legacy_import", false) else id, "Captain " + id, errors)
		_rules([captain.get("passive")], "Captain " + id, errors)
	for id in monsters:
		var m: Dictionary = monsters[id]
		_validate_unit(m, "Enemy " + id, errors)
		if not m.get("stances") is Array or m.get("stances", []).is_empty():
			errors.append("Enemy " + id + ": needs stance cards.")
			continue
		var stance_ids: Array = []
		for stance in m.stances:
			if not stance is Dictionary: errors.append("Invalid stance card."); continue
			if str(stance.get("id", "")).is_empty() or stance_ids.has(stance.get("id", "")): errors.append("Stance IDs must be unique and nonempty.")
			stance_ids.append(stance.get("id", ""))
			if not stance.get("reactions") is Array: errors.append("Stance reactions must be a list.")
			else:
				var seen: Array = []
				for reaction in stance.reactions:
					if not reaction is Dictionary: errors.append("Invalid reaction."); continue
					if str(reaction.get("id", "")).is_empty() or seen.has(reaction.get("id", "")): errors.append("Reaction IDs must be unique.")
					seen.append(reaction.get("id", ""))
					Rules.validate_spec("condition", reaction.get("conditions"), "Reaction condition", errors)
					_validate_effects(reaction.get("effects"), "Reaction effects", errors)
			_validate_effects(stance.get("effects"), "Stance effects", errors)
		_validate_effects(m.get("default_action"), "Default action " + id, errors)
		if not m.get("stance_loadout") is Array or m.get("stance_loadout", []).is_empty():
			errors.append("Enemy " + id + ": needs a weighted stance loadout.")
		else:
			for slot in m.stance_loadout:
				if not slot is Dictionary: errors.append("Invalid stance loadout."); continue
				if not stance_ids.has(slot.get("stance", "")) or not _integer(slot.get("count"), 1):
					errors.append("Enemy " + id + ": stance loadout has an invalid reference/count.")
	_walk_references(source, "Content", func(kind, id, path):
		if (kind == "cards" and not cards.has(id)) or (kind == "units" and not ships.has(id) and not monsters.has(id)):
			errors.append(path + ": missing " + kind + " reference '" + id + "'."))
	if not errors.is_empty(): return errors
	_validate_setup(source, ships, captains, cards, monsters, errors)
	return errors


static func _validate_effects(list: Variant, where: String, errors: Array, depth: int = 0) -> void:
	if depth > 16: return
	if not list is Array: errors.append(where + " must be a list."); return
	for effect in list:
		Rules.validate_spec("effect", effect, where, errors)
		if effect is Dictionary:
			var desc := Rules.descriptor("effect", effect.get("kind", ""))
			if not desc.is_empty() and not desc.contexts.has("stance"): errors.append(where + ": " + desc.title + " cannot execute as enemy stance/default activity.")
			if effect.get("kind") == "explosion":
				for key in ["main_effects", "adjacent_effects"]: _validate_effects(effect.get(key, []), where + "." + key, errors, depth + 1)


static func _validate_unit(unit: Dictionary, where: String, errors: Array) -> void:
	if unit.has("visual_rig"): errors.append_array(preload("res://scripts/visuals/rig_schema.gd").validate(unit.visual_rig,where+" visual rig"))
	if not _integer(unit.get("hull"), 1) or not _integer(unit.get("armour")):
		errors.append(where + ": hull must be positive and armour nonnegative.")
	if not unit.get("weapon") is Dictionary or not _integer(unit.get("weapon", {}).get("damage")) or unit.get("weapon", {}).get("range") not in ["Short", "Long"]:
		errors.append(where + ": configure weapon damage and Short/Long range.")
	if unit.has("color") and (not unit.color is String or not Color.html_is_valid(unit.color)):
		errors.append(where + ": use a valid HTML colour.")


static func _check_card(cards: Dictionary, id: Variant, owner: String, where: String, errors: Array) -> void:
	if not id is String or not cards.has(id) or (owner != "" and cards[id].get("owner") != owner):
		errors.append(where + ": card '" + str(id) + "' must exist and belong to its contributing ship/captain.")


static func _validate_setup(doc: Dictionary, ships: Dictionary, captains: Dictionary, cards: Dictionary, monsters: Dictionary, errors: Array) -> void:
	if not doc.get("setup") is Dictionary: errors.append("Configure Battle Setup."); return
	var setup: Dictionary = doc.setup
	if not setup.get("fleet") is Array or setup.get("fleet", []).size() not in range(1, 5):
		errors.append("Choose one to four ships.")
		return
	var seen_ships: Array = []
	var seen_captains: Array = []
	var points: Array = []
	for slot in setup.fleet:
		if not slot is Dictionary: errors.append("Invalid fleet slot."); continue
		var ship_id: String = str(slot.get("ship", ""))
		var captain_id: String = str(slot.get("captain", ""))
		if not ships.has(ship_id) or seen_ships.has(ship_id) or not captains.has(captain_id) or seen_captains.has(captain_id):
			errors.append("Fleet ships and captains must exist and be distinct.")
		seen_ships.append(ship_id)
		seen_captains.append(captain_id)
		if slot.get("position") not in Geometry.POSITIONS or points.has(slot.get("position")):
			errors.append("Fleet positions must be valid and distinct.")
		points.append(slot.get("position"))
		if not _integer(slot.get("level"), 1) or slot.get("level", 0) > 3:
			errors.append("Ship levels must be 1–3.")
			continue
		if ships.has(ship_id) and ships[ship_id].get("levels") is Dictionary:
			var levels: Dictionary = ships[ship_id].levels
			var l2: int = index_by_id(levels.get("two", []), slot.get("level_2", ""))
			var l3: int = index_by_id(levels.get("three", []), slot.get("level_3", ""))
			if slot.get("level", 1) >= 2 and l2 < 0: errors.append("Choose a valid level-2 branch for " + ship_id + ".")
			if slot.get("level", 1) >= 3 and (l3 < 0 or (l2 >= 0 and levels.two[l2].blocks == slot.get("level_3"))):
				errors.append("Choose an unblocked level-3 branch for " + ship_id + ".")
	if not setup.get("enemies") is Array or setup.get("enemies", []).is_empty() or setup.get("enemies", []).size() > 4:
		errors.append("Choose 1–4 enemy instances.")
	else:
		points.clear()
		for slot in setup.enemies:
			if not slot is Dictionary: errors.append("Invalid enemy instance."); continue
			if not monsters.has(slot.get("enemy", "")) or slot.get("position") not in Geometry.POSITIONS or points.has(slot.get("position")):
				errors.append("Enemy instances need valid definitions and distinct positions.")
			points.append(slot.get("position"))
	for key in ["mana_capacity", "mana_reward"]:
		if not _integer(setup.get(key)): errors.append(key + " must be a nonnegative integer.")
	if not _integer(setup.get("retain_threshold"), 1): errors.append("Retain threshold must be positive.")
	var basic: Variant = setup.get("basic_actions")
	if not basic is Dictionary or not _integer(basic.get("repair"), 1) or not _integer(basic.get("revive_threshold"), 1):
		errors.append("Basic repair and revive threshold must be positive.")
	if not setup.get("fixed_hand") is bool or not setup.get("opening_hand") is Array:
		errors.append("Configure shuffled or fixed opening hand.")
	if not errors.is_empty(): return
	var compiled := compile(doc)
	var deck: Array = compiled.deck_keys
	if deck.is_empty(): errors.append("Fleet deck must contain at least one card.")
	if setup.fixed_hand:
		var opening_size: int = 4 + setup.fleet.size()
		if setup.opening_hand.size() != opening_size: errors.append("Fixed opening hand needs exactly %d cards." % opening_size)
		for id in setup.opening_hand:
			var position := deck.find(id)
			if position < 0: errors.append("Opening hand exceeds available copies of " + str(id) + ".")
			else: deck.remove_at(position)


static func repair_fleet_branch(slot: Dictionary, ship: Dictionary) -> void:
	if slot.level < 2:
		slot.level_2 = ""
		slot.level_3 = ""
		return
	if index_by_id(ship.levels.two, slot.get("level_2", "")) < 0: slot.level_2 = ship.levels.two[0].id
	if slot.level < 3:
		slot.level_3 = ""
		return
	var blocked: String = ship.levels.two[index_by_id(ship.levels.two, slot.level_2)].blocks
	if index_by_id(ship.levels.three, slot.get("level_3", "")) < 0 or slot.level_3 == blocked:
		for package in ship.levels.three:
			if package.id != blocked:
				slot.level_3 = package.id
				break


static func compile(source: Dictionary) -> Dictionary:
	var doc := migrate(source)
	var result := {"ships": [], "cards": {}, "enemies": [], "deck_keys": [], "positions": [], "setup": doc.setup.duplicate(true), "basic_actions": basic_rules(doc), "fixed_hand": doc.setup.fixed_hand, "opening_hand": doc.setup.opening_hand.duplicate()}
	for i in doc.setup.fleet.size():
		var entry: Dictionary = doc.setup.fleet[i]
		var ship := compile_ship(doc, entry)
		result.positions.append(entry.position)
		for slot in ship.loadout:
			var definition: Dictionary = doc.cards[index_by_id(doc.cards, slot.card)]
			result.cards[definition.id] = present_card(definition, i, ship.name)
			for copy in int(slot.count): result.deck_keys.append(definition.id)
		result.ships.append(ship)
	for i in doc.setup.enemies.size():
		var entry: Dictionary = doc.setup.enemies[i]
		var enemy: Dictionary = doc.leviathans[index_by_id(doc.leviathans, entry.enemy)].duplicate(true)
		enemy["position"] = Geometry.POSITIONS.find(entry.position)
		enemy["instance_id"] = enemy.id + "@" + str(i)
		result.enemies.append(enemy)
	result["monster"] = result.enemies[0] if not result.enemies.is_empty() else {}
	result["enemy_position"] = result.enemies[0].position if not result.enemies.is_empty() else 0
	result["stances"] = result.monster.get("stances", [])
	return result


static func compile_ship(doc: Dictionary, entry: Dictionary) -> Dictionary:
	var ship: Dictionary = doc.ships[index_by_id(doc.ships, entry.ship)].duplicate(true)
	var captain_index := index_by_id(doc.captains, entry.captain)
	var captain: Dictionary = doc.captains[captain_index].duplicate(true) if captain_index >= 0 else {"name": "Unassigned"}
	ship["captain"] = captain
	ship["level"] = entry.level
	ship["active_rules"] = ship.get("rules", []).duplicate(true) + ship.resource.get("rules", []).duplicate(true)
	if captain_index >= 0: ship.active_rules.append(captain.passive.duplicate(true))
	var loadout: Array = [{"card": ship.starter, "count": 2}]
	if ship.get("starter_two","")!="":loadout.append({"card":ship.starter_two,"count":2})
	if captain_index >= 0: loadout.append({"card":captain.card,"count":2})
	for level in ["two", "three"]:
		if int(entry.level) < (2 if level == "two" else 3): continue
		var package_index: int = index_by_id(ship.levels[level], entry.get("level_2" if level == "two" else "level_3", ""))
		if package_index < 0: continue
		var package: Dictionary = ship.levels[level][package_index]
		loadout.append({"card": package.card, "count": 2})
		ship.active_rules.append(package.rule.duplicate(true))
		ship.active_rules.append(package.passive.duplicate(true))
	if ship.has("legacy_loadout"): loadout = ship.legacy_loadout.duplicate(true)
	ship["loadout"] = loadout
	return ship


static func present_card(source: Dictionary, owner: int = 0, owner_name: String = "") -> Dictionary:
	var card := source.duplicate(true)
	card["owner"] = owner
	card["allowed_positions"] = source.get("positions", Geometry.POSITIONS).duplicate()
	card["ranks"] = ", ".join(card.allowed_positions)
	card["tag_ids"] = source.get("traits", []).duplicate()
	if not card.tag_ids.has(source.get("type", "")): card.tag_ids.append(source.get("type", ""))
	card["tags"] = str(source.get("type", "")) + (" · " + " · ".join(source.get("traits", [])) if not source.get("traits", []).is_empty() else "")
	var lines: Array = []
	for r in source.get("rules", []): lines.append(Rules.rule_text(r, owner_name))
	card["effect"] = "\n".join(lines)
	return card


static func effects_text(effects: Array, owner_name: String = "") -> String:
	var parts: Array = []
	for effect in effects: parts.append(Rules.text("effect", effect, owner_name))
	return " → ".join(parts)


static func references(doc: Dictionary, kind: String, id: String) -> Array:
	var result: Array = []
	for i in doc.setup.get("fleet", []).size():
		if doc.setup.fleet[i].get("ship" if kind == "ships" else "captain", "") == id and kind in ["ships", "captains"]:
			result.append("Battle Setup fleet slot " + str(i + 1))
	for i in doc.setup.get("enemies", []).size():
		if kind == "leviathans" and doc.setup.enemies[i].enemy == id: result.append("Battle Setup enemy slot " + str(i + 1))
	if kind == "cards":
		for ship in doc.ships:
			if ship.starter == id: result.append(ship.name + " starter pair")
			if ship.get("starter_two","")==id:result.append(ship.name+" second starter pair")
			for tier in ["two", "three"]:
				for package in ship.levels[tier]:
					if package.card == id: result.append(ship.name + " / " + package.name)
			for slot in ship.get("legacy_loadout", []):
				if slot.card == id: result.append(ship.name + " imported loadout")
		for captain in doc.captains:
			if captain.card == id: result.append(captain.name + " pair")
		if doc.setup.get("opening_hand", []).has(id): result.append("Battle Setup fixed opening hand")
	if kind in ["ships", "captains"]:
		for card in doc.cards:
			if card.owner == id: result.append("Card owner: " + card.name)
	_walk_references(doc, "Content", func(reference_kind, reference_id, path):
		if reference_id == id and ((reference_kind == "cards" and kind == "cards") or (reference_kind == "units" and kind in ["ships", "leviathans"])): result.append(path))
	return result


static func _walk_references(value: Variant, path: String, visitor: Callable, depth: int = 0) -> void:
	if depth > 40: return
	if value is Dictionary:
		var fields := Rules.reference_fields(value)
		for key in fields:
			if value.get(key, "") is String and value.get(key, "") != "": visitor.call(fields[key], value[key], path + "." + key)
		for key in value: _walk_references(value[key], path + "." + str(key), visitor, depth + 1)
	elif value is Array:
		for i in value.size(): _walk_references(value[i], path + "[" + str(i) + "]", visitor, depth + 1)


static func read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Cannot read " + path + ": " + error_string(FileAccess.get_open_error())}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Malformed JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	var errors := validate(parser.data)
	if not errors.is_empty(): return {"ok": false, "error": "\n".join(errors)}
	return {"ok": true, "document": migrate(parser.data), "migrated": parser.data.version != 3}


static func save_document(path: String, source: Dictionary) -> String:
	var errors := validate(source)
	if not errors.is_empty(): return "\n".join(errors)
	var doc := migrate(source)
	errors = validate(doc)
	if not errors.is_empty(): return "\n".join(errors)
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Cannot write " + path + ": " + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(doc, "\t", false) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot save content: " + error_string(error)
	return ""

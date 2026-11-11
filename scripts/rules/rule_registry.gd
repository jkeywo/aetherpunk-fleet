extends RefCounted
## Code-owned chunks. Data supplies only registered IDs and typed parameters.
static var catalog: Dictionary = {}
const TYPES := ["Attack", "Guard", "Manoeuvre", "Support"]
const LIMITS := ["once_per_action", "once_per_turn", "once_per_hit"]
const UNIT_TARGETS := ["owner", "event_actor", "event_target", "chosen_ally", "chosen_enemy", "all_allies", "all_enemies", "fleet_front", "fleet_rear", "fleet_ends", "fleet_middle"]
const TARGETS := ["owner", "event_actor", "event_target", "chosen_ally", "chosen_enemy", "all_allies", "all_enemies", "source_slot", "chosen_slot", "event_slot", "self_card", "chosen_circle_card", "adjacent_cards", "chosen_stance", "chosen_reaction"]
const ZONES := ["circle", "discard_top", "hand", "discard", "ship", "captain", "stance", "any"]


static func field(type: String, initial: Variant, minimum: int = 0, choices: Array = []) -> Dictionary:
	return {"type": type, "default": initial, "min": minimum, "choices": choices}


static func add(category: String, id: String, title: String, schema: Dictionary, handler: Callable, targets: Array = [], zones: Array = []) -> void:
	catalog[category][id] = {"id": id, "title": title, "fields": schema, "handler": handler, "targets": targets, "zones": zones, "contexts": ["card", "ship", "captain", "stance", "upgrade"]}


static func ensure() -> void:
	if not catalog.is_empty():
		return
	for category in ["trigger", "condition", "effect", "modifier", "cost", "value"]:
		catalog[category] = {}
	for event in ["on_play", "adjacent_card_played", "attack_started", "hit_resolved", "hull_damaged", "armour_absorbed", "cover_absorbed", "shields_absorbed", "moved", "repaired", "revived", "discarded", "reaction_resolved", "turn_start", "turn_end", "resource_changed", "shields_added", "cards_drawn"]:
		add("trigger", event, event.replace("_", " ").capitalize(), {"subject": field("enum", "owner", 0, ["owner", "actor", "target", "self_card", "adjacent", "allied", "enemy", "any"]), "card_type": field("enum", "", 0, [""] + TYPES), "reason": field("enum", "", 0, ["", "mana", "basic", "effect", "refresh"]), "minimum": field("int", 1)}, _trigger.bind(event), [], ZONES)
	add("trigger", "passive", "While active", {"subject": field("enum", "owner", 0, ["owner", "self_card", "any"])}, _passive, [], ZONES)
	add("condition", "always", "Always", {}, _always)
	add("condition", "reaction_trigger", "Common reaction trigger", {"family": field("enum", "card_type", 0, ["card_type", "position", "damaged", "healed"]), "card_type": field("enum", "Attack", 0, TYPES), "position": field("enum", "front", 0, ["front", "upper", "lower", "rear"])}, _common_reaction)
	add("condition", "all", "All conditions", {"items": field("conditions", [])}, _all)
	add("condition", "any", "Any condition", {"items": field("conditions", [])}, _any)
	add("condition", "not", "Not", {"condition": field("condition", {"kind": "always"})}, _not)
	add("condition", "adjacent", "Adjacent card matches", {"card_type": field("enum", "", 0, [""] + TYPES), "trait": field("string", ""), "card_id": field("string", ""), "minimum": field("int", 1)}, _adjacent, ["self_card"])
	for kind in ["resource_at_least", "health_at_most", "health_at_least", "missing_health_at_least", "shields_at_least", "armour_at_least"]:
		add("condition", kind, kind.replace("_", " ").capitalize(), {"target": field("target", "owner", 0, UNIT_TARGETS), "amount": field("value", 1)}, _unit_condition.bind(kind), UNIT_TARGETS)
	add("condition", "card_matches", "Card matches", {"target": field("enum", "event_card", 0, ["self_card", "event_card"]), "card_type": field("enum", "", 0, [""] + TYPES), "trait": field("string", ""), "card_id": field("string", "")}, _card_condition)
	add("condition", "position", "Unit occupies position", {"target": field("target", "owner", 0, UNIT_TARGETS), "position": field("enum", "front", 0, ["front", "upper", "lower", "rear"])}, _position, UNIT_TARGETS)
	add("condition", "identity", "Unit identity matches", {"target": field("target", "owner", 0, UNIT_TARGETS), "id": field("string", "")}, _identity, UNIT_TARGETS)
	add("condition", "status", "Unit status", {"target": field("target", "chosen_enemy", 0, UNIT_TARGETS), "status": field("enum", "alive", 0, ["alive", "defeated", "shielded", "stunned"])}, _status, UNIT_TARGETS)
	add("condition", "hand_count", "Hand count at least", {"amount": field("value", 2)}, _hand_count)
	add("condition", "top_discard", "This is the top discard", {}, _top_discard)
	add("condition", "reaction_category", "Reaction category matches", {"category": field("string", "Retaliation")}, _reaction_category)
	add("condition", "persistence_at_least", "Persistence at least", {"target": field("target", "self_card", 0, ["self_card", "chosen_circle_card"]), "amount": field("value", 1)}, _persistence)
	add("condition", "metric_at_least", "Event metric at least", {"metric": field("enum", "hull_damage", 0, ["amount", "hull_damage", "cover_absorbed", "armour_absorbed", "shields_absorbed", "printed_cost", "healed"]), "amount": field("value", 1)}, _metric)
	add("effect", "attack", "Attack", {"target": field("target", "chosen_enemy", 0, UNIT_TARGETS), "damage": field("value", {"kind": "weapon_damage", "target": "owner"}), "hits": field("value", 1, 1), "range": field("enum", "weapon", 0, ["weapon", "Short", "Long"])}, _attack, UNIT_TARGETS)
	for kind in ["add_shields", "repair", "recovery", "gain_resource", "spend_resource"]:
		add("effect", kind, kind.replace("_", " ").capitalize(), {"target": field("target", "owner", 0, UNIT_TARGETS), "amount": field("value", 2)}, _unit_effect.bind(kind), UNIT_TARGETS)
	add("effect", "add_cover", "Add slot cover", {"target": field("target", "source_slot", 0, ["source_slot", "chosen_slot", "event_slot"]), "amount": field("value", 2)}, _cover, ["source_slot", "chosen_slot", "event_slot"])
	add("effect", "move", "Move or swap with adjacent position", {"target": field("target", "owner", 0, ["owner", "chosen_ally"]), "destination": field("enum", "chosen_slot", 0, ["chosen_slot", "front", "upper", "lower", "rear"]), "guard": field("value", 0)}, _move)
	add("effect", "swap", "Swap chosen adjacent ships", {"first": field("target", "owner", 0, ["owner", "chosen_ally", "chosen_pair_first"]), "second": field("target", "chosen_ally", 0, ["chosen_ally", "event_actor", "event_target", "chosen_pair_second"]), "pair_choice": field("enum", "No", 0, ["No", "Yes"]), "guard": field("value", 0)}, _swap)
	add("effect", "swap_ends", "Swap frontmost and rearmost allies", {"fallback_damage": field("value", 0)}, _swap_ends)
	add("effect", "rear_to_front", "Move rearmost ally to front", {}, _rear_to_front)
	add("effect", "draw", "Draw cards", {"amount": field("value", 1)}, _draw)
	add("effect", "discard", "Discard cards from hand", {"amount": field("value", 1)}, _discard)
	add("effect", "scry", "Scry and choose cards", {"look": field("value", 3, 1), "take": field("value", 1)}, _scry)
	add("effect", "stun", "Suppress a visible reaction", {"target": field("target", "chosen_reaction", 0, ["chosen_reaction", "event_reaction"])}, _stun)
	add("effect", "confuse", "Discard and replace a visible stance", {"target": field("target", "chosen_stance", 0, ["chosen_stance", "event_stance"])}, _confuse)
	add("effect", "add_persistence", "Add persistence tokens", {"target": field("target", "self_card", 0, ["self_card", "chosen_circle_card", "adjacent_cards"]), "amount": field("value", 1)}, _add_persistence)
	add("effect", "gain_mana", "Gain temporary mana", {"amount": field("value", 1)}, _gain_mana)
	for stat in ["weapon_damage", "weapon_range", "armour", "max_hull", "resource_capacity", "mana_capacity", "mana_generation", "cost", "repair_amount", "hit_count", "attack_damage", "per_hit_damage", "shield_amount"]:
		add("modifier", stat, stat.replace("_", " ").capitalize(), {"target": field("target", "owner", 0, UNIT_TARGETS + ["adjacent_cards", "self_card", "all_cards", "fleet"]), "amount": field("value", 1), "range": field("enum", "Long", 0, ["Short", "Long"]), "card_type": field("enum", "", 0, [""] + TYPES), "trait": field("string", "")}, _modifier, UNIT_TARGETS + ["adjacent_cards", "self_card", "all_cards", "fleet"])
	add("cost", "ship_resource", "Spend personal resource", {"target": field("target", "owner", 0, ["owner"]), "amount": field("value", 2)}, _resource_cost, ["owner"])
	add("value", "constant", "Constant", {"amount": field("int", 1)}, _constant)
	add("value", "weapon_damage", "Weapon damage", {"target": field("target", "owner", 0, UNIT_TARGETS)}, _weapon_value, UNIT_TARGETS)
	add("value", "resource_count", "Personal resource count", {"target": field("target", "owner", 0, UNIT_TARGETS)}, _resource_value, UNIT_TARGETS)
	add("value", "missing_hp", "Missing hull", {"target": field("target", "chosen_ally", 0, UNIT_TARGETS)}, _missing_value, UNIT_TARGETS)
	add("value", "adjacent_count", "Matching adjacent cards", {"card_type": field("enum", "", 0, [""] + TYPES), "trait": field("string", ""), "card_id": field("string", "")}, _adjacent_value)
	for operation in ["sum", "product", "min", "max"]:
		add("value", operation, operation.capitalize(), {"values": field("values", [1, 1])}, _arithmetic.bind(operation))

	# Only expose fields that can affect this chunk.
	for id in catalog.modifier:
		var d: Dictionary = catalog.modifier[id]
		if id == "weapon_range":
			d.fields.erase("amount")
		else:
			d.fields.erase("range")
		if id in ["weapon_range", "weapon_damage", "armour", "max_hull", "resource_capacity"]:
			d.fields.target = field("target", "owner", 0, UNIT_TARGETS)
		if id in ["mana_capacity", "mana_generation"]:
			d.fields.target = field("target", "fleet", 0, ["fleet"])
		elif id == "cost":
			d.fields.target = field("target", "self_card", 0, ["adjacent_cards", "self_card", "all_cards"])
	for id in catalog.effect:
		var d: Dictionary = catalog.effect[id]
		if d.fields.has("target") and d.fields.target.choices.has("all_allies"):
			d.fields["exclude_owner"] = field("enum", "No", 0, ["No", "Yes"])
			d.fields["filter"] = field("condition", {"kind": "always"})

	for id in catalog.effect:
		if id not in ["attack", "add_shields", "repair", "add_cover", "swap_ends", "rear_to_front"]:
			catalog.effect[id].contexts = ["card", "ship", "captain", "upgrade"]

	for category in catalog:
		for id in catalog[category]:
			for key in catalog[category][id].fields:
				if key == "card_id": catalog[category][id].fields[key]["reference"] = "cards"
				if id == "identity" and key == "id": catalog[category][id].fields[key]["reference"] = "units"


static func reference_fields(spec: Dictionary) -> Dictionary:
	ensure()
	var result: Dictionary = {}
	for category in catalog:
		for key in catalog[category].get(spec.get("kind", ""), {}).get("fields", {}):
			var meta: Dictionary = catalog[category][spec.kind].fields[key]
			if meta.has("reference"): result[key] = meta.reference
	return result


static func descriptor(category: String, kind: String) -> Dictionary:
	ensure()
	return catalog.get(category, {}).get(kind, {})


static func ids(category: String) -> Array:
	ensure()
	return catalog.get(category, {}).keys()


static func fresh(category: String, kind: String) -> Dictionary:
	var result := {"kind": kind}
	for key in descriptor(category, kind).get("fields", {}):
		result[key] = descriptor(category, kind).fields[key].default.duplicate(true) if descriptor(category, kind).fields[key].default is Dictionary or descriptor(category, kind).fields[key].default is Array else descriptor(category, kind).fields[key].default
	return result


static func rule(event: String = "on_play", effects: Array = [], zone: String = "circle") -> Dictionary:
	return {"id": "rule", "trigger": {"kind": event, "subject": "self_card"}, "conditions": {"kind": "always"}, "costs": [], "effects": effects.duplicate(true), "modifiers": [], "limit": "once_per_action", "optional": false, "zone": zone}


static func condition(value: Variant, ctx: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for group in ["all", "any", "not"]:
		if value.has(group):
			return condition({"kind": group, "condition": value[group]} if group == "not" else {"kind": group, "items": value[group]}, ctx)
	var desc := descriptor("condition", value.get("kind", "always"))
	return not desc.is_empty() and bool(desc.handler.call(value, ctx))


static func number(value: Variant, ctx: Dictionary, depth: int = 0) -> int:
	if depth > 16:
		return 0
	if value is int or value is float:
		return maxi(0, int(value))
	if not value is Dictionary:
		return 0
	var desc := descriptor("value", value.get("kind", ""))
	var nested := ctx.duplicate()
	nested["value_depth"] = depth + 1
	return 0 if desc.is_empty() else clampi(int(desc.handler.call(value, nested)), 0, 99999)


static func execute(spec: Dictionary, ctx: Dictionary) -> bool:
	var desc := descriptor("effect", spec.get("kind", ""))
	return false if desc.is_empty() else bool(desc.handler.call(spec, ctx))


static func matches(spec: Dictionary, ctx: Dictionary) -> bool:
	var desc := descriptor("trigger", spec.get("kind", ""))
	return not desc.is_empty() and bool(desc.handler.call(spec, ctx))


static func validate_spec(category: String, spec: Variant, where: String, errors: Array, depth: int = 0) -> void:
	if depth > 16:
		errors.append(where + ": nesting exceeds 16 levels.")
		return
	if category == "value" and (spec is int or spec is float):
		if not is_finite(float(spec)) or spec < 0 or spec != floor(spec):
			errors.append(where + ": needs a nonnegative integer.")
		return
	if category == "condition" and spec is Dictionary:
		for group in ["all", "any", "not"]:
			if spec.has(group):
				validate_spec(category, {"kind": group, "condition": spec[group]} if group == "not" else {"kind": group, "items": spec[group]}, where, errors, depth + 1)
				return
	if not spec is Dictionary:
		errors.append(where + ": needs a " + category + " object.")
		return
	var desc := descriptor(category, spec.get("kind", ""))
	if desc.is_empty():
		errors.append(where + ": unknown " + category + " '" + str(spec.get("kind", "")) + "'.")
		return
	for key in spec:
		if key != "kind" and not desc.fields.has(key):
			errors.append(where + ": unsupported field '" + key + "'.")
	for key in desc.fields:
		var meta: Dictionary = desc.fields[key]
		var value: Variant = spec.get(key, meta.default)
		match meta.type:
			"int":
				if not (value is int or value is float) or not is_finite(float(value)) or value < meta.min or value != floor(value):
					errors.append(where + "." + key + ": needs an integer ≥ " + str(meta.min) + ".")
			"enum", "target":
				if not meta.choices.has(value):
					errors.append(where + "." + key + ": choose one of " + ", ".join(meta.choices) + ".")
			"string":
				if not value is String:
					errors.append(where + "." + key + ": needs text.")
			"value", "condition":
				validate_spec(meta.type, value, where + "." + key, errors, depth + 1)
			"conditions", "values":
				if not value is Array:
					errors.append(where + "." + key + ": needs a list.")
				else:
					for i in value.size():
						validate_spec("condition" if meta.type == "conditions" else "value", value[i], where + "." + key + "[" + str(i) + "]", errors, depth + 1)
	if category == "effect" and spec.kind == "scry" and spec.get("look", 3) is int and spec.get("take", 1) is int and spec.get("take", 1) > spec.get("look", 3):
		errors.append(where + ": scry take cannot exceed look.")
	if category == "effect" and spec.kind == "attack" and spec.get("hits", 1) is int and spec.get("hits", 1) < 1:
		errors.append(where + ": an attack needs at least one hit.")


static func validate_rule(value: Variant, where: String, errors: Array, context: String = "") -> void:
	if not value is Dictionary:
		errors.append(where + ": needs a rule object.")
		return
	if str(value.get("id", "")).is_empty():
		errors.append(where + ": needs a stable rule ID.")
	validate_spec("trigger", value.get("trigger"), where + ".trigger", errors)
	validate_spec("condition", value.get("conditions", {"kind": "always"}), where + ".conditions", errors)
	if value.get("limit", "once_per_action") not in LIMITS or value.get("zone", "circle") not in ZONES or not value.get("optional", false) is bool:
		errors.append(where + ": invalid limit, zone, or optional flag.")
	for category in ["effects", "costs", "modifiers"]:
		if not value.get(category, []) is Array:
			errors.append(where + "." + category + ": needs a list.")
			continue
		for i in value.get(category, []).size():
			validate_spec({"effects": "effect", "costs": "cost", "modifiers": "modifier"}[category], value[category][i], where + "." + category + "[" + str(i) + "]", errors)
	if not value.get("trigger", {}) is Dictionary or not value.get("effects", []) is Array or not value.get("modifiers", []) is Array or not value.get("costs", []) is Array: return

	if context != "":
		var zones: Array = ["circle", "hand", "discard", "discard_top", "any"] if context == "card" else ["ship", "captain", "any"]
		if not zones.has(value.get("zone", "circle")): errors.append(where + ": zone is incompatible with " + context + ".")
		for effect in value.get("effects", []):
			if not effect is Dictionary: continue
			var desc := descriptor("effect", effect.get("kind", ""))
			if not desc.is_empty() and not desc.contexts.has(context): errors.append(where + ": " + desc.title + " is incompatible with " + context + ".")
			var root_choice: bool = value.get("optional", false) or (context == "card" and value.trigger.get("kind") == "on_play")
			if not root_choice:
				for field_name in ["target", "first", "second", "destination"]:
					if str(effect.get(field_name, "")).begins_with("chosen_") and effect.get(field_name) != "chosen_enemy":
						errors.append(where + ": automatic responses need owner/event/group targets; chosen targets belong to pending On Play rules or optional boosts.")
						break
	if value.get("effects", []).is_empty() and value.get("modifiers", []).is_empty():
		errors.append(where + ": add an effect or modifier.")
	if value.get("trigger", {}).get("kind") == "passive" and not value.get("effects", []).is_empty():
		errors.append(where + ": passive rules use modifiers, not repeated effects.")
	if value.get("trigger", {}).get("kind") != "passive" and not value.get("modifiers", []).is_empty():
		errors.append(where + ": modifiers require a passive rule.")
	if value.get("optional", false) and value.get("trigger", {}).get("kind") not in ["on_play", "moved", "repaired", "attack_started"]:
		errors.append(where + ": optional boosts must belong to a pending root play, move, repair, or attack.")
	if value.get("trigger", {}).get("kind") == "on_play" and not value.get("costs", []).is_empty() and value.get("optional", false):
		pass


static func _target_text(selector: String) -> String:
	return {"owner": "{{rule_owner}}", "event_actor": "that card's owner", "event_target": "that target", "chosen_ally": "chosen ally", "chosen_enemy": "chosen enemy", "all_allies": "all player ships", "all_enemies": "all enemies", "self_card": "this card", "adjacent_cards": "adjacent cards", "source_slot": "this slot", "fleet": "the fleet"}.get(selector, selector.replace("_", " "))


static func _named_text(value: String, owner_name: String) -> String:
	return value.replace("{{rule_owner}}", owner_name if not owner_name.is_empty() else "this ship")


static func text(category: String, spec: Variant, owner_name: String = "") -> String:
	return _named_text(_raw_text(category, spec), owner_name)


static func _raw_text(category: String, spec: Variant) -> String:
	if spec is int or spec is float:
		return str(int(spec))
	if not spec is Dictionary:
		return "?"
	for group in ["all", "any", "not"]:
		if category == "condition" and spec.has(group):
			return _raw_text(category, {"kind": group, "condition": spec[group]} if group == "not" else {"kind": group, "items": spec[group]})
	var desc := descriptor(category, spec.get("kind", ""))
	var formatted := _formatted(category, spec)
	if formatted != "":
		if spec.has("filter") and spec.filter != {"kind": "always"}: formatted += " where " + _raw_text("condition", spec.filter)
		if spec.get("exclude_owner", "No") == "Yes": formatted += " (other ships only)"
		if category == "trigger":
			if spec.get("card_type", "") != "" and spec.kind != "adjacent_card_played": formatted += " [" + spec.card_type + "]"
			if spec.get("minimum", 1) > 1: formatted += " (event amount ≥ " + str(spec.minimum) + ")"
			if spec.get("subject", "owner") in ["actor", "target", "allied", "enemy", "any"]: formatted += " / " + str(spec.subject).replace("_", " ")
		if category == "modifier" and spec.get("trait", "") != "": formatted += " with " + spec.trait
		return formatted
	if desc.is_empty():
		return "Unknown " + category + ": " + str(spec.get("kind", "?"))
	var values: Array = []
	for key in desc.fields:
		var meta: Dictionary = desc.fields[key]
		var value: Variant = spec.get(key, meta.default)
		if (value is String and value.is_empty()) or (value is Array and value.is_empty()):
			continue
		if meta.type in ["value", "condition"]:
			values.append(key.replace("_", " ") + " " + _raw_text(meta.type, value))
		elif meta.type in ["values", "conditions"]:
			var parts: Array = []
			for child in value:
				parts.append(_raw_text("value" if meta.type == "values" else "condition", child))
			values.append(" / ".join(parts))
		else:
			values.append(key.replace("_", " ") + " " + (_target_text(str(value)) if meta.type == "target" else str(value)))
	return str(desc.title) + (" (" + "; ".join(values) + ")" if not values.is_empty() else "")


static func rule_text(spec: Dictionary, owner_name: String = "") -> String:
	var lines: Array = [_raw_text("trigger", spec.get("trigger", {}))]
	if spec.get("conditions", {"kind": "always"}) != {"kind": "always"}:
		lines.append("if " + _raw_text("condition", spec.conditions))
	for cost in spec.get("costs", []):
		lines.append(_raw_text("cost", cost))
	var result := " · ".join(lines) + ": "
	var effects: Array = []
	for effect in spec.get("effects", []):
		effects.append(_raw_text("effect", effect))
	for modifier in spec.get("modifiers", []):
		effects.append(_raw_text("modifier", modifier))
	result += " → ".join(effects)
	if spec.get("optional", false):
		result = "Optional boost · " + result
	if spec.get("trigger", {}).get("kind") != "passive":
		result += " [" + str(spec.get("limit", "once_per_action")).replace("_", " ") + "]"
	if spec.get("zone", "circle") == "discard_top":
		result += " [top of discard]"
	return _named_text(result, owner_name)


static func _trigger(p: Dictionary, c: Dictionary, kind: String) -> bool:
	var event: Dictionary = c.get("event", {})
	var actual: String = event.get("kind", "")
	if kind == "adjacent_card_played":
		if actual != "on_play" or int(c.get("uid", -1)) < 0 or int(event.get("uid", -1)) < 0:
			return false
		if not c.state.are_adjacent_cards(c.uid, event.uid):
			return false
	elif actual != kind:
		return false
	var subject: String = p.get("subject", "owner")
	if kind not in ["adjacent_card_played", "turn_start", "turn_end"]:
		match subject:
			"self_card":
				if event.get("uid", -2) != c.get("uid", -1): return false
			"owner":
				var field_name: String = "target" if kind in ["hull_damaged", "armour_absorbed", "cover_absorbed", "shields_absorbed", "revived", "resource_changed"] else "actor"
				if event.get(field_name, -999) != c.owner: return false
			"actor":
				if event.get("actor", -999) != c.owner: return false
			"target":
				if event.get("target", -999) != c.owner: return false
			"adjacent":
				if not c.state.are_adjacent_cards(c.get("uid", -1), event.get("uid", -1)): return false
			"allied":
				if int(event.get("actor", -1)) < 0: return false
			"enemy":
				if int(event.get("actor", 0)) >= 0: return false
	if p.get("card_type", "") != "" and not _matches_card(event.get("card", {}), p):
		return false
	if p.get("reason", "") != "" and event.get("reason", "") != p.reason:
		return false
	return int(event.get("amount", 1)) >= int(p.get("minimum", 1))


static func _passive(_p: Dictionary, _c: Dictionary) -> bool: return false
static func _always(_p: Dictionary, _c: Dictionary) -> bool: return true
static func _all(p: Dictionary, c: Dictionary) -> bool:
	for item in p.get("items", []):
		if not condition(item, c): return false
	return true
static func _any(p: Dictionary, c: Dictionary) -> bool:
	for item in p.get("items", []):
		if condition(item, c): return true
	return false
static func _not(p: Dictionary, c: Dictionary) -> bool: return not condition(p.get("condition", {}), c)
static func _matches_card(card: Dictionary, p: Dictionary) -> bool:
	return (p.get("card_type", "") == "" or card.get("type", "") == p.card_type) and (p.get("trait", "") == "" or (card.get("traits", []).has(p.trait) or card.get("type", "") == p.trait or (p.trait == "Movement" and card.get("type", "") == "Manoeuvre"))) and (p.get("card_id", "") == "" or card.get("id", "") == p.card_id)
static func _adjacent(p: Dictionary, c: Dictionary) -> bool: return _adjacent_value(p, c) >= int(p.get("minimum", 1))
static func _adjacent_value(p: Dictionary, c: Dictionary) -> int:
	var count := 0
	for card in c.state.context_neighbours(c):
		if _matches_card(card, p): count += 1
	return count
static func _card_condition(p: Dictionary, c: Dictionary) -> bool:
	return _matches_card(c.state.card(c.uid) if p.get("target", "event_card") == "self_card" and int(c.get("uid", -1)) >= 0 else c.get("event", {}).get("card", {}), p)
static func _unit_condition(p: Dictionary, c: Dictionary, kind: String) -> bool:
	var units: Array = c.state.targets(p.get("target", "owner"), c)
	var amount := number(p.get("amount", 1), c)
	for id in units:
		var unit: Dictionary = c.state.unit(id)
		if unit.is_empty(): continue
		match kind:
			"resource_at_least":
				if int(unit.get("resource", 0)) >= amount: return true
			"health_at_most":
				if int(unit.hull) <= amount: return true
			"health_at_least":
				if int(unit.hull) >= amount: return true
			"missing_health_at_least":
				if int(unit.max_hull) - int(unit.hull) >= amount: return true
			"shields_at_least":
				if int(unit.get("guard", 0)) >= amount: return true
			"armour_at_least":
				if c.state.stat(id, "armour", c) >= amount: return true
	return false
static func _position(p: Dictionary, c: Dictionary) -> bool:
	for id in c.state.targets(p.get("target", "owner"), c):
		var position: int = c.get("predicted_formation", c.state.formation).find(id) if id >= 0 else c.state.position_of(id)
		if position == ["front", "upper", "lower", "rear"].find(p.get("position", "front")): return true
	return false
static func _identity(p: Dictionary, c: Dictionary) -> bool:
	for id in c.state.targets(p.get("target", "owner"), c):
		if c.state.unit(id).get("id", "") == p.get("id", ""): return true
	return false
static func _status(p: Dictionary, c: Dictionary) -> bool:
	for id in c.state.targets(p.get("target", "chosen_enemy"), c):
		var u: Dictionary = c.state.unit(id)
		match p.get("status", "alive"):
			"alive":
				if u.get("hull", 0) > 0: return true
			"defeated":
				if u.get("hull", 0) <= 0: return true
			"shielded":
				if u.get("guard", 0) > 0: return true
			"stunned":
				if c.state.unit_stunned(id): return true
	return false
static func _hand_count(p: Dictionary, c: Dictionary) -> bool: return c.state.hand_count() >= number(p.get("amount", 2), c)
static func _top_discard(_p: Dictionary, c: Dictionary) -> bool: return not c.state.discard.is_empty() and c.state.discard.back() == c.get("uid", -1)
static func _reaction_category(p: Dictionary, c: Dictionary) -> bool: return c.get("event", {}).get("category", "") == p.get("category", "")
static func _persistence(p: Dictionary, c: Dictionary) -> bool:
	for uid in c.state.targets(p.get("target", "self_card"), c):
		if c.state.persistence.get(uid, 0) >= number(p.get("amount", 1), c): return true
	return false
static func _metric(p: Dictionary, c: Dictionary) -> bool: return int(c.get("event", {}).get(p.get("metric", "hull_damage"), 0)) >= number(p.get("amount", 1), c)
static func _attack(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_attack(p, c)
static func _unit_effect(p: Dictionary, c: Dictionary, kind: String) -> bool: return c.state.effect_unit(kind, p, c)
static func _cover(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_cover(p, c)
static func _move(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_move(p, c)
static func _swap(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_swap(p, c)
static func _swap_ends(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_swap_ends(p, c)
static func _rear_to_front(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_rear_front(p, c)
static func _draw(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_draw(p, c)
static func _discard(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_discard(p, c)
static func _scry(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_scry(p, c)
static func _stun(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_stun(p, c)
static func _confuse(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_confuse(p, c)
static func _add_persistence(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_persistence(p, c)
static func _gain_mana(p: Dictionary, c: Dictionary) -> bool: return c.state.effect_mana(p, c)
static func _modifier(_p: Dictionary, _c: Dictionary) -> bool: return true
static func _resource_cost(p: Dictionary, c: Dictionary) -> bool: return c.state.pay_resource(p, c)
static func _constant(p: Dictionary, _c: Dictionary) -> int: return int(p.get("amount", 1))
static func _weapon_value(p: Dictionary, c: Dictionary) -> int:
	var units: Array = c.state.targets(p.get("target", "owner"), c)
	return c.state.stat(units[0], "weapon_damage", c) if not units.is_empty() else 0
static func _resource_value(p: Dictionary, c: Dictionary) -> int:
	var units: Array = c.state.targets(p.get("target", "owner"), c)
	return int(c.state.unit(units[0]).get("resource", 0)) if not units.is_empty() else 0
static func _missing_value(p: Dictionary, c: Dictionary) -> int:
	var units: Array = c.state.targets(p.get("target", "chosen_ally"), c)
	if units.is_empty(): return 0
	var u: Dictionary = c.state.unit(units[0])
	return maxi(0, int(u.get("max_hull", 0)) - int(u.get("hull", 0)))
static func _arithmetic(p: Dictionary, c: Dictionary, operation: String) -> int:
	var values: Array = p.get("values", [])
	if values.is_empty(): return 0
	var result := number(values[0], c, int(c.get("value_depth", 0)))
	for value in values.slice(1):
		var n := number(value, c, int(c.get("value_depth", 0)))
		match operation:
			"sum": result += n
			"product": result *= n
			"min": result = mini(result, n)
			"max": result = maxi(result, n)
		result = clampi(result, 0, 99999)
	return result


static func _formatted(category: String, p: Dictionary) -> String:
	var kind: String = p.get("kind", "")
	if category == "value":
		match kind:
			"constant": return str(p.get("amount", 1))
			"weapon_damage": return "weapon damage"
			"resource_count": return "current resource"
			"missing_hp": return "missing hull"
			"adjacent_count": return "matching adjacent cards"
			"sum", "product", "min", "max":
				var values: Array = []
				for item in p.get("values", []): values.append(_raw_text("value", item))
				return "(" + (" + " if kind == "sum" else (" × " if kind == "product" else " " + kind + " ")).join(values) + ")"
	if category == "trigger":
		var owner: String = p.get("subject", "owner")
		match kind:
			"passive": return "While active"
			"on_play": return "On Play" if owner == "self_card" else "After {{rule_owner}} plays a card"
			"adjacent_card_played": return "After an adjacent " + p.get("card_type", "") + " card is played"
			"discarded": return "On Discard" + (" for " + p.reason if p.get("reason", "") != "" else " (deliberate only)")
			"moved": return "After " + ("an adjacent card moves a ship" if owner == "adjacent" else "{{rule_owner}} moves")
			"repaired": return "After actual repair"
			"revived": return "After revival"
			"hull_damaged": return "After " + ("an adjacent card deals hull damage" if owner == "adjacent" else "hull damage")
			"armour_absorbed": return "After armour reduces a hit"
			"shields_added": return "After " + ("an adjacent card adds shields" if owner == "adjacent" else "shields are added")
			"cover_absorbed": return "After cover absorbs damage"
			"shields_absorbed": return "After shields absorb damage"
			"attack_started": return "When an attack starts"
			"hit_resolved": return "After a hit resolves"
			"reaction_resolved": return "After an enemy reaction"
			"turn_start": return "At player-turn start"
			"turn_end": return "At fleet-phase end"
			"resource_changed": return "After resource changes"
			"cards_drawn": return "After cards are drawn"
	if category == "condition":
		match kind:
			"reaction_trigger": return common_reaction_text(p)
			"always": return "always"
			"adjacent": return "at least %d adjacent %s%s%s" % [p.get("minimum", 1), p.get("card_type", "") if p.get("card_type", "") != "" else "card", " with " + p.trait if p.get("trait", "") != "" else "", " (" + p.card_id + ")" if p.get("card_id", "") != "" else ""]
			"resource_at_least": return _target_text(p.get("target", "owner")) + " has " + _raw_text("value", p.get("amount", 1)) + "+ resource"
			"card_matches": return ("this card matches " if p.get("target", "event_card") == "self_card" else "event card matches ") + str(p.get("card_type", "")) + (" / " + p.trait if p.get("trait", "") != "" else "") + (" / " + p.card_id if p.get("card_id", "") != "" else "")
			"top_discard": return "this is the top discard"
			"reaction_category": return "reaction is " + p.get("category", "")
			"metric_at_least": return p.get("metric", "hull_damage").replace("_", " ") + " ≥ " + _raw_text("value", p.get("amount", 1))
			"position": return _target_text(p.get("target", "owner")) + " is at " + p.get("position", "front")
			"all", "any":
				var parts: Array = []
				for child in p.get("items", []): parts.append(_raw_text("condition", child))
				return (" AND " if kind == "all" else " OR ").join(parts) if not parts.is_empty() else "always"
			"not": return "not (" + _raw_text("condition", p.get("condition", {})) + ")"
	if category == "effect":
		var amount := _raw_text("value", p.get("amount", 1))
		var target: String = "" if p.get("target", "owner") == "chosen_ally" else " → " + _target_text(p.get("target", "owner"))
		match kind:
			"attack": return "Attack %s × %s [%s]" % [_raw_text("value", p.get("hits", 1)), _raw_text("value", p.get("damage", {"kind": "weapon_damage"})), p.get("range", "weapon")] + ("" if p.get("target", "chosen_enemy") in ["chosen_enemy", "chosen_ally"] else " → " + _target_text(p.get("target", "chosen_enemy")))
			"add_shields": return "+" + amount + " shields" + target
			"repair": return "Repair " + amount + target
			"recovery": return "Repair/recover " + amount + target
			"add_cover": return "+" + amount + " cover" + ("" if p.get("target", "source_slot") == "source_slot" else target)
			"gain_resource": return "Gain " + amount + " resource" + target
			"spend_resource": return "Spend " + amount + " resource" + target
			"move": return "Move/swap" + ("" if p.get("destination", "chosen_slot") == "chosen_slot" else " to " + p.destination) + ("; both gain " + _raw_text("value", p.get("guard", 0)) + " shields" if _raw_text("value", p.get("guard", 0)) != "0" else "")
			"swap": return "Swap adjacent ships" + ("; both gain " + _raw_text("value", p.get("guard", 0)) + " shields" if _raw_text("value", p.get("guard", 0)) != "0" else "")
			"draw": return "Draw " + amount
			"discard": return "Discard " + amount + " from hand"
			"scry": return "Scry " + _raw_text("value", p.get("look", 3)) + ", take " + _raw_text("value", p.get("take", 1)) + "; order top/discard"
			"stun": return "Stun one visible reaction until fleet phase ends"
			"confuse": return "Confuse: replace a visible stance"
			"add_persistence": return "+" + amount + " persistence" + ("" if p.get("target", "self_card") == "self_card" else target)
			"gain_mana": return "Gain " + amount + " temporary mana"
			"swap_ends": return "Swap frontmost and rearmost allies"
			"rear_to_front": return "Move rearmost ally to front"
	if category == "modifier":
		if kind == "weapon_range": return "Weapon range → " + p.get("range", "Long") + " / " + _target_text(p.get("target", "owner"))
		return ("−" if kind == "cost" else "+") + _raw_text("value", p.get("amount", 1)) + " " + ("first-hit damage" if kind == "attack_damage" else kind.replace("_", " ")) + ("" if p.get("target", "owner") in ["fleet", "self_card"] else " → " + _target_text(p.get("target", "owner"))) + (" (" + p.card_type + ")" if p.get("card_type", "") != "" else "")
	if category == "cost":
		return "Spend " + _raw_text("value", p.get("amount", 2)) + " personal resource"
	return ""

static func reaction_condition_text(condition: Dictionary, owner_name: String = "") -> String:
	match condition.get("kind",""):
		"card_matches":
			var matches: Array=[]
			for key in ["card_type","trait","card_id"]:
				if condition.get(key,"")!="":matches.append(str(condition[key]))
			return "On played "+(" ".join(matches) if not matches.is_empty() else "card")
		"all","any":
			var parts: Array=[]
			for child in condition.get("items",[]):parts.append(reaction_condition_text(child,owner_name))
			return (" AND " if condition.kind=="all" else " OR ").join(parts) if not parts.is_empty() else "always"
		"not":return "not ("+reaction_condition_text(condition.get("condition",{}),owner_name)+")"
	return text("condition",condition,owner_name)


static func common_reaction_text(spec: Dictionary) -> String:
	match spec.get("family","card_type"):
		"card_type": return "Played " + spec.get("card_type","Attack") + " card"
		"position": return "Played card from " + {"front":"Front","upper":"Upper Flank","lower":"Lower Flank","rear":"Rear"}.get(spec.get("position","front"),str(spec.get("position","")).capitalize())
		"damaged": return "On monster damaged"
		"healed": return "On heal"
	return "Unknown reaction trigger"


static func _common_reaction(p: Dictionary, c: Dictionary) -> bool:
	var event: Dictionary = c.get("event",{})
	match p.get("family","card_type"):
		"card_type": return event.get("played_card",false) and event.get("card",{}).get("type","") == p.get("card_type","Attack")
		"position":
			if not event.get("played_card",false): return false
			var point: int = event.get("played_from",-1)
			return point == {"front":0,"upper":1,"lower":2,"rear":3}.get(p.get("position","front"),-999)
		"damaged": return int(event.get("hull_damage",0)) > 0
		"healed": return int(event.get("player_healed",0)) > 0
	return false

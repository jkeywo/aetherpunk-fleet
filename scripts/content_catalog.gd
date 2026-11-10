extends RefCounted
## Version-2 definitions. Version-1 migration is read-only until explicit Save.
const DEFAULT_BASIC_RULES := {"repair": 2, "revive_threshold": 4}
const Legacy = preload("res://scripts/content_legacy.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CARD_EFFECTS = Legacy.CARD_EFFECTS
const MONSTER_EFFECTS = Legacy.MONSTER_EFFECTS
const TAGS = Legacy.TAGS
const TRIGGERS := ["tag", "damage", "tag_position", "healed", "cost"]
const CARD_EVENTS := ["played", "damage", "guard", "repair", "draw", "discard", "movement"]
const TRIGGER_EFFECTS := ["damage_monster", "guard", "repair", "draw_discard"]
const STATS := ["damage", "guard", "healing", "cost"]
const EFFECT_NAMES = Legacy.EFFECT_NAMES
const TARGET_NAMES := {"actor": "Source / acting ship", "event_actor": "Event's acting ship", "ally": "Chosen ship",
	"repaired": "Repaired ship", "front": "Frontmost occupied", "rear": "Rearmost occupied",
	"upper": "Upper Middle", "lower": "Lower Middle", "ends": "Front and rear", "sides": "Both middle positions", "all": "All surviving ships"}


static func normalized(value: Variant) -> Variant:
	return Legacy.normalized(value)


static func index_by_id(entries: Array, id: String) -> int:
	return Legacy.index_by_id(entries, id)


static func migrate(source: Dictionary) -> Dictionary:
	var doc: Dictionary = normalized(source)
	if doc.get("version", 0) != 1:
		return doc
	doc.version = 2
	doc.setup["positions"] = ["front", "upper", "rear"]
	doc.setup["enemy_position"] = "front"
	for card in doc.cards:
		var positions: Array = []
		for rank in card.get("ranks", []):
			for point in ([0] if int(rank) == 1 else ([1, 2] if int(rank) == 2 else [3])):
				if not positions.has(Geometry.POSITIONS[point]):
					positions.append(Geometry.POSITIONS[point])
		card["positions"] = positions
		card.erase("ranks")
		card["on_play"] = []
		card["modifiers"] = []
		card["triggers"] = []
	for monster in doc.leviathans:
		var reactions: Array = monster.reactions
		var intents: Array = monster.intents
		var r0: int = maxi(0, index_by_id(reactions, monster.starting_reaction))
		var i0: int = maxi(0, index_by_id(intents, monster.starting_intent))
		var stances: Array = []
		for index in maxi(reactions.size(), intents.size()):
			var reaction: Dictionary = reactions[(r0 + index) % reactions.size()].duplicate(true)
			if reaction.trigger.kind == "tag_rank":
				reaction.trigger.kind = "tag_position"
				var rank: int = int(reaction.trigger.rank)
				reaction.trigger.erase("rank")
				reaction.trigger["positions"] = ["front"] if rank == 1 else (["upper", "lower"] if rank == 2 else ["rear"])
			var intent: Dictionary = intents[(i0 + index) % intents.size()]
			stances.append({"id": "stance_" + str(index + 1), "name": reaction.name + " / " + intent.name,
				"reactions": [reaction], "effects": intent.effects.duplicate(true)})
		monster["stances"] = stances
		monster["starting_stance"] = stances[0].id
		for key in ["reactions", "intents", "starting_reaction", "starting_intent"]:
			monster.erase(key)
	return doc


static func empty_document() -> Dictionary:
	var doc := Legacy.empty_document()
	doc.version = 2
	doc.setup["positions"] = ["front", "upper", "rear"]
	doc.setup["enemy_position"] = "front"
	return doc


static func _downgrade(doc: Dictionary) -> Dictionary:
	var old := doc.duplicate(true)
	old.version = 1
	for card in old.get("cards", []):
		card["ranks"] = [1, 2, 3]
	for monster in old.get("leviathans", []):
		monster["reactions"] = [{"id": "compat", "name": "Validation adapter", "trigger": {"kind": "tag", "tag": "Attack"},
			"effects": [{"kind": "damage_ship", "target": "actor", "amount": 0}]}]
		monster["intents"] = [{"id": "compat", "name": "Validation adapter", "effects": [{"kind": "damage_ship", "target": "all", "amount": 0}]}]
		monster["starting_reaction"] = "compat"
		monster["starting_intent"] = "compat"
	return old


static func _condition(value: Variant, where: String, errors: Array) -> void:
	if not value is Dictionary:
		errors.append(where + " needs an adjacency condition.")
	elif not Legacy._integer(value.get("min")) or value.get("tag", "") not in TAGS + [""]:
		errors.append(where + " needs a nonnegative neighbour count and supported tag.")


static func _effects(effects: Variant, context: String, where: String, errors: Array, trigger: Dictionary = {}) -> void:
	if not effects is Array:
		errors.append(where + " effects must be a list.")
		return
	if effects.is_empty():
		return
	var adapted: Array = effects.duplicate(true)
	for effect in adapted:
		if effect is Dictionary:
			if effect.get("target") in ["upper", "lower", "sides", "event_actor"]:
				effect.target = "actor" if context == "reaction" else ("ally" if context == "card" else "all")
	Legacy._effects(adapted, context, where, errors, trigger)
	if context == "trigger":
		pass


static func validate(value: Variant) -> Array:
	if not value is Dictionary:
		return ["Content must be an object."]
	if value.get("version") == 1:
		return Legacy.validate(value)
	if value.get("version") != 2:
		return ["Unsupported content version; expected 1 or 2."]
	# Check base structure before passing it to the compatibility validator.
	for key in ["ships", "cards", "leviathans"]:
		if not value.get(key) is Array:
			return [key + " must be a list."]
		for entry in value[key]:
			if not entry is Dictionary:
				return [key + " entries must be objects."]
	if not value.get("setup") is Dictionary:
		return ["Battle setup must be an object."]
	var errors: Array = Legacy.validate(_downgrade(value))
	var setup: Dictionary = value.setup
	if setup.has("basic_actions"):
		var basic: Variant = setup.basic_actions
		if not basic is Dictionary:
			errors.append("Basic actions must configure repair and revive threshold.")
		else:
			for key in DEFAULT_BASIC_RULES:
				if not Legacy._integer(basic.get(key), 1):
					errors.append("Basic action %s must be a positive integer." % key)
	var positions: Variant = setup.get("positions")
	if not positions is Array or positions.size() != 3:
		errors.append("Assign a position to each of the three ships.")
	else:
		var seen: Array = []
		for position in positions:
			if not Geometry.POSITIONS.has(position) or seen.has(position):
				errors.append("Ships need distinct valid diamond positions.")
			seen.append(position)
	if not Geometry.POSITIONS.has(setup.get("enemy_position")):
		errors.append("Choose a valid enemy diamond position.")
	for card in value.cards:
		var where: String = "Card " + str(card.get("id", "?"))
		var points: Variant = card.get("positions")
		if not points is Array or points.is_empty():
			errors.append(where + " needs a permitted acting position.")
		else:
			for point in points:
				if not Geometry.POSITIONS.has(point):
					errors.append(where + " has an unknown acting position.")
		for section in ["on_play", "modifiers", "triggers"]:
			if not card.get(section) is Array:
				errors.append(where + " " + section + " must be a list.")
		if card.get("on_play") is Array:
			for rule in card.on_play:
				if not rule is Dictionary:
					errors.append(where + " has an invalid on-play rule.")
					continue
				_condition(rule.get("condition"), where, errors)
				_effects(rule.get("effects"), "card", where, errors)
		if card.get("modifiers") is Array:
			for rule in card.modifiers:
				if not rule is Dictionary:
					errors.append(where + " has an invalid modifier.")
					continue
				if rule.get("stat") not in STATS or not Legacy._integer(rule.get("amount")) or rule.get("tag", "") not in TAGS + [""]:
					errors.append(where + " has an invalid additive modifier.")
				_condition(rule.get("condition"), where, errors)
		if card.get("triggers") is Array:
			var ids: Array = []
			for rule in card.triggers:
				if not rule is Dictionary:
					errors.append(where + " has an invalid trigger.")
					continue
				if not rule.get("id") is String or str(rule.get("id", "")).is_empty() or ids.has(rule.get("id")):
					errors.append(where + " trigger IDs must be nonempty and unique.")
				ids.append(rule.get("id"))
				if rule.get("event") not in CARD_EVENTS or rule.get("tag", "") not in TAGS + [""] or not Legacy._integer(rule.get("threshold")):
					errors.append(where + " has an unsupported trigger event, tag, or threshold.")
				_condition(rule.get("condition"), where, errors)
				if not rule.get("effects") is Array:
					errors.append(where + " trigger needs effects.")
				else:
					for effect in rule.effects:
						if not effect is Dictionary or effect.get("kind") not in TRIGGER_EFFECTS:
							errors.append(where + " triggers support automatic damage, guard, repair, and draw/discard effects.")
							continue
						if effect.kind in ["guard", "repair"] and effect.get("target", "actor") not in ["actor", "event_actor"]:
							errors.append(where + " trigger effects need source/event actor targets.")
						if not Legacy._integer(effect.get("amount")) or (effect.kind == "draw_discard" and not Legacy._integer(effect.get("discard"))):
							errors.append(where + " trigger effect amounts must be nonnegative integers.")
	for monster in value.leviathans:
		var where: String = "Leviathan " + str(monster.get("id", "?"))
		var stances: Dictionary = Legacy._entries(monster.get("stances"), where + " stances", errors)
		if stances.is_empty() or not stances.has(monster.get("starting_stance")):
			errors.append(where + " needs stances and a valid starting stance.")
		for stance in stances.values():
			_effects(stance.get("effects"), "intent", where + " / " + stance.name, errors)
			if not stance.get("reactions") is Array:
				errors.append(where + " stance reactions must be a list.")
				continue
			var rules := Legacy._entries(stance.reactions, where + " reactions", errors)
			for reaction in rules.values():
				var trigger: Variant = reaction.get("trigger")
				if not trigger is Dictionary or trigger.get("kind") not in TRIGGERS:
					errors.append(where + " has an invalid reaction trigger.")
					continue
				if trigger.kind in ["tag", "tag_position"] and trigger.get("tag") not in TAGS:
					errors.append(where + " needs a reaction tag.")
				if trigger.kind == "tag_position":
					if not trigger.get("positions") is Array or trigger.positions.is_empty():
						errors.append(where + " needs trigger positions.")
					else:
						for point in trigger.positions:
							if point not in Geometry.POSITIONS:
								errors.append(where + " has an invalid trigger position.")
				if trigger.kind in ["damage", "healed", "cost"] and not Legacy._integer(trigger.get("threshold")):
					errors.append(where + " needs a nonnegative reaction threshold.")
				_effects(reaction.get("effects"), "reaction", where, errors, trigger)
	return errors


static func read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read " + path + ": " + error_string(FileAccess.get_open_error())}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var errors := validate(json.data)
	if not errors.is_empty():
		return {"ok": false, "error": "\n".join(errors)}
	var migrated: bool = json.data.version == 1
	return {"ok": true, "document": migrate(json.data), "migrated": migrated}


static func save_document(path: String, document: Dictionary) -> String:
	var errors := validate(document)
	if not errors.is_empty():
		return "\n".join(errors)
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write " + path + ": " + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(document, "\t", false) + "\n")
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, absolute)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot save content: " + error_string(result)
	return ""


static func references(document: Dictionary, kind: String, id: String) -> Array:
	return Legacy.references(document, kind, id)


static func new_effect(kind: String) -> Dictionary:
	return Legacy.new_effect(kind)


static func trigger_text(trigger: Dictionary) -> String:
	if trigger.get("kind") == "tag_position":
		return "After a %s action whose actor is at %s" % [trigger.get("tag", "?"), ", ".join(trigger.get("positions", []))]
	return Legacy.trigger_text(trigger)


static func effects_text(effects: Array) -> String:
	var lines: Array = []
	for effect in effects:
		var amount: int = int(effect.get("amount", 0))
		match effect.get("kind"):
			"guard":
				if effect.get("target") == "event_actor":
					lines.append("Give the event's acting ship %d guard." % amount)
				else:
					lines.append(Legacy.effects_text([effect]))
			"repair":
				var recipient: String = {"actor": "source ship", "event_actor": "event's acting ship"}.get(effect.get("target", ""), "chosen ship")
				lines.append("Restore %d hull to the %s." % [amount, recipient])
			"damage_ship":
				lines.append("Deal %d damage to %s." % [amount, str(TARGET_NAMES.get(effect.get("target"), "target")).to_lower()])
			"swap_adjacent":
				lines.append("Move to an adjacent position, swapping its occupant if needed.")
			"swap_ends":
				lines.append("Swap frontmost and rearmost survivors." + (" A lone survivor takes %d damage instead." % amount if amount > 0 else " Requires two survivors."))
			_:
				lines.append(Legacy.effects_text([effect]))
	return " ".join(lines)


static func condition_text(condition: Dictionary) -> String:
	return "at least %d adjacent %s card(s)" % [condition.get("min", 0), condition.get("tag", "any") if condition.get("tag", "") != "" else "any"]


static func present_card(source: Dictionary, owner: int = 0) -> Dictionary:
	var card := source.duplicate(true)
	card["owner"] = owner
	card["allowed_positions"] = source.get("positions", []).duplicate()
	card["ranks"] = ", ".join(source.get("positions", []))
	card["tag_ids"] = source.get("tags", []).duplicate()
	card["tags"] = " · ".join(source.get("tags", []))
	var text := effects_text(source.get("effects", []))
	for rule in source.get("on_play", []):
		text += "\nIf " + condition_text(rule.condition) + ": " + effects_text(rule.effects)
	for rule in source.get("modifiers", []):
		text += "\nWhile " + condition_text(rule.condition) + ": neighbours %s%d %s%s." % ["−" if rule.stat == "cost" else "+", rule.amount, rule.stat, " (" + rule.tag + ")" if rule.get("tag", "") != "" else ""]
	for rule in source.get("triggers", []):
		text += "\nOnce/turn: adjacent %s%s ≥%d, with %s: %s" % [rule.event, " (" + rule.tag + ")" if rule.get("tag", "") != "" else "", rule.threshold, condition_text(rule.condition), effects_text(rule.effects)]
	card["effect"] = text
	return card


static func compile(content: Dictionary) -> Dictionary:
	var doc := migrate(content)
	var result := {"ships": [], "cards": {}, "monster": {}, "stances": [], "positions": doc.setup.positions.duplicate(),
		"enemy_position": doc.setup.enemy_position, "fixed_hand": doc.setup.fixed_hand, "opening_hand": doc.setup.opening_hand.duplicate(), "basic_actions": basic_rules(doc)}
	for id in doc.setup.ships:
		result.ships.append(doc.ships[index_by_id(doc.ships, id)].duplicate(true))
	for card in doc.cards:
		var owner: int = doc.setup.ships.find(card.owner)
		if owner >= 0:
			result.cards[card.id] = present_card(card, owner)
	var monster: Dictionary = doc.leviathans[index_by_id(doc.leviathans, doc.setup.leviathan)]
	result.monster = {"id": monster.id, "name": monster.name, "hull": int(monster.hull)}
	result.stances = monster.stances.duplicate(true)
	result["starting_stance"] = index_by_id(monster.stances, monster.starting_stance)
	return result


static func basic_rules(doc: Dictionary) -> Dictionary:
	return doc.get("setup", {}).get("basic_actions", DEFAULT_BASIC_RULES).duplicate(true)

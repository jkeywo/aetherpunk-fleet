extends RefCounted
## Versioned content IO, validation, compilation, and generated rules text.

const CARD_EFFECTS := ["damage_monster", "guard", "repair", "swap_adjacent", "swap_pair_guard", "draw_discard"]
const MONSTER_EFFECTS := ["damage_ship", "swap_ends", "rear_to_front"]
const TAGS := ["Attack", "Movement", "Guard", "Repair", "Tactic"]
const TRIGGERS := ["tag", "damage", "tag_rank", "healed", "cost"]
const EFFECT_NAMES := {"damage_monster": "Damage leviathan", "guard": "Gain / give guard",
	"repair": "Repair chosen ship", "swap_adjacent": "Swap actor with neighbour",
	"swap_pair_guard": "Swap pair and give guard", "draw_discard": "Draw, then discard",
	"damage_ship": "Damage ships", "swap_ends": "Swap formation ends", "rear_to_front": "Move rear ship to front"}
const TARGET_NAMES := {"actor": "Acting ship", "ally": "Chosen ship", "repaired": "Repaired ship",
	"front": "Frontmost ship", "rear": "Rearmost ship", "ends": "Front and rear (once each)", "all": "All surviving ships"}


static func empty_document() -> Dictionary:
	return {"version": 1, "ships": [], "cards": [], "leviathans": [],
		"setup": {"leviathan": "", "ships": [], "fixed_hand": false, "opening_hand": []}}


static func read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read %s (%s)." % [path, error_string(FileAccess.get_open_error())]}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		return {"ok": false, "error": "Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	var errors := validate(parser.data)
	if not errors.is_empty():
		return {"ok": false, "error": "\n".join(errors)}
	return {"ok": true, "document": normalized(parser.data)}


static func normalized(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = normalized(value[key])
		return result
	if value is Array:
		return value.map(func(item): return normalized(item))
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	return value


static func save_document(path: String, document: Dictionary) -> String:
	var errors := validate(document)
	if not errors.is_empty():
		return "\n".join(errors)
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(document, "\t", false) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Writing content failed: " + error_string(write_error)
	# Rename replaces the destination only after the complete validated document is written.
	var error := DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot replace saved content: " + error_string(error)
	return ""


static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and value >= minimum and float(value) == floorf(float(value))


static func _entries(value: Variant, label: String, errors: Array) -> Dictionary:
	var result: Dictionary = {}
	if not value is Array:
		errors.append(label + " must be a list.")
		return result
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	for entry in value:
		if not entry is Dictionary:
			errors.append(label + " contains a non-object entry.")
			continue
		var id: Variant = entry.get("id", null)
		if not id is String or pattern.search(id) == null:
			errors.append(label + " IDs must start with a letter and contain lowercase letters, digits, or underscores.")
			continue
		if result.has(id):
			errors.append("Duplicate %s ID: %s." % [label, id])
		result[id] = entry
		if not entry.get("name", null) is String or str(entry.get("name", "")).strip_edges().is_empty():
			errors.append("%s %s needs a name." % [label, id])
	return result


static func _effects(value: Variant, context: String, path: String, errors: Array, trigger: Dictionary = {}) -> void:
	if not value is Array or value.is_empty():
		errors.append(path + " needs at least one effect.")
		return
	var kinds: Array = CARD_EFFECTS if context == "card" else MONSTER_EFFECTS
	for index in value.size():
		var effect: Variant = value[index]
		var where := "%s effect %d" % [path, index + 1]
		if not effect is Dictionary:
			errors.append(where + " must be an object.")
			continue
		var kind: Variant = effect.get("kind", "")
		if not kinds.has(kind):
			errors.append(where + " has an unsupported effect type.")
			continue
		if kind not in ["swap_adjacent", "rear_to_front"] and not _integer(effect.get("amount", null)):
			errors.append(where + " needs a nonnegative integer amount.")
		if kind == "draw_discard" and not _integer(effect.get("discard", null)):
			errors.append(where + " needs a nonnegative integer discard count.")
		if kind == "guard":
			if effect.get("target", "") not in ["actor", "ally"]:
				errors.append(where + " needs an actor or chosen-ship target.")
			if effect.has("exclude_actor") and not effect.exclude_actor is bool:
				errors.append(where + " exclude-actor flag must be true or false.")
		if kind == "damage_ship":
			var allowed := ["front", "rear", "ends", "all"]
			if context == "reaction":
				allowed.append_array(["actor", "repaired"])
			if not allowed.has(effect.get("target", "")):
				errors.append(where + " has an unavailable target.")
			if effect.get("target", "") == "repaired" and trigger.get("kind", "") != "healed":
				errors.append(where + " can target the repaired ship only with a healing trigger.")


static func validate(document: Variant) -> Array:
	var errors: Array = []
	if not document is Dictionary:
		return ["Content must be a JSON object."]
	if not _integer(document.get("version", null), 1) or document.get("version") != 1:
		errors.append("Unsupported content version; expected version 1.")
	var ships := _entries(document.get("ships"), "Ship", errors)
	var cards := _entries(document.get("cards"), "Card", errors)
	var monsters := _entries(document.get("leviathans"), "Leviathan", errors)
	for id in cards:
		var card: Dictionary = cards[id]
		var path := "Card " + str(id)
		if not ships.has(card.get("owner", "")):
			errors.append(path + " references a missing owning ship.")
		if not _integer(card.get("cost", null)) or not _integer(card.get("pays", null), 1):
			errors.append(path + " needs a nonnegative cost and positive payment value.")
		var ranks: Variant = card.get("ranks")
		if not ranks is Array or ranks.is_empty():
			errors.append(path + " needs at least one permitted rank.")
		else:
			for rank in ranks:
				if not _integer(rank, 1) or rank > 3:
					errors.append(path + " ranks must be 1, 2, or 3.")
		var tags: Variant = card.get("tags")
		if not tags is Array:
			errors.append(path + " tags must be a list.")
		else:
			for tag in tags:
				if not TAGS.has(tag):
					errors.append(path + " has an unsupported tag.")
		_effects(card.get("effects"), "card", path, errors)
	for id in ships:
		var ship: Dictionary = ships[id]
		var path := "Ship " + str(id)
		if not _integer(ship.get("hull", null), 1):
			errors.append(path + " needs positive maximum hull.")
		if not ship.get("role") is String or str(ship.get("role", "")).strip_edges().is_empty():
			errors.append(path + " needs a role.")
		if not ship.get("color") is String or not Color.html_is_valid(str(ship.get("color", ""))):
			errors.append(path + " needs a valid HTML colour.")
		var loadout: Variant = ship.get("loadout")
		if not loadout is Array:
			errors.append(path + " loadout must be a list.")
			continue
		var seen: Array = []
		for slot in loadout:
			if not slot is Dictionary:
				errors.append(path + " has an invalid loadout entry.")
				continue
			var card_id: Variant = slot.get("card", "")
			if not cards.has(card_id):
				errors.append(path + " loadout references missing card " + str(card_id) + ".")
			elif cards[card_id].get("owner") != id:
				errors.append(path + " loadout card " + str(card_id) + " belongs to another ship.")
			if not _integer(slot.get("count", null), 1):
				errors.append(path + " loadout copy counts must be positive integers.")
			if seen.has(card_id):
				errors.append(path + " repeats a loadout entry; use its copy count.")
			seen.append(card_id)
	for id in monsters:
		var monster: Dictionary = monsters[id]
		if not _integer(monster.get("hull", null), 1):
			errors.append("Leviathan " + str(id) + " needs positive maximum hull.")
		for list_name in ["reactions", "intents"]:
			var behaviors := _entries(monster.get(list_name), str(id) + " " + list_name, errors)
			if behaviors.is_empty():
				errors.append(str(id) + " needs at least one " + list_name + " entry.")
			var starting := "starting_reaction" if list_name == "reactions" else "starting_intent"
			if not behaviors.has(monster.get(starting, "")):
				errors.append(str(id) + " has a missing " + starting + ".")
			for behavior_id in behaviors:
				var behavior: Dictionary = behaviors[behavior_id]
				var path := "%s / %s" % [id, behavior_id]
				var trigger: Dictionary = {}
				if list_name == "reactions":
					if not behavior.get("trigger") is Dictionary:
						errors.append(path + " needs a trigger.")
					else:
						trigger = behavior.trigger
						if not TRIGGERS.has(trigger.get("kind", "")):
							errors.append(path + " has an unsupported trigger.")
						if trigger.get("kind") in ["tag", "tag_rank"] and not TAGS.has(trigger.get("tag", "")):
							errors.append(path + " needs a supported trigger tag.")
						if trigger.get("kind") == "tag_rank" and (not _integer(trigger.get("rank"), 1) or trigger.get("rank", 0) > 3):
							errors.append(path + " needs a trigger rank from 1 to 3.")
						if trigger.get("kind") in ["damage", "healed", "cost"] and not _integer(trigger.get("threshold")):
							errors.append(path + " needs a nonnegative trigger threshold.")
				_effects(behavior.get("effects"), "reaction" if list_name == "reactions" else "intent", path, errors, trigger)
	var setup: Variant = document.get("setup")
	if not setup is Dictionary:
		errors.append("Battle setup must be an object.")
		return errors
	if not monsters.has(setup.get("leviathan", "")):
		errors.append("Battle setup needs an existing leviathan.")
	var fleet: Variant = setup.get("ships")
	if not fleet is Array or fleet.size() != 3:
		errors.append("Battle setup needs exactly three ordered ships.")
		return errors
	var selected: Array = []
	var available: Dictionary = {}
	for id in fleet:
		if not ships.has(id):
			errors.append("Battle setup references missing ship " + str(id) + ".")
			continue
		if selected.has(id):
			errors.append("Battle setup repeats ship " + str(id) + "; choose three distinct ships.")
		selected.append(id)
		if ships[id].get("loadout") is Array:
			for slot in ships[id].loadout:
				if slot is Dictionary and _integer(slot.get("count"), 1):
					var key: Variant = slot.get("card", "")
					available[key] = int(available.get(key, 0)) + int(slot.count)
	var total := 0
	for count in available.values():
		total += int(count)
	if total < 7:
		errors.append("The selected fleet deck needs at least seven cards.")
	if not setup.get("fixed_hand") is bool:
		errors.append("Opening-hand mode must be true or false.")
	elif not setup.get("opening_hand") is Array:
		errors.append("Opening hand must be a list, including when random mode is selected.")
	elif setup.fixed_hand:
		var opening: Variant = setup.get("opening_hand")
		if not opening is Array or opening.size() != 7:
			errors.append("A fixed opening hand needs exactly seven cards.")
		else:
			for id in opening:
				if int(available.get(id, 0)) <= 0:
					errors.append("Fixed opening hand exceeds available copies of " + str(id) + ".")
				else:
					available[id] -= 1
	return errors


static func index_by_id(entries: Array, id: String) -> int:
	for index in entries.size():
		if entries[index].id == id:
			return index
	return -1


static func references(document: Dictionary, kind: String, id: String) -> Array:
	var found: Array = []
	if kind == "ships":
		if document.setup.ships.has(id):
			found.append("Battle Setup / ship formation")
		for card in document.cards:
			if card.owner == id:
				found.append("Owning ship of card " + card.name)
	elif kind == "cards":
		for ship in document.ships:
			for slot in ship.loadout:
				if slot.card == id:
					found.append("Loadout of " + ship.name)
		if document.setup.get("fixed_hand", false) and document.setup.opening_hand.has(id):
			found.append("Battle Setup / fixed opening hand")
	elif kind == "leviathans" and document.setup.leviathan == id:
		found.append("Battle Setup / selected leviathan")
	return found


static func new_effect(kind: String) -> Dictionary:
	match kind:
		"guard": return {"kind": kind, "target": "actor", "amount": 4, "exclude_actor": false}
		"draw_discard": return {"kind": kind, "amount": 2, "discard": 1}
		"damage_ship": return {"kind": kind, "target": "front", "amount": 3}
		"swap_adjacent", "rear_to_front": return {"kind": kind}
		"swap_ends": return {"kind": kind, "amount": 3}
		_: return {"kind": kind, "amount": 4}


static func trigger_text(trigger: Dictionary) -> String:
	match trigger.get("kind"):
		"tag": return "After an action with the %s tag" % trigger.get("tag", "?")
		"tag_rank": return "After a %s action finishes with its actor in rank %s" % [trigger.get("tag", "?"), trigger.get("rank", "?")]
		"damage": return "After an action deals at least %s leviathan hull damage" % trigger.get("threshold", 0)
		"healed": return "After an action restores at least %s hull" % trigger.get("threshold", 0)
		"cost": return "After an action with printed cost at least %s" % trigger.get("threshold", 0)
	return "Choose a trigger."


static func effects_text(effects: Array) -> String:
	var lines: Array = []
	for effect in effects:
		var amount: int = int(effect.get("amount", 0))
		match effect.get("kind"):
			"damage_monster": lines.append("Deal %d damage." % amount)
			"guard":
				lines.append(("Gain %d guard." if effect.get("target") == "actor" else "Give the chosen %sship %d guard.") % (
					amount if effect.get("target") == "actor" else ["other " if effect.get("exclude_actor", false) else "", amount]))
			"repair": lines.append("Restore %d hull to the chosen ship." % amount)
			"swap_adjacent": lines.append("Swap the acting ship with a chosen neighbour.")
			"swap_pair_guard": lines.append("Swap a chosen neighbouring pair. Give each %d guard." % amount)
			"draw_discard": lines.append("Draw %d cards, then discard %d if able." % [amount, effect.get("discard", 0)])
			"damage_ship": lines.append("Deal %d damage to %s." % [amount, str(TARGET_NAMES.get(effect.get("target"), "the chosen target")).to_lower()])
			"swap_ends": lines.append("Swap frontmost and rearmost survivors. A lone survivor takes %d damage instead." % amount)
			"rear_to_front": lines.append("Move the surviving rearmost ship to the front.")
	return " ".join(lines)


static func compile(document: Dictionary) -> Dictionary:
	var result := {"ships": [], "cards": {}, "monster": {}, "reactions": [], "intents": [],
		"fixed_hand": document.setup.fixed_hand, "opening_hand": document.setup.opening_hand.duplicate()}
	var selected: Array = document.setup.ships
	for id in selected:
		result.ships.append(document.ships[index_by_id(document.ships, id)].duplicate(true))
	for source in document.cards:
		var owner: int = selected.find(source.owner)
		if owner < 0:
			continue
		var card: Dictionary = source.duplicate(true)
		card.owner = owner
		card["allowed_ranks"] = source.ranks.map(func(rank): return int(rank))
		var ranks: Array = card.allowed_ranks.duplicate()
		ranks.sort()
		card["ranks"] = "Any" if ranks.size() == 3 else ("–" if ranks in [[1, 2], [2, 3]] else ", ").join(ranks.map(func(rank): return str(rank)))
		card["tag_ids"] = source.tags.duplicate()
		card["tags"] = " · ".join(source.tags)
		card["effect"] = effects_text(source.effects)
		result.cards[source.id] = card
	var monster: Dictionary = document.leviathans[index_by_id(document.leviathans, document.setup.leviathan)]
	result.monster = {"id": monster.id, "name": monster.name, "hull": int(monster.hull)}
	for reaction in monster.reactions:
		var entry: Dictionary = reaction.duplicate(true)
		entry["trigger_definition"] = reaction.trigger.duplicate(true)
		entry.trigger = trigger_text(reaction.trigger)
		entry["effect"] = effects_text(reaction.effects)
		result.reactions.append(entry)
	for intent in monster.intents:
		var entry: Dictionary = intent.duplicate(true)
		entry["trigger"] = "At the end of the fleet phase"
		entry["effect"] = effects_text(intent.effects)
		result.intents.append(entry)
	result["starting_reaction"] = index_by_id(monster.reactions, monster.starting_reaction)
	result["starting_intent"] = index_by_id(monster.intents, monster.starting_intent)
	return result

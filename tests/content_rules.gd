extends SceneTree
const Catalog = preload("res://scripts/content_catalog.gd")
const Store = preload("res://scripts/content_store.gd")
const State = preload("res://scripts/battle_state.gd")
var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/gdd_content.json"))
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func uid_for(battle, key: String) -> int:
	for uid in battle.hand:
		if battle.card_keys[uid] == key:
			return uid
	return -1


func _run() -> void:
	_validation()
	_persistence()
	_compound()
	_definitions()
	print("Content rules: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _validation() -> void:
	expect(Catalog.validate(fixture).is_empty(), "GDD fixture is invalid.")
	for malformed in [null, [], 1, "bad", {}, {"version": 2}, {"version": 1, "ships": null, "cards": 3, "leviathans": []}]:
		expect(not Catalog.validate(malformed).is_empty(), "Malformed document was accepted.")
	var bad := fixture.duplicate(true)
	bad.ships[0].hull = 0
	expect(not Catalog.validate(bad).is_empty(), "Zero hull accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].pays = 0
	expect(not Catalog.validate(bad).is_empty(), "Zero payment accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].cost = -1
	expect(not Catalog.validate(bad).is_empty(), "Negative cost accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].ranks = []
	expect(not Catalog.validate(bad).is_empty(), "Empty rank list accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].owner = "missing"
	expect(not Catalog.validate(bad).is_empty(), "Missing owner accepted.")
	bad = fixture.duplicate(true)
	bad.ships[0].loadout[0].card = "broadside"
	expect(not Catalog.validate(bad).is_empty(), "Wrong-owner loadout accepted.")
	bad = fixture.duplicate(true)
	bad.setup.ships = ["bastion", "bastion", "lamplighter"]
	expect(not Catalog.validate(bad).is_empty(), "Duplicate selected ships accepted.")
	bad = fixture.duplicate(true)
	bad.setup.opening_hand = ["salvo", "salvo", "salvo", "salvo", "salvo", "salvo", "salvo"]
	expect(not Catalog.validate(bad).is_empty(), "Opening hand exceeded copy counts.")
	bad = fixture.duplicate(true)
	bad.leviathans[0].reactions = []
	expect(not Catalog.validate(bad).is_empty(), "Missing reactions accepted.")
	bad = fixture.duplicate(true)
	bad.leviathans[0].starting_intent = "missing"
	expect(not Catalog.validate(bad).is_empty(), "Missing starting intent accepted.")
	bad = fixture.duplicate(true)
	bad.leviathans[0].reactions[0].effects[0].target = "repaired"
	expect(not Catalog.validate(bad).is_empty(), "Repaired target without healing trigger accepted.")
	bad = fixture.duplicate(true)
	bad.cards[0].effects = [{"kind": "unknown"}]
	expect(not Catalog.validate(bad).is_empty(), "Unknown effect accepted.")
	bad = fixture.duplicate(true)
	bad.setup.fixed_hand = false
	bad.setup.erase("opening_hand")
	expect(not Catalog.validate(bad).is_empty(), "Random mode accepted a missing opening-hand list.")
	expect(Catalog.references(fixture, "cards", "broadside").size() == 2, "Card references omitted loadout or fixed hand.")
	expect(Catalog.references(fixture, "ships", "bastion").size() == 4, "Ship references omitted formation or owned cards.")
	expect(Catalog.references(fixture, "leviathans", "stormmaw").size() == 1, "Leviathan reference omitted setup.")


func _persistence() -> void:
	var directory := "user://content_rules_tests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/content.json"
	expect(Catalog.save_document(path, fixture) == "", "Initial content save failed.")
	var before := FileAccess.get_file_as_string(path)
	var read := Catalog.read_document(path)
	expect(read.ok and Catalog.validate(read.document).is_empty(), "Saved content could not be loaded.")
	var changed := fixture.duplicate(true)
	changed.cards[3].name = "Renamed Broadside"
	changed.cards[3].effects[0].amount = 11
	expect(Catalog.save_document(path, changed) == "", "Replacing an existing saved file failed.")
	read = Catalog.read_document(path)
	expect(read.ok and read.document.cards[3].effects[0].amount == 11, "Saved effect failed to round-trip.")
	var valid_text := FileAccess.get_file_as_string(path)
	changed.cards[0].pays = -1
	expect(Catalog.save_document(path, changed) != "", "Invalid draft saved.")
	expect(FileAccess.get_file_as_string(path) == valid_text, "Failed validation changed saved content.")
	expect(Catalog.save_document(directory + "/missing/sub/content.json", fixture) != "", "Write to missing parent reported success.")
	var store = Store.new()
	store.path = path
	expect(store.reload_content(), "Store reload failed.")
	var saved_before: Dictionary = store.snapshot()
	store.path = directory + "/missing/sub/content.json"
	expect(not store.save_content(fixture) and store.saved == saved_before, "Failed write mutated saved in-memory content.")
	store.free()
	var malformed_path := directory + "/malformed.json"
	var file := FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string("{not JSON")
	file.close()
	expect(not Catalog.read_document(malformed_path).ok, "Malformed JSON loaded.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	expect(not before.is_empty(), "Initial serialization was empty.")


func _compound() -> void:
	var content := fixture.duplicate(true)
	content.cards.append({"id": "combo", "name": "Compound Manoeuvre", "owner": "bastion", "cost": 2, "pays": 3,
		"ranks": [1, 2, 3], "tags": ["Attack", "Movement", "Guard"], "effects": [
			{"kind": "damage_monster", "amount": 10}, {"kind": "swap_adjacent"},
			{"kind": "guard", "target": "actor", "amount": 4}, {"kind": "repair", "amount": 2},
			{"kind": "draw_discard", "amount": 2, "discard": 2}, {"kind": "damage_monster", "amount": 5}]})
	content.ships[0].loadout.append({"card": "combo", "count": 2})
	content.setup.opening_hand[0] = "combo"
	content.leviathans[0].reactions[1].effects[0].amount = 2
	content.leviathans[0].reactions[1].trigger.threshold = 14
	content.leviathans[0].starting_reaction = "recoil"
	expect(Catalog.validate(content).is_empty(), "Compound definition invalid.")
	var battle = State.new(123, content)
	battle.ships[1].hull = 15
	var uid := uid_for(battle, "combo")
	var payer := uid_for(battle, "brace")
	var random_before: int = battle.rng.state
	var hand_before: Array = battle.hand.duplicate()
	expect(battle.validate(uid, [payer], 1, 2) != "", "Nonadjacent compound movement accepted.")
	var preview: Dictionary = battle.preview(uid, [payer], 1, 1)
	expect(preview.ok and "70 → 55" in preview.text and "Violent Recoil triggers" in preview.text, "Compound public preview incorrect.")
	expect(battle.hand == hand_before and battle.rng.state == random_before, "Compound preview drew cards or consumed RNG.")
	expect(battle.play(uid, [payer], 1, 1) == "", "Compound action rejected.")
	expect(battle.phase == "discard" and battle.monster_hull == 60, "Draw/discard did not suspend later effects.")
	expect(battle.ships[0].guard == 4 and battle.ships[1].hull == 17 and battle.formation == [1, 0, 2], "Pre-discard effects were out of order.")
	expect(battle.pending.discard_remaining == 2 and battle.held.size() == 2, "Pending discard lost action context or held payment.")
	expect(battle.end_phase() != "", "Pending compound permitted enemy phase.")
	battle.discard_for_relay(battle.hand[0])
	expect(battle.phase == "discard" and battle.monster_hull == 60 and battle.reaction_index == 1, "First discard resolved the action early.")
	battle.discard_for_relay(battle.hand[0])
	expect(battle.phase == "fleet" and battle.monster_hull == 55, "Second discard did not resume remaining damage.")
	expect(battle.ships[0].guard == 2 and battle.ships[0].hull == 28, "Reaction did not use total actual damage or new guard.")
	var reactions: Array = battle.history.filter(func(line): return line.begins_with("Reaction: "))
	expect(reactions.size() == 1, "Compound action triggered more than one reaction.")
	var all: Array = battle.hand + battle.deck + battle.discard + battle.held
	var unique: Dictionary = {}
	for instance in all:
		unique[instance] = true
	expect(all.size() == 20 and unique.size() == 20, "Compound draw/discard lost or duplicated cards.")

	# The same movement choice is reused, validated after each preceding swap.
	content.cards[-1].effects = [{"kind": "swap_adjacent"}, {"kind": "swap_pair_guard", "amount": 2}]
	content.cards[-1].tags = ["Movement"]
	battle = State.new(5, content)
	expect(battle.play(uid_for(battle, "combo"), [uid_for(battle, "brace")], 1) == "", "Ordered paired movements rejected.")
	expect(battle.formation == [0, 1, 2], "Two composed swaps did not execute in order.")


func _definitions() -> void:
	var content := fixture.duplicate(true)
	content.cards[3].name = "Renamed Cannon"
	content.cards[3].effects[0].amount = 12
	content.cards[3].cost = 1
	content.cards[3].pays = 4
	content.cards[3].ranks = [1, 3]
	var battle = State.new(7, content)
	var broadside := uid_for(battle, "broadside")
	expect(battle.card(broadside).name == "Renamed Cannon" and battle.card(broadside).pays == 4, "Card fields did not compile.")
	expect(battle.card(broadside).ranks == "1, 3" and "12 damage" in battle.card(broadside).effect, "Generated card rules differ from effects.")
	expect(battle.play(broadside, [uid_for(battle, "escort")]) != "", "Edited ranks were ignored.")
	battle.formation = [1, 0, 2]
	expect(battle.play(broadside, [uid_for(battle, "escort")]) == "" and battle.monster_hull == 58, "Renamed card did not use its configured damage/cost.")

	content = fixture.duplicate(true)
	var ship: Dictionary = content.ships[0].duplicate(true)
	ship.id = "ironclad"
	ship.name = "Ironclad / Mk II"
	ship.hull = 40
	var mapping: Dictionary = {}
	for card in content.cards.duplicate(true):
		if card.owner == "bastion":
			var copy: Dictionary = card.duplicate(true)
			copy.id = card.id + "_iron"
			copy.owner = ship.id
			mapping[card.id] = copy.id
			content.cards.append(copy)
	for slot in ship.loadout:
		slot.card = mapping[slot.card]
	content.ships.append(ship)
	var monster: Dictionary = content.leviathans[0].duplicate(true)
	monster.id = "wyrm"
	monster.name = "Cloud Wyrm"
	monster.hull = 120
	content.leviathans.append(monster)
	content.setup.leviathan = "wyrm"
	content.setup.ships = ["kestrel", "ironclad", "lamplighter"]
	content.setup.fixed_hand = false
	expect(Catalog.validate(content).is_empty(), "New ship/leviathan content invalid.")
	battle = State.new(9, content)
	var again = State.new(9, content)
	expect(battle.monster_hull == 120 and battle.definitions.monster.name == "Cloud Wyrm", "Selected new leviathan ignored.")
	expect(battle.ships[0].id == "kestrel" and battle.ships[1].max_hull == 40, "Saved fleet order or ship hull ignored.")
	expect(battle.hand.size() == 7 and battle.hand == again.hand and battle.deck == again.deck, "Seeded random opening hand incorrect.")
	expect(battle.result_summary("victory").starting_hull == 78, "Result denominator did not use edited fleet hull.")
	content.ships[-1].hull = 99
	expect(battle.ships[1].max_hull == 40, "Battle retained mutable editor references.")

	content = fixture.duplicate(true)
	content.leviathans[0].reactions = [content.leviathans[0].reactions[0]]
	content.leviathans[0].intents = [content.leviathans[0].intents[0]]
	battle = State.new(1, content)
	expect(battle.play(uid_for(battle, "advance"), [uid_for(battle, "tow")], 1) == "" and battle.reaction_index == 0, "Single reaction deck failed to replace itself.")
	var reaction_count: int = battle.history.filter(func(line): return line.begins_with("Reaction: ")).size()
	expect(reaction_count == 1 and battle.ships[0].hull == 25, "Single reaction chained into itself.")
	expect(battle.play(-1, [uid_for(battle, "escort")], 11) == "" and battle.ships[0].hull == 22, "Single reaction did not trigger on the next action.")
	battle.end_phase()
	battle.refresh([])
	expect(battle.intent_index == 0 and battle.phase == "fleet", "Single intent deck could not cycle.")

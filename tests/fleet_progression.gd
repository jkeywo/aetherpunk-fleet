extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var doc := fixture.duplicate(true)
	doc.setup.fixed_hand = false
	for level in [1, 2, 3]:
		for slot in doc.setup.fleet:
			slot.level = level
			slot.level_2 = "defence" if level >= 2 else ""
			slot.level_3 = "bulwark" if level >= 3 else ""
		expect(Catalog.validate(doc).is_empty(), "Legal ship progression rejected.")
		var b = State.new(1, doc)
		expect(b.card_keys.size() == {1: 12, 2: 18, 3: 24}[level], "Pair-based deck size wrong.")
		for ship in b.definitions.ships:
			expect(ship.loadout.all(func(slot): return slot.count == 2), "A package did not contribute an exact pair.")
	doc.setup.fleet[0].level_3 = "artillery"
	expect(not Catalog.validate(doc).is_empty(), "Blocked level-3 branch accepted.")
	doc = fixture.duplicate(true)
	doc.setup.fixed_hand = false
	doc.setup.fleet[0].captain = "rook"
	doc.setup.fleet[1].captain = "iona"
	expect(Catalog.validate(doc).is_empty(), "Captain reassignment rejected.")
	var b = State.new(1, doc)
	expect(b.definitions.cards.command_barrage.owner == 0 and b.definitions.cards.field_orders.owner == 1, "Captain card did not use its assigned ship.")
	expect(b.stat(0, "armour") == 3 and b.stat(1, "weapon_damage") == 6, "Upgrade passive stats did not apply.")
	doc.setup.fleet[1].captain = "rook"
	expect(not Catalog.validate(doc).is_empty(), "Duplicate captain assignment accepted.")
	b = State.new(1, fixture)
	doc = fixture.duplicate(true)
	doc.ships[0].hull = 999
	expect(b.ships[0].max_hull == 28, "Battle retained mutable content references.")
	# Resource gain distinguishes mitigation recipients and actual repair actors.
	b = State.new(1, fixture)
	b.enemies[0].stances = [{"id": "quiet", "name": "Quiet", "reactions": [], "effects": []}]
	var c := {"owner": -1, "uid": -1, "event": {}, "ancestry": []}
	b._start_action({"owner": 0, "uid": -1}, "test")
	b._stage = ""
	b._hit({"target": 0, "damage": 2, "index": 1, "total": 1}, c)
	b._drain()
	expect(b.ships[0].resource == 1, "Armour mitigation did not gain Resolve.")
	var n := neutral()
	var ship := ship_def(n, "lamplighter")
	ship.resource.rules = [rule("repair_gain", "repaired", [{"kind": "gain_resource", "target": "owner", "amount": 1}], "owner", "ship")]
	card_def(n, "patch").rules[0].effects = [{"kind": "repair", "target": "chosen_ally", "amount": 3}]
	b = State.new(1, n)
	b.ships[0].hull = 20
	expect(b.play(uid_for(b, "patch"), [], 0, -1, 0) == "" and b.ships[2].resource == 1, "Repair resource went to recipient instead of acting tender.")
	n = neutral()
	var r := rule("optional", "on_play", [{"kind": "add_shields", "target": "owner", "amount": 3}], "owner", "ship")
	r.optional = true
	r.costs = [{"kind": "ship_resource", "target": "owner", "amount": 2}]
	ship_def(n, "bastion").resource.rules = [r]
	var automatic := rule("automatic", "on_play", [{"kind": "add_cover", "target": "source_slot", "amount": 3}], "owner", "ship")
	automatic.costs = [{"kind": "ship_resource", "target": "owner", "amount": 2}]
	ship_def(n, "bastion").resource.rules.append(automatic)
	b = State.new(1, n)
	b.ships[0].resource = 2
	var uid := uid_for(b, "brace")
	var options: Array = b.boost_options(uid, b._context(uid, -1, -1, 0))
	expect(options.size() == 1, "Eligible optional boost missing.")
	var key: String = options[0].key
	var before := JSON.stringify(b.board_snapshot())
	var preview: Dictionary = b.preview(uid, [], -1, -1, 0, {"boosts": [key]})
	expect(preview.ok and JSON.stringify(b.board_snapshot()) == before, "Boost preview spent real resources.")
	expect(b.play(uid, [], -1, -1, 0, {"boosts": [key]}) == "" and b.ships[0].resource == 0 and b.ships[0].guard == 3 and b.cover[0] == 0, "Optional resource spend did not reserve before automatic spend.")
	b = State.new(1, n)
	expect(b.play(uid_for(b, "brace"), [], -1, -1, 0, {"boosts": [key]}) != "", "Unfunded boost accepted.")
	b.ships[0].resource = 99
	b.effect_unit("gain_resource", {"target": "owner", "amount": 1}, {"owner": 0, "uid": -1, "event": {}, "ancestry": []})
	expect(b.ships[0].resource == 6, "Personal resource capacity ignored.")
	b.ships[0].hull = 0
	b._cleanup()
	expect(b.ships[0].resource == 0, "Defeat retained resource.")
	done("Fleet progression and personal resources")

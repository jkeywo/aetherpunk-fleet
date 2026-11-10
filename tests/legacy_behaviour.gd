extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var doc := Catalog.migrate(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/diamond_content.json")))
	for design in doc.cards:
		design.cost = 0
		design.positions = Geometry.POSITIONS.duplicate()
	for enemy in doc.leviathans:
		enemy.stances = [{"id":"quiet","name":"Quiet","reactions":[],"effects":[]}]
		enemy.stance_loadout = [{"stance":"quiet","count":1}]
		enemy.default_action = []
	var b = State.new(1,doc)
	all_in_hand(b)
	var uid := uid_for(b,"escort")
	expect(b.validate(uid,[],0,-1,0) != "", "Imported exclude-actor guard accepted its owner.")
	expect(b.play(uid,[],1,-1,0) == "" and b.ships[1].guard == 6, "Imported ally guard changed.")
	b = State.new(1,doc)
	all_in_hand(b)
	uid = uid_for(b,"tow")
	var pair: Array = b.choices(uid,"primary",0)
	expect(pair.size() > 0 and pair[0].value >= 100,"Imported arbitrary adjacent pair choice missing.")
	expect(b.play(uid,[],100 + 0 * 4 + 1,-1,0) == "" and b.formation == [1,0,-1,2],"Imported pair swap forced the acting ship.")
	expect(b.ships[0].guard == 2 and b.ships[1].guard == 2 and b.ships[2].guard == 0,"Imported pair guard applied to wrong ships.")
	for target in ["front","rear","ends"]:
		var sample := doc.duplicate(true)
		sample.leviathans[0].stances[0].effects = Catalog.converted([{"kind":"damage_ship","target":target,"amount":3}],true)
		b = State.new(1,sample)
		b.end_phase()
		expect(b.ships[0].hull == (25 if target in ["front","ends"] else 28) and b.ships[2].hull == (15 if target in ["rear","ends"] else 18),"Imported " + target + " targeting changed.")
	var sample := doc.duplicate(true)
	sample.leviathans[0].stances[0].reactions = [{"id":"actor","name":"Actor Counter","category":"Retaliation","conditions":{"kind":"always"},"effects":Catalog.converted([{"kind":"damage_ship","target":"actor","amount":3}],true)}]
	b = State.new(1,sample)
	all_in_hand(b)
	# Disable the action effect so this tests the reaction's event actor alone.
	b.definitions.cards.broadside.rules = [rule("play","on_play",[{"kind":"gain_resource","target":"owner","amount":0}])]
	b.play(uid_for(b,"broadside"),[],-1,-1,0)
	expect(b.ships[1].hull == 17 and b.ships[0].hull == 28 and b.monster_hull == 70,"Imported actor retaliation hit its enemy owner or front ship.")
	# Scry crosses a short draw pile and reshuffles without losing revealed cards.
	b = State.new(1,neutral())
	b.discard = b.deck.slice(2)
	b.deck = b.deck.slice(0,2)
	b.effect_scry({"look":4,"take":1},{"owner":0,"uid":-1,"event":{},"ancestry":[]})
	expect(b.pending.revealed.size() == 4 and conserved(b),"Scry did not use available cards beyond a reshuffle.")
	# Value formulas use upgraded weapons, not a stale printed statistic.
	b = State.new(1,fixture)
	var c := {"state":b,"owner":1,"uid":uid_for(b,"broadside"),"event":{}}
	expect(R.number({"kind":"sum","values":[{"kind":"weapon_damage","target":"owner"},3]},c) == 9,"Weapon formula ignored level-2 upgrade.")
	# Typed contexts reject primitives that cannot execute in enemy activity.
	var bad := fixture.duplicate(true)
	bad.leviathans[0].default_action = [{"kind":"scry","look":3,"take":1}]
	expect(not Catalog.validate(bad).is_empty(),"Enemy scry accepted despite no decision context.")
	done("Imported behavior and edge cases")

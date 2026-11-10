extends "res://tests/support/v3_test.gd"
const RuleForm = preload("res://scripts/rules/rule_editor.gd")
func buttons(node: Node, caption: String) -> Array:
	var result: Array = []
	if node is Button and node.text == caption: result.append(node)
	for child in node.get_children(): result.append_array(buttons(child,caption))
	return result
func _run() -> void:
	var source := rule("compound","on_play",[attack(3),{"kind":"add_shields","target":"owner","amount":1}])
	var form := RuleForm.new()
	root.add_child(form)
	form.configure(source)
	buttons(form,"↓")[0].pressed.emit()
	expect(source.effects[0].kind == "add_shields" and source.effects[1].kind == "attack","Generic form did not commit effect reordering.")
	var specs := form.find_children("*","VBoxContainer",true,false)
	for spec in specs:
		if spec.get_script() == preload("res://scripts/rules/spec_editor.gd") and spec.category == "effect" and spec.spec.kind == "add_shields":
			var spins := spec.find_children("*","SpinBox",true,false)
			spins[0].value = 4
			break
	expect(source.effects[0].amount == 4 and "+4 shields" in R.rule_text(source),"Typed field change did not update data/generated text.")
	buttons(form,"Remove")[0].pressed.emit()
	expect(source.effects.size() == 1 and source.effects[0].kind == "attack","Generic Remove failed.")
	buttons(form,"Add effect")[0].pressed.emit()
	expect(source.effects.size() == 2 and source.effects[1].kind == "add_shields","Generic Add failed.")
	form.free()
	var doc := neutral()
	doc.captains[0].passive.modifiers = [{"kind":"max_hull","target":"owner","amount":5}]
	var b = State.new(1,doc)
	expect(b.ships[0].max_hull == 33 and b.result_summary("victory").starting_hull == 71,"Starting max hull did not include captain.")
	b.ships[0].hull = 0
	b._cleanup()
	expect(b.result_summary("victory").starting_hull == 71 and b.result_summary("victory").ships[0].max_hull == 33,"Defeat changed the starting fleet denominator.")
	doc = neutral()
	doc.setup.mana_capacity = 3
	doc.captains[0].passive.modifiers = [{"kind":"mana_generation","target":"fleet","amount":2}]
	b = State.new(1,doc)
	b.end_phase()
	expect(b.mana == 3,"Mana generation modifier did not affect retention grant.")
	# Optional trigger filters are checked before offering/reserving a boost.
	doc = neutral()
	var optional := rule("attack-only","on_play",[{"kind":"add_shields","target":"owner","amount":1}],"owner","ship")
	optional.optional = true
	optional.trigger.card_type = "Attack"
	optional.costs = [{"kind":"ship_resource","target":"owner","amount":2}]
	doc.ships[0].resource.rules = [optional]
	b = State.new(1,doc)
	b.ships[0].resource = 2
	expect(b.boost_options(uid_for(b,"brace")).is_empty(),"Attack-only boost was offered for Guard.")
	for bad in [1,[],null]:
		var malformed := fixture.duplicate(true)
		malformed.ships[0].resource = bad
		expect(not Catalog.validate(malformed).is_empty(),"Malformed resource structure crashed or passed validation.")
	var metrics_doc := neutral()
	metrics_doc.leviathans[0].armour = 2
	metrics_doc.leviathans[0].stances[0].reactions = [{"id":"mitigation","name":"Mitigation Counter","category":"Test","conditions":{"all":[{"kind":"metric_at_least","metric":"armour_absorbed","amount":3},{"kind":"identity","target":"event_target","id":"stormmaw"}]},"effects":[attack(1,1,"Long","chosen_ally")]}]
	card_def(metrics_doc,"brace").rules[0].effects = [attack(1,3)]
	b = State.new(1,metrics_doc)
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(b.monster_hull == 70 and b.ships[0].hull == 27,"Reaction did not aggregate explicitly filtered mitigation or identify its target.")
	metrics_doc.leviathans[0].stances[0].reactions[0].conditions = {"kind":"metric_at_least","metric":"hull_damage","amount":1}
	b = State.new(1,metrics_doc)
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(b.ships[0].hull == 28,"Default hull threshold counted mitigated damage.")
	var referenced := fixture.duplicate(true)
	referenced.cards[0].rules[1].conditions = {"kind":"adjacent","card_id":"storm_lens","minimum":1}
	expect(not Catalog.references(referenced,"cards","storm_lens").is_empty(),"Rule-level card reference not protected from deletion.")
	referenced.cards[0].rules[1].conditions.card_id = "nonexistent"
	expect(not Catalog.validate(referenced).is_empty(),"Missing rule-level card reference accepted.")
	var paused_doc := neutral()
	card_def(paused_doc,"brace").rules[0].effects = [{"kind":"scry","look":3,"take":1},attack(2)]
	var suspended = State.new(1,paused_doc)
	suspended.play(uid_for(suspended,"brace"),[],-1,-1,0)
	var weak: WeakRef = weakref(suspended)
	suspended = null
	expect(weak.get_ref() == null,"Abandoned scry queue retained a reference cycle.")
	var initial := neutral()
	initial.ships[0].resource.rules = [rule("start","turn_start",[{"kind":"gain_resource","target":"owner","amount":1}],"owner","ship")]
	b = State.new(1,initial)
	expect(b.ships[0].resource == 1 and b.phase == "fleet", "First player turn skipped authored start rules.")
	done("Authoring chunks and modifier edges")

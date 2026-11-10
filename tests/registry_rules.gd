extends "res://tests/support/v3_test.gd"
const Spec = preload("res://scripts/rules/spec_editor.gd")
func _run() -> void:
	for category in ["trigger", "condition", "effect", "modifier", "cost", "value"]:
		for id in R.ids(category):
			var spec := R.fresh(category,id)
			var errors: Array = []
			R.validate_spec(category,spec,"test",errors)
			expect(errors.is_empty(), category + "/" + id + " schema rejected its own defaults: " + str(errors))
			expect(not R.text(category,spec).is_empty() and R.descriptor(category,id).handler.is_valid(), "Chunk missing text/executor: " + id)
			var before := JSON.stringify(spec)
			var editor := Spec.new()
			root.add_child(editor)
			editor.configure(category,spec)
			expect(editor.get_child_count() > 0 and JSON.stringify(spec) == before, "Generated form mutated " + id)
			editor.free()
	# Execute each effect through a card, the same route used by previews.
	for id in R.ids("effect"):
		var doc := neutral()
		var effect := R.fresh("effect",id)
		if id == "move": effect.destination = "upper"
		card_def(doc,"brace").rules[0].effects = [effect]
		doc.leviathans[0].stances[0].reactions = [{"id":"counter","name":"Counter","category":"Test","conditions":{"kind":"card_matches","card_type":"Support"},"effects":[]}]
		var b = State.new(1,doc)
		var uid := uid_for(b,"brace")
		var options: Dictionary = {}
		var primary := -1
		for group in ["primary","enemy","circle","stance","reaction","slot"]:
			var list: Array = b.choices(uid,group,0)
			if not list.is_empty():
				if group == "primary": primary = list[0].value
				else: options[group] = list[0].value
		var seed: int = b.rng.state
		var preview: Dictionary = b.preview(uid,[],primary,-1,0,options)
		expect(preview.ok and b.rng.state == seed, "Chunk preview failed: " + id + ": " + preview.text)
		expect(b.play(uid,[],primary,-1,0,options) == "", "Chunk execution failed: " + id)
		while b.phase == "discard": b.discard_for_relay(b.hand[0])
		if b.phase == "scry":
			var shown: Array = b.pending.revealed.duplicate()
			b.choose_scry(shown.slice(0,b.pending.take),shown.slice(b.pending.take),[])
		expect(b.phase == "fleet" and conserved(b), "Chunk did not finish/conserve cards: " + id)
	var errors: Array = []
	R.validate_rule({"id":"bad","trigger":5,"effects":42},"bad",errors)
	expect(errors.size() >= 2,"Malformed nested rule not rejected safely.")
	var b = State.new(1,neutral())
	var ctx := {"state":b,"owner":0,"uid":uid_for(b,"brace"),"event":{"actor":0,"target":1,"card":b.card(uid_for(b,"brace"))}}
	expect(R.condition({"all":[{"kind":"always"},{"not":{"kind":"health_at_most","amount":1}}]},ctx),"Boolean composition failed.")
	expect(R.number({"kind":"product","values":[99999,99999]},ctx) == 99999,"Arithmetic not bounded.")
	b.effect_unit("add_shields",{"target":"all_allies","amount":2,"filter":{"kind":"identity","target":"event_target","id":"kestrel"}},ctx)
	expect(b.ships[0].guard == 0 and b.ships[1].guard == 2 and b.ships[2].guard == 0,"Filtered group selected wrong units.")
	# Complete the allied chain after a killing hit, before reporting victory.
	var doc := neutral()
	card_def(doc,"brace").rules[0].effects = [attack(99),{"kind":"repair","target":"owner","amount":3}]
	card_def(doc,"brace").cost = 1
	b = State.new(1,doc)
	b.ships[0].hull = 20
	b.play(uid_for(b,"brace"),[uid_for(b,"patch")],-1,-1,0)
	expect(b.outcome == "victory" and b.ships[0].hull == 23 and b.discard.size() == 1,"Victory cut off compound effect/payment.")
	# Ordered conditions see the position produced by preceding blocks.
	doc = neutral()
	card_def(doc,"brace").rules[0].effects = [{"kind":"move","target":"owner","destination":"upper","guard":0}]
	card_def(doc,"brace").rules[1] = rule("position-shot","on_play",[attack(3,1,"Short")],"self_card","circle",{"kind":"position","target":"owner","position":"upper"})
	b = State.new(1,doc)
	expect(b.play(uid_for(b,"brace"),[],-1,-1,0) == "" and b.monster_hull == 67,"Later block did not see new formation.")
	# Per-hit and per-turn limits, with no recursive self-entry.
	doc = neutral()
	card_def(doc,"brace").rules[0].effects = [attack(2,3)]
	doc.ships[0].resource.rules = [rule("hits","hit_resolved",[{"kind":"gain_resource","target":"owner","amount":1}],"owner","ship")]
	doc.ships[0].resource.rules[0].limit = "once_per_hit"
	b = State.new(1,doc)
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	expect(b.ships[0].resource == 3,"Per-hit limit collapsed multiple hits.")
	doc.ships[0].resource.rules[0].limit = "once_per_turn"
	b = State.new(1,doc)
	b.play(uid_for(b,"brace"),[],-1,-1,0)
	b.play(uid_for(b,"broadside"),[],-1,-1,1)
	expect(b.ships[0].resource == 1,"Per-turn rule fired repeatedly.")
	done("Registered chunks and executor")

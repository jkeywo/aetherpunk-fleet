extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size = Vector2i(1280,800)
	var doc := neutral()
	card_def(doc,"brace").rules[0].effects = [{"kind":"stun","target":"chosen_reaction"},{"kind":"confuse","target":"chosen_stance"},{"kind":"scry","look":3,"take":1},attack(3)]
	doc.leviathans[0].stances[0].reactions = [{"id":"counter","name":"Counter","category":"Test","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b = current_scene
	stage_card(b,"brace",0)
	expect(b.get_node("%StanceChoice").visible and b.get_node("%ReactionChoice").visible and b.get_node("%PlayButton").disabled,"Control targets were not explicit.")
	choose_first_targets(b)
	expect(not b.get_node("%PlayButton").disabled,"Valid control selections rejected.")
	b.get_node("%PlayButton").pressed.emit()
	await b.resolution_finished
	await flush()
	expect(b.state.phase == "scry" and b.scry_dialog.visible,"Committed scry chooser missing.")
	expect(b.get_node("%CancelButton").disabled and b.state.monster_hull == 70,"Scry could be cancelled or queue ran ahead.")
	var menus: Array = b.scry_body.find_children("*","OptionButton",true,false)
	expect(menus.size() == 3,"Revealed scry cards missing.")
	menus[0].select(0)
	menus[0].item_selected.emit(0)
	menus[2].select(2)
	menus[2].item_selected.emit(2)
	expect(b.scry_dialog.size.y <= root.size.y and b.scry_dialog.get_ok_button().get_global_rect().end.y <= b.scry_dialog.size.y, "Scry confirmation below visible dialog.")
	b.scry_dialog.get_ok_button().pressed.emit()
	await b.resolution_finished
	expect(b.state.phase == "fleet" and not b.scry_dialog.visible and b.state.monster_hull == 67,"Scry did not resume committed effects.")
	expect(conserved(b.state),"Control/scry UI lost cards.")
	# A one-card enemy deck must not react from its freshly revealed same UID.
	doc = neutral()
	doc.leviathans[0].stance_loadout[0].count = 1
	doc.leviathans[0].stances[0].reactions = [{"id":"counter","name":"Counter","category":"Test","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally")]}]
	card_def(doc,"brace").rules[0].effects = [{"kind":"confuse","target":"chosen_stance"}]
	var state = State.new(1,doc)
	state.play(uid_for(state,"brace"),[],-1,-1,0,{"stance":state.enemy_row[0]})
	expect(state.enemy_row.size() == 1 and not state.feedback_events.any(func(e): return e.kind == "reaction_triggered"),"Recycled physical stance reacted to its revealing action.")
	state.end_phase()
	expect(state.feedback_events.filter(func(e): return e.kind == "intent_triggered").size() == 1,"One-card deck activated more than once.")
	done("Control and scry interfaces")

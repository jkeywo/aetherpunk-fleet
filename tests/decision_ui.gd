extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size=Vector2i(1280,800)
	var doc:=neutral()
	card_def(doc,"brace").rules[0].effects=[{"kind":"stun","target":"chosen_reaction"},{"kind":"confuse","target":"chosen_stance"},{"kind":"scry","look":3},{"kind":"draw","amount":1},attack(3)]
	doc.leviathans[0].stances[0].reactions=[{"id":"counter","name":"Counter","category":"Test","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b=current_scene
	stage_card(b,"brace",0)
	await flush()
	expect(b.pending_play and not b.busy,"Targeted free card did not wait for choices.")
	expect(not b.get_node("%StanceChoice").visible and not b.get_node("%ReactionChoice").visible,"Target dropdowns still visible.")
	b._stance_pressed(b.state.enemy_row[0])
	b.stance_panel.reaction_selected.emit(str(b.state.enemy_row[0])+"/counter")
	await settle(b)
	expect(b.state.phase=="scry" and b.scry_dialog.visible,"Automatic control play did not open scry.")
	expect(b.get_node("%CancelButton").disabled and b.state.monster_hull==70,"Scry cancelled or queue ran ahead.")
	var menus: Array=b.scry_body.find_children("*","OptionButton",true,false)
	expect(menus.size()==3,"Scry cards missing.")
	menus[0].select(0)
	menus[0].item_selected.emit(0)
	menus[2].select(1)
	menus[2].item_selected.emit(1)
	expect(b.scry_dialog.size.y<=root.size.y and not b.scry_dialog.get_ok_button().disabled,"Scry choices not confirmable in viewport.")
	b.scry_dialog.get_ok_button().pressed.emit()
	await settle(b)
	expect(b.state.phase=="fleet" and b.state.monster_hull==67 and conserved(b.state),"Scry did not resume.")
	doc=neutral()
	doc.leviathans[0].stance_loadout[0].count=1
	doc.leviathans[0].stances[0].reactions=[{"id":"counter","name":"Counter","category":"Test","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally")]}]
	card_def(doc,"brace").rules[0].effects=[{"kind":"confuse","target":"chosen_stance"}]
	var state=State.new(1,doc)
	state.play(uid_for(state,"brace"),[],-1,-1,0,{"stance":state.enemy_row[0]})
	expect(state.enemy_row.size()==1 and not state.feedback_events.any(func(e): return e.kind=="reaction_triggered"),"Recycled stance reacted.")
	state.end_phase()
	expect(state.feedback_events.filter(func(e): return e.kind=="intent_triggered").size()==1,"One-card deck activated twice.")
	done("Control and scry interfaces")

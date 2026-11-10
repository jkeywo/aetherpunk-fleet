extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size=Vector2i(1280,800)
	var doc:=neutral(true)
	card_def(doc,"broadside").cost=2
	card_def(doc,"broadside").rules[0].effects=[attack(6)]
	await open_battle(doc)
	var b=current_scene
	b.state.mana=1
	b._render()
	var before:=JSON.stringify(b.state.board_snapshot())
	var order: Array=b.state.hand.duplicate()
	await drop_card(b,"broadside",0)
	b.get_node("%ManaButton").pressed.emit()
	expect(b.pending_play and b.state.mana==1,"Partial mana payment committed early.")
	b.get_node("%CancelButton").pressed.emit()
	expect(b.state.hand==order and JSON.stringify(b.state.board_snapshot())==before,"Cancel did not refund pending mana.")
	await drop_card(b,"broadside",0)
	b.get_node("%ManaButton").pressed.emit()
	await pay_with(b,"brace")
	await flush()
	expect(b.pending_play and not b.busy and b.state.discard.is_empty(),"Payment resolved before an explicit enemy target.")
	expect(not b.get_node("%EnemyChoice").visible and b.get_node_or_null("%PlayButton")==null,"Dropdown/confirmation controls remain.")
	b.get_node("%CancelButton").pressed.emit()
	expect(b.state.hand==order and b.state.mana==1,"Paid but untargeted cancellation failed.")
	await drop_card(b,"broadside",0)
	b.get_node("%ManaButton").pressed.emit()
	await pay_with(b,"brace")
	b.enemies.widgets[0].pressed.emit()
	await settle(b)
	expect(b.state.monster_hull==64 and b.state.mana==0 and b.state.discard.size()==1,"Clicking final target did not automatically resolve mixed payment.")
	expect(not b.pending_play and conserved(b.state),"Automatic resolution left pending state.")
	expect(b.discard_count_label.text=="1" and b.deck_count_label.text==str(b.state.deck.size()),"Pile count labels stale after committed payment.")
	doc=neutral()
	doc.ships[0].resource.rules=[rule("boost","on_play",[{"kind":"add_shields","target":"owner","amount":3}],"owner","ship")]
	doc.ships[0].resource.rules[0].optional=true
	doc.ships[0].resource.rules[0].costs=[{"kind":"ship_resource","target":"owner","amount":2}]
	await open_battle(doc)
	b=current_scene
	b.state.ships[0].resource=2
	b._select(uid_for(b.state,"brace"))
	b._show_boosts()
	expect(b.boost_dialog.visible,"Boosts unavailable before placing a free card.")
	var checks: Array=b.boost_dialog.find_children("*","CheckBox",true,false)
	checks[0].button_pressed=true
	b.boost_dialog.hide()
	b._cancel()
	expect(b.state.ships[0].resource==2,"Cancelling preselected boost spent resource.")
	b._select(uid_for(b.state,"brace"))
	b._show_boosts()
	checks=b.boost_dialog.find_children("*","CheckBox",true,false)
	checks[0].button_pressed=true
	b.boost_dialog.hide()
	b._circle_selected(0)
	await settle(b)
	expect(b.state.ships[0].resource==0 and b.state.ships[0].guard==3,"Preselected boost was lost on placement.")
	done("Automatic payment and direct targets")

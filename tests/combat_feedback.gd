extends "res://tests/support/v3_test.gd"
var beats: Array=[]
func _run() -> void:
	var doc:=neutral()
	card_def(doc,"brace").rules[0].effects=[attack(6),{"kind":"add_shields","target":"owner","amount":2}]
	doc.leviathans[0].stances[0].reactions=[{"id":"counter","name":"Counter","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(5,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b=current_scene
	b.feedback.beat_started.connect(func(kind): beats.append(kind))
	stage_card(b,"brace",0)
	await flush()
	expect(b.busy and b.get_node("%EndPhaseButton").disabled,"Automatic feedback did not lock input.")
	b._commit()
	await settle(b)
	expect(b.state.monster_hull==64 and b.state.ships[0].hull==25,"Automatic feedback repeated/changed resolution.")
	expect(beats.has("damage") and beats.has("guard") and beats.has("reaction_triggered"),"Combat feedback beats missing.")
	expect(beats.find("reaction_triggered")<beats.find("stance_changed"),"Replacement shown before reaction.")
	expect(not b.busy and not b.feedback.banner.visible,"Feedback did not unlock.")
	expect(b.feedback.overlay.get_child_count()==1,"Feedback leaked transient nodes.")
	done("Combat feedback")

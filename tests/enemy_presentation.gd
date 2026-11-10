extends "res://tests/support/v3_test.gd"
var opened: Array = []
var visible_during_attacks := true
var centered := true
var unlocked_during_effect := false
func _run() -> void:
	var doc := neutral(true)
	for enemy in doc.leviathans:
		enemy.default_action = [attack(1,1,"Long","chosen_ally")]
		enemy.stances[0].effects = [attack(1,1,"Long","chosen_ally")]
		enemy.stances[0].reactions = [{"id":"counter","name":"Counterstrike","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b = current_scene
	b.feedback.enemy_presentation_started.connect(func(kind,data):
		opened.append({"kind":kind,"data":data})
		centered = centered and b.feedback.enemy_card.scale.is_equal_approx(Vector2.ONE) and b.feedback.enemy_card.get_global_rect().get_center().distance_to(b.get_viewport_rect().size/2)<2
		unlocked_during_effect = unlocked_during_effect or not b.busy or not b.get_node("%EndPhaseButton").disabled)
	b.feedback.attack_started.connect(func(attacker,_target):
		if attacker<0: visible_during_attacks = visible_during_attacks and is_instance_valid(b.feedback.enemy_card) and b.feedback.enemy_card.visible)
	stage_card(b,"brace",0)
	await settle(b)
	expect(not opened.is_empty() and opened.all(func(item):return item.kind=="reaction_triggered" and item.data.name=="Counterstrike"),"Reactions did not show their own full-size effect card.")
	expect(centered and visible_during_attacks and not unlocked_during_effect,"Enemy card was not centered or disappeared/unlocked during attack animation.")
	expect(not is_instance_valid(b.feedback.enemy_card) and b.feedback.overlay.get_child_count()==1,"Reaction presentation leaked nodes after resolving.")
	var record: Dictionary = b.state.feedback_events.filter(func(event):return event.kind=="reaction_triggered")[0]
	var captured := JSON.stringify(record.presentation)
	for enemy in b.state.enemies: enemy.stances[0].reactions[0].name="Changed later"
	expect(JSON.stringify(record.presentation)==captured and record.presentation.name=="Counterstrike","Recorded enemy card depends on mutable live definition.")
	# Three cards from one owner guarantee both stance activations and weaker defaults.
	var chosen: Array = []
	for uid in b.state.stance_cards.size():
		if b.state.stance_cards[uid].owner==-1: chosen.append(uid)
	b.state.enemy_row=chosen.slice(0,3)
	b.state.stance_discard.clear()
	b.state.stance_deck=range(b.state.stance_cards.size()).filter(func(uid):return not b.state.enemy_row.has(uid))
	b._render()
	opened.clear()
	b.get_node("%EndPhaseButton").pressed.emit()
	await settle(b)
	expect(opened.size()==5 and opened.all(func(item):return item.kind=="intent_triggered"),"Enemy phase did not present each physical activation and default exactly once.")
	expect(opened.filter(func(item):return item.data.name=="Default action").size()==2,"Default intents have no generated effect card.")
	expect(centered and visible_during_attacks and not unlocked_during_effect,"Enemy intent did not remain enlarged during its effects.")
	expect(not is_instance_valid(b.feedback.enemy_card) and b.feedback.overlay.get_child_count()==1 and not b.busy,"Enemy phase did not clear presentation and unlock.")
	# A lethal enemy attack must close the presentation even if the done job is skipped.
	var ended_clean := [false]
	b.feedback.finished.connect(func():
		if b.state.outcome=="defeat": ended_clean[0]=not is_instance_valid(b.feedback.enemy_card))
	for ship in b.state.ships: ship.hull=0
	b.state.ships[0].hull=1
	b.state.formation=[0,-1,-1,-1]
	b._render()
	b.get_node("%EndPhaseButton").pressed.emit()
	await settle(b)
	expect(ended_clean[0],"Terminal resolution retained enlarged enemy card.")
	done("Full-size enemy effect presentations")

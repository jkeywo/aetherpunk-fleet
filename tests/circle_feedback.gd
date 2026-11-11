extends "res://tests/support/v3_test.gd"
var pulses: Array=[]
func _run() -> void:
	var doc:=neutral()
	var passive:=R.rule("passive",[],"circle")
	passive.id="discount"
	passive.modifiers=[{"kind":"cost","target":"adjacent_cards","amount":1,"card_type":"Attack"}]
	card_def(doc,"brace").rules[1]=passive
	card_def(doc,"broadside").cost=2
	card_def(doc,"broadside").rules[0].effects=[attack(3)]
	await open_battle(doc)
	var b=current_scene
	var source:=uid_for(b.state,"brace")
	b.state.play(source,[],-1,-1,0)
	b._render()
	b._select(uid_for(b.state,"broadside"))
	b.selected_slot=1
	b._update_controls()
	expect(b.circle_view.bonus_slots==[0] and "BONUS" in b.circle_view.buttons[0].text,"Contributor missing.")
	b.selected_slot=2
	b._update_controls()
	expect(b.circle_view.bonus_slots.is_empty(),"Nonadjacent stale highlight.")
	b._cancel()
	doc=neutral()
	card_def(doc,"brace").rules[1]=rule("chain","adjacent_card_played",[attack(2), {"kind": "add_shields", "target": "owner", "amount": 2}],"adjacent")
	await open_battle(doc)
	b=current_scene
	source=uid_for(b.state,"brace")
	b.state.play(source,[],-1,-1,0)
	b._render()
	b.circle_view.link_pulse_started.connect(func(from,to,event): pulses.append([from,to,event]))
	var centered_effects: Array = []
	b.feedback.beat_started.connect(func(kind):
		if kind not in ["damage", "guard"]: return
		var card: Control = b.feedback.player_card
		if card == null or card.get_meta("uid", -1) != source: return
		if b.circle_view.buttons[0].visible: return
		if card.resolving_rule_id != "chain": return
		var highlighted: Array = []
		for id in card.resolving_rule_rows:
			var row: PanelContainer = card.resolving_rule_rows[id]
			if row.get_theme_stylebox("panel").border_width_left > 0: highlighted.append(id)
		if highlighted != ["chain"]: return
		if card.get_global_rect().get_center().distance_to(b.get_viewport_rect().size / 2) < 2:
			var effect_rows: Array = card.resolving_effect_rows["chain"]
			var highlighted_effects: Array = []
			for index in effect_rows.size():
				if effect_rows[index].get_theme_stylebox("panel").border_width_left > 0:
					highlighted_effects.append(index)
			centered_effects.append([kind, card.resolving_effect_index, highlighted_effects]))

	stage_card(b,"broadside",1)
	await settle(b)
	expect(pulses.size()==1 and pulses[0][1]==source,"Auto play did not animate contributor link.")
	expect(b.circle_view.pulse_source==-1 and b.state.monster_hull==68,"Link animation changed rules/stayed active.")
	expect(centered_effects == [["damage", 0, [0]], ["guard", 1, [1]]], "Chained card did not highlight only the firing rule through both effects.")
	expect(b.feedback.player_card == null and b.circle_view.contents[0] == source and b.circle_view.buttons[0].visible, "Chained card did not return to its original slot.")
	done("Circle contribution feedback")

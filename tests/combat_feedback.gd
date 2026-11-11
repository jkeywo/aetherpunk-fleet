extends "res://tests/support/v3_test.gd"
var beats: Array=[]
var flashed_sides: Dictionary={}
func _run() -> void:
	var doc:=neutral()
	card_def(doc,"brace").rules[0].effects=[attack(6),{"kind":"add_shields","target":"owner","amount":2}]
	doc.leviathans[0].stances[0].reactions=[{"id":"counter","name":"Counter","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(5,1,"Long","chosen_ally"), {"kind":"add_cover","target":"source_slot","amount":2}]}]
	await open_battle(doc)
	var b=current_scene
	var support_targets: Array = []
	b.feedback.beat_started.connect(func(kind):
		beats.append(kind)
		if kind in ["guard", "cover"]: support_targets.append(b.feedback.effect_targets.duplicate(true)))
	var player_centered := [false]
	var circle_hidden := [false]
	var foreground_ok := [true]
	var attack_targets: Array = []
	b.feedback.attack_started.connect(func(attacker, target):
		attack_targets.append([target, b.feedback.effect_targets.get("units", []).duplicate()])
		var card: Control = b.feedback.player_card if attacker >= 0 else b.feedback.enemy_card
		if card == null:
			foreground_ok[0] = false
			return
		var stage: Control = card.get_parent()
		foreground_ok[0] = foreground_ok[0] and stage.get_canvas() == b.allies.get_canvas() and stage.get_canvas() == b.enemies.get_canvas()
		foreground_ok[0] = foreground_ok[0] and stage.z_index < mini(b.allies.z_index, b.enemies.z_index) and b.feedback.layer > 0
		if attacker >= 0:
			player_centered[0] = card.get_global_rect().get_center().distance_to(b.get_viewport_rect().size / 2) < 2 and card.resolving_rule_id == b.state.card(card.get_meta("uid")).rules[0].id and card.resolving_effect_index == 0
			circle_hidden[0] = not b.circle_view.buttons[0].visible
		else:
			foreground_ok[0] = foreground_ok[0] and b.feedback.player_card == null)

	b.feedback.duration_scale = 0.25
	stage_card(b,"brace",0)
	await flush()
	expect(b.busy and b.get_node("%EndPhaseButton").disabled,"Automatic feedback did not lock input.")
	b._commit()
	while b.busy:
		for side in [b.allies, b.enemies]:
			for unit in side.widgets.values():
				if "art" in unit and unit.art.modulate.g < 0.75 and unit.art.modulate.r > 0.95:
					flashed_sides[side.enemy] = true
		await process_frame
	await flush()
	expect(flashed_sides.has(false), "Damaged ship artwork did not flash red.")
	expect(flashed_sides.has(true), "Damaged monster artwork did not flash red.")
	for side in [b.allies, b.enemies]:
		for unit in side.widgets.values():
			if "art" in unit: expect(unit.art.modulate == Color.WHITE, "Damage flash left artwork tinted.")
	expect(b.state.monster_hull==64 and b.state.ships[0].hull==25,"Automatic feedback repeated/changed resolution.")
	expect(beats.has("damage") and beats.has("guard") and beats.has("reaction_triggered"),"Combat feedback beats missing.")
	expect(beats.find("reaction_triggered")<beats.find("stance_changed"),"Replacement shown before reaction.")
	expect(not b.busy and not b.feedback.banner.visible,"Feedback did not unlock.")
	expect(b.feedback.overlay.get_child_count()==1,"Feedback leaked transient nodes.")
	expect(player_centered[0] and circle_hidden[0], "Played card was not centered during its attack or was duplicated in the circle.")
	expect(foreground_ok[0], "A card obscured the entities or remained onscreen into the enemy reaction.")
	expect(b.feedback.card_stage.get_child_count() == 0 and b.circle_view.buttons[0].visible, "Played card did not return to the circle after resolving.")
	expect(attack_targets == [[-1, [-1]], [0, [0]]], "Player and enemy attacks did not highlight their resolved target.")
	expect(support_targets == [{"units": [0]}, {"slots": [4]}], "Shield and cover effects did not highlight the correct unit and slot.")
	expect(b.feedback.effect_targets.is_empty(), "Target highlight remained after resolution.")
	done("Combat feedback")

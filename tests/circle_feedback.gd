extends "res://tests/support/v2_test.gd"
var pulses: Array = []


func _run() -> void:
	var doc := neutral()
	var source := card_def(doc, "advance")
	source.modifiers = [
		{"stat": "damage", "amount": 2, "tag": "Attack", "condition": {"tag": "", "min": 0}},
		{"stat": "cost", "amount": 1, "tag": "Attack", "condition": {"tag": "", "min": 0}},
		{"stat": "guard", "amount": 99, "tag": "", "condition": {"tag": "", "min": 0}}]
	var shot := card_def(doc, "broadside")
	shot.cost = 2
	shot.effects = [{"kind": "damage_monster", "amount": 3}]
	shot.on_play = [{"condition": {"tag": "Attack", "min": 1}, "effects": [{"kind": "damage_monster", "amount": 1}]}]
	await open_battle(doc)
	var battle = current_scene
	var source_uid := uid_for(battle.state, "advance")
	battle.state.play(source_uid, [], -1, -1, 0)
	battle._render()
	field_key(battle, "broadside").pressed.emit()
	var circle = battle.circle_view
	expect(battle.get_node("%PlayButton").disabled, "Unpaid example should remain unaffordable.")
	expect(circle.bonus_slots == [0], "Bonus highlight disappeared before payment.")
	expect("BONUS" in circle.buttons[0].text, "Bonus source needs an explicit badge.")
	expect("+2 damage" in circle.buttons[0].tooltip_text and "−1 cost" in circle.buttons[0].tooltip_text, "Source tooltip lacks modifier explanations.")
	expect("Enables on-play" in str(circle.contribution_details[source_uid]) and "+99 guard" not in str(circle.contribution_details[source_uid]), "Conditional source or stat eligibility incorrect.")
	expect(circle.buttons[0].get_theme_stylebox("normal").border_width_left == 3, "Source needs a visible border beyond tint.")
	var preview: Dictionary = battle.state.preview(uid_for(battle.state, "broadside"), [], -1, -1, 1)
	expect(not preview.ok and preview.contributors == [source_uid], "Unaffordable preview failed to report public bonus sources.")
	circle.buttons[2].pressed.emit()
	expect(circle.bonus_slots.is_empty() and not "BONUS" in circle.buttons[0].text, "Moving to a nonadjacent slot left a stale bonus.")
	battle.get_node("%CancelButton").pressed.emit()
	field_key(battle, "broadside").pressed.emit()
	circle.buttons[3].pressed.emit()
	expect(circle.bonus_slots == [0], "Selecting another adjacent slot did not restore bonuses.")
	battle.get_node("%CancelButton").pressed.emit()
	expect(circle.bonus_slots.is_empty() and circle.selected == -1, "Cancelling left stale highlights.")

	# The amount condition must succeed before a neighbour is credited.
	card_def(doc, "broadside").on_play[0].condition.min = 2
	card_def(doc, "advance").modifiers = []
	var b = State.new(1, doc)
	b.play(uid_for(b, "advance"), [], -1, -1, 0)
	expect(b.contributing_cards(uid_for(b, "broadside"), 1).is_empty(), "An unmet conditional bonus was highlighted.")
	b.play(uid_for(b, "tow"), [], -1, -1, 2)
	expect(b.contributing_cards(uid_for(b, "broadside"), 1).size() == 2, "Both neighbours enabling a count condition should be highlighted.")
	b.play(uid_for(b, "escort"), [], -1, -1, 1)
	b.play(uid_for(b, "salvo"), [], -1, -1, 3)
	expect(b.expanded and b.contributing_cards(uid_for(b, "broadside"), 4).size() == 4, "Expanded-centre highlights used the wrong graph.")
	expect(b.contributing_cards(uid_for(b, "broadside"), 5).size() == 2, "Expanded corner should credit its two matching neighbours.")

	doc = chain_document()
	await open_battle(doc)
	battle = current_scene
	source_uid = uid_for(battle.state, "advance")
	battle.state.play(source_uid, [], -1, -1, 0)
	battle._render()
	circle = battle.circle_view
	var echo_uid := uid_for(battle.state, "tow")
	circle.link_pulse_started.connect(func(source_id, receiver_id, event): pulses.append([source_id, receiver_id, event]))
	field_key(battle, "tow").pressed.emit()
	circle.buttons[1].pressed.emit()
	var anticipated: Dictionary = battle.state.preview(echo_uid, [], -1, -1, 1)
	expect(anticipated.contributors == [source_uid] and "Will trigger" in str(anticipated.contribution_details), "Preview failed to identify an adjacent chained contributor.")
	battle.get_node("%PlayButton").pressed.emit()
	await circle.link_pulse_started
	expect(circle.pulse_source == 1 and circle.pulse_receiver == 0 and circle.pulse_event == "damage", "First pulse direction does not follow the cause.")
	expect("Towline Manoeuvre → Shield Advance" in battle.feedback.banner_label.text, "Chain banner does not name cause and receiver.")
	battle.get_node("%GearButton").pressed.emit()
	var paused_progress: float = circle.pulse_progress
	await flush()
	expect(paused and is_equal_approx(circle.pulse_progress, paused_progress), "Link animation ignored the battle pause.")
	battle.menu.id_pressed.emit(0)
	battle.menu.hide()
	await battle.resolution_finished
	expect(pulses == [[echo_uid, source_uid, "damage"], [source_uid, echo_uid, "guard"]], "Chain links did not pulse sequentially in causal order.")
	expect(circle.pulse_source == -1 and circle.pulse_receiver == -1 and circle.pulse_event == "", "Finished playback left a glowing chain.")
	expect(battle.state.monster_hull == 67 and battle.state.used_triggers.size() == 2, "Link feedback changed combat resolution.")
	var triggers: Array = battle.state.feedback_events.filter(func(event): return event.kind == "card_triggered")
	expect(triggers[0].source_uid == echo_uid and triggers[0].source_amount == 1 and triggers[1].source_event == "guard", "Recorded chain provenance incorrect.")
	expect(not battle.busy and not battle.feedback.running, "Link playback did not unlock input.")

	# Leaving during an active pulse must not resume an abandoned battle.
	await open_battle(doc)
	battle = current_scene
	battle.state.play(uid_for(battle.state, "advance"), [], -1, -1, 0)
	battle._render()
	field_key(battle, "tow").pressed.emit()
	battle.circle_view.buttons[1].pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	await battle.circle_view.link_pulse_started
	battle.get_node("%GearButton").pressed.emit()
	battle.menu.id_pressed.emit(2)
	await scene_changed
	await flush()
	expect(current_scene.name == "MainMenu" and not paused, "Leaving during a chain pulse failed.")
	done("Magic circle feedback")


func chain_document() -> Dictionary:
	var doc := neutral()
	card_def(doc, "advance").triggers = [trigger("ward", "damage", [{"kind": "guard", "target": "event_actor", "amount": 3}])]
	card_def(doc, "tow").effects = [{"kind": "damage_monster", "amount": 1}]
	card_def(doc, "tow").triggers = [trigger("echo", "guard", [{"kind": "damage_monster", "amount": 2}])]
	return doc

extends "res://tests/support/v3_test.gd"
var opened: Array = []
var visible_during_attacks := true
var centered := true
var unlocked_during_effect := false
var lifted_slot_stays_empty := true
func _run() -> void:
	var doc := neutral(true)
	for enemy in doc.leviathans:
		enemy.default_action = [attack(1,1,"Long","chosen_ally"), attack(1,1,"Long","chosen_ally")]
		enemy.stances[0].effects = [attack(1,1,"Long","chosen_ally"), attack(1,1,"Long","chosen_ally")]
		enemy.stances[0].reactions = [{"id":"counter","name":"Counterstrike","category":"Retaliation","conditions":{"kind":"always"},"effects":[attack(1,1,"Long","chosen_ally"), attack(1,1,"Long","chosen_ally")]}]
	await open_battle(doc)
	var b = current_scene
	var active_rows: Array = []
	b.feedback.enemy_presentation_started.connect(func(kind,data):
		opened.append({"kind":kind,"data":data})
		centered = centered and b.feedback.enemy_card.scale.is_equal_approx(Vector2.ONE) and b.feedback.enemy_card.get_global_rect().get_center().distance_to(b.get_viewport_rect().size/2)<2
		unlocked_during_effect = unlocked_during_effect or not b.busy or not b.get_node("%EndPhaseButton").disabled)
	b.feedback.attack_started.connect(func(attacker,_target):
		if attacker >= 0: return
		var card: Control = b.feedback.enemy_card
		visible_during_attacks = visible_during_attacks and is_instance_valid(card) and card.visible
		if not is_instance_valid(card): return
		var highlighted: Array = []
		for i in card.effect_rows.size():
			if card.effect_rows[i].get_theme_stylebox("panel").border_width_left > 0: highlighted.append(i)
		active_rows.append(highlighted))
	# Put the first reacting enemy in the middle slot to check slot identity.
	var reaction_row: Array = []
	for owner in [-2, -1, -3]:
		for uid in b.state.stance_cards.size():
			if b.state.stance_cards[uid].owner == owner:
				reaction_row.append(uid)
				break
	b.state.enemy_row = reaction_row.duplicate()
	b.state.stance_deck = range(b.state.stance_cards.size()).filter(func(uid): return not reaction_row.has(uid))
	b.state.stance_discard.clear()
	var incoming_uid: int = b.state.stance_deck[0]
	b._render()
	var middle_x: float = b.stance_panel.buttons[1].position.x
	var moving: Dictionary = {}
	var settled_before_next := [false]
	var exiting := [false]
	var exit_origin := [Vector2.ZERO]
	var moved_right := [false]
	var straight_exit := [true]
	var reaction_lifts: Dictionary = {}
	var watch_reaction_motion := func():
		_observe_lift(b, reaction_lifts)
		if exiting[0] and is_instance_valid(b.feedback.enemy_card):
			var card: Control = b.feedback.enemy_card
			moved_right[0] = moved_right[0] or card.position.x > exit_origin[0].x + 1.0
			straight_exit[0] = straight_exit[0] and card.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(card.position.y, exit_origin[0].y)
		var in_motion: Array = []
		for button in b.stance_panel.buttons:
			if button.has_meta("stance_uid") and button.position.y < 0.0:
				in_motion.append(button.get_meta("stance_uid"))
		if in_motion.size() != 1: return
		var uid: int = in_motion[0]
		moving[uid] = b.stance_panel.card_button(uid).position.x
	var watch_next_reaction := func(kind: String):
		if kind == "enemy_effect_finished" and is_instance_valid(b.feedback.enemy_card):
			exiting[0] = true
			exit_origin[0] = b.feedback.enemy_card.position
		elif kind == "reaction_triggered":
			exiting[0] = false
		if kind != "reaction_triggered" or opened.size() != 1: return
		var replacement: Control = b.stance_panel.card_button(incoming_uid)
		settled_before_next[0] = replacement != null and is_equal_approx(replacement.position.x, middle_x) and is_zero_approx(replacement.position.y)
	process_frame.connect(watch_reaction_motion)
	b.feedback.beat_started.connect(watch_next_reaction)
	b.feedback.duration_scale = 0.16
	stage_card(b,"brace",0)
	await settle(b)
	b.feedback.duration_scale = 0.01
	process_frame.disconnect(watch_reaction_motion)
	b.feedback.beat_started.disconnect(watch_next_reaction)
	expect(reaction_lifts.has(reaction_row[1]) and not moving.has(reaction_row[1]) and is_equal_approx(moving.get(incoming_uid, -1.0), middle_x), "Reacting card did not lift directly from its slot or the replacement entered the wrong slot.")
	expect(settled_before_next[0], "Reaction replacement did not settle before the next reaction.")
	expect(moved_right[0] and straight_exit[0], "Enlarged reaction card did not slide straight out at full size.")
	expect(opened.all(func(item):return item.data.get("owner_visual",{}).get("id","")==b.state.unit(item.data.owner).id),"Enlarged enemy card lost its owning monster visual identity.")
	expect(not opened.is_empty() and opened.all(func(item):return item.kind=="reaction_triggered" and item.data.name=="Counterstrike"),"Reactions did not show their own full-size effect card.")
	expect(centered and visible_during_attacks and not unlocked_during_effect,"Enemy card was not centered or disappeared/unlocked during attack animation.")
	expect(not is_instance_valid(b.feedback.enemy_card) and b.feedback.overlay.get_child_count()==1,"Reaction presentation leaked nodes after resolving.")
	var reaction_rows: Array = []
	for _item in opened: reaction_rows.append_array([[0], [1]])
	expect(active_rows == reaction_rows, "Reaction did not highlight each identical effect by its position as it resolved.")
	active_rows.clear()
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
	var initial_row: Array = b.state.enemy_row.duplicate()
	var original_columns: Dictionary = {}
	for button in b.stance_panel.buttons:
		original_columns[button.get_meta("stance_uid", -1)] = button.position.x
	var rows_at_activation: Array = []
	var activation_lifts: Dictionary = {}
	var refill_samples: Array = []
	var refilling := [false]
	var columns_stable := [true]
	var watch_beats := func(kind: String):
		if kind == "stance_changed": refilling[0] = true
		if kind != "intent_triggered": return
		var shown: Array = []
		for button in b.stance_panel.buttons:
			if not button.visible or not button.has_meta("stance_uid"): continue
			var uid: int = button.get_meta("stance_uid")
			shown.append(uid)
			columns_stable[0] = columns_stable[0] and is_equal_approx(button.position.x, original_columns.get(uid, -1.0))
		rows_at_activation.append(shown)
	var watch_motion := func():
		_observe_lift(b, activation_lifts)
		if not refilling[0]: return
		var entering: Array = []
		for button in b.stance_panel.buttons:
			if not button.has_meta("stance_uid") or button.position.y >= 0.0: continue
			entering.append(button.position.y)
		if not entering.is_empty(): refill_samples.append(entering)
	b.feedback.beat_started.connect(watch_beats)
	process_frame.connect(watch_motion)
	b.feedback.duration_scale = 0.16
	b.get_node("%EndPhaseButton").pressed.emit()
	await settle(b)
	b.feedback.beat_started.disconnect(watch_beats)
	process_frame.disconnect(watch_motion)
	b.feedback.duration_scale = 0.01
	expect(rows_at_activation == [initial_row, initial_row.slice(1), initial_row.slice(2), [], []] and columns_stable[0], "Resolved cards did not leave fixed gaps through the last default action.")
	expect(activation_lifts.size() == initial_row.size() and initial_row.all(func(uid): return activation_lifts.has(uid)), "Each resolving card should lift directly from the row.")
	expect(lifted_slot_stays_empty, "A lifted card appeared in the row while the enlarged version was onscreen.")
	expect(refill_samples.any(func(sample): return sample.size() == b.state.enemy_row.size() and sample.all(func(y): return is_equal_approx(y, sample[0]))), "Replacement cards did not slide in together.")
	expect(opened.size()==5 and opened.all(func(item):return item.kind=="intent_triggered"),"Enemy phase did not present each physical activation and default exactly once.")
	expect(opened.filter(func(item):return item.data.name=="Default action").size()==2,"Default intents have no generated effect card.")
	expect(active_rows == [[0], [1], [0], [1], [0], [1], [0], [1], [0], [1]], "Enemy stances and default actions did not highlight effects in order.")
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


func _observe_lift(battle, observed: Dictionary) -> void:
	var card: Control = battle.feedback.enemy_card
	if not is_instance_valid(card) or not card.has_meta("lifted_uid"): return
	var uid: int = card.get_meta("lifted_uid")
	observed[uid] = true
	var source: Control = battle.stance_panel.card_button(uid)
	lifted_slot_stays_empty = lifted_slot_stays_empty and (source == null or not source.visible)

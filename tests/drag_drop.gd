extends "res://tests/support/v2_test.gd"


func motion(point: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(40, -60)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event)
	await flush()


func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event)
	await flush()


func begin_drag(battle, key: String) -> void:
	var face := field_key(battle, key)
	await motion(face.get_global_transform_with_canvas() * Vector2(60, 60))
	var point: Vector2 = face.get_global_transform_with_canvas() * Vector2(60, 60)
	await mouse(point, true)
	await motion(point + Vector2(0, -80), true)
	expect(root.gui_is_dragging() and battle.dragged_uid == face.get_meta("uid"), "Native mouse gesture did not start a hand-card drag.")


func hover_slot(battle, slot: int) -> Vector2:
	var button: Control = battle.circle_view.buttons[slot]
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2)
	await motion(point, true)
	return point


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var doc := neutral()
	card_def(doc, "advance").tags = ["Tactic"]
	card_def(doc, "advance").effects = [{"kind": "guard", "target": "actor", "amount": 2}]
	card_def(doc, "advance").modifiers = [
		{"stat": "damage", "amount": 2, "tag": "Attack", "condition": {"tag": "", "min": 0}},
		{"stat": "cost", "amount": 1, "tag": "", "condition": {"tag": "", "min": 0}}]
	card_def(doc, "salvo").cost = 1
	card_def(doc, "salvo").effects = [{"kind": "damage_monster", "amount": 3}]
	card_def(doc, "salvo").on_play = [{"condition": {"tag": "Tactic", "min": 1}, "effects": [{"kind": "damage_monster", "amount": 2}]}]
	await open_battle(doc)
	var battle = current_scene
	var before: String = JSON.stringify(battle.state.board_snapshot())
	var rng_before: int = battle.state.rng.state
	await begin_drag(battle, "advance")
	expect(battle.circle_view.valid_drop_slots == [0, 1, 2, 3], "Initial legal slots not highlighted.")
	expect(is_equal_approx(field_key(battle, "advance").modulate.a, 0.35), "Dragged source was not faded.")
	expect(battle.get_node("%EndPhaseButton").disabled and battle._begin_card_drag(uid_for(battle.state, "tow")).is_empty(), "Active drag allowed another action or drag.")
	expect("DROP HERE" in battle.circle_view.buttons[0].text and battle.circle_view.buttons[4].disabled, "Drop labels or locked slots incorrect.")
	var point := await hover_slot(battle, 0)
	expect(battle.drag_hover_slot == 0 and battle.circle_view.selected == 0, "Native hover did not preview the destination.")
	expect(JSON.stringify(battle.state.board_snapshot()) == before and battle.state.rng.state == rng_before, "Dragging mutated combat state or RNG.")
	await mouse(point, false)
	expect(not root.gui_is_dragging() and battle.dragged_uid == -1 and not battle.circle_view.drag_active, "Successful drop left drag state active.")
	expect(battle.selected_uid == uid_for(battle.state, "advance") and battle.selected_slot == 0, "Drop did not select the card and slot.")
	expect(battle.state.play_order.is_empty() and battle.state.hand.size() == 7 and battle.state.discard.is_empty(), "Drop played or spent a card without confirmation.")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.circle[0] >= 0 and conserved(battle.state), "Dropped card could not be confirmed normally.")

	await begin_drag(battle, "salvo")
	expect(battle.circle_view.valid_drop_slots == [1, 2, 3], "Occupied slot remained a valid destination.")
	var payload: Dictionary = battle.drag_payload.duplicate()
	expect(not battle._can_drop_card({"kind": "fleet_hand_card", "uid": 0}, 1), "Foreign drag payload accepted.")
	var stale := payload.duplicate()
	stale.serial -= 1
	expect(not battle._can_drop_card(stale, 1), "Stale drag payload accepted.")
	point = await hover_slot(battle, 1)
	expect(battle.circle_view.bonus_slots == [0] and "BONUS" in battle.circle_view.buttons[0].text, "Hovering adjacent did not highlight the bonus source.")
	expect("+2 damage" in str(battle.circle_view.contribution_details) and "−1 cost" in str(battle.circle_view.contribution_details), "Drag preview lacks damage/discount explanations.")
	expect("70 → 61" in battle.get_node("%Inspection").text, "Drag preview did not include the conditional effect and modifiers.")
	point = await hover_slot(battle, 2)
	expect(battle.circle_view.bonus_slots.is_empty() and "Payment 0 / 1" in battle.get_node("%Inspection").text, "Nonadjacent drag preview retained a bonus or wrong cost.")
	point = await hover_slot(battle, 3)
	await mouse(point, false)
	expect(battle.selected_slot == 3 and battle.payment.is_empty() and battle.state.play_order.size() == 1, "Drop bypassed confirmation or retained unrelated payment.")
	expect(not battle._can_drop_card(payload, 2), "Completed drag token remained usable.")

	# Pending plays must be cancelled before another card is dragged.
	expect(battle.pending_play and field_key(battle, "salvo") == null, "Dropped card did not leave the hand for a pending circle slot.")
	expect(battle._begin_card_drag(uid_for(battle.state, "patch")).is_empty(), "Another drag started while a play was pending.")
	battle.get_node("%CancelButton").pressed.emit()
	var before_invalid: String = JSON.stringify(battle.state.board_snapshot())
	await begin_drag(battle, "patch")
	point = await hover_slot(battle, 0)
	expect(not battle._can_drop_card(battle.drag_payload, 0), "Occupied circle slot accepted a drop.")
	await mouse(point, false)
	expect(not battle.pending_play and battle.selected_uid == -2, "Invalid occupied drop staged an action.")
	await begin_drag(battle, "patch")
	point = await hover_slot(battle, 4)
	expect(not battle._can_drop_card(battle.drag_payload, 4), "Locked circle slot accepted a drop.")
	await mouse(point, false)
	expect(JSON.stringify(battle.state.board_snapshot()) == before_invalid and not battle.pending_play, "Locked drop changed combat state.")
	await begin_drag(battle, "patch")
	await motion(Vector2(400, 410), true)
	await mouse(Vector2(400, 410), false)
	expect(battle.drag_hover_slot == -1 and is_equal_approx(field_key(battle, "patch").modulate.a, 1.0), "Cancelled native drag retained hover or faded source.")

	battle.state.definitions.cards.salvo.cost = 99
	await begin_drag(battle, "salvo")
	expect(battle.circle_view.valid_drop_slots.is_empty() and "Unavailable" in battle.circle_view.buttons[1].text, "Impossible funding was marked valid.")
	await mouse(Vector2(400, 410), false)
	battle.state.definitions.cards.salvo.cost = 1
	battle.state.definitions.cards.salvo.allowed_positions = ["rear"]
	await begin_drag(battle, "salvo")
	expect(battle.circle_view.valid_drop_slots.is_empty(), "Acting-position restriction was ignored.")
	await mouse(Vector2(400, 410), false)
	battle.state.definitions.cards.salvo.allowed_positions = Geometry.POSITIONS.duplicate()
	battle.state.formation[1] = -1
	battle.state.ships[1].hull = 0
	await begin_drag(battle, "salvo")
	expect(battle.circle_view.valid_drop_slots.is_empty(), "Destroyed owner's card was playable by dragging.")
	await mouse(Vector2(400, 410), false)
	var selection: int = uid_for(battle.state, "salvo")
	battle.busy = true
	expect(battle._begin_card_drag(selection).is_empty(), "Dragging began during feedback playback.")
	battle.busy = false
	battle.state.phase = "discard"
	expect(battle._begin_card_drag(selection).is_empty(), "Dragging began during mandatory discard.")
	battle.state.phase = "refresh"
	expect(battle._begin_card_drag(selection).is_empty(), "Dragging began during hand refresh.")

	await open_battle(doc)
	battle = current_scene
	for pair in [["advance", 0], ["escort", 1], ["brace", 2], ["patch", 3]]:
		battle.state.play(uid_for(battle.state, pair[0]), [], -1, -1, pair[1])
	battle._clear_draft()
	battle._render()
	await begin_drag(battle, "salvo")
	expect(battle.circle_view.valid_drop_slots == [4, 5, 6, 7, 8], "Expanded circle did not expose its five empty slots.")
	point = await hover_slot(battle, 4)
	expect(battle.circle_view.bonus_slots == [0], "Expanded-centre hover missed its bonus source.")
	point = await hover_slot(battle, 5)
	expect(battle.circle_view.bonus_slots == [0], "Expanded-corner hover missed its adjacent source.")
	point = await hover_slot(battle, 6)
	expect(battle.circle_view.bonus_slots.is_empty(), "Expanded-corner hover included a nonadjacent source.")
	await mouse(point, false)
	expect(battle.selected_slot == 6 and battle.state.play_order.size() == 4, "Expanded drop auto-played or selected the wrong slot.")
	done("Card drag and drop")

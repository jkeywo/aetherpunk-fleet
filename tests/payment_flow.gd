extends "res://tests/drag_drop.gd"

func drop_card(battle, key: String, slot: int) -> void:
	await begin_drag(battle, key)
	var point := await hover_slot(battle, slot)
	await mouse(point, false)

func pay_card(battle, key: String) -> void:
	field_key(battle, key).pressed.emit()
	await battle.payment_finished

func _run() -> void:
	root.size = Vector2i(1280, 800)
	await open_battle()
	var battle = current_scene
	var initial_hand: Array = battle.state.hand.duplicate()
	var initial_board := JSON.stringify(battle.state.board_snapshot())
	var initial_rng: int = battle.state.rng.state
	var initial_history: Array = battle.state.history.duplicate()
	var uid := uid_for(battle.state, "salvo")
	# Clicking a card before placing it selects it; it cannot prepay another card.
	field_key(battle, "salvo").pressed.emit()
	field_key(battle, "escort").pressed.emit()
	expect(battle.selected_uid == uid_for(battle.state, "escort") and battle.payment.is_empty(), "Cards could be discarded as payment before placement.")
	battle.get_node("%CancelButton").pressed.emit()
	await drop_card(battle, "salvo", 0)
	expect(battle.pending_play and battle.selected_uid == uid, "Drop did not begin a pending play.")
	expect(field_key(battle, "salvo") == null and battle.hand_view.get_child_count() == 6, "Pending card remained visible in hand.")
	expect(battle.circle_view.contents[0] == uid and "PENDING" in battle.circle_view.buttons[0].text, "Pending card was not shown on its destination.")
	expect(battle.state.circle[0] == -1 and JSON.stringify(battle.state.board_snapshot()) == initial_board, "Dropping resolved or mutated the real battle.")
	expect(battle.get_node("%CancelButton").text == "Cancel Play" and battle.get_node("%EndPhaseButton").disabled, "Pending play lacks rollback or allows ending the turn.")
	expect(battle._begin_card_drag(uid_for(battle.state, "tow")).is_empty(), "Another drag began during pending payment.")
	await pay_card(battle, "escort")
	expect(battle.payment.size() == 1 and field_key(battle, "escort") == null and battle.hand_view.get_child_count() == 5, "Clicking payment did not visually discard it.")
	expect("+1 pending" in battle.get_node("%DiscardPile").text and battle.get_node("%PlayButton").disabled, "Partial payment UI incorrect.")
	expect(battle.state.hand == initial_hand and battle.state.discard.is_empty() and battle.state.monster_hull == 70, "Partial payment committed cards or effects.")
	battle.get_node("%CancelButton").pressed.emit()
	expect(not battle.pending_play and battle.selected_uid == -2 and battle.payment.is_empty(), "Cancel did not clear pending play.")
	expect(battle.hand_view.get_child_count() == 7 and battle.circle_view.contents[0] == -1, "Cancel failed to restore the pending card/payment.")
	expect(battle.state.hand == initial_hand and JSON.stringify(battle.state.board_snapshot()) == initial_board and battle.state.rng.state == initial_rng and battle.state.history == initial_history, "Cancel changed card order, state, RNG, or history.")
	expect(not battle.state.card(uid).has("pending_status") and not battle.feedback.running and not battle.feedback.banner.visible, "Cancel leaked pending presentation state.")
	# Fully paid remains cancellable until explicit resolution.
	await drop_card(battle, "salvo", 1)
	await pay_card(battle, "escort")
	await pay_card(battle, "brace")
	expect(battle.state.payment_total(battle.payment) == 3 and not battle.get_node("%PlayButton").disabled and battle.get_node("%PlayButton").text == "Resolve Card", "Fully funded pending play was not ready.")
	field_key(battle, "patch").pressed.emit()
	expect(battle.payment.size() == 2 and field_key(battle, "patch") != null, "Already-funded play accepted another payment.")
	battle.get_node("%CancelButton").pressed.emit()
	expect(battle.state.hand == initial_hand and battle.hand_view.get_child_count() == 7 and battle.state.monster_hull == 70, "Cancelling fully funded play failed to refund everything.")
	await drop_card(battle, "salvo", 1)
	await pay_card(battle, "escort")
	await pay_card(battle, "brace")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.monster_hull == 56 and battle.state.circle[1] == uid and battle.state.discard.size() == 2 and battle.state.hand.size() == 4, "Resolve did not commit the paid card/effect exactly once.")
	expect(not battle.pending_play and battle.payment.is_empty() and conserved(battle.state), "Resolve left pending state or lost cards.")
	await flush()
	expect(battle.feedback.overlay.get_child_count() == 1, "Payment animations leaked nodes.")
	# Targeted free cards wait for an explicit choice and can be cancelled.
	var doc := neutral()
	card_def(doc, "escort").effects = [{"kind": "guard", "target": "ally", "exclude_actor": true, "amount": 3}]
	await open_battle(doc)
	battle = current_scene
	await drop_card(battle, "escort", 0)
	expect(battle.get_node("%TargetChoice").get_item_id(0) == -999 and battle.target == -1 and battle.get_node("%PlayButton").disabled, "Targeted pending card silently chose its target.")
	select_option_by_id(battle.get_node("%TargetChoice"), 1)
	expect(not battle.get_node("%PlayButton").disabled and battle.state.ships[1].guard == 0, "Choosing a target resolved early or did not enable resolution.")
	battle.get_node("%CancelButton").pressed.emit()
	expect(battle.state.ships[1].guard == 0 and battle.hand_view.get_child_count() == 7, "Cancelling a targeted free card did not roll back.")
	await drop_card(battle, "escort", 0)
	select_option_by_id(battle.get_node("%TargetChoice"), 1)
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.ships[1].guard == 3 and conserved(battle.state), "Targeted staged card failed to resolve.")
	# Basic actions also keep their own discarded card reversible until confirmed.
	await open_battle(neutral())
	battle = current_scene
	battle.state.ships[0].hull = 24
	battle._render()
	await begin_drag(battle, "brace")
	var widget: Control = battle.allies.target_widget(0)
	var point: Vector2 = widget.get_global_rect().get_center()
	await motion(point, true)
	await mouse(point, false)
	expect(battle.pending_play and battle.basic_target == 0 and field_key(battle, "brace") == null and "+1 pending" in battle.get_node("%DiscardPile").text, "Basic action did not stage its discarded card.")
	battle.get_node("%CancelButton").pressed.emit()
	expect(battle.state.ships[0].hull == 24 and battle.state.discard.is_empty() and field_key(battle, "brace") != null, "Basic action cancel failed to restore its card without healing.")
	var draw_doc := fixture.duplicate(true)
	draw_doc.setup.opening_hand[0] = "relay"
	await open_battle(draw_doc)
	battle = current_scene
	await drop_card(battle, "relay", 0)
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.phase == "discard" and not battle.pending_play and battle.get_node("%CancelButton").disabled, "Resolved draw/discard retained a cancellable pending play.")
	field_key(battle, "tow").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.phase == "fleet" and conserved(battle.state), "Mandatory discard did not resume the committed card.")
	await drop_card(battle, "salvo", 1)
	battle.get_node("%GearButton").pressed.emit()
	battle.menu.id_pressed.emit(2)
	await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(not current_scene.pending_play and current_scene.state.hand.size() == 7 and current_scene.state.play_order.is_empty(), "Leaving a pending play contaminated the next battle.")
	done("Pending card payment")

func select_option_by_id(control: OptionButton, id: int) -> void:
	for index in control.item_count:
		if control.get_item_id(index) == id:
			control.select(index)
			control.item_selected.emit(index)
			return
	expect(false, "Required target unavailable.")

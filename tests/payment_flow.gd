extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size = Vector2i(1280, 800)
	var doc := neutral()
	card_def(doc, "broadside").cost = 2
	card_def(doc, "broadside").rules[0].effects = [attack(6)]
	await open_battle(doc)
	var b = current_scene
	b.state.mana = 1
	b._render()
	var initial := JSON.stringify(b.state.board_snapshot())
	var order: Array = b.state.hand.duplicate()
	var rng: int = b.state.rng.state
	await drop_card(b, "broadside", 0)
	expect(b.pending_play and b.state.circle[0] == -1 and b.circle_view.contents[0] >= 0, "Drop did not stage placement.")
	b.get_node("%ManaButton").pressed.emit()
	await pay_with(b, "brace")
	expect(b.selected_crystals == 1 and b.payment.size() == 1 and not b.get_node("%PlayButton").disabled, "Mixed payment not ready.")
	expect(b.state.mana == 1 and b.state.hand == order, "Draft payment mutated battle.")
	b.get_node("%CancelButton").pressed.emit()
	expect(not b.pending_play and b.state.hand == order and b.state.rng.state == rng, "Cancel failed to restore order/RNG.")
	expect(JSON.stringify(b.state.board_snapshot()) == initial and b.hand_view.get_child_count() == 7, "Cancel changed snapshot.")
	await drop_card(b, "broadside", 0)
	b.get_node("%ManaButton").pressed.emit()
	await pay_with(b, "brace")
	b.get_node("%PlayButton").pressed.emit()
	await b.resolution_finished
	expect(b.state.mana == 0 and b.state.monster_hull == 64 and b.state.discard.size() == 1, "Resolved mixed payment incorrect.")
	expect(not b.pending_play and conserved(b.state), "Payment leaked cards.")
	await flush()
	expect(b.feedback.overlay.get_child_count() == 1, "Payment animation leaked.")
	# Optional spending remains a reservation until Resolve.
	doc = neutral()
	doc.ships[0].resource.rules = [rule("boost", "on_play", [{"kind":"add_shields","target":"owner","amount":3}], "owner", "ship")]
	doc.ships[0].resource.rules[0].optional = true
	doc.ships[0].resource.rules[0].costs = [{"kind":"ship_resource","target":"owner","amount":2}]
	await open_battle(doc)
	b = current_scene
	b.state.ships[0].resource = 2
	stage_card(b, "brace", 0)
	b._show_boosts()
	expect(b.boost_dialog.visible and b._boost_options().size() == 1, "Boost chooser missing.")
	expect(b.boost_dialog.size.y <= root.size.y, "Boost dialog exceeds viewport.")
	b.selected_boosts = [b._boost_options()[0].key]
	b.boost_dialog.hide()
	b._update_controls()
	b.get_node("%CancelButton").pressed.emit()
	expect(b.state.ships[0].resource == 2 and b.state.ships[0].guard == 0, "Cancel spent reserved resource.")
	stage_card(b, "brace", 0)
	expect(b.boost_dialog.size.y <= root.size.y, "Boost dialog exceeds viewport.")
	b.selected_boosts = [b._boost_options()[0].key]
	b._update_controls()
	b.get_node("%PlayButton").pressed.emit()
	await b.resolution_finished
	expect(b.state.ships[0].resource == 0 and b.state.ships[0].guard == 3, "Optional boost failed.")
	done("Native drag and payment")

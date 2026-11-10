extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var b = State.new(1, neutral())
	var uid := uid_for(b, "brace")
	b.ships[0].hull = 24
	expect(b.basic_preview(uid, 0).ok and b.ships[0].hull == 24, "Basic preview mutates.")
	expect(b.play_basic(uid, 0) == "" and b.ships[0].hull == 26 and b.discard.has(uid), "Basic repair did not discard for two hull.")
	expect(b.play_order.is_empty() and conserved(b), "Basic put card in circle/lost cards.")
	b = State.new(1, neutral())
	expect(b.play_basic(uid_for(b, "brace"), 1) == "" and b.formation == [1,0,-1,2], "Adjacent swap failed.")
	expect(b.validate_basic(uid_for(b, "patch"), 1) != "", "Nonadjacent swap accepted.")
	b = State.new(1, neutral())
	b.ships[0].hull = 0
	b.ships[0].resource = 4
	b._cleanup()
	expect(b.ships[0].resource == 0 and b.position_of(0) == -1, "Defeat did not reset resource.")
	expect(b.play_basic(uid_for(b, "brace"), 0) == "" and b.ships[0].recovery == 2 and b.ships[0].hull == 0, "Recovery threshold ignored.")
	all_in_hand(b)
	expect(b.play_basic(uid_for(b, "brace"), 0) == "" and b.ships[0].hull == 4 and b.position_of(0) >= 0, "Revival failed.")
	root.size = Vector2i(1280,800)
	await open_battle(neutral())
	var ui = current_scene
	ui.state.ships[0].hull = 24
	ui._render()
	await begin_drag(ui, "brace")
	var point := await hover_ship(ui, 0)
	expect(ui.drag_hover_ship == 0, "Self repair hover not identified.")
	await mouse(point, false)
	expect(ui.pending_play and ui.basic_target == 0 and ui.state.ships[0].hull == 24, "Basic drop committed early.")
	ui.get_node("%CancelButton").pressed.emit()
	expect(ui.state.ships[0].hull == 24 and ui.hand_view.get_child_count() == 7, "Basic Cancel failed.")
	await begin_drag(ui, "brace")
	point = await hover_ship(ui, 0)
	await mouse(point, false)
	ui.get_node("%PlayButton").pressed.emit()
	await ui.resolution_finished
	expect(ui.state.ships[0].hull == 26 and ui.state.discard.size() == 1, "Basic drag/Resolve failed.")
	done("Basic recovery and swaps")

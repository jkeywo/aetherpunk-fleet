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
	await mouse(point,false)
	await settle(ui)
	expect(not ui.pending_play and ui.state.ships[0].hull==26 and ui.state.discard.size()==1,"Repair did not resolve immediately on drop.")
	expect(ui.get_node_or_null("%ManoeuvreButton")==null,"Redundant manoeuvre button remains.")
	await open_battle(neutral())
	ui=current_scene
	await begin_drag(ui,"brace")
	point=await hover_ship(ui,102)
	expect(ui.drag_hover_ship==102,"Empty position did not accept movement hover.")
	await mouse(point,false)
	await settle(ui)
	expect(ui.state.formation[2]==0 and ui.state.formation[0]==-1,"Drop did not move into adjacent empty slot.")
	expect(ui.state.discard.size()==1 and conserved(ui.state),"Basic move did not consume exactly one card.")
	done("Basic recovery and swaps")

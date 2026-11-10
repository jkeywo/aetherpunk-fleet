extends "res://tests/support/v3_test.gd"

func faces(node: Node) -> Array:
	var result: Array = []
	if node.has_meta("discard_uid"): result.append(node)
	for child in node.get_children(): result.append_array(faces(child))
	return result

func _run() -> void:
	root.size = Vector2i(1280, 800)
	await open_battle(neutral())
	var b = current_scene
	var pile: Control = b.get_node("%DiscardPile")
	var point: Vector2 = pile.get_global_transform_with_canvas() * (pile.size / 2)
	await motion(point)
	await mouse(point, true)
	await mouse(point, false)
	await flush()
	expect(is_instance_valid(b.discard_dialog) and b.discard_dialog.visible, "Clicking discard did not open viewer.")
	expect(faces(b.discard_dialog).is_empty(), "Empty discard displayed cards.")
	b.discard_dialog.get_ok_button().pressed.emit()
	b.discard_dialog.hide()
	# Real physical copies must retain their exact order, even with repeated designs.
	var ids: Array = b.state.deck.slice(0, 4)
	for uid in ids:
		b.state.deck.erase(uid)
		b.state.discard.append(uid)
	var before := JSON.stringify([b.state.deck, b.state.discard, b.state.hand])
	pile.pressed.emit()
	await flush()
	var shown := faces(b.discard_dialog)
	var expected: Array = ids.duplicate()
	expected.reverse()
	expect(shown.map(func(face): return face.get_meta("discard_uid")) == expected, "Discard viewer does not show newest-to-oldest physical order.")
	expect(shown[0].info.name == b.state.card(expected[0]).name and shown[0].owner_info.name == b.state.ships[b.state.card(expected[0]).owner].name, "Discard faces lost definition/owner styling.")
	expect(shown[0]._get_drag_data(Vector2.ZERO) == null, "Inspection cards can be dragged into play.")
	expect(JSON.stringify([b.state.deck, b.state.discard, b.state.hand]) == before, "Opening viewer mutated battle piles.")
	b.discard_dialog.hide()
	b.state.deck.append_array(b.state.discard)
	b.state.discard.clear()
	pile.pressed.emit()
	await flush()
	expect(faces(b.discard_dialog).is_empty() and "0 cards" in b.discard_dialog.title, "Reopened viewer retained stale cards.")
	expect(b.discard_dialog.size.x <= root.size.x and b.discard_dialog.size.y <= root.size.y, "Discard viewer exceeds viewport.")
	b.discard_dialog.hide()
	root.size = Vector2i(1024, 640)
	pile.pressed.emit()
	await flush()
	expect(b.discard_dialog.size.x <= root.size.x and b.discard_dialog.size.y <= root.size.y, "Discard viewer exceeds smaller viewport.")
	done("Discard viewer")

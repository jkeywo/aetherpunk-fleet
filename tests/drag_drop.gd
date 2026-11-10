extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size = Vector2i(1280,800)
	var doc := neutral()
	card_def(doc,"brace").cost = 1
	await open_battle(doc)
	var b = current_scene
	var initial := JSON.stringify(b.state.board_snapshot())
	await begin_drag(b,"brace")
	expect(b.circle_view.drop_errors[4] != "", "Expanded slot accepted early.")
	var point := await hover_slot(b,0)
	expect(b.drag_hover_slot == 0 and b.circle_view.drop_errors[0] == "", "Valid drag target missing.")
	await mouse(point,false)
	expect(b.pending_play and JSON.stringify(b.state.board_snapshot()) == initial, "Drop committed prematurely.")
	expect("PENDING" in b.circle_view.buttons[0].text and b.hand_view.get_child_count() == 6, "Pending presentation missing.")
	b.get_node("%CancelButton").pressed.emit()
	expect(b.hand_view.get_child_count() == 7 and not root.gui_is_dragging(), "Drag cancel failed.")
	await begin_drag(b,"brace")
	await mouse(Vector2(20,60),false)
	expect(not b.pending_play and b.dragged_uid == -1, "Outside drop left drag state.")
	done("Native circle drag targets")

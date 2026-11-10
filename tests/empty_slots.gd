extends "res://tests/support/v3_test.gd"
func unframed(button: Button) -> bool:
	for state in ["normal","hover","pressed","focus"]:
		var style: StyleBoxFlat=button.get_theme_stylebox(state)
		if style.border_width_left!=0 or style.bg_color.a!=0:return false
	return true
func _run() -> void:
	await open_battle(neutral())
	var b=current_scene
	expect(unframed(b.allies.widgets[2]),"Idle player vacancy still has a frame.")
	expect(unframed(b.enemies.widgets[1]),"Idle enemy vacancy still has a frame.")
	expect(b.circle_view.buttons.slice(0,4).all(func(button):return unframed(button)),"Idle magic-circle vacancies still have frames.")
	var uid: int=uid_for(b.state,"broadside")
	b._select(uid)
	expect(unframed(b.allies.widgets[2]),"Attack selection framed an unrelated formation vacancy.")
	expect(b.circle_view.buttons[0].get_theme_stylebox("normal").border_width_left>0,"Selecting a playable card did not reveal circle destinations.")
	b._cancel()
	var payload: Dictionary=b._begin_card_drag(uid_for(b.state,"patch"))
	expect(b.allies.widgets[2].get_theme_stylebox("normal").border_width_left==3,"Valid basic-move vacancy has no frame.")
	b._finish_card_drag()
	expect(unframed(b.allies.widgets[2]) and unframed(b.circle_view.buttons[0]),"Cancelling drag left vacancy frames behind.")
	b.state.cover[2]=3;b._render()
	expect(unframed(b.allies.widgets[2]) and b.allies.cover_clouds.has(2),"Frameless vacancy hid its slot cover.")
	b.allies.show_rule_preview({102:"Click to choose slot"})
	expect(b.allies.widgets[2].get_theme_stylebox("normal").border_width_left==3,"Explicit slot target not framed.")
	b.allies.show_rule_preview()
	expect(unframed(b.allies.widgets[2]),"Clearing slot targeting did not remove its frame.")
	done("Contextual empty slot frames")

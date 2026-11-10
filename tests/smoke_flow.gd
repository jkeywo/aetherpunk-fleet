extends "res://tests/support/v3_test.gd"
func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.get_node("ContentStore").saved = fixture.duplicate(true)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "FleetPreparation", "Main menu bypassed fleet preparation.")
	current_scene.launch_button.pressed.emit()
	await scene_changed
	var b = current_scene
	b.feedback.duration_scale = 0.01
	await flush()
	expect(b.hand_view.get_child_count() == 7 and b.state.enemies.size() == 3, "Saved fleet/enemies not loaded.")
	expect(b.stance_panel.get_child_count() > 0 and b.state.enemy_row.size() == 3, "Shared row missing.")
	expect(b.allies.widgets.size() == 4 and b.enemies.widgets.size() == 4, "Diamond slots missing.")
	expect(b.circle_view.buttons[4].disabled, "Circle expanded too early.")
	stage_card(b, "broadside", 1)
	choose_first_targets(b)
	await pay_with(b, "brace")
	expect(not b.get_node("%PlayButton").disabled, "Paid targeted play not ready.")
	var before: int = b.state.monster_hull
	b.get_node("%PlayButton").pressed.emit()
	await b.resolution_finished
	expect(b.state.circle[1] >= 0 and b.state.monster_hull < before, "Card did not resolve.")
	expect(b.hand_view.get_child_count() == 5 and conserved(b.state), "Hand not updated.")
	b.get_node("%EndPhaseButton").pressed.emit()
	await b.resolution_finished
	expect(b.state.round_number == 2 and b.state.phase == "refresh", "Enemy phase failed.")
	b.get_node("%PlayButton").pressed.emit()
	await b.resolution_finished
	expect(b.state.hand.size() == 7 and b.state.mana == 1, "Retained-hand refresh/mana failed.")
	b.get_node("%GearButton").pressed.emit()
	expect(paused, "Menu did not pause.")
	b.menu.id_pressed.emit(0)
	b.menu.hide()
	expect(not paused, "Resume failed.")
	b.get_node("%GearButton").pressed.emit()
	b.menu.id_pressed.emit(2)
	await scene_changed
	expect(current_scene.name == "MainMenu" and not paused, "Menu route failed.")
	done("Battle UI navigation")

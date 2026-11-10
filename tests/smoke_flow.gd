extends "res://tests/support/v2_test.gd"


func _run() -> void:
	root.get_node("ContentStore").saved = fixture.duplicate(true)
	root.get_node("ContentStore").migration_pending = false
	change_scene_to_file("res://scenes/main_menu.tscn")
	await scene_changed
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	var battle = current_scene
	battle.feedback.duration_scale = 0.02
	await flush()
	expect(battle.state.formation.size() == 4 and battle.allies.widgets.size() == 4 and battle.enemies.widgets.size() == 4, "Formation UI missing slots.")
	expect(battle.hand_view.get_child_count() == 7 and battle.circle_view.buttons.size() == 9, "Hand/circle UI missing.")
	expect(battle.circle_view.buttons[4].disabled, "Centre unlocked before expansion.")
	stage_card(battle, "broadside", 1)
	await pay_with(battle, "brace")
	expect(battle.selected_slot == 1 and not battle.get_node("%PlayButton").disabled, "Circle slot selection or payment failed.")
	expect("70 → 61" in battle.get_node("%Inspection").text, "Preview did not show known damage.")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.circle[1] >= 0 and battle.state.discard.size() == 1 and battle.state.monster_hull == 61, "Played card/payment UI resolution incorrect.")
	expect(battle.circle_view.contents[1] >= 0 and battle.hand_view.get_child_count() == 5, "Circle and hand did not update.")
	battle.get_node("%EndPhaseButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.round_number == 2 and battle.state.play_order.is_empty(), "Round cleanup failed.")
	battle.get_node("%PlayButton").pressed.emit()
	await battle.resolution_finished
	expect(battle.state.hand.size() == 7 and battle.state.phase == "fleet", "Refill failed.")
	battle.get_node("%GearButton").pressed.emit()
	expect(paused, "Battle menu did not pause playback.")
	battle.menu.id_pressed.emit(0)
	battle.menu.hide()
	expect(not paused, "Resume did not unpause.")
	battle.get_node("%GearButton").pressed.emit()
	battle.menu.id_pressed.emit(2)
	await scene_changed
	expect(current_scene.name == "MainMenu" and not paused, "Main Menu route failed.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.state.monster_hull == 70 and current_scene.state.play_order.is_empty(), "New battle retained state.")
	current_scene.get_node("%WinButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Victory", "Debug victory route failed.")
	current_scene.get_node("%SecondaryButton").pressed.emit()
	await scene_changed
	done("Battle UI navigation")

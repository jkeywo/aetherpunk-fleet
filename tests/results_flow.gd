extends "res://tests/support/v3_test.gd"
func _run() -> void:
	var doc := neutral()
	card_def(doc, "brace").rules[0].effects = [attack(99)]
	root.get_node("BattleSession").editor_playtest = true
	await open_battle(doc)
	var b = current_scene
	b.state.ships[0].hull = 17
	b.state.ships[1].hull = 0
	b.state.ships[2].hull = 13
	b.state.formation[1] = -1
	b.state.round_number = 4
	b._render()
	stage_card(b, "brace", 0)
	b.get_node("%PlayButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Victory", "Actual victory failed.")
	expect(current_scene.get_node("%SurvivorsValue").text == "2 / 3" and current_scene.get_node("%HullValue").text == "30 / 66", "Hull/survivors incorrect.")
	expect(current_scene.get_node("%RoundsValue").text == "4" and current_scene.find_child("ReturnToEditor", true, false) != null, "Round/editor return missing.")
	root.get_node("ContentStore").saved.ships[0].hull = 31
	expect(current_scene.summary.starting_hull == 66, "Result changed after content edit.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	b = current_scene
	b.feedback.duration_scale = 0.01
	expect(b.state.ships[0].max_hull == 31 and b.state.round_number == 1 and b.state.mana == 0 and b.state.play_order.is_empty(), "Retry did not use clean saved setup.")
	b.state.enemies[0].stances[0].effects = [attack(99, 1, "Long", "all_allies")]
	b.get_node("%EndPhaseButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Defeat" and current_scene.get_node("%HullValue").text == "0 / 69", "Actual defeat totals failed.")
	current_scene.find_child("ReturnToEditor", true, false).pressed.emit()
	await scene_changed
	expect(current_scene.tabs.get_tab_count() == 4, "Playtest return failed.")
	done("Battle results")

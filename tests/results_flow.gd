extends "res://tests/support/v2_test.gd"


func _run() -> void:
	await open_battle()
	var battle = current_scene
	battle.state.monster_hull = 4
	battle.state.ships[0].hull = 17
	battle.state.ships[1].hull = 0
	battle.state.ships[2].hull = 13
	battle.state.formation[1] = -1
	battle.state.round_number = 4
	battle._render()
	field_key(battle, "advance").pressed.emit()
	field_key(battle, "tow").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Victory", "Actual victory route failed.")
	expect(current_scene.get_node("%SurvivorsValue").text == "2 / 3" and current_scene.get_node("%HullValue").text == "30 / 66", "Victory statistics incorrect.")
	expect(current_scene.get_node("%RoundsValue").text == "4", "Victory round count incorrect.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	battle = current_scene
	battle.feedback.duration_scale = 0.02
	expect(battle.state.formation == [0, 1, -1, 2] and battle.state.used_triggers.is_empty() and battle.state.circle.all(func(uid): return uid < 0), "Retry did not clear new state.")
	expect(battle.state.monster_hull == 70 and battle.state.round_number == 1, "Retry retained damage or round.")
	battle.state.round_number = 2
	battle.state.definitions.stances[battle.state.stance_index].effects = [{"kind": "damage_ship", "target": "all", "amount": 99}]
	battle.get_node("%EndPhaseButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Defeat", "Actual defeat route failed.")
	expect(current_scene.get_node("%HullValue").text == "0 / 66" and current_scene.get_node("%RoundsValue").text == "2", "Defeat statistics incorrect.")
	current_scene.get_node("%SecondaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "MainMenu", "Result menu failed.")
	done("Battle results")

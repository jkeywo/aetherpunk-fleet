extends "res://tests/support/v2_test.gd"
var beats: Array = []
var hull_before_reaction := -1


func on_beat(kind: String) -> void:
	beats.append(kind)
	if kind == "reaction_triggered":
		for widget in current_scene.allies.widgets.values():
			if widget.get_meta("ship_index", -1) == 0:
				hull_before_reaction = int(widget.bar.value)


func _run() -> void:
	await open_battle()
	var battle = current_scene
	battle.feedback.beat_started.connect(on_beat)
	stage_card(battle, "advance", 0)
	choose_first_targets(battle)
	await pay_with(battle, "tow")
	battle.get_node("%PlayButton").pressed.emit()
	expect(battle.busy and battle.get_node("%EndPhaseButton").disabled, "Feedback input lock missing.")
	battle.get_node("%PlayButton").pressed.emit()
	battle.get_node("%EndPhaseButton").pressed.emit()
	expect(battle.state.monster_hull == 66 and battle.state.round_number == 1, "Repeated input resolved twice.")
	await battle.resolution_finished
	expect(hull_before_reaction == 28 and battle.state.ships[0].hull == 25, "Reaction damage appeared before announcement.")
	expect(beats.find("movement") < beats.find("reaction_triggered") and beats.find("stance_changed") > beats.find("reaction_triggered"), "Feedback stage order incorrect.")
	expect(not battle.busy and not battle.feedback.running, "Feedback did not unlock.")
	expect(not battle.feedback.banner.visible and battle.circle_view.contents[0] >= 0, "Feedback ended with stale overlay or missing card.")
	await flush()
	expect(battle.feedback.overlay.get_child_count() == 1, "Transient animation nodes leaked.")
	stage_card(battle, "brace", 1)
	await pay_with(battle, "escort")
	battle.get_node("%PlayButton").pressed.emit()
	battle.get_node("%GearButton").pressed.emit()
	battle.menu.id_pressed.emit(2)
	await scene_changed
	expect(current_scene.name == "MainMenu" and not paused, "Leaving during playback failed.")
	await flush()
	expect(current_scene.name == "MainMenu", "Abandoned playback changed scenes.")
	done("Combat feedback")

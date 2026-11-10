extends SceneTree
## Verifies real battle summaries, result navigation, detached data, and clean retries.

const State = preload("res://scripts/battle_state.gd")
var failures: int = 0
var checks: int = 0
var session: Node


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _open_battle() -> void:
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	current_scene.feedback.duration_scale = 0.02
	await process_frame


func _button(key: String) -> Button:
	for button in current_scene.get_node("%Hand").get_children():
		if current_scene.state.card_keys[button.get_meta("uid")] == key:
			return button
	return null


func _fresh_battle() -> void:
	var battle = current_scene
	expect(battle.name == "Game", "Retry did not enter battle.")
	expect(battle.state.round_number == 1 and battle.state.monster_hull == 70, "Retry retained round or monster hull.")
	expect(battle.state.formation == [0, 1, 2], "Retry retained a damaged formation.")
	for ship in battle.state.ships:
		expect(ship.hull == ship.max_hull and ship.guard == 0, "Retry retained hull damage or guard.")
	expect(battle.state.hand.size() == 7 and battle.state.deck.size() == 11 and battle.state.discard.is_empty(), "Retry retained card piles.")
	expect(battle.state.reaction_index == 0 and battle.state.intent_index == 0, "Retry retained enemy behaviour.")
	expect(battle.selected_uid == -2 and not battle.busy and not battle.feedback.running, "Retry retained UI or animation state.")
	expect(session.last_result.is_empty(), "Retry retained stale result data.")


func _run() -> void:
	session = root.get_node("BattleSession")
	var sample = State.new(7)
	expect(sample.result_summary().is_empty(), "Unfinished battle produced a real result.")
	sample.outcome = "victory"
	sample.ships[0].hull = 17
	sample.ships[1].hull = 0
	sample.ships[2].hull = 13
	sample.round_number = 4
	var summary: Dictionary = sample.result_summary()
	expect(summary.survivors == 2 and summary.remaining_hull == 30 and summary.starting_hull == 66, "Summary hull denominator or survivor count incorrect.")
	expect(summary.hull_percent == 45 and summary.rounds == 4 and not summary.is_test, "Summary percentage or rounds incorrect.")
	session.record_result(summary)
	sample.ships[0].hull = 1
	summary.ships[0].hull = 2
	expect(session.last_result.ships[0].hull == 17, "Stored summary retained mutable battle references.")

	# Real lethal card, with one destroyed ship and damage on both survivors.
	await _open_battle()
	var battle = current_scene
	battle.state.ships[0].hull = 17
	battle.state.ships[1].hull = 0
	battle.state.ships[2].hull = 13
	battle.state.formation = [0, 2]
	battle.state.monster_hull = 4
	battle.state.round_number = 4
	battle._render()
	_button("advance").pressed.emit()
	_button("tow").pressed.emit()
	battle.get_node("%PlayButton").pressed.emit()
	expect(battle.busy and session.last_result.is_empty(), "Results appeared before feedback finished.")
	await scene_changed
	expect(current_scene.name == "Victory", "Real win did not enter victory screen.")
	expect(current_scene.get_node("%SurvivorsValue").text == "2 / 3", "Victory survivor count incorrect.")
	expect(current_scene.get_node("%HullValue").text == "30 / 66", "Victory hull total incorrect.")
	expect(current_scene.get_node("%HullPercent").text == "45% of starting fleet", "Victory hull percentage incorrect.")
	expect(current_scene.get_node("%RoundsValue").text == "4", "Victory rounds incorrect.")
	expect(current_scene.get_node("%Ships").get_child_count() == 3, "Result omitted destroyed ships.")
	var lost := current_scene.get_node("%Ships/Kestrel")
	expect(lost.get_node("%HullBar").value == 0 and lost.get_node("Row/Stats/HullRow/SurvivalStatus").text == "DESTROYED", "Destroyed ship status incorrect.")
	expect(current_scene.get_node("%Ships/Bastion").get_node("%HullBar").value == 17, "Survivor hull display incorrect.")
	expect(current_scene.get_node("%PrimaryButton").text == "Retry Battle" and current_scene.get_node("%SecondaryButton").text == "Main Menu", "Result buttons incorrect.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	_fresh_battle()

	# Real defeat on round two must not count an unplayed third round.
	battle = current_scene
	battle.feedback.duration_scale = 0.02
	battle.state.round_number = 2
	battle.state.intent_index = 2
	for ship in battle.state.ships:
		ship.hull = 1
	battle.get_node("%EndPhaseButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "Defeat", "Real loss did not enter defeat screen.")
	expect(current_scene.get_node("%SurvivorsValue").text == "0 / 3" and current_scene.get_node("%HullValue").text == "0 / 66", "Defeat fleet summary incorrect.")
	expect(current_scene.get_node("%RoundsValue").text == "2", "Defeat counted an extra round.")
	for row in current_scene.get_node("%Ships").get_children():
		expect(row.get_node("Row/Stats/HullRow/SurvivalStatus").text == "DESTROYED", "Defeat listed a survivor.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	_fresh_battle()

	# Debug outcomes are labelled and preserve actual current fleet statistics.
	current_scene.get_node("%WinButton").pressed.emit()
	await scene_changed
	expect(current_scene.summary.is_test and "TEST RESULT" in current_scene.get_node("%Eyebrow").text, "Debug outcome was not labelled.")
	expect(current_scene.get_node("%HullValue").text == "66 / 66", "Debug outcome fabricated hull values.")
	current_scene.get_node("%SecondaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "MainMenu", "Victory Main Menu failed.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	current_scene.get_node("%LossButton").pressed.emit()
	await scene_changed
	current_scene.get_node("%SecondaryButton").pressed.emit()
	await scene_changed
	expect(current_scene.name == "MainMenu", "Defeat Main Menu failed.")

	# Direct scene launch with no matching summary must never show stale statistics.
	session.clear_result()
	change_scene_to_file("res://scenes/victory.tscn")
	await scene_changed
	expect(current_scene.summary.is_empty() and current_scene.get_node("%HullValue").text == "—", "Direct launch displayed fabricated or stale results.")
	current_scene.get_node("%PrimaryButton").pressed.emit()
	await scene_changed
	_fresh_battle()
	print("Battle results: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)

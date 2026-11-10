extends SceneTree
## Exercises actual UI selection, payment, target choices, outcomes, and exit.

const MENU_BUTTONS := "Center/Panel/Margin/Content/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if change_scene_to_file("res://scenes/main_menu.tscn") != OK:
		_fail("Could not load main menu.")
		return
	await scene_changed
	await _press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	await process_frame
	if not await _check_battle_and_play():
		return
	await _press("EndPhaseButton")
	if current_scene.state.phase != "refresh":
		_fail("End Fleet Phase did not resolve intent.")
		return
	await _press("PlayButton")
	if current_scene.state.phase != "fleet" or current_scene.state.hand.size() != 7:
		_fail("Refill Hand did not begin another fleet phase.")
		return
	if not await _check_relay_ui():
		return
	await _press("WinButton")
	await scene_changed
	if not _expect("Victory"):
		return
	await _press("PrimaryButton")
	await scene_changed
	await _press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	await _press("LossButton")
	await scene_changed
	if not _expect("Defeat"):
		return
	await _press("PrimaryButton")
	await scene_changed
	await _press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	if current_scene.selected_uid != -2 or current_scene.state.monster_hull != 70:
		_fail("A restarted battle retained state.")
		return
	# Real card resolution must navigate automatically on victory.
	current_scene.state.monster_hull = 4
	_card_button("advance").pressed.emit()
	_card_button("tow").pressed.emit()
	await _press("PlayButton")
	await scene_changed
	if not _expect("Victory"):
		return
	await _press("PrimaryButton")
	await scene_changed
	await _press("PrimaryButton")
	await scene_changed
	# Real simultaneous enemy damage must navigate automatically on defeat.
	for ship in current_scene.state.ships:
		ship.hull = 1
	current_scene.state.intent_index = 2
	await _press("EndPhaseButton")
	await scene_changed
	if not _expect("Defeat"):
		return
	await _press("PrimaryButton")
	await scene_changed
	await _press("PrimaryButton")
	await scene_changed
	await _press("MenuButton")
	await scene_changed
	if not _expect("MainMenu"):
		return
	print("PASS: battle content, selection, payment, preview, cancellation, movement, reaction, refresh, real and test outcomes, reset, menu. Pressing Exit.")
	await _press("SecondaryButton")


func _card_button(key: String) -> Button:
	for button in current_scene.get_node("%Hand").get_children():
		var uid: int = button.get_meta("uid")
		if current_scene.state.card_keys[uid] == key:
			return button
	return null


func _check_battle_and_play() -> bool:
	var battle = current_scene
	var formation := battle.get_node("%Formation")
	if formation.get_child_count() != 3:
		return _fail("Expected three ships.")
	for index in 3:
		var ship := formation.get_child(index)
		if ship.name != ["Bastion", "Kestrel", "Lamplighter"][index] or ship.get_node("%HullBar").value != [28, 20, 18][index]:
			return _fail("Incorrect ship order or hull.")
	if battle.get_node("%MonsterBar").value != 70 or battle.get_node("%ReactionName").text != "Buffeting Wings":
		return _fail("Incorrect enemy opening.")
	if battle.get_node("%IntentName").text != "Rending Bite" or battle.get_node("%Hand").get_child_count() != 7:
		return _fail("Incorrect intent or opening hand.")
	_card_button("advance").pressed.emit()
	if not battle.get_node("%PlayButton").disabled:
		return _fail("Unpaid action was enabled.")
	if battle.get_node("%TargetChoice").item_count != 1:
		return _fail("Movement should offer one adjacent ship at the front.")
	_card_button("tow").pressed.emit()
	if battle.get_node("%PlayButton").disabled or not "Buffeting Wings triggers" in battle.get_node("%Inspection").text:
		return _fail("Paid movement lacked reaction preview.")
	if battle.state.monster_hull != 70 or battle.state.hand.size() != 7:
		return _fail("Drafting mutated battle state.")
	await _press("CancelButton")
	if battle.selected_uid != -2 or battle.state.hand.size() != 7:
		return _fail("Cancel spent cards or retained selection.")
	_card_button("advance").pressed.emit()
	_card_button("tow").pressed.emit()
	await _press("PlayButton")
	if battle.state.monster_hull != 66 or battle.state.ships[0].hull != 25:
		return _fail("Actual action or reaction damage incorrect.")
	if battle.get_node("%Formation").get_child(0).name != "Kestrel":
		return _fail("Formation view did not update.")
	if battle.get_node("%Hand").get_child_count() != 5 or battle.state.discard.size() != 2:
		return _fail("Played and payment cards were not removed.")
	if battle.get_node("%ReactionName").text == "Buffeting Wings":
		return _fail("Reaction view did not update.")
	if not "Shield Advance" in battle.get_node("%History").text:
		return _fail("Action history missing.")
	_card_button("escort").pressed.emit()
	var picker := battle.get_node("%TargetChoice") as OptionButton
	if picker.item_count != 2:
		return _fail("Escort did not offer both other ships.")
	picker.select(1)
	picker.item_selected.emit(1)
	_card_button("broadside").pressed.emit()
	await _press("PlayButton")
	if battle.state.ships[2].guard != 6:
		return _fail("Explicit target selection did not resolve on Lamplighter.")
	return true


func _check_relay_ui() -> bool:
	# Arrange a legal 18-card fixture with Relay in hand, preserving all instances.
	var battle = current_scene
	var relay_uid := -1
	for uid in battle.state.deck:
		if battle.state.card_keys[uid] == "relay":
			relay_uid = uid
			break
	if relay_uid == -1:
		# A reshuffled Relay may already be in the refreshed hand.
		for uid in battle.state.hand:
			if battle.state.card_keys[uid] == "relay":
				relay_uid = uid
				break
	if relay_uid == -1:
		return _fail("Relay fixture could not find a card instance.")
	if not battle.state.hand.has(relay_uid):
		var deck_index: int = battle.state.deck.find(relay_uid)
		battle.state.deck[deck_index] = battle.state.hand[0]
		battle.state.hand[0] = relay_uid
	battle._render()
	_card_button("relay").pressed.emit()
	if battle.get_node("%PlayButton").disabled:
		return _fail("Zero-cost Relay required payment.")
	await _press("PlayButton")
	if battle.state.phase != "discard" or not battle.get_node("%EndPhaseButton").disabled:
		return _fail("Relay UI did not require its discard before continuing.")
	var count_before: int = battle.state.hand.size()
	battle.get_node("%Hand").get_child(0).pressed.emit()
	if battle.busy:
		await battle.resolution_finished
	if battle.state.phase != "fleet" or battle.state.hand.size() != count_before - 1:
		return _fail("Relay UI discard did not finish the action.")
	return true


func _press(button_name: String) -> void:
	var origin = current_scene
	if origin.name == "Game":
		origin.feedback.duration_scale = 0.02
	var path := "%" + button_name if current_scene.name == "Game" else MENU_BUTTONS + button_name
	var button := current_scene.get_node(path) as Button
	button.pressed.emit()
	if is_instance_valid(origin) and origin.name == "Game" and origin.busy:
		await origin.resolution_finished


func _expect(expected: String) -> bool:
	if current_scene.name != expected:
		return _fail("Expected %s, got %s." % [expected, current_scene.name])
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false

extends SceneTree
## Exercises actual navigation buttons and checks the battle presentation.

const MENU_BUTTONS := "Center/Panel/Margin/Content/"
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if change_scene_to_file("res://scenes/main_menu.tscn") != OK:
		_fail("Could not load main menu.")
		return
	await scene_changed
	_press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	await process_frame
	if not _check_battle():
		return
	_press("WinButton")
	await scene_changed
	if not _expect("Victory"):
		return
	_press("PrimaryButton")
	await scene_changed
	if not _expect("MainMenu"):
		return
	_press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	_press("LossButton")
	await scene_changed
	if not _expect("Defeat"):
		return
	_press("PrimaryButton")
	await scene_changed
	_press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	if current_scene.selected_card_id != "":
		_fail("A restarted battle retained card selection.")
		return
	_press("MenuButton")
	await scene_changed
	if not _expect("MainMenu"):
		return
	print("PASS: fleet hull, leviathan, seven cards, GDD data, inspection, both outcomes, restart, menu. Pressing Exit.")
	_press("SecondaryButton")


func _check_battle() -> bool:
	var formation := current_scene.get_node("%Formation")
	if formation.get_child_count() != 3:
		return _fail("Expected three ships.")
	var expected_hull := [28, 20, 18]
	var expected_names := ["Bastion", "Kestrel", "Lamplighter"]
	for index in 3:
		var ship := formation.get_child(index)
		if ship.name != expected_names[index] or ship.get_node("%HullBar").value != expected_hull[index]:
			return _fail("Incorrect ship order or hull.")
	if current_scene.get_node("%MonsterBar").value != 70:
		return _fail("Expected 70 leviathan hull.")
	if current_scene.get_node("%ReactionName").text != "Buffeting Wings":
		return _fail("Incorrect reaction.")
	if current_scene.get_node("%IntentName").text != "Rending Bite":
		return _fail("Incorrect enemy intent.")
	var hand := current_scene.get_node("%Hand")
	if hand.get_child_count() != 7:
		return _fail("Expected seven cards.")
	if current_scene.get_node("%PileCounts").text != "DECK  11    /    DISCARD  0":
		return _fail("Incorrect pile counts.")
	hand.get_child(3).pressed.emit()
	if current_scene.selected_card_id != "salvo" or not "Deal 14 damage" in current_scene.get_node("%Inspection").text:
		return _fail("Card inspection failed.")
	if not hand.get_child(3).button_pressed:
		return _fail("Inspected card was not highlighted.")
	hand.get_child(0).pressed.emit()
	if hand.get_child(3).button_pressed or not hand.get_child(0).button_pressed:
		return _fail("Selection highlight did not move.")
	if hand.get_child_count() != 7 or current_scene.get_node("%MonsterBar").value != 70:
		return _fail("Inspection mutated the encounter.")
	return true


func _press(button_name: String) -> void:
	var path := "%" + button_name if current_scene.name == "Game" else MENU_BUTTONS + button_name
	var button := current_scene.get_node(path) as Button
	button.pressed.emit()


func _expect(expected: String) -> bool:
	if current_scene.name != expected:
		return _fail("Expected %s, got %s." % [expected, current_scene.name])
	return true


func _fail(message: String) -> bool:
	failed = true
	push_error(message)
	quit(1)
	return false

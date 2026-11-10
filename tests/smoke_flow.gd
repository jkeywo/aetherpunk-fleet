extends SceneTree
## Exercises the real buttons and scene transitions, including application exit.

const BUTTONS := "Center/Panel/Margin/Content/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var error := change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		_fail("Could not load main menu.")
		return
	await scene_changed
	if not _expect("MainMenu"):
		return
	_press("PrimaryButton")
	await scene_changed
	if not _expect("Game"):
		return
	_press("PrimaryButton")
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
	_press("SecondaryButton")
	await scene_changed
	if not _expect("Defeat"):
		return
	_press("PrimaryButton")
	await scene_changed
	if not _expect("MainMenu"):
		return
	print("PASS: start, victory, return, restart, defeat, return. Pressing Exit.")
	_press("SecondaryButton")


func _press(button_name: String) -> void:
	var button := current_scene.get_node(BUTTONS + button_name) as Button
	button.pressed.emit()


func _expect(expected: String) -> bool:
	if current_scene.name != expected:
		_fail("Expected %s, got %s." % [expected, current_scene.name])
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

extends "res://scripts/screen.gd"


func _ready() -> void:
	super._ready()
	%EditorButton.pressed.connect(_navigate.bind("res://scenes/editor.tscn"))
	if ContentStore.saved.is_empty():
		primary_button.disabled = true
		$Center/Panel/Margin/Content/Description.text = "Content could not be loaded. Open Editor to repair it."


func _navigate(destination: String) -> void:
	if destination == "res://scenes/game.tscn":
		BattleSession.editor_playtest = false
	super._navigate(destination)

extends "res://scripts/screen.gd"


func _ready() -> void:
	super._ready()
	%EditorButton.pressed.connect(_navigate.bind("res://scenes/editor.tscn"))
	if ContentStore.saved.is_empty():
		primary_button.disabled = true
		$Center/Panel/Margin/Content/Description.text = "Content could not be loaded. Open Editor to repair it."
		$Center/Panel/Margin/Content/Description.show()


func _navigate(destination: String) -> void:
	if destination in ["res://scenes/game.tscn", "res://scenes/fleet_preparation.tscn"]:
		BattleSession.editor_playtest = false
	super._navigate(destination)

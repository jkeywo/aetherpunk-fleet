extends Control
## Shared presentation and navigation for the initial four-screen flow.

@export_file("*.tscn") var primary_scene: String
@export_file("*.tscn") var secondary_scene: String

@onready var primary_button: Button = %PrimaryButton
@onready var secondary_button: Button = %SecondaryButton


func _ready() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 22
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#173548")
	normal.border_color = Color("#729da8")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#28536a")
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#e8bd77")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(6)
	theme_resource.set_stylebox("normal", "Button", normal)
	theme_resource.set_stylebox("hover", "Button", hover)
	theme_resource.set_stylebox("pressed", "Button", hover)
	theme_resource.set_stylebox("focus", "Button", focus)
	theme = theme_resource

	primary_button.pressed.connect(_navigate.bind(primary_scene))
	secondary_button.pressed.connect(_navigate.bind(secondary_scene))
	primary_button.grab_focus()


func _navigate(destination: String) -> void:
	if destination.is_empty():
		get_tree().quit()
		return
	if destination in ["res://scenes/main_menu.tscn", "res://scenes/editor.tscn"]:
		BattleSession.editor_playtest = false
	var error := get_tree().change_scene_to_file(destination)
	if error != OK:
		push_error("Unable to open scene %s: %s" % [destination, error_string(error)])

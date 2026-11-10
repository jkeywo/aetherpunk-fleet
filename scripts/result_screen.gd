extends "res://scripts/screen.gd"
## Displays a detached battle summary; retry creates a fresh Game scene.

const ShipScene = preload("res://scenes/components/ship_panel.tscn")
@export_enum("victory", "defeat") var outcome: String = "victory"
var summary: Dictionary = {}


func _ready() -> void:
	super._ready()
	_style_results()
	if BattleSession.editor_playtest:
		var return_button := Button.new()
		return_button.name = "ReturnToEditor"
		return_button.text = "Return to Editor"
		return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_button.get_parent().add_child(return_button)
		return_button.pressed.connect(_navigate.bind("res://scenes/editor.tscn"))
	if not BattleSession.editor_playtest:
		var prepare := Button.new()
		prepare.name = "PrepareFleet"
		prepare.text = "Prepare Fleet"
		prepare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_button.get_parent().add_child(prepare)
		prepare.pressed.connect(_navigate.bind("res://scenes/fleet_preparation.tscn"))
	summary = BattleSession.last_result.duplicate(true)
	if summary.is_empty() or summary.get("outcome", "") != outcome:
		summary.clear()
		%Description.text = "No completed battle is available."
		%SurvivorsValue.text = "—"
		%HullValue.text = "—"
		%HullPercent.text = "No fleet data"
		%RoundsValue.text = "—"
		var empty := Label.new()
		empty.text = "Retry Battle to begin a new encounter."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%Ships.add_child(empty)
		return
	%SurvivorsValue.text = "%d / %d" % [summary.survivors, summary.ships.size()]
	%HullValue.text = "%d / %d" % [summary.remaining_hull, summary.starting_hull]
	%HullPercent.text = "%d%% of starting fleet" % summary.hull_percent
	%RoundsValue.text = str(summary.rounds)
	if summary.is_test:
		%Eyebrow.text = "TEST RESULT / CURRENT FLEET"
		%Description.text = "Test outcome. Statistics reflect the current battle."
	for ship in summary.ships:
		_add_ship_result(ship)


func _add_ship_result(ship: Dictionary) -> void:
	var panel := ShipScene.instantiate()
	panel.name = ship.name.validate_node_name()
	panel.custom_minimum_size = Vector2(0, 78)
	%Ships.add_child(panel)
	panel.get_node("%Rank").hide()
	panel.get_node("%ShipName").text = ship.name
	panel.get_node("%Role").text = ship.role
	panel.get_node("%Role").modulate = Color(ship.color)
	panel.get_node("%Hull").text = "HULL  %d / %d" % [ship.hull, ship.max_hull]
	panel.get_node("%HullBar").max_value = ship.max_hull
	panel.get_node("%HullBar").value = ship.hull
	panel.get_node("%ShipArt").custom_minimum_size = Vector2(95, 52)
	panel.get_node("%ShipArt").accent = Color(ship.color)
	panel.get_node("%ShipArt").set_art(str(ship.get("id",str(ship.name).to_lower())))
	var status := panel.get_node("Row/Stats/HullRow/Guard") as Label
	status.name = "SurvivalStatus"
	status.text = "SURVIVED" if ship.alive else "DESTROYED"
	status.modulate = Color("#9ce6b7") if ship.alive else Color("#ff927f")
	if not ship.alive:
		panel.get_node("%ShipArt").modulate = Color("#777d84")


func _style_results() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#102632")
	panel.border_color = Color("#30505c")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	theme.set_stylebox("panel", "PanelContainer", panel)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#07161e")
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#78b7aa")
	fill.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", background)
	theme.set_stylebox("fill", "ProgressBar", fill)
	%Heading.modulate = Color("#e8bd77") if outcome == "victory" else Color("#ff927f")

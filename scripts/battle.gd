extends Control
## Battle-screen presentation. Selecting a card never spends it or changes combat.

const Setup = preload("res://data/battle_setup.gd")
const ShipScene = preload("res://scenes/components/ship_panel.tscn")
const CardScene = preload("res://scenes/components/hand_card.tscn")

var selected_card_id: String = ""


func _ready() -> void:
	theme = _make_theme()
	%MenuButton.pressed.connect(_navigate.bind("res://scenes/main_menu.tscn"))
	%WinButton.pressed.connect(_navigate.bind("res://scenes/victory.tscn"))
	%LossButton.pressed.connect(_navigate.bind("res://scenes/defeat.tscn"))
	%MonsterName.text = Setup.MONSTER.name.to_upper()
	%MonsterHull.text = "HULL  %d / %d" % [Setup.MONSTER.hull, Setup.MONSTER.hull]
	%MonsterBar.max_value = Setup.MONSTER.hull
	%MonsterBar.value = Setup.MONSTER.hull
	%ReactionName.text = Setup.REACTION.name
	%ReactionTrigger.text = Setup.REACTION.trigger
	%ReactionEffect.text = Setup.REACTION.effect
	%IntentName.text = Setup.INTENT.name
	%IntentTrigger.text = Setup.INTENT.trigger
	%IntentEffect.text = Setup.INTENT.effect
	%HandCount.text = "SHARED HAND  ·  %d / 7" % Setup.OPENING_HAND.size()
	%PileCounts.text = "DECK  %d    /    DISCARD  0" % (Setup.CARDS.size() * Setup.COPIES_PER_CARD - Setup.OPENING_HAND.size())
	for index in Setup.SHIPS.size():
		_add_ship(index)
	for card_id in Setup.OPENING_HAND:
		_add_card(card_id)


func _add_ship(index: int) -> void:
	var ship: Dictionary = Setup.SHIPS[index]
	var panel := ShipScene.instantiate()
	panel.name = ship.name
	%Formation.add_child(panel)
	panel.get_node("%Rank").text = ["01  /  FRONT", "02  /  CENTRE", "03  /  REAR"][index]
	panel.get_node("%ShipName").text = ship.name
	panel.get_node("%Role").text = ship.role
	panel.get_node("%Role").modulate = Color(ship.color)
	panel.get_node("%Hull").text = "HULL  %d / %d" % [ship.hull, ship.hull]
	panel.get_node("%HullBar").max_value = ship.hull
	panel.get_node("%HullBar").value = ship.hull
	panel.get_node("%ShipArt").accent = Color(ship.color)


func _add_card(card_id: String) -> void:
	var card: Dictionary = Setup.CARDS[card_id]
	var ship: Dictionary = Setup.SHIPS[card.owner]
	var button := CardScene.instantiate() as Button
	button.name = card_id
	%Hand.add_child(button)
	button.get_node("%Owner").text = ship.name.to_upper()
	button.get_node("%Owner").modulate = Color(ship.color)
	button.get_node("%CardName").text = card.name
	button.get_node("%Cost").text = "COST %d" % card.cost
	button.get_node("%Payment").text = "PAYS %d" % card.pays
	button.get_node("%Ranks").text = "RANKS  " + card.ranks
	button.get_node("%Tags").text = card.tags
	button.get_node("%Effect").text = card.effect
	button.tooltip_text = "%s — %s\nCost: %d | Pays: %d | Ranks: %s\n%s\n%s\nInspection only; combat is not active yet." % [
		card.name, ship.name, card.cost, card.pays, card.ranks, card.tags, card.effect]
	button.pressed.connect(_inspect_card.bind(card_id))
	button.focus_entered.connect(_inspect_card.bind(card_id))


func _inspect_card(card_id: String) -> void:
	selected_card_id = card_id
	for button in %Hand.get_children():
		button.set_pressed_no_signal(button.name == card_id)
	var card: Dictionary = Setup.CARDS[card_id]
	var ship: Dictionary = Setup.SHIPS[card.owner]
	%Inspection.text = "%s / %s  ·  Cost %d / Pays %d  ·  Ranks %s  ·  %s" % [
		ship.name, card.name, card.cost, card.pays, card.ranks, card.effect]


func _navigate(destination: String) -> void:
	var error := get_tree().change_scene_to_file(destination)
	if error != OK:
		push_error("Unable to open %s: %s" % [destination, error_string(error)])


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", Color("#e7ecea"))
	var panel := _box(Color("#102632"), Color("#30505c"))
	result.set_stylebox("panel", "PanelContainer", panel)
	var button := _box(Color("#132e3b"), Color("#3f6573"))
	var hover := _box(Color("#1c3e4d"), Color("#89b6bf"))
	var selected := _box(Color("#253e46"), Color("#e8bd77"))
	result.set_stylebox("normal", "Button", button)
	result.set_stylebox("hover", "Button", hover)
	result.set_stylebox("pressed", "Button", selected)
	result.set_stylebox("hover_pressed", "Button", selected)
	var focus := _box(Color.TRANSPARENT, Color("#e8bd77"))
	result.set_stylebox("focus", "Button", focus)
	var background := _box(Color("#07161e"), Color("#203d48"))
	var fill := _box(Color("#78b7aa"), Color.TRANSPARENT)
	result.set_stylebox("background", "ProgressBar", background)
	result.set_stylebox("fill", "ProgressBar", fill)
	return result


func _box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

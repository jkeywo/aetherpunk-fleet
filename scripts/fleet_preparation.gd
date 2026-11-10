extends Control
## Encounter preparation owns a session draft, never the authored content document.
const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const Formation = preload("res://scripts/formation_view.gd")
const Ui = preload("res://scripts/ui_theme.gd")
var source: Dictionary = {}
var draft: Dictionary = {}
var fingerprint := ""
var prefer_fixed := true
var fixed_available := false
var controls: Dictionary = {}
var details: Array = []
var columns: HBoxContainer
var content_scroll: ScrollContainer
var status: Label
var opening: CheckBox
var opening_note: Label
var launch_button: Button
var formation: Control
var encounter: Label


func _ready() -> void:
	get_tree().auto_accept_quit = true
	BattleSession.editor_playtest = false
	source = ContentStore.snapshot()
	fingerprint = JSON.stringify(Catalog.normalized(source)).sha256_text()
	draft = source.duplicate(true)
	prefer_fixed = source.get("setup", {}).get("fixed_hand", false)
	var remembered: Dictionary = BattleSession.preparation_draft
	if remembered.get("fingerprint", "") == fingerprint and draft.has("setup"):
		draft.setup.fleet = remembered.fleet.duplicate(true)
		prefer_fixed = remembered.prefer_fixed
	theme = Ui.make()
	_build()
	_render()


func _label(parent: Node, text: String, font: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#07121b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_label(header, "FLEET PREPARATION", 27).modulate = Color("#e8bd77")
	_button(header, "Reset to Saved Fleet", _reset)
	_button(header, "Main Menu", _back)
	_label(outer, "Choose three ships, assign their captains, and select upgrades. Changing an occupied ship, captain, or position swaps the two assignments.", 14).modulate = Color("#91b9c6")
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content_scroll.add_child(body)
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	body.add_child(columns)
	var overview := HBoxContainer.new()
	_body_panel(body, overview)
	formation = Formation.new()
	formation.custom_minimum_size = Vector2(360, 255)
	overview.add_child(formation)
	var briefing := VBoxContainer.new()
	briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(briefing)
	_label(briefing, "FORMATION & ENCOUNTER", 18).modulate = Color("#e8bd77")
	encounter = _label(briefing, "", 15)
	opening = CheckBox.new()
	opening.text = "Use saved opening when compatible"
	briefing.add_child(opening)
	opening.toggled.connect(func(value): prefer_fixed = value; _update())
	opening_note = _label(briefing, "", 14)
	_label(briefing, "Selections are kept for this session. Content definitions and the editor's saved setup are unchanged.", 13).modulate = Color("#91b9c6")
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	outer.add_child(footer)
	status = _label(footer, "", 15)
	status.custom_minimum_size.y = 48
	launch_button = _button(footer, "Launch Battle", _launch)
	launch_button.custom_minimum_size = Vector2(200, 48)


func _body_panel(parent: Node, body: Control) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	panel.add_child(body)


func _menu(parent: Node, label_text: String, options: Array, current: Variant, callback: Callable, key: String, enabled: bool = true) -> OptionButton:
	_label(parent, label_text, 12).modulate = Color("#91b9c6")
	var menu := OptionButton.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.fit_to_longest_item = false
	parent.add_child(menu)
	for item in options:
		menu.add_item(item.label)
		menu.set_item_metadata(menu.item_count - 1, item.value)
		menu.get_popup().set_item_tooltip(menu.item_count - 1, item.get("tooltip", ""))
		if typeof(item.value) == typeof(current) and item.value == current: menu.select(menu.item_count - 1)
	menu.disabled = not enabled
	menu.item_selected.connect(func(index): callback.call(menu.get_item_metadata(index)))
	controls[key] = menu
	return menu


func _render() -> void:
	for child in columns.get_children():
		columns.remove_child(child)
		child.queue_free()
	controls.clear()
	details.clear()
	if not draft.get("setup", {}).get("fleet") is Array:
		status.text = "Saved fleet content is unavailable. " + ContentStore.last_error
		launch_button.disabled = true
		return
	for i in draft.setup.fleet.size():
		var slot: Dictionary = draft.setup.fleet[i]
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 285
		column.add_theme_constant_override("separation", 6)
		_body_panel(columns, column)
		_label(column, "SHIP %d" % (i + 1), 12).modulate = Color("#e8bd77")
		var ship: Dictionary = draft.ships[Catalog.index_by_id(draft.ships, slot.ship)]
		var ship_options: Array = []
		for entry in draft.ships: ship_options.append({"label": entry.name, "value": entry.id})
		_menu(column, "Airship", ship_options, slot.ship, _change.bind(i, "ship"), "ship_" + str(i))
		var captain_options: Array = []
		for entry in draft.captains: captain_options.append({"label": entry.name + " · Tier " + str(entry.tier), "value": entry.id, "tooltip": Rules.rule_text(entry.passive)})
		_menu(column, "Captain", captain_options, slot.captain, _change.bind(i, "captain"), "captain_" + str(i))
		var points: Array = []
		for point in 4: points.append({"label": Geometry.POSITION_NAMES[point], "value": Geometry.POSITIONS[point]})
		_menu(column, "Starting position", points, slot.position, _change.bind(i, "position"), "position_" + str(i))
		_menu(column, "Level", [{"label": "1 · Starter + captain pairs", "value": 1}, {"label": "2 · Add one upgrade pair", "value": 2}, {"label": "3 · Add both upgrade pairs", "value": 3}], slot.level, _change.bind(i, "level"), "level_" + str(i))
		var level_two: Array = []
		for package in ship.levels.two: level_two.append({"label": package.name, "value": package.id, "tooltip": _package_text(package)})
		_menu(column, "Level 2 branch", level_two, slot.level_2, _change.bind(i, "level_2"), "level_2_" + str(i), slot.level >= 2)
		var blocked := ""
		var branch := Catalog.index_by_id(ship.levels.two, slot.level_2)
		if branch >= 0: blocked = ship.levels.two[branch].blocks
		var level_three: Array = []
		var blocked_name := ""
		for package in ship.levels.three:
			if package.id == blocked: blocked_name = package.name
			else: level_three.append({"label": package.name, "value": package.id, "tooltip": _package_text(package)})
		_menu(column, "Level 3 branch", level_three, slot.level_3, _change.bind(i, "level_3"), "level_3_" + str(i), slot.level >= 3)
		_label(column, ("Blocked by level 2: " + blocked_name) if blocked_name != "" else "Choose level 2 to determine the available paths.", 12).modulate = Color("#e8bd77")
		var summary := _label(column, "", 14)
		summary.custom_minimum_size.y = 90
		details.append(summary)
		var rewards := _label(column, "", 12)
		rewards.modulate = Color("#91c8ad")
		details.append(rewards)
	opening.set_pressed_no_signal(prefer_fixed)
	opening.disabled = not source.setup.fixed_hand
	_update()


func _change(value: Variant, index: int, key: String) -> void:
	var slot: Dictionary = draft.setup.fleet[index]
	if key in ["ship", "captain", "position"]:
		for i in draft.setup.fleet.size():
			if i != index and draft.setup.fleet[i][key] == value:
				draft.setup.fleet[i][key] = slot[key]
				if key == "ship": _repair_branch(draft.setup.fleet[i])
	slot[key] = value
	_repair_branch(slot)
	_render()
	controls[key + "_" + str(index)].grab_focus()


func _package_text(package: Dictionary) -> String:
	var index := Catalog.index_by_id(draft.cards, package.card)
	return "2 × " + draft.cards[index].name + "\n" + Rules.rule_text(package.rule) + "\n" + Rules.rule_text(package.passive)


func _repair_branch(slot: Dictionary) -> void:
	Catalog.repair_fleet_branch(slot, draft.ships[Catalog.index_by_id(draft.ships, slot.ship)])


func _candidate() -> Dictionary:
	var result := draft.duplicate(true)
	result.setup.fixed_hand = false
	fixed_available = false
	if Catalog.validate(result).is_empty() and source.setup.fixed_hand:
		var pool: Array = Catalog.compile(result).deck_keys.duplicate()
		fixed_available = source.setup.opening_hand.size() == 7
		for id in source.setup.opening_hand:
			if not pool.has(id): fixed_available = false; break
			pool.erase(id)
	result.setup.fixed_hand = prefer_fixed and fixed_available
	return result


func _update() -> void:
	var candidate := _candidate()
	var errors := Catalog.validate(candidate)
	launch_button.disabled = not errors.is_empty()
	if not errors.is_empty():
		status.text = "Cannot launch: " + str(errors[0])
		status.modulate = Color("#ff927f")
		return
	var compiled := Catalog.compile(candidate)
	var sim = State.new(0, candidate)
	var board: Dictionary = sim.board_snapshot()
	var total_hull := 0
	for i in compiled.ships.size():
		var ship: Dictionary = compiled.ships[i]
		var unit_data: Dictionary = board.ships[i]
		total_hull += unit_data.max_hull
		var lines: Array = ["%s · HULL %d · ARMOUR %d" % [ship.role, unit_data.max_hull, unit_data.armour], "Weapon %d · %s   /   %s %d" % [unit_data.weapon.damage, unit_data.weapon.range, ship.resource.name, unit_data.resource_capacity]]
		var count := 0
		for pair in ship.loadout:
			count += int(pair.count)
			lines.append("%d × %s" % [pair.count, compiled.cards[pair.card].name])
		details[i * 2].text = "\n".join(lines)
		details[i * 2].tooltip_text = "%d physical cards\n" % count + Rules.rule_text(ship.captain.passive)
		var rewards: Array = ["Captain: " + Rules.rule_text(ship.captain.passive)]
		var slot: Dictionary = candidate.setup.fleet[i]
		for tier in ["two", "three"]:
			if slot.level < (2 if tier == "two" else 3): continue
			var package: Dictionary = ship.levels[tier][Catalog.index_by_id(ship.levels[tier], slot["level_2" if tier == "two" else "level_3"])]
			rewards.append(package.name + ": " + Rules.rule_text(package.passive))
			rewards.append(Rules.rule_text(package.rule))
		details[i * 2 + 1].text = "\n".join(rewards)
		if ship.has("legacy_loadout"): details[i * 2 + 1].text += "\nImported card loadout retained."
	formation.configure(board, false)
	var enemies: Array = []
	for enemy in compiled.enemies: enemies.append(enemy.name + " · " + Geometry.POSITION_NAMES[enemy.position])
	encounter.text = "Enemy fleet\n" + "\n".join(enemies)
	opening_note.text = "Saved fixed opening: " + ", ".join(source.setup.opening_hand.map(func(id): return compiled.cards[id].name)) if candidate.setup.fixed_hand else ("Shuffled seven-card opening. The saved opening contains cards unavailable to this fleet." if prefer_fixed and source.setup.fixed_hand else "Shuffled seven-card opening.")
	status.text = "%d ships · %d cards · %d total hull\n%s" % [compiled.ships.size(), compiled.deck_keys.size(), total_hull, "Saved opening" if candidate.setup.fixed_hand else "Shuffled opening"]
	status.modulate = Color("#91c8ad")


func _remember() -> void:
	BattleSession.preparation_draft = {"fingerprint": fingerprint, "fleet": draft.setup.fleet.duplicate(true), "prefer_fixed": prefer_fixed}


func _reset() -> void:
	draft = source.duplicate(true)
	prefer_fixed = source.setup.fixed_hand
	_render()


func _back() -> void:
	if draft.has("setup"): _remember()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _launch() -> void:
	var candidate := _candidate()
	var errors := Catalog.validate(candidate)
	if not errors.is_empty():
		status.text = "Cannot launch: " + str(errors[0])
		return
	_remember()
	BattleSession.prepared_content = candidate.duplicate(true)
	BattleSession.editor_playtest = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

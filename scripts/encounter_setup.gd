extends Control

const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")

var draft: Dictionary
var slots: Array = ["", "", "", ""]
var monsters: Dictionary = {}
var selected_monster := ""
var selected_slot := -1
var formation: Control
var inspector: VBoxContainer
var start_button: Button
var status: Label

func _ready() -> void:
	draft = BattleSession.encounter_content.duplicate(true)
	if draft.is_empty():
		get_tree().change_scene_to_file.call_deferred("res://scenes/fleet_preparation.tscn")
		return
	for monster in draft.leviathans:
		monsters[monster.id] = monster
	for entry in draft.setup.enemies:
		slots[Geometry.POSITIONS.find(entry.position)] = entry.enemy
	theme = preload("res://scripts/ui_theme.gd").make()
	_build()
	for point in slots.size():
		if slots[point] != "":
			selected_slot = point
			selected_monster = slots[point]
			break
	_render()

func _build() -> void:
	var sky = preload("res://scripts/sky_background.gd").new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_button(header, "Back to Fleet", _back)
	var title := _label(header, "ENCOUNTER SETUP", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(outer, "Drag monsters onto the formation. Rearrange placed monsters by dragging them between slots. Click a monster to inspect its stats and cards.")
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)
	var board_scroll := ScrollContainer.new()
	board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(board_scroll)
	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_scroll.add_child(board)
	formation = preload("res://scripts/formation_view.gd").new()
	formation.large_cards = true
	formation.custom_minimum_size = Vector2(470, 370)
	formation.position_selected.connect(_select_slot)
	board.add_child(formation)
	_label(board, "MONSTERS", 16)
	var roster := HFlowContainer.new()
	roster.name = "MonsterRoster"
	board.add_child(roster)
	for monster in monsters.values():
		var button := _button(roster, monster.name, _inspect_monster.bind(monster.id))
		button.set_drag_forwarding(_begin_drag.bind(monster.id, -1, button), Callable(), Callable())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = .72
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 8)
	scroll.add_child(inspector)
	var footer := HBoxContainer.new()
	outer.add_child(footer)
	status = _label(footer, "")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button = _button(footer, "Start Battle", _start)

func _label(parent: Node, value: String, font_size: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _render() -> void:
	var enemies: Array = []
	var positions: Array = [-1, -1, -1, -1]
	var card_count := 0
	draft.setup.enemies.clear()
	for point in slots.size():
		var id: String = slots[point]
		if id.is_empty():
			continue
		positions[point] = enemies.size()
		var monster: Dictionary = monsters[id]
		enemies.append(monster.merged({"default_text": Catalog.effects_text(monster.default_action, monster.name)}))
		draft.setup.enemies.append({"enemy": id, "position": Geometry.POSITIONS[point]})
		for entry in monsters[id].stance_loadout:
			card_count += int(entry.count)
	formation.configure({"enemies": enemies, "enemy_formation": positions}, true)
	for point in slots.size():
		var widget: Button = formation.widgets[point]
		var drag_source := Callable()
		if slots[point] != "":
			drag_source = _begin_drag.bind(slots[point], point, widget)
		widget.set_drag_forwarding(drag_source, _can_drop.bind(point), _drop.bind(point))
	start_button.disabled = enemies.is_empty()
	status.text = "Place at least one monster." if enemies.is_empty() else "%d monsters · %d stance cards" % [enemies.size(), card_count]
	_inspect()

func _select_slot(point: int) -> void:
	if slots[point] == "":
		return
	selected_slot = point
	selected_monster = slots[point]
	_inspect()

func _inspect_monster(id: String) -> void:
	selected_slot = -1
	selected_monster = id
	_inspect()

func _inspect() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	if selected_monster == "":
		_label(inspector, "Select a monster to inspect it.")
		return
	var monster: Dictionary = monsters[selected_monster]
	_label(inspector, monster.name, 23).set_meta("plain_text", true)
	_label(inspector, "Hull %d · Armour %d · Weapon %d %s" % [monster.hull, monster.armour, monster.weapon.damage, monster.weapon.range])
	if selected_slot >= 0:
		_label(inspector, Geometry.POSITION_NAMES[selected_slot]).set_meta("plain_text", true)
		_button(inspector, "Remove from encounter", _remove_selected)
	_label(inspector, "Default action", 16)
	var fallback := Catalog.effects_text(monster.default_action, monster.name)
	_label(inspector, fallback if not fallback.is_empty() else "None")
	_label(inspector, "Stance cards", 18)
	var counts: Dictionary = {}
	for entry in monster.stance_loadout:
		counts[entry.stance] = counts.get(entry.stance, 0) + int(entry.count)
	for stance in monster.stances:
		if not counts.has(stance.id):
			continue
		var panel := PanelContainer.new()
		inspector.add_child(panel)
		var card := VBoxContainer.new()
		panel.add_child(card)
		var copies: int = counts[stance.id]
		var quantity := "1 copy" if copies == 1 else "%d copies" % copies
		_label(card, "%s · %s" % [stance.name, quantity], 16).set_meta("plain_text", true)
		var intent := Catalog.effects_text(stance.effects, monster.name)
		_label(card, "Intent — " + (intent if not intent.is_empty() else "None"))
		for reaction in stance.reactions:
			_label(card, reaction.name + " — " + Rules.reaction_condition_text(reaction.conditions, monster.name) + " → " + Catalog.effects_text(reaction.effects, monster.name))

func _begin_drag(_position: Vector2, id: String, origin: int, control: Control) -> Dictionary:
	var preview := Label.new()
	preview.text = monsters[id].name
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_drag_preview(preview)
	var notes: Dictionary = {}
	for point in slots.size():
		if point == origin:
			continue
		var widget: Button = formation.widgets[point]
		var label := "Place monster"
		if slots[point] != "":
			label = "Swap monsters" if origin >= 0 else "Replace monster"
		notes[widget.get_meta("ship_index", 100 + point)] = label
	formation.show_rule_preview(notes)
	return {"encounter": get_instance_id(), "monster": id, "origin": origin}

func _can_drop(_position: Vector2, data: Variant, point: int) -> bool:
	if not data is Dictionary or data.get("encounter") != get_instance_id():
		return false
	var origin: int = data.get("origin", -1)
	return monsters.has(data.get("monster")) and origin != point and (origin == -1 or (origin in range(slots.size()) and slots[origin] == data.monster))

func _drop(position: Vector2, data: Variant, point: int) -> void:
	if not _can_drop(position, data, point):
		return
	if data.origin >= 0:
		slots[data.origin] = slots[point]
	slots[point] = data.monster
	selected_monster = data.monster
	selected_slot = point
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(formation):
		formation.show_rule_preview()

func _remove_selected() -> void:
	slots[selected_slot] = ""
	selected_slot = -1
	_render()

func _back() -> void:
	BattleSession.encounter_content = draft.duplicate(true)
	get_tree().change_scene_to_file("res://scenes/fleet_preparation.tscn")

func _start() -> void:
	var errors := Catalog.validate(draft)
	if not errors.is_empty():
		status.text = errors[0]
		return
	BattleSession.encounter_content = draft.duplicate(true)
	BattleSession.prepared_content = draft.duplicate(true)
	BattleSession.editor_playtest = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

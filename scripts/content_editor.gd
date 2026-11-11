extends Control
## Draft-only content authoring. Shared chunk metadata owns all ability forms.
const Catalog = preload("res://scripts/content_catalog.gd")
const R = preload("res://scripts/rules/rule_registry.gd")
const Spec = preload("res://scripts/rules/spec_editor.gd")
const RuleEditor = preload("res://scripts/rules/rule_editor.gd")
const State = preload("res://scripts/battle_state.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CardFace = preload("res://scripts/card_face.gd")
const Formation = preload("res://scripts/formation_view.gd")
const Circle = preload("res://scripts/circle_view.gd")
const Row = preload("res://scripts/enemy_row_view.gd")
const Ui = preload("res://scripts/ui_theme.gd")
const KINDS := ["leviathans", "ships", "captains", "cards"]
const TITLES := ["Enemies", "Ships", "Captains", "Cards"]
var draft: Dictionary = {}
var selected_ids: Dictionary = {}
var tabs: TabContainer
var inspector_tabs: TabContainer
var searches: Dictionary = {}
var browsers: Dictionary = {}
var forms: Dictionary = {}
var fields: Dictionary = {}
var setup_controls: Dictionary = {}
var preview_form: VBoxContainer
var setup_form: VBoxContainer
var preview_widget: Control
var status: RichTextLabel
var dirty_label: Label
var save_button: Button
var test_button: Button
var revert_button: Button
var leave_dialog: ConfirmationDialog
var leave_destination := "menu"
var editing_stance := ""
var preview_position := "front"
var preview_expanded := false
var preview_slot := 0
var preview_tags: Dictionary = {}
var _loading := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	draft = Catalog.migrate(ContentStore.snapshot()) if not ContentStore.saved.is_empty() else Catalog.empty_document()
	selected_ids = ContentStore.editor_state.get("selected", {}).duplicate()
	editing_stance = ContentStore.editor_state.get("editing_stance", "")
	preview_position = ContentStore.editor_state.get("preview_position", "front")
	preview_expanded = ContentStore.editor_state.get("preview_expanded", false)
	preview_slot = ContentStore.editor_state.get("preview_slot", 0)
	preview_tags = ContentStore.editor_state.get("preview_tags", {}).duplicate()
	theme = Ui.make()
	_build()
	tabs.current_tab = clampi(ContentStore.editor_state.get("tab", 0), 0, 3)
	for kind in KINDS: searches[kind].text = ContentStore.editor_state.get("searches", {}).get(kind, "")
	_refresh()
	_message("Version 3 / ships, captains, paired upgrades, shared enemy deck, and registered rules." if not ContentStore.migration_pending else "Legacy content migrated in memory. Save All explicitly writes version 3; imported rule counts are flagged.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_destination = "quit"
		_request_leave()


func _box(parent: Node, horizontal: bool = false) -> BoxContainer:
	var box: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	parent.add_child(box)
	return box


func _label(parent: Node, text: String, size_value: int = 13) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent is HBoxContainer: label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size_value)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	parent.add_child(button)
	button.pressed.connect(action)
	return button


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#07121b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var outer := _box(margin)
	var header := _box(outer, true)
	var title := _label(header, "CONTENT EDITOR", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dirty_label = _label(header, "", 13)
	dirty_label.custom_minimum_size.x = 120
	dirty_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	dirty_label.modulate = Color("#e8bd77")
	save_button = _button(header, "Save All", _save)
	revert_button = _button(header, "Revert Unsaved Changes", _revert)
	test_button = _button(header, "Save & Test Battle", _test_battle)
	_button(header, "Main Menu", _request_menu)
	status = RichTextLabel.new()
	status.custom_minimum_size.y = 44
	status.fit_content = false
	status.scroll_active = true
	status.selection_enabled = true
	outer.add_child(status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 880
	outer.add_child(split)
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.x = 560
	split.add_child(tabs)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var panel := HSplitContainer.new()
		panel.name = TITLES[i]
		panel.split_offset = 205
		tabs.add_child(panel)
		var list_panel := PanelContainer.new()
		panel.add_child(list_panel)
		var list := _box(list_panel)
		var search := LineEdit.new()
		search.placeholder_text = "Search " + TITLES[i].to_lower()
		list.add_child(search)
		searches[kind] = search
		search.text_changed.connect(func(_value): _refresh_list(kind))
		var entries := ItemList.new()
		entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
		entries.custom_minimum_size.x = 190
		list.add_child(entries)
		browsers[kind] = entries
		entries.item_selected.connect(func(index):
			selected_ids[kind] = entries.get_item_metadata(index)
			_rebuild_form()
			_live_preview())
		var tools := _box(list, true)
		_button(tools, "New", _new_entry.bind(kind))
		_button(tools, "Duplicate", _duplicate_entry.bind(kind))
		_button(tools, "Delete", _delete_entry.bind(kind))
		var form_panel := PanelContainer.new()
		panel.add_child(form_panel)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		form_panel.add_child(scroll)
		var form := _box(scroll)
		form.custom_minimum_size.x = 330
		forms[kind] = form
	tabs.tab_changed.connect(func(_index): _rebuild_form(); _live_preview())
	inspector_tabs = TabContainer.new()
	inspector_tabs.custom_minimum_size.x = 315
	split.add_child(inspector_tabs)
	for title_text in ["Preview", "Battle Setup"]:
		var panel := PanelContainer.new()
		panel.name = title_text
		inspector_tabs.add_child(panel)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		var column := _box(scroll) as VBoxContainer
		column.custom_minimum_size.x = 280
		if title_text == "Preview": preview_form = column
		else: setup_form = column
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Unsaved content"
	leave_dialog.ok_button_text = "Save"
	leave_dialog.cancel_button_text = "Cancel"
	leave_dialog.add_button("Discard", true, "discard")
	add_child(leave_dialog)
	leave_dialog.confirmed.connect(func(): if _save(): _leave())
	leave_dialog.custom_action.connect(func(action): if action == "discard": _leave())


func _kind() -> String: return KINDS[maxi(0, tabs.current_tab)]
func selected_entry() -> Dictionary:
	var kind := _kind()
	var index := Catalog.index_by_id(draft[kind], selected_ids.get(kind, ""))
	return draft[kind][index] if index >= 0 else {}


func _refresh() -> void:
	for kind in KINDS: _refresh_list(kind)
	_rebuild_form()
	_build_setup()
	_live_preview()
	_dirty()


func _refresh_list(kind: String) -> void:
	var list: ItemList = browsers[kind]
	list.clear()
	var filter: String = searches[kind].text.to_lower()
	for entry in draft[kind]:
		if filter != "" and not (filter in str(entry.name).to_lower() or filter in str(entry.id).to_lower()): continue
		list.add_item(entry.name)
		list.set_item_metadata(list.item_count - 1, entry.id)
		if selected_ids.get(kind, "") == entry.id: list.select(list.item_count - 1)
	if list.get_selected_items().is_empty() and list.item_count > 0:
		list.select(0)
		selected_ids[kind] = list.get_item_metadata(0)


func _edit(entry: Dictionary, key: String, value: Variant) -> void:
	entry[key] = value
	_dirty()
	_live_preview()


func _dirty() -> void:
	dirty_label.text = "Unsaved changes" if is_dirty() else "Saved"


func is_dirty() -> bool:
	return ContentStore.migration_pending or JSON.stringify(Catalog.normalized(draft)) != JSON.stringify(Catalog.normalized(ContentStore.saved))


func _row(parent: Node, caption: String) -> HBoxContainer:
	var row := _box(parent, true) as HBoxContainer
	var label := _label(row, caption)
	label.custom_minimum_size.x = 128
	label.size_flags_horizontal = Control.SIZE_FILL
	return row


func _line(parent: Node, caption: String, entry: Dictionary, key: String, field_key: String = "") -> LineEdit:
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = str(entry.get(key, ""))
	_row(parent, caption).add_child(edit)
	edit.text_changed.connect(func(value): _edit(entry, key, value))
	if field_key != "": fields[field_key] = edit
	return edit


func _number(parent: Node, caption: String, initial: int, update: Callable, field_key: String = "", minimum: int = 0, maximum: int = 9999) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, caption).add_child(spin)
	spin.value_changed.connect(func(value): update.call(int(value)))
	if field_key != "": fields[field_key] = spin
	return spin


func _options(kind: String, owner: String = "") -> Array:
	var result: Array = []
	for entry in draft[kind]:
		if owner == "" or entry.get("owner", "") == owner:
			result.append({"value": entry.id, "label": entry.name})
	return result


func _menu(parent: Node, caption: String, values: Array, initial: Variant, update: Callable, field_key: String = "") -> OptionButton:
	var menu := OptionButton.new()
	menu.fit_to_longest_item = false
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, caption).add_child(menu)
	for item in values:
		var value: Variant = item.value if item is Dictionary else item
		var title: String = item.label if item is Dictionary else str(item).capitalize()
		menu.add_item(title)
		menu.set_item_metadata(menu.item_count - 1, value)
		if value == initial: menu.select(menu.item_count - 1)
	menu.item_selected.connect(func(index): update.call(menu.get_item_metadata(index)))
	if field_key != "": fields[field_key] = menu
	return menu


func _rules_list(parent: Node, rules: Array, title: String, zone: String) -> void:
	var heading := _box(parent, true)
	_label(heading, title, 14)
	_button(heading, "Add Rule", func():
		var rule := R.rule("on_play" if zone == "circle" else "turn_start", [{"kind": "gain_resource", "target": "owner", "amount": 1}], zone)
		rule.id = _id(rules, "rule")
		if zone != "circle": rule.trigger.subject = "owner"
		rules.append(rule)
		_dirty()
		_rebuild_form())
	for index in rules.size():
		var column := _panel(parent)
		_tools(column, rules, index)
		var editor := RuleEditor.new()
		column.add_child(editor)
		editor.configure(rules[index])
		editor.changed.connect(func(): _dirty(); _live_preview())


func _tools(parent: Node, list: Array, index: int) -> void:
	var tools := _box(parent, true)
	_button(tools, "↑", _move.bind(list, index, -1))
	_button(tools, "↓", _move.bind(list, index, 1))
	_button(tools, "Remove", func(): list.remove_at(index); _dirty(); _rebuild_form(); _live_preview())


func _move(list: Array, index: int, delta: int) -> void:
	var destination := index + delta
	if destination < 0 or destination >= list.size(): return
	var entry: Variant = list[index]
	list.remove_at(index)
	list.insert(destination, entry)
	_dirty()
	_rebuild_form()
	_live_preview()


func _panel(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	return _box(panel) as VBoxContainer


func _effects(parent: Node, list: Array, title: String = "ORDERED EFFECTS") -> void:
	var heading := _box(parent, true)
	_label(heading, title, 14)
	_button(heading, "Add Effect", func(): list.append(R.fresh("effect", "attack")); _dirty(); _rebuild_form())
	for index in list.size():
		var column := _panel(parent)
		_tools(column, list, index)
		var editor := Spec.new()
		column.add_child(editor)
		editor.configure("effect", list[index])
		editor.changed.connect(func(): _dirty(); _live_preview())


func _rebuild_form() -> void:
	if not is_instance_valid(tabs): return
	fields.clear()
	var form: VBoxContainer = forms[_kind()]
	_clear(form)
	var entry := selected_entry()
	if entry.is_empty(): _label(form, "Create or select content."); return
	_label(form, entry.id, 12).modulate = Color("#80a7b7")
	_line(form, "Name", entry, "name", "name")
	match _kind():
		"cards": _card_form(form, entry)
		"ships": _ship_form(form, entry)
		"captains":
			_number(form, "Tier", entry.tier, func(value): _edit(entry, "tier", value), "tier", 1, 3)
			_menu(form, "Card pair", _options("cards", entry.id), entry.card, func(value): _edit(entry, "card", value), "captain_card")
			_label(form, "PASSIVE / one registered rule block", 14)
			var editor := RuleEditor.new()
			form.add_child(editor)
			editor.configure(entry.passive)
			editor.changed.connect(func(): _dirty(); _live_preview())
		"leviathans": _enemy_form(form, entry)


func _card_form(form: Node, entry: Dictionary) -> void:
	_menu(form, "Owning source", _options("ships") + _options("captains"), entry.owner, func(value): _edit(entry, "owner", value), "owner")
	_menu(form, "Primary type", R.TYPES, entry.type, func(value): _edit(entry, "type", value), "type")
	_number(form, "Mana cost", entry.cost, func(value): _edit(entry, "cost", value), "cost")
	_number(form, "Mana produced", entry.pays, func(value): _edit(entry, "pays", value), "pays", 1)
	var traits := LineEdit.new()
	traits.text = ", ".join(entry.traits)
	traits.placeholder_text = "Traits, separated by commas"
	_row(form, "Traits").add_child(traits)
	traits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	traits.text_changed.connect(func(value):
		var values: Array = []
		for item in value.split(","):
			if item.strip_edges() != "": values.append(item.strip_edges())
		_edit(entry, "traits", values))
	var points := _box(form, true)
	for point in Geometry.POSITIONS:
		var check := CheckBox.new()
		check.text = point
		check.button_pressed = entry.positions.has(point)
		points.add_child(check)
		fields["position_" + point] = check
		check.toggled.connect(func(enabled):
			if enabled and not entry.positions.has(point): entry.positions.append(point)
			elif not enabled: entry.positions.erase(point)
			_dirty()
			_live_preview())
	if entry.get("legacy_import", false):
		_label(form, "Imported rule count preserved. New cards use 1–3 blocks.", 12).modulate = Color("#e8bd77")
		_button(form, "Adopt 1–3-block card convention", func(): entry.erase("legacy_import"); _dirty(); _rebuild_form(); _live_preview())
	_rules_list(form, entry.rules, "RULE BLOCKS / 1–3 total, including On Play; starter 1, upgrades 2/3, captain = tier", "circle")


func _open_rig_editor(entry: Dictionary) -> void:
	var dialog = preload("res://scripts/visuals/rig_editor.gd").new()
	add_child(dialog)
	var visual: Dictionary = preload("res://scripts/art_assets.gd").visual_rig(entry, entry in draft.leviathans)
	dialog.configure(visual, entry.id, entry.name)
	dialog.applied.connect(func(value):
		entry["visual_rig"] = value.duplicate(true)
		_dirty(); _rebuild_form(); _live_preview())
	dialog.popup_centered(Vector2i(mini(1180, int(get_viewport_rect().size.x*.96)), mini(740, int(get_viewport_rect().size.y*.94))))


func _unit_form(form: Node, entry: Dictionary) -> void:
	_button(form, "Sprites & animation…", func(): _open_rig_editor(entry))
	_number(form, "Maximum hull", entry.hull, func(value): _edit(entry, "hull", value), "hull", 1)
	_number(form, "Armour per hit", entry.armour, func(value): _edit(entry, "armour", value), "armour")
	_number(form, "Weapon damage", entry.weapon.damage, func(value): _edit(entry.weapon, "damage", value), "weapon_damage")
	_menu(form, "Weapon range", ["Short", "Long"], entry.weapon.range, func(value): _edit(entry.weapon, "range", value), "weapon_range")


func _ship_form(form: Node, entry: Dictionary) -> void:
	_line(form, "Role", entry, "role", "role")
	_unit_form(form, entry)
	var colour := ColorPickerButton.new()
	colour.color = Color(entry.color)
	colour.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(form, "Colour").add_child(colour)
	colour.color_changed.connect(func(value): _edit(entry, "color", value.to_html()))
	_menu(form, "Starter pair / simple", _options("cards", entry.id), entry.starter, func(value): _edit(entry, "starter", value), "starter")
	_menu(form,"Starter pair / two effects",[{"label":"None / imported single pair","value":""}]+_options("cards",entry.id),entry.get("starter_two",""),func(value):_edit(entry,"starter_two",value),"starter_two")
	if entry.has("legacy_loadout"):
		_label(form, "Imported loadout retained until you adopt pair progression.", 12)
		for slot in entry.legacy_loadout:
			_number(form, slot.card, slot.count, func(value): _edit(slot, "count", value), "", 1)
		_button(form, "Use paired level progression", func(): entry.erase("legacy_loadout"); _dirty(); _rebuild_form(); _build_setup())
	_line(form, "Resource name", entry.resource, "name", "resource_name")
	_number(form, "Resource capacity", entry.resource.capacity, func(value): _edit(entry.resource, "capacity", value), "resource_capacity", 1)
	_rules_list(form, entry.resource.rules, "RESOURCE GAIN / AUTOMATIC SPEND / OPTIONAL BOOSTS", "ship")
	_rules_list(form, entry.rules, "BASE SHIP RULES", "ship")
	for tier in ["two", "three"]:
		_label(form, "LEVEL " + ("2 / two choices" if tier == "two" else "3 / three choices"), 17)
		for package in entry.levels[tier]:
			var panel := _panel(form)
			_line(panel, "Branch name", package, "name")
			_label(panel, "Stable branch ID: " + package.id, 12)
			_menu(panel, "Card pair", _options("cards", entry.id), package.card, func(value): _edit(package, "card", value))
			if tier == "two":
				var choices: Array = []
				for other in entry.levels.three: choices.append({"value": other.id, "label": other.name})
				_menu(panel, "Blocks level 3", choices, package.blocks, func(value): _edit(package, "blocks", value))
			for key in ["rule", "passive"]:
				_label(panel, "SPECIAL RULE" if key == "rule" else "PASSIVE UPGRADE", 13)
				var editor := RuleEditor.new()
				panel.add_child(editor)
				editor.configure(package[key])
				editor.changed.connect(func(): _dirty(); _live_preview())


func _enemy_form(form: Node, entry: Dictionary) -> void:
	_unit_form(form, entry)
	_effects(form, entry.default_action, "WEAKER DEFAULT ACTION / if no activation this phase")
	_label(form, "SHARED DECK CONTRIBUTION / physical copies", 14)
	for stance in entry.stances:
		var count := 0
		for slot in entry.stance_loadout:
			if slot.stance == stance.id: count = slot.count
		_number(form, stance.name, count, func(value):
			var index := -1
			for i in entry.stance_loadout.size():
				if entry.stance_loadout[i].stance == stance.id: index = i
			if value == 0 and index >= 0: entry.stance_loadout.remove_at(index)
			elif index >= 0: entry.stance_loadout[index].count = value
			elif value > 0: entry.stance_loadout.append({"stance": stance.id, "count": value})
			_dirty(); _live_preview())
	if Catalog.index_by_id(entry.stances, editing_stance) < 0: editing_stance = entry.stances[0].id
	var choices: Array = []
	for stance in entry.stances: choices.append({"value": stance.id, "label": stance.name})
	_menu(form, "Editing stance", choices, editing_stance, func(value): editing_stance = value; _rebuild_form(); _live_preview(), "editing_stance")
	var tools := _box(form, true)
	_button(tools, "New Stance", _new_stance.bind(entry))
	_button(tools, "Duplicate Stance", _duplicate_stance.bind(entry))
	_button(tools, "Delete Stance", _delete_stance.bind(entry))
	var stance: Dictionary = entry.stances[Catalog.index_by_id(entry.stances, editing_stance)]
	_line(form, "Stance name", stance, "name", "stance_name")
	var add := _box(form, true)
	_label(add, "REACTIONS / first matching rule per enemy", 14)
	_button(add, "Add Reaction", func():
		stance.reactions.append({"id": _id(stance.reactions, "reaction"), "name": "New Reaction", "category": "Retaliation", "conditions": {"kind": "reaction_trigger", "family": "card_type", "card_type": "Attack"}, "effects": [{"kind": "attack", "target": "chosen_ally", "damage": 2, "hits": 1, "range": "weapon"}]})
		_dirty(); _rebuild_form())
	for index in stance.reactions.size():
		var reaction: Dictionary = stance.reactions[index]
		var column := _panel(form)
		_tools(column, stance.reactions, index)
		_line(column, "Name", reaction, "name")
		_line(column, "Category", reaction, "category")
		var labels: Array=[{"label":"Played card type","value":"card_type"},{"label":"Played from position","value":"position"},{"label":"On monster damaged","value":"damaged"},{"label":"On heal","value":"healed"}]
		var family: String = reaction.conditions.get("family", "custom") if reaction.conditions.get("kind") == "reaction_trigger" and not reaction.get("custom_trigger",false) else "custom"
		labels.append({"label":"Custom trigger","value":"custom"})
		_menu(column,"Trigger",labels,family,func(value):
			if value == "custom":
				reaction.custom_trigger=true
			else:
				reaction.erase("custom_trigger")
				reaction.conditions={"kind":"reaction_trigger","family":value,"card_type":"Attack","position":"front"}
			_dirty(); _rebuild_form(); _live_preview(), "reaction_trigger_" + reaction.id)
		if family == "card_type": _menu(column,"Card type",R.TYPES,reaction.conditions.get("card_type","Attack"),func(value): reaction.conditions.card_type=value; _dirty(); _live_preview(),"reaction_type_"+reaction.id)
		elif family == "position": _menu(column,"Played from",[{"label":"Front","value":"front"},{"label":"Upper Flank","value":"upper"},{"label":"Lower Flank","value":"lower"},{"label":"Rear","value":"rear"}],reaction.conditions.get("position","front"),func(value): reaction.conditions.position=value; _dirty(); _live_preview(),"reaction_position_"+reaction.id)
		elif family == "custom":
			var spec:=Spec.new()
			spec.set_meta("custom_reaction",reaction.id)
			column.add_child(spec)
			spec.configure("condition",reaction.conditions)
			spec.changed.connect(func(): _dirty(); _live_preview())
		_effects(column, reaction.effects)
	_effects(form, stance.effects, "ENEMY-PHASE ACTIVATION")


func _build_setup() -> void:
	_clear(setup_form)
	setup_controls.clear()
	_label(setup_form, "BATTLE PREPARATION", 17)
	for i in draft.setup.fleet.size():
		var slot: Dictionary = draft.setup.fleet[i]
		var panel := _panel(setup_form)
		_label(panel, "SHIP " + str(i + 1), 14)
		setup_controls["ship_" + str(i)] = _menu(panel, "Ship", _options("ships"), slot.ship, func(value): slot.ship = value; _repair_branch(slot); _dirty(); _build_setup.call_deferred())
		setup_controls["captain_" + str(i)] = _menu(panel, "Captain", _options("captains"), slot.captain, func(value): _edit(slot, "captain", value))
		setup_controls["level_" + str(i)] = _number(panel, "Level", slot.level, func(value): slot.level = value; _repair_branch(slot); _dirty(); _build_setup.call_deferred(), "", 1, 3)
		setup_controls["point_" + str(i)] = _menu(panel, "Position", Geometry.POSITIONS, slot.position, func(value): _edit(slot, "position", value))
		var index := Catalog.index_by_id(draft.ships, slot.ship)
		if index >= 0:
			var ship: Dictionary = draft.ships[index]
			if slot.level >= 2:
				var values: Array = []
				for package in ship.levels.two: values.append({"value": package.id, "label": package.name})
				setup_controls["l2_" + str(i)] = _menu(panel, "Level 2", values, slot.level_2, func(value): slot.level_2 = value; _repair_branch(slot); _dirty(); _build_setup.call_deferred())
			if slot.level >= 3:
				var blocked := ""
				var branch := Catalog.index_by_id(ship.levels.two, slot.level_2)
				if branch >= 0: blocked = ship.levels.two[branch].blocks
				var values: Array = []
				for package in ship.levels.three:
					if package.id != blocked: values.append({"value": package.id, "label": package.name})
				setup_controls["l3_" + str(i)] = _menu(panel, "Level 3", values, slot.level_3, func(value): _edit(slot, "level_3", value))
			_label(panel, "Deck: " + ("imported loadout" if ship.has("legacy_loadout") else str(2 + int(slot.level) * 2) + " cards / pairs include captain"), 12)
	_label(setup_form, "ENEMY DIAMOND / 1–4 instances", 15)
	for i in draft.setup.enemies.size():
		var slot: Dictionary = draft.setup.enemies[i]
		var panel := _panel(setup_form)
		setup_controls["enemy_" + str(i)] = _menu(panel, "Enemy", _options("leviathans"), slot.enemy, func(value): _edit(slot, "enemy", value))
		setup_controls["enemy_point_" + str(i)] = _menu(panel, "Position", Geometry.POSITIONS, slot.position, func(value): _edit(slot, "position", value))
		_button(panel, "Remove Enemy", func(): if draft.setup.enemies.size() > 1: draft.setup.enemies.remove_at(i); _dirty(); _build_setup())
	var add := _button(setup_form, "Add Enemy", func():
		var used: Array = draft.setup.enemies.map(func(slot): return slot.position)
		for point in Geometry.POSITIONS:
			if not used.has(point):
				draft.setup.enemies.append({"enemy": draft.leviathans[0].id, "position": point})
				break
		_dirty(); _build_setup())
	add.disabled = draft.setup.enemies.size() >= 4 or draft.leviathans.is_empty()
	_label(setup_form, "MANA / BASIC ACTIONS", 15)
	for key in ["mana_capacity", "mana_reward", "retain_threshold"]:
		setup_controls[key] = _number(setup_form, key.replace("_", " ").capitalize(), int(draft.setup[key]), func(value): _edit(draft.setup, key, value), "", 1 if key == "retain_threshold" else 0)
	for key in ["repair", "revive_threshold"]:
		setup_controls["basic_" + key] = _number(setup_form, key.replace("_", " ").capitalize(), int(draft.setup.basic_actions[key]), func(value): _edit(draft.setup.basic_actions, key, value), "", 1)
	var fixed := CheckBox.new()
	fixed.text = "Fixed seven-card opening hand"
	fixed.button_pressed = draft.setup.fixed_hand
	setup_form.add_child(fixed)
	setup_controls.fixed_hand = fixed
	fixed.toggled.connect(func(value): draft.setup.fixed_hand = value; _dirty(); _build_setup.call_deferred())
	if draft.setup.fixed_hand:
		while draft.setup.opening_hand.size() < 7: draft.setup.opening_hand.append("")
		for i in 7:
			setup_controls["opening_" + str(i)] = _menu(setup_form, "Card " + str(i + 1), _options("cards"), draft.setup.opening_hand[i], func(value): draft.setup.opening_hand[i] = value; _dirty())
	_label(setup_form, "Shared enemy row draws three physical cards. More contributed copies mean more activation opportunities. Save validates pair ownership, counts, positions, and all references.", 12)


func _repair_branch(slot: Dictionary) -> void:
	var index := Catalog.index_by_id(draft.ships, slot.ship)
	if index >= 0: Catalog.repair_fleet_branch(slot, draft.ships[index])


func _live_preview() -> void:
	if not is_instance_valid(preview_form): return
	_clear(preview_form)
	var entry := selected_entry()
	if entry.is_empty(): _label(preview_form, "Select content to preview."); return
	_label(preview_form, "LIVE / UNSAVED DRAFT", 13).modulate = Color("#d6adee")
	if _kind() == "cards" or _kind() == "captains":
		var source: Dictionary = entry
		if _kind() == "captains":
			preview_form.add_child(preload("res://scripts/art_assets.gd").portrait_view(entry.id,Vector2(150,200)))
			_label(preview_form, entry.name + " / Tier " + str(entry.tier), 18)
			var index := Catalog.index_by_id(draft.cards, entry.card)
			if index < 0: _label(preview_form, "Choose an existing captain card pair."); return
			source = draft.cards[index]
		var preview_owner: String = source.owner
		for assignment in draft.setup.fleet:
			if assignment.captain == source.owner: preview_owner = assignment.ship
		var owner_index := Catalog.index_by_id(draft.ships, preview_owner)
		var owner: Dictionary = draft.ships[owner_index] if owner_index >= 0 else entry
		if _kind() == "captains": _label(preview_form, R.rule_text(entry.passive, owner.name), 12)
		var face := CardFace.new()
		face.custom_minimum_size = Vector2(270, 340)
		preview_form.add_child(face)
		face.configure(Catalog.present_card(source), owner)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_widget = face
		_label(preview_form, "Full generated rules are available in the tooltip.", 12)
		var expanded_check := CheckBox.new()
		expanded_check.text = "Expanded adjacency context"
		expanded_check.button_pressed = preview_expanded
		preview_form.add_child(expanded_check)
		expanded_check.toggled.connect(func(value): preview_expanded = value; preview_slot = mini(preview_slot, 3); _live_preview())
		var slots: Array = []
		for point in (9 if preview_expanded else 4): slots.append({"value": point, "label": Geometry.SLOT_NAMES[point]})
		_menu(preview_form, "Preview slot", slots, preview_slot, func(value): preview_slot = value; _live_preview())
		var contents: Array = [-1, -1, -1, -1, -1, -1, -1, -1, -1]
		var data: Dictionary = {0: Catalog.present_card(source)}
		contents[preview_slot] = 0
		for point in Geometry.neighbours(preview_slot, preview_expanded):
			var type: String = preview_tags.get(point, "")
			if type != "":
				contents[point] = point + 1
				data[point + 1] = {"name": type, "type": type, "effect": "", "rules": [], "traits": []}
		var circle := Circle.new()
		circle.custom_minimum_size.y = 200
		preview_form.add_child(circle)
		circle.configure(contents, preview_expanded, data, {}, preview_slot)
		for point in Geometry.neighbours(preview_slot, preview_expanded):
			_menu(preview_form, Geometry.SLOT_NAMES[point], [""] + R.TYPES, preview_tags.get(point, ""), func(value): preview_tags[point] = value; _live_preview())
		_preview_conditions(source, contents, data, str(owner.name))
	else:
		_menu(preview_form, "Preview position", Geometry.POSITIONS, preview_position, func(value): preview_position = value; _live_preview())
		var view := Formation.new()
		view.custom_minimum_size.y = 250
		preview_form.add_child(view)
		var data := entry.duplicate(true)
		data["max_hull"] = maxi(1, int(entry.hull))
		data["guard"] = 0
		data["resource_name"] = entry.get("resource", {}).get("name", "")
		data["resource_capacity"] = entry.get("resource", {}).get("capacity", 0)
		data["resource"] = 0
		if _kind() == "ships": data["mechanic_text"] = "\n".join(entry.resource.rules.map(func(rule): return R.rule_text(rule, entry.name)))
		if _kind() == "ships" and Catalog.validate(draft).is_empty():
			var sim = State.new(0, draft)
			for unit_data in sim.board_snapshot().ships:
				if unit_data.id == entry.id: data = unit_data.duplicate(true)
		var point := Geometry.POSITIONS.find(preview_position)
		var board := {"ships": [data], "enemies": [data], "formation": [-1, -1, -1, -1], "enemy_formation": [-1, -1, -1, -1], "enemy_position": point, "monster_hull": entry.hull, "cover": [0, 0, 0, 0, 0, 0, 0, 0]}
		board.formation[point] = 0
		board.enemy_formation[point] = 0
		view.configure(board, _kind() == "leviathans", entry)
		preview_widget = view
		if _kind() == "leviathans":
			var index := Catalog.index_by_id(entry.stances, editing_stance)
			if index < 0: index = 0
			var row := Row.new()
			row.custom_minimum_size.y = 110
			preview_form.add_child(row)
			var stance: Dictionary = entry.stances[index].duplicate(true)
			stance["uid"] = 0
			stance["owner_name"] = entry.name
			stance["owner_visual"] = {"id":entry.id}
			if entry.has("visual_rig"): stance.owner_visual["visual_rig"] = entry.visual_rig.duplicate(true)
			row.configure([stance])
			_label(preview_form, "Default: " + Catalog.effects_text(entry.default_action, entry.name), 12)
		else:
			_label(preview_form, "Resource / " + entry.resource.name, 15)
			for rule in entry.resource.rules: _label(preview_form, R.rule_text(rule, entry.name), 12)
	var errors := Catalog.validate(draft)
	if not errors.is_empty(): _label(preview_form, "Draft validation: " + str(errors[0]), 12).modulate = Color("#ff927f")


func _preview_conditions(source: Dictionary, contents: Array, cards: Dictionary, owner_name: String) -> void:
	var valid := Catalog.validate(draft).is_empty()
	if not valid: return
	var sim = State.new(0, draft)
	if sim.init_error != "": return
	sim.circle.fill(-1)
	sim.play_order.clear()
	sim.expanded = preview_expanded
	var incoming := -1
	for slot in contents.size():
		if contents[slot] < 0: continue
		var virtual: Dictionary = source.duplicate(true) if slot == preview_slot else {"id": "preview_" + str(slot), "name": cards[contents[slot]].name, "owner": "", "type": cards[contents[slot]].type, "traits": [], "cost": 0, "pays": 1, "positions": Geometry.POSITIONS.duplicate(), "rules": []}
		var uid: int = sim.card_keys.size()
		sim.card_keys.append(virtual.id)
		sim.definitions.cards[virtual.id] = Catalog.present_card(virtual, 0)
		if slot == preview_slot: incoming = uid
		else: sim.circle[slot] = uid; sim.play_order.append(uid)
	var ctx := {"state": sim, "uid": incoming, "owner": 0, "slot": preview_slot, "event": {"kind": "on_play", "uid": incoming, "actor": 0, "card": sim.card(incoming)}, "proposed_uid": incoming, "proposed_slot": preview_slot}
	for rule in source.rules:
		_label(preview_form, ("ACTIVE / " if R.condition(rule.get("conditions", {"kind": "always"}), ctx) else "Inactive / ") + R.rule_text(rule, owner_name), 12)


func _id(entries: Array, prefix: String) -> String:
	var candidate := prefix
	var index := 2
	while Catalog.index_by_id(entries, candidate) >= 0:
		candidate = prefix + "_" + str(index)
		index += 1
	return candidate


func _new_entry(kind: String) -> void:
	var id := _id(draft[kind], {"ships": "ship", "captains": "captain", "cards": "card", "leviathans": "enemy"}[kind])
	var entry: Dictionary
	if kind == "cards":
		if draft.ships.is_empty(): _message("Create a ship first.", true); return
		entry = _new_card(id, draft.ships[0].id)
	elif kind == "captains":
		var card_id := _id(draft.cards, id + "_orders")
		draft.cards.append(_new_card(card_id, id))
		entry = {"id": id, "name": "New Captain", "tier": 1, "card": card_id, "passive": _new_passive("captain")}
	elif kind == "ships":
		var card_id := _id(draft.cards, id + "_starter")
		draft.cards.append(_new_card(card_id, id))
		entry = {"id": id, "name": "New Ship", "role": "SPECIALIST", "color": "#91c8ad", "hull": 20, "armour": 0, "weapon": {"damage": 4, "range": "Long"}, "resource": {"name": "Charge", "capacity": 6, "rules": []}, "starter": card_id, "starter_two": _id(draft.cards,id+"_starter_two"), "rules": [], "levels": {"two": [], "three": []}}
		var second_starter:=_new_card(entry.starter_two,id,2)
		second_starter.name="New Compound Starter"
		draft.cards.append(second_starter)
		for level in ["two", "three"]:
			for i in (2 if level == "two" else 3):
				var rule := R.rule("turn_start", [{"kind": "gain_resource", "target": "owner", "amount": 1}], "ship")
				rule.trigger.subject = "owner"
				var upgrade_id := _id(draft.cards, id + "_" + level + "_" + str(i))
				var upgrade := _new_card(upgrade_id, id, 2 if level == "two" else 3)
				upgrade.name = "New Level %d Card %d" % [2 if level == "two" else 3, i + 1]
				draft.cards.append(upgrade)
				entry.levels[level].append({"id": level + "_" + str(i), "name": "New " + level + " branch " + str(i + 1), "card": upgrade_id, "blocks": "three_" + str(i), "rule": rule, "passive": _new_passive("ship")})
	else:
		entry = {"id": id, "name": "New Enemy", "hull": 30, "armour": 0, "weapon": {"damage": 4, "range": "Long"}, "default_action": [{"kind": "attack", "target": "chosen_ally", "damage": 2, "hits": 1, "range": "weapon"}], "stances": [{"id": "strike", "name": "Strike", "reactions": [], "effects": [{"kind": "attack", "target": "chosen_ally", "damage": 4, "hits": 1, "range": "weapon"}]}], "stance_loadout": [{"stance": "strike", "count": 3}]}
	draft[kind].append(entry)
	selected_ids[kind] = id
	_refresh()


func _new_card(id: String, owner: String, ability_count: int = 1) -> Dictionary:
	var play := R.rule("on_play", [{"kind": "add_shields", "target": "owner", "amount": 2}])
	play.id = "play"
	var rules: Array = [play]
	if ability_count >= 2:
		var cover := R.rule("on_play", [{"kind": "add_cover", "target": "source_slot", "amount": 2}])
		cover.id = "cover"
		rules.append(cover)
	if ability_count >= 3:
		var persistence := R.rule("on_play", [{"kind": "add_persistence", "target": "self_card", "amount": 1}])
		persistence.id = "persistence"
		rules.append(persistence)
	return {"id": id, "name": "New Card", "owner": owner, "type": "Support", "traits": [], "cost": 1, "pays": 1, "positions": Geometry.POSITIONS.duplicate(), "rules": rules}


func _new_passive(zone: String) -> Dictionary:
	var rule := R.rule("passive", [], zone)
	rule.id = "passive"
	rule.modifiers = [{"kind": "armour", "target": "owner", "amount": 1}]
	return rule


func _duplicate_entry(kind: String) -> void:
	var entry := selected_entry()
	if entry.is_empty(): return
	var copy := entry.duplicate(true)
	copy.id = _id(draft[kind], entry.id + "_copy")
	copy.name += " Copy"
	if kind in ["ships", "captains"]:
		var mapping: Dictionary = {}
		for card in draft.cards.duplicate():
			if card.owner != entry.id: continue
			var card_copy: Dictionary = card.duplicate(true)
			card_copy.id = _id(draft.cards, card.id + "_copy")
			card_copy.name += " Copy"
			card_copy.owner = copy.id
			mapping[card.id] = card_copy.id
			draft.cards.append(card_copy)
		if kind == "ships":
			copy.starter = mapping.get(copy.starter, copy.starter)
			if copy.get("starter_two","")!="":copy.starter_two=mapping.get(copy.starter_two,copy.starter_two)
			for tier in ["two", "three"]:
				for package in copy.levels[tier]: package.card = mapping.get(package.card, package.card)
			for slot in copy.get("legacy_loadout", []): slot.card = mapping.get(slot.card, slot.card)
		else: copy.card = mapping.get(copy.card, copy.card)
	draft[kind].append(copy)
	selected_ids[kind] = copy.id
	_refresh()


func _delete_entry(kind: String) -> void:
	var entry := selected_entry()
	if entry.is_empty(): return
	var references := Catalog.references(draft, kind, entry.id)
	if not references.is_empty():
		_message("Cannot delete " + entry.name + ". Change these references first:\n" + "\n".join(references), true)
		return
	draft[kind].remove_at(Catalog.index_by_id(draft[kind], entry.id))
	selected_ids.erase(kind)
	_refresh()


func _new_stance(entry: Dictionary) -> void:
	var id := _id(entry.stances, "stance")
	entry.stances.append({"id": id, "name": "New Stance", "reactions": [], "effects": [{"kind": "attack", "target": "chosen_ally", "damage": 3, "hits": 1, "range": "weapon"}]})
	entry.stance_loadout.append({"stance": id, "count": 1})
	editing_stance = id
	_dirty(); _rebuild_form(); _live_preview()


func _duplicate_stance(entry: Dictionary) -> void:
	var copy: Dictionary = entry.stances[Catalog.index_by_id(entry.stances, editing_stance)].duplicate(true)
	copy.id = _id(entry.stances, copy.id + "_copy")
	copy.name += " Copy"
	entry.stances.append(copy)
	entry.stance_loadout.append({"stance": copy.id, "count": 1})
	editing_stance = copy.id
	_dirty(); _rebuild_form(); _live_preview()


func _delete_stance(entry: Dictionary) -> void:
	if entry.stances.size() <= 1: _message("Keep at least one stance definition.", true); return
	entry.stances.remove_at(Catalog.index_by_id(entry.stances, editing_stance))
	entry.stance_loadout = entry.stance_loadout.filter(func(slot): return slot.stance != editing_stance)
	editing_stance = entry.stances[0].id
	_dirty(); _rebuild_form(); _live_preview()


func _message(text: String, error: bool = false) -> void:
	status.text = text
	status.modulate = Color("#ff927f") if error else Color("#9ce6b7")


func _save() -> bool:
	if not ContentStore.save_content(draft):
		_message("Cannot save:\n" + ContentStore.last_error, true)
		return false
	draft = ContentStore.snapshot()
	_refresh()
	_dirty()
	_message("Saved project content. Start Game, Retry, and playtests use this setup. No Git commit was created.")
	return true


func _revert() -> void:
	draft = ContentStore.snapshot()
	_refresh()
	_message("Restored the last saved document.")


func _remember() -> void:
	var queries: Dictionary = {}
	for kind in KINDS: queries[kind] = searches[kind].text
	ContentStore.editor_state = {"tab": tabs.current_tab, "selected": selected_ids.duplicate(), "searches": queries, "editing_stance": editing_stance, "preview_position": preview_position, "preview_expanded": preview_expanded, "preview_slot": preview_slot, "preview_tags": preview_tags.duplicate()}


func _test_battle() -> void:
	if not _save(): return
	_remember()
	BattleSession.editor_playtest = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _request_menu() -> void:
	leave_destination = "menu"
	_request_leave()


func _request_leave() -> void:
	if is_dirty():
		leave_dialog.dialog_text = "Save this draft before leaving? Discard restores the saved content."
		leave_dialog.popup_centered()
	else: _leave()


func _leave() -> void:
	_remember()
	BattleSession.editor_playtest = false
	if leave_destination == "quit": get_tree().quit()
	else: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

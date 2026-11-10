extends Control
## Three-tab editor. All widgets edit a detached draft; only Save writes content.

const Catalog = preload("res://scripts/content_catalog.gd")
const Geometry = preload("res://scripts/battle_geometry.gd")
const CardFace = preload("res://scripts/card_face.gd")
const FormationView = preload("res://scripts/formation_view.gd")
const CircleView = preload("res://scripts/circle_view.gd")
const StanceView = preload("res://scripts/stance_view.gd")
var preview_form: VBoxContainer
var inspector_tabs: TabContainer
var preview_widget: Control
var preview_slot := 0
var preview_expanded := false
var preview_tags: Dictionary = {}
var preview_position := "front"
var editing_stance := ""
const KINDS := ["leviathans", "ships", "cards"]
const TITLES := ["Leviathans", "Ships", "Cards"]
var draft: Dictionary = {}
var selected_ids: Dictionary = {}
var fields: Dictionary = {}
var effect_controls: Array = []
var rule_previews: Array = []
var setup_controls: Dictionary = {}
var browsers: Dictionary = {}
var searches: Dictionary = {}
var forms: Dictionary = {}
var toolbars: Dictionary = {}
var tabs: TabContainer
var setup_form: VBoxContainer
var dirty_label: Label
var status: RichTextLabel
var leave_dialog: ConfirmationDialog
var save_button: Button
var revert_button: Button
var test_button: Button
var leave_destination: String = "menu"


func _ready() -> void:
	get_tree().auto_accept_quit = false
	draft = Catalog.migrate(ContentStore.snapshot()) if not ContentStore.saved.is_empty() else Catalog.empty_document()
	selected_ids = ContentStore.editor_state.get("selected", {}).duplicate()
	editing_stance = ContentStore.editor_state.get("editing_stance", "")
	preview_slot = int(ContentStore.editor_state.get("preview_slot", 0))
	preview_expanded = ContentStore.editor_state.get("preview_expanded", false)
	preview_position = ContentStore.editor_state.get("preview_position", "front")
	preview_tags = ContentStore.editor_state.get("preview_tags", {}).duplicate()
	theme = _editor_theme()
	_build_ui()
	tabs.current_tab = clampi(int(ContentStore.editor_state.get("tab", 0)), 0, 2)
	for kind in KINDS:
		searches[kind].text = ContentStore.editor_state.get("searches", {}).get(kind, "")
	_refresh_all()
	if not ContentStore.last_error.is_empty():
		_message("Content loading failed. Repair the draft before saving:\n" + ContentStore.last_error, true)
	elif ContentStore.migration_pending:
		_message("Version-1 content is loaded in compatibility mode. Save All explicitly upgrades the file to version 2.")
	else:
		_message("Choose a tab to edit content. Save All applies the draft to the next battle; Save & Test Battle launches it now.")


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(leave_dialog):
		leave_destination = "quit"
		_request_leave()


func _editor_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 15
	result.set_color("font_color", "Label", Color("#e7ecea"))
	result.set_font_size("normal_font_size", "RichTextLabel", 14)
	var normal := _style(Color("#132e3b"), Color("#3f6573"))
	var hover := _style(Color("#1c3e4d"), Color("#89b6bf"))
	var focus := _style(Color.TRANSPARENT, Color("#e8bd77"))
	result.set_stylebox("panel", "PanelContainer", _style(Color("#102632"), Color("#30505c")))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, normal)
		result.set_stylebox("hover", type, hover)
		result.set_stylebox("pressed", type, hover)
		result.set_stylebox("focus", type, focus)
	result.set_stylebox("normal", "LineEdit", normal)
	result.set_stylebox("focus", "LineEdit", focus)
	result.set_stylebox("panel", "TabContainer", _style(Color("#0c202b"), Color("#30505c")))
	result.set_stylebox("tab_selected", "TabBar", hover)
	result.set_stylebox("tab_unselected", "TabBar", normal)
	result.set_stylebox("panel", "ItemList", normal)
	result.set_stylebox("selected", "ItemList", hover)
	return result


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _box(parent: Node, vertical: bool = true) -> BoxContainer:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	return box


func _label(parent: Node, text: String, size_value: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _row(parent: Node, caption: String) -> HBoxContainer:
	var row := _box(parent, false) as HBoxContainer
	var label := _label(row, caption, 14)
	label.custom_minimum_size.x = 130
	label.size_flags_horizontal = Control.SIZE_FILL
	return row


func _line(parent: Node, caption: String, value: String, callback: Callable, key: String = "") -> LineEdit:
	var control := LineEdit.new()
	control.text = value
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, caption).add_child(control)
	control.text_changed.connect(callback)
	if not key.is_empty():
		fields[key] = control
	return control


func _number(parent: Node, caption: String, value: int, callback: Callable, key: String = "", minimum: int = 0) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = minimum
	control.max_value = 9999
	control.allow_greater = true
	control.step = 1
	control.value = value
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, caption).add_child(control)
	control.value_changed.connect(func(number): callback.call(int(number)))
	if not key.is_empty():
		fields[key] = control
	return control


func _check(parent: Node, caption: String, value: bool, callback: Callable, key: String = "") -> CheckBox:
	var control := CheckBox.new()
	control.text = caption
	control.button_pressed = value
	parent.add_child(control)
	control.toggled.connect(callback)
	if not key.is_empty():
		fields[key] = control
	return control


func _dropdown(parent: Node, caption: String, options: Array, value: String, callback: Callable, key: String = "") -> OptionButton:
	var control := OptionButton.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.fit_to_longest_item = false
	var selected := -1
	for option in options:
		control.add_item(option.label)
		control.set_item_metadata(control.item_count - 1, option.value)
		if option.value == value:
			selected = control.item_count - 1
	if selected < 0:
		control.add_item("Choose…" if value.is_empty() else "Missing: " + value)
		selected = control.item_count - 1
		control.set_item_metadata(selected, value)
	control.select(selected)
	_row(parent, caption).add_child(control)
	control.item_selected.connect(func(index): callback.call(control.get_item_metadata(index)))
	if not key.is_empty():
		fields[key] = control
	return control


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#07121b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.custom_minimum_size.x = 1100
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var layout := _box(margin)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := _box(layout, false)
	_label(header, "CONTENT EDITOR", 24)
	dirty_label = _label(header, "Saved", 14)
	dirty_label.custom_minimum_size.x = 125
	dirty_label.size_flags_horizontal = Control.SIZE_FILL
	save_button = _button(header, "Save All", _save)
	revert_button = _button(header, "Revert Unsaved Changes", _revert)
	test_button = _button(header, "Save & Test Battle", _test_battle)
	_button(header, "Main Menu", _request_menu)
	status = RichTextLabel.new()
	status.custom_minimum_size.y = 55
	status.bbcode_enabled = false
	layout.add_child(status)
	var workspace := _box(layout, false)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.custom_minimum_size.y = 560
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(tabs)
	for index in KINDS.size():
		var kind: String = KINDS[index]
		var page := HBoxContainer.new()
		page.name = TITLES[index]
		page.add_theme_constant_override("separation", 12)
		tabs.add_child(page)
		var browser := _box(page)
		browser.custom_minimum_size.x = 205
		browser.size_flags_horizontal = Control.SIZE_FILL
		var search := LineEdit.new()
		search.placeholder_text = "Search " + kind
		browser.add_child(search)
		searches[kind] = search
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size = Vector2(205, 350)
		browser.add_child(list)
		browsers[kind] = list
		search.text_changed.connect(func(_text): _refresh_browser(kind))
		list.item_selected.connect(func(item): _select_entry(kind, list.get_item_metadata(item)))
		var actions := _box(browser, false)
		toolbars[kind] = {
			"new": _button(actions, "New", _new_entry.bind(kind)),
			"duplicate": _button(actions, "Duplicate", _duplicate_entry.bind(kind)),
			"delete": _button(actions, "Delete", _delete_entry.bind(kind))}
		for button in toolbars[kind].values():
			button.add_theme_font_size_override("font_size", 13)
		var form_scroll := ScrollContainer.new()
		form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(form_scroll)
		var form := _box(form_scroll)
		form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		forms[kind] = form
	tabs.tab_changed.connect(func(_index): _rebuild_form())
	inspector_tabs = TabContainer.new()
	inspector_tabs.custom_minimum_size.x = 330
	workspace.add_child(inspector_tabs)
	var preview_scroll := ScrollContainer.new()
	preview_scroll.name = "Preview"
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_tabs.add_child(preview_scroll)
	preview_form = _box(preview_scroll) as VBoxContainer
	preview_form.custom_minimum_size.x = 305
	var setup_panel := PanelContainer.new()
	setup_panel.name = "Battle Setup"
	inspector_tabs.add_child(setup_panel)
	var setup_scroll := ScrollContainer.new()
	setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setup_panel.add_child(setup_scroll)
	setup_form = _box(setup_scroll) as VBoxContainer
	setup_form.custom_minimum_size.x = 285
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Unsaved changes"
	leave_dialog.dialog_text = "Save changes before returning to the main menu?"
	leave_dialog.get_ok_button().text = "Save & Leave"
	leave_dialog.add_button("Discard", false, "discard")
	leave_dialog.confirmed.connect(func():
		if _save():
			_go_menu())
	leave_dialog.custom_action.connect(func(action):
		if action == "discard":
			leave_dialog.hide()
			_go_menu())
	add_child(leave_dialog)


func _kind() -> String:
	return KINDS[tabs.current_tab]


func selected_entry(kind: String = "") -> Dictionary:
	if kind.is_empty():
		kind = _kind()
	var index := Catalog.index_by_id(draft[kind], str(selected_ids.get(kind, "")))
	return {} if index < 0 else draft[kind][index]


func _refresh_all() -> void:
	for kind in KINDS:
		if Catalog.index_by_id(draft[kind], str(selected_ids.get(kind, ""))) < 0:
			selected_ids[kind] = "" if draft[kind].is_empty() else draft[kind][0].id
		_refresh_browser(kind)
	_rebuild_form()
	_build_setup()
	_dirty_changed()


func _refresh_browser(kind: String) -> void:
	var list: ItemList = browsers[kind]
	list.clear()
	var query: String = searches[kind].text.to_lower()
	for entry in draft[kind]:
		if not query.is_empty() and not (str(entry.name) + " " + str(entry.id)).to_lower().contains(query):
			continue
		list.add_item(entry.name)
		list.set_item_metadata(list.item_count - 1, entry.id)
		list.set_item_tooltip(list.item_count - 1, entry.id)
		if entry.id == selected_ids.get(kind, ""):
			list.select(list.item_count - 1)
	toolbars[kind]["duplicate"].disabled = selected_entry(kind).is_empty()
	toolbars[kind].delete.disabled = selected_entry(kind).is_empty()


func _select_entry(kind: String, id: String) -> void:
	selected_ids[kind] = id
	_rebuild_form()


func _rebuild_form() -> void:
	var kind := _kind()
	var form: VBoxContainer = forms[kind]
	_clear(form)
	fields.clear()
	effect_controls.clear()
	rule_previews.clear()
	var entry := selected_entry(kind)
	if entry.is_empty():
		_label(form, "Choose an entry, or use New to create one.")
		_update_preview()
		return
	_label(form, str(entry.id), 12).modulate = Color("#80a7b7")
	_line(form, "Name", entry.name, func(value): _edit_value(entry, "name", value), "name")
	if kind == "ships":
		_ship_form(form, entry)
	elif kind == "cards":
		_card_form(form, entry)
	else:
		_leviathan_form(form, entry)
	_update_preview()


func _edit_value(entry: Dictionary, key: String, value: Variant) -> void:
	entry[key] = value
	_dirty_changed()
	_update_preview()
	if key == "name":
		_refresh_browser(_kind())
		_build_setup()
		_refresh_behavior_names()


func _dirty_changed() -> void:
	dirty_label.text = "Unsaved changes" if is_dirty() else "Saved"
	dirty_label.modulate = Color("#e8bd77") if is_dirty() else Color("#9ce6b7")


func is_dirty() -> bool:
	return ContentStore.migration_pending or JSON.stringify(draft) != JSON.stringify(Catalog.migrate(ContentStore.saved))


func _options(kind: String) -> Array:
	var options: Array = []
	for entry in draft[kind]:
		options.append({"value": entry.id, "label": "%s (%s)" % [entry.name, entry.id]})
	return options


func _ship_form(form: VBoxContainer, entry: Dictionary) -> void:
	_line(form, "Role", entry.role, func(value): _edit_value(entry, "role", value), "role")
	_number(form, "Maximum hull", int(entry.hull), func(value): _edit_value(entry, "hull", value), "hull", 1)
	var color := ColorPickerButton.new()
	color.color = Color(entry.color)
	color.custom_minimum_size = Vector2(120, 34)
	color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(form, "Colour").add_child(color)
	color.color_changed.connect(func(value): _edit_value(entry, "color", "#" + value.to_html(false)))
	fields["color"] = color
	_label(form, "CARD LOADOUT / copies contributed to the shared deck", 13)
	var owned: Array = []
	for card in draft.cards:
		if card.owner == entry.id:
			owned.append(card.id)
			var count := 0
			for slot in entry.loadout:
				if slot.card == card.id:
					count = int(slot.count)
			_number(form, card.name, count, func(value): _set_count(entry, card.id, value), "copies_" + card.id)
	for slot in entry.loadout.duplicate(true):
		if not owned.has(slot.card):
			_label(form, "Invalid loadout reference: " + slot.card, 13).modulate = Color("#ff927f")
			_button(form, "Remove " + slot.card, func():
				_set_count(entry, slot.card, 0)
				_rebuild_form())
	if owned.is_empty():
		_label(form, "Create cards owned by this ship in the Cards tab.")


func _set_count(ship: Dictionary, card_id: String, count: int) -> void:
	var replacement: Array = []
	var existing := false
	for slot in ship.loadout:
		if slot.card != card_id:
			replacement.append(slot)
		else:
			existing = true
			if count > 0:
				replacement.append({"card": card_id, "count": count})
	if count > 0 and not existing:
		replacement.append({"card": card_id, "count": count})
	ship.loadout = replacement
	_dirty_changed()
	_build_setup()


func _card_form(form: VBoxContainer, entry: Dictionary) -> void:
	_dropdown(form, "Owning ship", _options("ships"), entry.owner, func(value): _edit_value(entry, "owner", value), "owner")
	_number(form, "Cost", int(entry.cost), func(value): _edit_value(entry, "cost", value), "cost")
	_number(form, "Payment value", int(entry.pays), func(value): _edit_value(entry, "pays", value), "pays", 1)
	_label(form, "Acting positions", 14)
	var ranks := _box(form, false)
	for point in Geometry.POSITIONS:
		_check(ranks, point, entry.positions.has(point), func(checked): _toggle_value(entry.positions, point, checked), "position_" + point)
	var tags := _box(form, false)
	for tag in Catalog.TAGS:
		_check(tags, tag, entry.tags.has(tag), func(checked): _toggle_value(entry.tags, tag, checked), "tag_" + tag)
	_effects_form(form, entry.effects, "card")
	var preview := _label(form, Catalog.effects_text(entry.effects), 14)
	preview.modulate = Color("#e8bd77")
	fields["preview"] = preview
	_circle_rules_form(form, entry)


func _toggle_value(items: Array, value: Variant, enabled: bool) -> void:
	if enabled and not items.has(value):
		items.append(value)
	elif not enabled:
		items.erase(value)
	_dirty_changed()
	_update_preview()


func _leviathan_form(form: VBoxContainer, entry: Dictionary) -> void:
	_number(form, "Maximum hull", int(entry.hull), func(value): _edit_value(entry, "hull", value), "hull", 1)
	var options: Array = []
	for stance in entry.stances:
		options.append({"value": stance.id, "label": stance.name})
	_dropdown(form, "Starting stance", options, entry.starting_stance, func(value): _edit_value(entry, "starting_stance", value), "starting_stance")
	if Catalog.index_by_id(entry.stances, editing_stance) < 0:
		editing_stance = entry.starting_stance
	_dropdown(form, "Editing stance", options, editing_stance, func(value): editing_stance = value; _rebuild_form.call_deferred(), "editing_stance")
	var tools := _box(form, false)
	_button(tools, "New Stance", _new_stance.bind(entry))
	_button(tools, "Duplicate", _duplicate_stance.bind(entry))
	_button(tools, "Delete", _delete_stance.bind(entry))
	var stance: Dictionary = entry.stances[Catalog.index_by_id(entry.stances, editing_stance)]
	_line(form, "Stance name", stance.name, func(value): _edit_value(stance, "name", value), "stance_name")
	_label(form, "REACTIONS / first match fires, then changes stance", 13)
	_button(form, "Add Reaction", _add_behavior.bind(stance, "reactions"))
	for index in stance.reactions.size():
		var rule: Dictionary = stance.reactions[index]
		var panel := PanelContainer.new()
		form.add_child(panel)
		var content := _box(panel)
		var row := _box(content, false)
		_label(row, rule.id, 12)
		_button(row, "↑", _move_behavior.bind(stance, "reactions", index, -1))
		_button(row, "↓", _move_behavior.bind(stance, "reactions", index, 1))
		_button(row, "Remove", _remove_behavior.bind(stance, "reactions", index))
		_line(content, "Name", rule.name, func(value): _edit_value(rule, "name", value))
		_trigger_form(content, rule.trigger)
		_effects_form(content, rule.effects, "reaction")
	_label(form, "ENEMY-PHASE ACTIVITY / then changes stance", 13)
	_effects_form(form, stance.effects, "intent")


func _refresh_behavior_names() -> void:
	if _kind() != "leviathans":
		return
	var entry := selected_entry()
	for key in ["starting_stance", "editing_stance"]:
		if fields.has(key):
			var control: OptionButton = fields[key]
			for index in control.item_count:
				var found := Catalog.index_by_id(entry.stances, control.get_item_metadata(index))
				if found >= 0:
					control.set_item_text(index, entry.stances[found].name)


func _trigger_form(parent: Node, trigger: Dictionary) -> void:
	var options: Array = []
	for kind in Catalog.TRIGGERS:
		options.append({"value": kind, "label": {"tag": "Action has tag", "damage": "Leviathan damage threshold",
			"tag_position": "Action tag + final actor position", "healed": "Hull restored threshold", "cost": "Printed cost threshold"}[kind]})
	_dropdown(parent, "Trigger", options, trigger.kind, func(value):
		trigger.clear()
		trigger["kind"] = value
		if value in ["tag", "tag_position"]:
			trigger["tag"] = "Attack"
		if value == "tag_position":
			trigger["positions"] = ["front"]
		if value in ["damage", "healed", "cost"]:
			trigger["threshold"] = 1
		_dirty_changed()
		_rebuild_form.call_deferred())
	if trigger.kind in ["tag", "tag_position"]:
		var tags: Array = []
		for tag in Catalog.TAGS:
			tags.append({"value": tag, "label": tag})
		_dropdown(parent, "Required tag", tags, trigger.tag, func(value): _edit_value(trigger, "tag", value))
	if trigger.kind == "tag_position":
		for point in Geometry.POSITIONS:
			_check(parent, point, trigger.positions.has(point), func(value): _toggle_value(trigger.positions, point, value))
	if trigger.kind in ["damage", "healed", "cost"]:
		_number(parent, "Threshold", int(trigger.threshold), func(value): _edit_value(trigger, "threshold", value))
	var preview := _label(parent, Catalog.trigger_text(trigger), 12)
	preview.modulate = Color("#e8bd77")
	rule_previews.append({"label": preview, "kind": "trigger", "value": trigger})


func _effects_form(parent: Node, effects: Array, context: String) -> void:
	var title := _box(parent, false)
	_label(title, "ORDERED EFFECTS", 13)
	var kinds: Array = Catalog.TRIGGER_EFFECTS if context == "trigger" else (Catalog.CARD_EFFECTS if context == "card" else Catalog.MONSTER_EFFECTS)
	_button(title, "Add Effect", func():
		effects.append(Catalog.new_effect(kinds[0]))
		_dirty_changed()
		_rebuild_form())
	for index in effects.size():
		var effect: Dictionary = effects[index]
		var panel := PanelContainer.new()
		parent.add_child(panel)
		var content := _box(panel)
		var options: Array = []
		for kind in kinds:
			options.append({"value": kind, "label": Catalog.EFFECT_NAMES[kind]})
		var kind_input := _dropdown(content, "Effect " + str(index + 1), options, effect.kind, func(value):
			effects[index] = Catalog.new_effect(value)
			_dirty_changed()
			_rebuild_form.call_deferred())
		var actions := _box(content, false)
		var up := _button(actions, "Move Up", _move_effect.bind(effects, index, -1))
		var down := _button(actions, "Move Down", _move_effect.bind(effects, index, 1))
		up.disabled = index == 0
		down.disabled = index == effects.size() - 1
		var remove := _button(actions, "Remove", func():
			effects.remove_at(index)
			_dirty_changed()
			_rebuild_form())
		var controls := {"kind": kind_input, "up": up, "down": down, "remove": remove}
		if effect.kind in ["guard", "damage_ship"] or (context == "trigger" and effect.kind == "repair"):
			var targets: Array = ["actor", "event_actor"] if context == "trigger" else (["actor", "ally"] if effect.kind == "guard" else ["front", "rear", "upper", "lower", "sides", "ends", "all"])
			if context == "reaction":
				targets.append_array(["actor", "repaired"])
			var target_options: Array = []
			for target in targets:
				target_options.append({"value": target, "label": Catalog.TARGET_NAMES[target]})
			controls["target"] = _dropdown(content, "Target", target_options, effect.get("target", "actor"), func(value):
				_edit_value(effect, "target", value)
				_rebuild_form.call_deferred())
		if effect.has("amount"):
			controls["amount"] = _number(content, "Amount" if effect.kind != "swap_ends" else "Lone-ship damage", int(effect.amount), func(value): _edit_value(effect, "amount", value))
		if effect.kind == "draw_discard":
			controls["discard"] = _number(content, "Then discard", int(effect.discard), func(value): _edit_value(effect, "discard", value))
		if effect.kind == "guard" and effect.get("target") == "ally":
			_check(content, "Exclude the acting ship", effect.get("exclude_actor", false), func(value): _edit_value(effect, "exclude_actor", value))
		effect_controls.append(controls)
		var preview := _label(content, Catalog.effects_text([effect]), 12)
		preview.modulate = Color("#80a7b7")
		rule_previews.append({"label": preview, "kind": "effects", "value": [effect]})


func _move_effect(effects: Array, index: int, direction: int) -> void:
	var destination := index + direction
	if destination < 0 or destination >= effects.size():
		return
	var effect: Dictionary = effects[index]
	effects.remove_at(index)
	effects.insert(destination, effect)
	_dirty_changed()
	_rebuild_form()


func _move_behavior(entry: Dictionary, list_name: String, index: int, direction: int) -> void:
	var destination := index + direction
	if destination < 0 or destination >= entry[list_name].size():
		return
	var behavior: Dictionary = entry[list_name][index]
	entry[list_name].remove_at(index)
	entry[list_name].insert(destination, behavior)
	_dirty_changed()
	_rebuild_form()


func _add_behavior(entry: Dictionary, list_name: String) -> void:
	var id := _new_id(entry[list_name], "reaction" if list_name == "reactions" else "intent")
	var behavior := {"id": id, "name": "New " + ("Reaction" if list_name == "reactions" else "Intent"),
		"effects": [{"kind": "damage_ship", "target": "front", "amount": 3}]}
	if list_name == "reactions":
		behavior["trigger"] = {"kind": "tag", "tag": "Movement"}
	entry[list_name].append(behavior)
	_dirty_changed()
	_rebuild_form()


func _remove_behavior(entry: Dictionary, list_name: String, index: int) -> void:
	entry[list_name].remove_at(index)
	_dirty_changed()
	_rebuild_form()


func _update_preview() -> void:
	for preview in rule_previews:
		if is_instance_valid(preview.label):
			preview.label.text = Catalog.trigger_text(preview.value) if preview.kind == "trigger" else Catalog.effects_text(preview.value)
	if fields.has("preview") and is_instance_valid(fields.preview):
		fields.preview.text = Catalog.effects_text(selected_entry().effects)
	_live_preview()


func _build_setup() -> void:
	_clear(setup_form)
	setup_controls.clear()
	_label(setup_form, "BATTLE SETUP", 18)
	_label(setup_form, "Used by Start Game, Retry, and editor playtests.", 13).modulate = Color("#80a7b7")
	setup_controls["leviathan"] = _dropdown(setup_form, "Leviathan", _options("leviathans"), draft.setup.leviathan, func(value): _edit_value(draft.setup, "leviathan", value))
	while draft.setup.ships.size() < 3:
		draft.setup.ships.append("")
	for rank in 3:
		setup_controls["ship_" + str(rank)] = _dropdown(setup_form, "Ship " + str(rank + 1), _options("ships"), draft.setup.ships[rank], func(value):
			draft.setup.ships[rank] = value
			_dirty_changed()
			_build_setup.call_deferred())
	var point_options: Array = []
	for point in Geometry.POSITIONS:
		point_options.append({"value": point, "label": point})
	for index in 3:
		setup_controls["point_" + str(index)] = _dropdown(setup_form, "Ship %d position" % (index + 1), point_options, draft.setup.positions[index], func(value): draft.setup.positions[index] = value; _dirty_changed())
	setup_controls["enemy_point"] = _dropdown(setup_form, "Enemy position", point_options, draft.setup.enemy_position, func(value): draft.setup.enemy_position = value; _dirty_changed())
	_label(setup_form, "BASIC ACTIONS / discard the dragged card", 14)
	var basic := Catalog.basic_rules(draft)
	setup_controls["basic_repair"] = _number(setup_form, "Basic repair", basic.repair, func(value): _set_basic_rule("repair", value))
	setup_controls["revive_threshold"] = _number(setup_form, "Revive threshold", basic.revive_threshold, func(value): _set_basic_rule("revive_threshold", value))
	setup_controls["fixed_hand"] = _check(setup_form, "Use fixed opening hand", draft.setup.fixed_hand, func(value):
		draft.setup.fixed_hand = value
		_dirty_changed()
		_build_setup.call_deferred())
	if draft.setup.fixed_hand:
		_label(setup_form, "Choose exactly seven cards; copy counts must exist in the selected fleet deck.", 13)
		var options: Array = []
		var added: Array = []
		for ship in draft.ships:
			if not draft.setup.ships.has(ship.id):
				continue
			for slot in ship.loadout:
				var index := Catalog.index_by_id(draft.cards, slot.card)
				if index >= 0 and not added.has(slot.card):
					options.append({"value": slot.card, "label": draft.cards[index].name})
					added.append(slot.card)
		while draft.setup.opening_hand.size() < 7:
			draft.setup.opening_hand.append("")
		for index in 7:
			setup_controls["opening_" + str(index)] = _dropdown(setup_form, "Card " + str(index + 1), options, draft.setup.opening_hand[index], func(value):
				draft.setup.opening_hand[index] = value
				_dirty_changed())
	else:
		_label(setup_form, "Draw seven cards from the shuffled fleet deck.", 13)
	_label(setup_form, "Save writes data/content.json. It does not create a Git commit.", 12).modulate = Color("#80a7b7")


func _new_id(entries: Array, prefix: String) -> String:
	var index := 1
	while Catalog.index_by_id(entries, prefix + "_" + str(index)) >= 0:
		index += 1
	return prefix + "_" + str(index)


func _new_entry(kind: String) -> void:
	var id := _new_id(draft[kind], kind.trim_suffix("s"))
	var entry: Dictionary
	match kind:
		"ships":
			entry = {"id": id, "name": "New Ship", "role": "SUPPORT", "hull": 20, "color": "#91c8ad", "loadout": []}
		"cards":
			entry = {"id": id, "name": "New Card", "owner": "" if draft.ships.is_empty() else draft.ships[0].id,
				"cost": 1, "pays": 1, "positions": Geometry.POSITIONS.duplicate(), "tags": ["Attack"], "effects": [{"kind": "damage_monster", "amount": 4}], "on_play": [], "modifiers": [], "triggers": []}
		_:
			entry = {"id": id, "name": "New Leviathan", "hull": 70, "starting_stance": "stance_1",
				"stances": [{"id": "stance_1", "name": "Hunting", "reactions": [],
				"effects": [{"kind": "damage_ship", "target": "front", "amount": 7}]}]}
	draft[kind].append(entry)
	selected_ids[kind] = id
	searches[kind].text = ""
	_refresh_all()


func _duplicate_entry(kind: String) -> void:
	var source := selected_entry(kind)
	if source.is_empty():
		return
	var entry := source.duplicate(true)
	entry.id = _new_id(draft[kind], source.id + "_copy")
	entry.name += " Copy"
	if kind == "ships":
		var mapping: Dictionary = {}
		for card in draft.cards.duplicate(true):
			if card.owner == source.id:
				var copy: Dictionary = card.duplicate(true)
				copy.id = _new_id(draft.cards, card.id + "_copy")
				copy.owner = entry.id
				mapping[card.id] = copy.id
				draft.cards.append(copy)
		for slot in entry.loadout:
			slot.card = mapping.get(slot.card, slot.card)
	draft[kind].append(entry)
	selected_ids[kind] = entry.id
	searches[kind].text = ""
	_refresh_all()


func _delete_entry(kind: String) -> void:
	var entry := selected_entry(kind)
	if entry.is_empty():
		return
	var references := Catalog.references(draft, kind, entry.id)
	if not references.is_empty():
		_message("Cannot delete " + entry.name + ". Change these references first:\n" + "\n".join(references), true)
		return
	draft[kind].remove_at(Catalog.index_by_id(draft[kind], entry.id))
	selected_ids[kind] = ""
	_refresh_all()


func _remember_ui() -> void:
	var search_values: Dictionary = {}
	for kind in KINDS:
		search_values[kind] = searches[kind].text
	ContentStore.editor_state = {"tab": tabs.current_tab, "selected": selected_ids.duplicate(), "searches": search_values, "editing_stance": editing_stance, "preview_slot": preview_slot, "preview_expanded": preview_expanded, "preview_position": preview_position, "preview_tags": preview_tags.duplicate()}


func _save() -> bool:
	if not ContentStore.save_content(draft):
		_message("Cannot save:\n" + ContentStore.last_error, true)
		return false
	_dirty_changed()
	_message("Saved project content. Start Game and Retry use this battle setup.")
	return true


func _revert() -> void:
	draft = Catalog.migrate(ContentStore.snapshot()) if not ContentStore.saved.is_empty() else Catalog.empty_document()
	_refresh_all()
	_message("Unsaved changes reverted.")


func _test_battle() -> void:
	if not _save():
		return
	_remember_ui()
	BattleSession.editor_playtest = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _request_menu() -> void:
	leave_destination = "menu"
	_request_leave()


func _request_leave() -> void:
	if is_dirty():
		leave_dialog.dialog_text = "Save changes before closing the game?" if leave_destination == "quit" else "Save changes before returning to the main menu?"
		leave_dialog.popup_centered()
	else:
		_go_menu()


func _go_menu() -> void:
	_remember_ui()
	BattleSession.editor_playtest = false
	if leave_destination == "quit":
		get_tree().quit()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _message(text: String, error: bool = false) -> void:
	status.text = text
	status.modulate = Color("#ff927f") if error else Color("#9ce6b7")

func _new_stance(entry: Dictionary) -> void:
	var id := _new_id(entry.stances, "stance")
	entry.stances.append({"id": id, "name": "New Stance", "reactions": [], "effects": [{"kind": "damage_ship", "target": "front", "amount": 4}]})
	editing_stance = id
	_dirty_changed()
	_rebuild_form()


func _duplicate_stance(entry: Dictionary) -> void:
	var copy: Dictionary = entry.stances[Catalog.index_by_id(entry.stances, editing_stance)].duplicate(true)
	copy.id = _new_id(entry.stances, copy.id + "_copy")
	copy.name += " Copy"
	entry.stances.append(copy)
	editing_stance = copy.id
	_dirty_changed()
	_rebuild_form()


func _delete_stance(entry: Dictionary) -> void:
	if entry.stances.size() == 1 or entry.starting_stance == editing_stance:
		_message("Keep one stance and choose another starting stance before deleting this one.", true)
		return
	entry.stances.remove_at(Catalog.index_by_id(entry.stances, editing_stance))
	editing_stance = entry.starting_stance
	_dirty_changed()
	_rebuild_form()


func _condition_form(parent: Node, condition: Dictionary) -> void:
	var tags: Array = [{"value": "", "label": "Any card"}]
	for tag in Catalog.TAGS:
		tags.append({"value": tag, "label": tag})
	_dropdown(parent, "Adjacent tag", tags, condition.get("tag", ""), func(value): _edit_value(condition, "tag", value))
	_number(parent, "Minimum neighbours", condition.get("min", 0), func(value): _edit_value(condition, "min", value))


func _circle_rules_form(parent: Node, entry: Dictionary) -> void:
	for section in ["on_play", "modifiers", "triggers"]:
		var row := _box(parent, false)
		_label(row, {"on_play": "CONDITIONAL ON PLAY", "modifiers": "ONGOING BONUSES", "triggers": "CHAINED TRIGGERS / ONCE PER TURN"}[section], 13)
		_button(row, "Add Rule", func():
			var rule := {"condition": {"tag": "", "min": 0}}
			if section == "modifiers":
				rule.merge({"stat": "damage", "amount": 1, "tag": ""})
			else:
				rule["effects"] = [{"kind": "damage_monster", "amount": 1}]
				if section == "triggers":
					rule.merge({"id": _new_id(entry.triggers, "trigger"), "name": "New Trigger", "event": "played", "tag": "", "threshold": 1})
			entry[section].append(rule)
			_dirty_changed()
			_rebuild_form())
		for index in entry[section].size():
			var rule: Dictionary = entry[section][index]
			var panel := PanelContainer.new()
			parent.add_child(panel)
			var column := _box(panel)
			var tools := _box(column, false)
			_button(tools, "↑", _move_effect.bind(entry[section], index, -1))
			_button(tools, "↓", _move_effect.bind(entry[section], index, 1))
			_button(tools, "Remove rule", func(): entry[section].remove_at(index); _dirty_changed(); _rebuild_form())
			if section == "triggers":
				_line(column, "Name", rule.name, func(value): _edit_value(rule, "name", value))
				var events: Array = []
				for event in Catalog.CARD_EVENTS:
					events.append({"value": event, "label": event})
				_dropdown(column, "Neighbour event", events, rule.event, func(value): _edit_value(rule, "event", value))
				_number(column, "Event threshold", rule.threshold, func(value): _edit_value(rule, "threshold", value))
			if section in ["modifiers", "triggers"]:
				var tags: Array = [{"value": "", "label": "Any tag"}]
				for tag in Catalog.TAGS:
					tags.append({"value": tag, "label": tag})
				_dropdown(column, "Affected/event tag", tags, rule.tag, func(value): _edit_value(rule, "tag", value))
			if section == "modifiers":
				var stats: Array = []
				for stat in Catalog.STATS:
					stats.append({"value": stat, "label": stat})
				_dropdown(column, "Bonus stat", stats, rule.stat, func(value): _edit_value(rule, "stat", value))
				_number(column, "Bonus / cost reduction", rule.amount, func(value): _edit_value(rule, "amount", value))
			_condition_form(column, rule.condition)
			if section != "modifiers":
				_effects_form(column, rule.effects, "trigger" if section == "triggers" else "card")


func _live_preview() -> void:
	if not is_instance_valid(preview_form):
		return
	_clear(preview_form)
	var entry := selected_entry()
	if entry.is_empty():
		_label(preview_form, "Select content to preview.")
		return
	_label(preview_form, "LIVE / UNSAVED DRAFT", 13).modulate = Color("#d6adee")
	var points: Array = []
	for point in Geometry.POSITIONS:
		points.append({"value": point, "label": point})
	if _kind() == "cards":
		var owner_index := Catalog.index_by_id(draft.ships, entry.get("owner", ""))
		var owner: Dictionary = {} if owner_index < 0 else draft.ships[owner_index]
		var info := Catalog.present_card(entry)
		var face := CardFace.new()
		face.custom_minimum_size = Vector2(286, 340)
		face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview_form.add_child(face)
		face.configure(info, owner)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_widget = face
		_check(preview_form, "Expanded context", preview_expanded, func(value): preview_expanded = value; preview_slot = mini(preview_slot, 3); _live_preview())
		var slots: Array = []
		for slot in (9 if preview_expanded else 4):
			slots.append({"value": str(slot), "label": Geometry.SLOT_NAMES[slot]})
		_dropdown(preview_form, "Preview slot", slots, str(preview_slot), func(value): preview_slot = int(value); _live_preview())
		var contents: Array = [-1, -1, -1, -1, -1, -1, -1, -1, -1]
		var data: Dictionary = {0: info}
		contents[preview_slot] = 0
		var neighbours: Array = []
		for slot in Geometry.neighbours(preview_slot, preview_expanded):
			var tag: String = preview_tags.get(slot, "")
			if tag != "":
				contents[slot] = slot + 1
				data[slot + 1] = {"name": tag, "tag_ids": [tag], "effect": ""}
				neighbours.append(data[slot + 1])
		var mini := CircleView.new()
		mini.custom_minimum_size = Vector2(0, 200)
		preview_form.add_child(mini)
		mini.configure(contents, preview_expanded, data, {}, preview_slot)
		var active: Array = []
		for rule in entry.get("on_play", []):
			if Geometry.condition_matches(rule.condition, neighbours):
				active.append(Catalog.effects_text(rule.effects))
		_label(preview_form, "Active conditional bonuses: " + ("None" if active.is_empty() else " ".join(active)), 13).modulate = Color("#9ce6b7")
		for modifier in entry.get("modifiers", []):
			var count := 0
			if Geometry.condition_matches(modifier.condition, neighbours):
				for neighbour in neighbours:
					if modifier.get("tag", "") == "" or neighbour.tag_ids.has(modifier.tag):
						count += 1
			_label(preview_form, "%s %s%d: affects %d neighbour(s)." % [modifier.stat, "−" if modifier.stat == "cost" else "+", modifier.amount, count], 13)
		for slot in Geometry.neighbours(preview_slot, preview_expanded):
			var tags: Array = [{"value": "", "label": "Empty"}]
			for tag in Catalog.TAGS:
				tags.append({"value": tag, "label": tag})
			_dropdown(preview_form, Geometry.SLOT_NAMES[slot], tags, preview_tags.get(slot, ""), func(value): preview_tags[slot] = value; _live_preview())
		if not Catalog.validate(draft).is_empty():
			_label(preview_form, "Draft needs validation; preview only.", 12).modulate = Color("#ff927f")
	else:
		_dropdown(preview_form, "Preview position", points, preview_position, func(value): preview_position = value; _live_preview())
		var board := {"ships": [], "formation": [-1, -1, -1, -1], "enemy_position": Geometry.POSITIONS.find(preview_position), "monster_hull": int(entry.get("hull", 1))}
		var view := FormationView.new()
		view.custom_minimum_size = Vector2(0, 250)
		preview_form.add_child(view)
		if _kind() == "ships":
			var unit := entry.duplicate(true)
			unit["max_hull"] = maxi(1, int(entry.get("hull", 1)))
			unit["guard"] = 0
			board.ships = [unit]
			board.formation[Geometry.POSITIONS.find(preview_position)] = 0
			view.configure(board)
		else:
			view.configure(board, true, entry)
			var options: Array = []
			for stance in entry.stances:
				options.append({"value": stance.id, "label": stance.name})
			if Catalog.index_by_id(entry.stances, editing_stance) < 0:
				editing_stance = entry.starting_stance
			_dropdown(preview_form, "Preview stance", options, editing_stance, func(value): editing_stance = value; _rebuild_form())
			var stance_view := StanceView.new()
			preview_form.add_child(stance_view)
			stance_view.configure(entry.stances[Catalog.index_by_id(entry.stances, editing_stance)])
		preview_widget = view


func _set_basic_rule(key: String, value: int) -> void:
	var basic := Catalog.basic_rules(draft)
	basic[key] = value
	draft.setup["basic_actions"] = basic
	_dirty_changed()

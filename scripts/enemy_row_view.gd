extends Control
signal card_selected(uid: int)
signal card_hovered(uid: int)
signal card_exited(uid: int)
signal reaction_selected(key: String)
const Catalog = preload("res://scripts/content_catalog.gd")
const Rules = preload("res://scripts/rules/rule_registry.gd")
const ReactionBadge = preload("res://scripts/reaction_badge.gd")
const KeywordText = preload("res://scripts/keyword_text.gd")
const MonsterPortrait = preload("res://scripts/monster_portrait.gd")
const INSPECTION_HEIGHT := 220.0
var buttons: Array = []
var row: Array = []
var selected := -1
var reaction_buttons: Dictionary={}
var trigger_keys: Array=[]
var _activation_slots: Array = []
var _lifted_uid := -1


func _ready() -> void:
	resized.connect(_arrange)
	_arrange()


func begin_activations() -> void:
	if not _activation_slots.is_empty(): return
	for button in buttons:
		_activation_slots.append(button.get_meta("stance_uid", -1))


func end_activations() -> void:
	_activation_slots.clear()


func card_button(uid: int) -> Control:
	for button in buttons:
		if button.get_meta("stance_uid", -1) == uid: return button
	return null


func lift_card(uid: int) -> void:
	_lifted_uid = uid
	var button := card_button(uid)
	if button != null: button.hide()


func clear_lift() -> void:
	_lifted_uid = -1


func animate_refill(duration: float, uid: int = -1) -> void:
	var incoming := buttons.filter(func(button): return button.has_meta("stance_uid") and (uid < 0 or button.get_meta("stance_uid") == uid))
	if incoming.is_empty(): return
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for button in incoming:
		button.position.y = -44.0
		button.modulate.a = 0.0
		tween.tween_property(button, "position:y", 0.0, duration)
		tween.tween_property(button, "modulate:a", 1.0, duration)
	await tween.finished


func configure(cards: Array, stunned: Dictionary = {}, highlighted: int = -1, capacity: int = 0) -> void:
	row = cards.duplicate(true)
	selected = highlighted
	for child in get_children():
		remove_child(child)
		child.queue_free()
	buttons.clear()
	reaction_buttons.clear()
	trigger_keys.clear()
	var count := capacity if capacity > 0 else (1 if row.size() == 1 and size.x < 400 else 3)
	var display := row
	if not _activation_slots.is_empty():
		var by_uid: Dictionary = {}
		for stance in row: by_uid[stance.uid] = stance
		display = _activation_slots.map(func(uid): return by_uid.get(uid, {}))
		count = _activation_slots.size()
	for index in maxi(count, display.size()):
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.clip_contents = true
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#102632")
			style.border_color = Color("#5a7783")
			style.set_border_width_all(1)
			style.set_corner_radius_all(5)
			button.add_theme_stylebox_override(state,style)
		button.add_theme_font_size_override("font_size", 11)
		add_child(button)
		buttons.append(button)
		if index >= display.size() or display[index].is_empty():
			if not _activation_slots.is_empty(): button.hide()
			button.text = "ENEMY ROW: Empty\nNo additional physical cards available"
			button.disabled = true
			continue
		var stance: Dictionary = display[index]
		var inspecting := stance.has("copies")
		if inspecting: button.focus_mode = Control.FOCUS_NONE
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12 if inspecting else 6)
		button.add_child(margin)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8 if inspecting else 2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(column)
		if inspecting:
			margin.minimum_size_changed.connect(_fit_inspection.bind(margin))
		var owner_row:=HBoxContainer.new()
		owner_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
		column.add_child(owner_row)
		var portrait := MonsterPortrait.new()
		portrait.configure(stance.get("owner_visual", {}), stance.get("owner", -999), Vector2(76, 38) if inspecting else Vector2(48, 24))
		owner_row.add_child(portrait)
		var heading := Label.new()
		heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		heading.add_theme_font_size_override("font_size", 15 if inspecting else 11)
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.text = stance.owner_name if inspecting else "%d: %s" % [index + 1, stance.get("owner_name", "Enemy")]
		owner_row.add_child(heading)
		if inspecting or stance.get("reactions", []).size() <= 1:
			var stance_title := Label.new()
			stance_title.text = stance.name
			if inspecting:
				stance_title.text += " · %s" % ("1 copy" if int(stance.copies) == 1 else "%d copies" % int(stance.copies))
			stance_title.set_meta("plain_text", true)
			stance_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stance_title.add_theme_font_size_override("font_size", 19 if inspecting else 11)
			stance_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			column.add_child(stance_title)
		for reaction in stance.get("reactions",[]):
			if inspecting:
				_add_inspection_reaction(column, stance, reaction)
				continue
			var react := Button.new()
			var key := str(stance.uid)+"/"+str(reaction.id)
			react.text=("Stunned: " if stunned.has(key) else "Reaction: ")+Rules.reaction_condition_text(reaction.conditions,stance.get("owner_name", ""))+" → "+Catalog.effects_text(reaction.effects, stance.get("owner_name", ""))
			var badge := _reaction_badge(reaction, 34)
			if badge != null:
				react.text=("Stunned: " if stunned.has(key) else "")+"→ "+Catalog.effects_text(reaction.effects,stance.get("owner_name",""))
				react.custom_minimum_size.y=36
				react.set_meta("keyword_left_padding", badge.custom_minimum_size.x + 10)
				badge.position=Vector2(4,1)
				react.add_child(badge)
				if stunned.has(key):badge.modulate=Color("#83929b")
			react.add_theme_font_size_override("font_size",10)
			react.clip_text=true
			for state in ["normal","hover","pressed","hover_pressed"]:
				var style := StyleBoxFlat.new()
				style.bg_color = Color("#152e3b")
				style.border_color = Color("#3d6476")
				style.set_border_width_all(1)
				style.set_corner_radius_all(3)
				react.add_theme_stylebox_override(state,style)
			react.tooltip_text=reaction.name+"\n"+Rules.reaction_condition_text(reaction.conditions,stance.get("owner_name", ""))+" → "+Catalog.effects_text(reaction.effects, stance.get("owner_name", ""))
			react.set_meta("base_tooltip",react.tooltip_text)
			reaction_buttons[key]=react
			column.add_child(react)
			react.pressed.connect(func(): reaction_selected.emit(key))
			react.mouse_entered.connect(func(): card_hovered.emit(stance.uid))
			react.mouse_exited.connect(func(): card_exited.emit(stance.uid))
		var intent_text := "Intent: " + Catalog.effects_text(stance.get("effects", []), stance.get("owner_name", ""))
		if inspecting:
			_add_inspection_text(column, "Intent", intent_text)
		else:
			var body := Label.new()
			body.name = "Intent"
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_theme_font_size_override("font_size", 10)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.max_lines_visible = 1
			body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			body.text = intent_text
			column.add_child(body)
		button.tooltip_text = "%s: %s\n" % [stance.get("owner_name", "Enemy"), stance.name]
		for reaction in stance.get("reactions", []):
			button.tooltip_text += reaction.name + " [" + reaction.get("category", "") + "]\n" + Rules.reaction_condition_text(reaction.conditions, stance.get("owner_name", "")) + " → " + Catalog.effects_text(reaction.effects, stance.get("owner_name", "")) + "\n"
		button.tooltip_text += "Enemy phase: " + Catalog.effects_text(stance.get("effects", []), stance.get("owner_name", ""))
		if not inspecting: button.tooltip_text += "\nReplacements remain hidden until revealed."
		button.set_meta("stance_uid", stance.uid)
		if stance.uid == _lifted_uid: button.hide()
		button.pressed.connect(func(): card_selected.emit(stance.uid))
		button.mouse_entered.connect(func(): card_hovered.emit(stance.uid))
		button.mouse_exited.connect(func(): card_exited.emit(stance.uid))
		if highlighted == stance.uid: button.modulate = Color("#f6d491")
	_arrange()

func _fit_inspection(margin: MarginContainer) -> void:
	custom_minimum_size.y = maxf(INSPECTION_HEIGHT, margin.get_combined_minimum_size().y + 2.0)

func _reaction_badge(reaction: Dictionary, extent: int) -> Control:
	if reaction.conditions.get("kind") != "reaction_trigger" or reaction.get("custom_trigger", false):
		return null
	var badge := ReactionBadge.new()
	badge.configure(reaction.conditions, extent)
	return badge

func _add_inspection_reaction(column: VBoxContainer, stance: Dictionary, reaction: Dictionary) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#152e3b")
	style.border_color = Color("#3d6476")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 8)
	panel.add_theme_stylebox_override("panel", style)
	column.add_child(panel)
	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	panel.add_child(contents)
	var badge := _reaction_badge(reaction, 44)
	if badge != null:
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		contents.add_child(badge)
	var owner: String = stance.get("owner_name", "")
	var rule_text := "%s\n%s\n%s" % [
		reaction.name,
		Rules.reaction_condition_text(reaction.conditions, owner),
		Catalog.effects_text(reaction.effects, owner),
	]
	_add_inspection_text(contents, "ReactionRules", rule_text)

func _add_inspection_text(parent: Container, node_name: String, value: String) -> void:
	var label := KeywordText.new()
	label.name = node_name
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.configure(value, 15, get_theme_color("font_color", "Label"), HORIZONTAL_ALIGNMENT_LEFT, false, true)
	parent.add_child(label)

func _arrange() -> void:
	for index in buttons.size():
		buttons[index].position.x = index * size.x / maxf(1, buttons.size())
		buttons[index].size = Vector2(size.x / maxf(1, buttons.size()) - 5, size.y)

func show_trigger_preview(keys: Array = [], provisional: bool = false) -> void:
	trigger_keys=keys.duplicate()
	for key in reaction_buttons:
		var button: Button=reaction_buttons[key]
		var active: bool=keys.has(key)
		button.tooltip_text=str(button.get_meta("base_tooltip",""))+("\nWould trigger with this action; complete payment/targets." if provisional else "\nWill trigger with this action.") if active else str(button.get_meta("base_tooltip",""))
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Color("#4a3029") if active else Color("#152e3b")
			style.border_color=Color("#ffbd78") if active else Color("#3d6476")
			style.set_border_width_all(3 if active else 1)
			style.set_corner_radius_all(3)
			button.add_theme_stylebox_override(state,style)
		button.set_meta("trigger_preview",active)
